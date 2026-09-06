// Graphe orienté chargé INTÉGRALEMENT en mémoire (§ 11.7 de la spécification).
//
// Représentation CSR (Compressed Sparse Row) : compacte et rapide à parcourir.
//   _fwdOffset[u].._fwdOffset[u+1]  -> tranche de _fwdTarget = successeurs de u
//   _revOffset[u].._revOffset[u+1]  -> tranche de _revSource = prédécesseurs de u
// Pour n nœuds et m arêtes : 2·(n+1) + 2·m entiers, plus les noms des nœuds.
// Ex. 2 000 000 nœuds / 8 000 000 arêtes ≈ 80 Mo pour les tableaux CSR.
//
// Quatre algorithmes de plus court chemin s'exécutent ici SANS aucun accès
// base : BFS bidirectionnel, Dijkstra, Dijkstra bidirectionnel, A* (ALT).
// Aucune requête SQL dans ce fichier.
//
// C# 8.0 : pas de collection expressions — les chemins vides s'écrivent
// `new List<string>()`.

using System;
using System.Collections.Generic;

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services
{
    public sealed class DirectedGraph
    {
        // Garde-fou : nombre max de nœuds visités par sens. En mémoire on peut
        // être bien plus généreux qu'avec le BFS SQL (30 000) car il n'y a plus de
        // latence par palier — seulement de la RAM transitoire.
        private const int MaxVisitedPerSide = 300_000;

        // Garde-fou commun aux parcours à file de priorité (Dijkstra, Dijkstra
        // bidirectionnel, A*) : on autorise à peu près l'équivalent des deux
        // fronts du BFS réunis.
        private const int MaxVisited = 600_000;

        // Poids d'une arête. Ici toutes les arêtes valent 1 : le « coût » d'un
        // chemin est donc son nombre d'arêtes, exactement comme le BFS. Si un jour
        // la table portait une vraie pondération, c'est le seul endroit à changer.
        private const int EdgeWeight = 1;

        private readonly Dictionary<string, int> _index;
        private readonly string[] _names;
        private readonly int[] _fwdOffset;
        private readonly int[] _fwdTarget;
        private readonly int[] _revOffset;
        private readonly int[] _revSource;

        // Repères ALT pour A* (voir PrepareLandmarks). Remplis APRÈS la
        // construction, une seule fois. Tant qu'ils sont nuls, A* se comporte
        // exactement comme Dijkstra (heuristique = 0).
        private int[] _landmarks = Array.Empty<int>();
        private int[][]? _lmDistFrom;  // _lmDistFrom[k][v] = distance repère_k -> v
        private int[][]? _lmDistTo;    // _lmDistTo[k][v]   = distance v -> repère_k

        public int NodeCount => _names.Length;
        public int EdgeCount => _fwdTarget.Length;
        public int LandmarkCount => _landmarks.Length;

        // Estimation grossière de l'empreinte mémoire (octets).
        public long ApproximateBytes
        {
            get
            {
                long csr = 4L * (_fwdOffset.Length + _revOffset.Length + _fwdTarget.Length + _revSource.Length);
                long names = 0;
                foreach (var s in _names) names += 24 + 2L * s.Length; // objet string + chars UTF-16
                long dict = _index.Count * 56L;                        // ordre de grandeur
                return csr + names + dict;
            }
        }

        private DirectedGraph(Dictionary<string, int> index, string[] names,
            int[] fwdOffset, int[] fwdTarget, int[] revOffset, int[] revSource)
        {
            _index = index;
            _names = names;
            _fwdOffset = fwdOffset;
            _fwdTarget = fwdTarget;
            _revOffset = revOffset;
            _revSource = revSource;
        }

        // Construit le graphe à partir du flux d'arêtes ORIENTÉES (source -> cible).
        public static DirectedGraph Build(IEnumerable<(string From, string To)> directedEdges)
        {
            var index = new Dictionary<string, int>();
            var names = new List<string>();

            int Idx(string node)
            {
                if (index.TryGetValue(node, out var i)) return i;
                i = names.Count;
                index[node] = i;
                names.Add(node);
                return i;
            }

            var edges = new List<(int From, int To)>();
            foreach (var (from, to) in directedEdges)
                edges.Add((Idx(from), Idx(to)));

            var n = names.Count;
            var m = edges.Count;

            // 1. compter le degré (sortant et entrant) de chaque nœud
            var fwdOffset = new int[n + 1];
            var revOffset = new int[n + 1];
            foreach (var (u, v) in edges)
            {
                fwdOffset[u + 1]++;
                revOffset[v + 1]++;
            }

            // 2. sommes préfixes -> offsets
            for (var i = 0; i < n; i++)
            {
                fwdOffset[i + 1] += fwdOffset[i];
                revOffset[i + 1] += revOffset[i];
            }

            // 3. remplir les tableaux d'arêtes
            var fwdTarget = new int[m];
            var revSource = new int[m];
            var fwdCursor = (int[])fwdOffset.Clone();
            var revCursor = (int[])revOffset.Clone();
            foreach (var (u, v) in edges)
            {
                fwdTarget[fwdCursor[u]++] = v;
                revSource[revCursor[v]++] = u;
            }

            return new DirectedGraph(index, names.ToArray(), fwdOffset, fwdTarget, revOffset, revSource);
        }

        private ReadOnlySpan<int> Successors(int u)
            => _fwdTarget.AsSpan(_fwdOffset[u], _fwdOffset[u + 1] - _fwdOffset[u]);

        private ReadOnlySpan<int> Predecessors(int u)
            => _revSource.AsSpan(_revOffset[u], _revOffset[u + 1] - _revOffset[u]);

        // BFS bidirectionnel non pondéré, entièrement en mémoire. Même logique que
        // LineVisEdgRepository.ShortestPath, mais sur les tableaux CSR.
        public ShortestPathResult ShortestPath(string sourceId, string targetId, int maxDepth = 12)
        {
            if (!_index.TryGetValue(sourceId, out var s) || !_index.TryGetValue(targetId, out var t))
                return new ShortestPathResult(new List<string>(), false); // nœud inconnu

            if (s == t)
                return new ShortestPathResult(new List<string> { _names[s] }, true);

            var forwardPrev = new Dictionary<int, int> { [s] = -1 }; // -1 = racine
            var backwardNext = new Dictionary<int, int> { [t] = -1 };
            var forwardFrontier = new List<int> { s };
            var backwardFrontier = new List<int> { t };

            for (var step = 0; step < maxDepth; step++)
            {
                if (forwardFrontier.Count == 0 && backwardFrontier.Count == 0) break;

                var expandForward = step % 2 == 0;

                if (expandForward && forwardFrontier.Count > 0 && forwardPrev.Count < MaxVisitedPerSide)
                {
                    var next = new List<int>();
                    foreach (var u in forwardFrontier)
                        foreach (var v in Successors(u))
                            if (forwardPrev.TryAdd(v, u))
                            {
                                next.Add(v);
                                if (backwardNext.ContainsKey(v))
                                    return BuildPath(v, forwardPrev, backwardNext);
                            }
                    forwardFrontier = next;
                }
                else if (!expandForward && backwardFrontier.Count > 0 && backwardNext.Count < MaxVisitedPerSide)
                {
                    var next = new List<int>();
                    foreach (var u in backwardFrontier)
                        foreach (var w in Predecessors(u))
                            if (backwardNext.TryAdd(w, u))
                            {
                                next.Add(w);
                                if (forwardPrev.ContainsKey(w))
                                    return BuildPath(w, forwardPrev, backwardNext);
                            }
                    backwardFrontier = next;
                }
            }

            return new ShortestPathResult(new List<string>(), false);
        }

        private ShortestPathResult BuildPath(int meeting, Dictionary<int, int> forwardPrev, Dictionary<int, int> backwardNext)
        {
            var path = new List<string> { _names[meeting] };

            for (var cur = forwardPrev[meeting]; cur != -1; cur = forwardPrev[cur])
                path.Insert(0, _names[cur]);

            for (var cur = backwardNext[meeting]; cur != -1; cur = backwardNext[cur])
                path.Add(_names[cur]);

            return new ShortestPathResult(path, true);
        }

        // ---------------------------------------------------------------------
        // Variante DIJKSTRA (à sens unique, file de priorité).
        //
        // Dijkstra généralise le BFS aux graphes PONDÉRÉS : au lieu d'avancer
        // palier par palier, on traite toujours en premier le nœud dont le coût
        // cumulé depuis la source est le plus petit. On se sert ici d'une file
        // de priorité (PriorityQueue<élément, priorité> de .NET : la priorité est
        // le coût, la file rend toujours le plus petit).
        //
        // Comme toutes les arêtes valent 1 (EdgeWeight), ce Dijkstra renvoie le
        // MÊME chemin que le BFS ; il est là pour montrer l'algorithme. Sur un
        // vrai graphe pondéré, c'est cette méthode qu'il faudrait utiliser (le
        // BFS, lui, donnerait un chemin faux).
        //
        //   maxCost : plafond de coût cumulé (= plafond de longueur ici). Au-delà,
        //             on cesse d'explorer — équivalent du maxDepth du BFS.
        // ---------------------------------------------------------------------
        public ShortestPathResult ShortestPathDijkstra(string sourceId, string targetId, int maxCost = 20)
        {
            if (!_index.TryGetValue(sourceId, out var s) || !_index.TryGetValue(targetId, out var t))
                return new ShortestPathResult(new List<string>(), false); // nœud inconnu

            if (s == t)
                return new ShortestPathResult(new List<string> { _names[s] }, true);

            // dist[u] = plus petit coût connu pour aller de la source à u.
            // prev[u] = nœud d'où l'on est arrivé à u sur ce meilleur chemin
            //           (-1 = la source elle-même).
            var dist = new Dictionary<int, int> { [s] = 0 };
            var prev = new Dictionary<int, int> { [s] = -1 };

            // La file de priorité : on y met (nœud, coût) et Dequeue() rend
            // toujours le nœud de plus petit coût.
            var frontier = new PriorityQueue<int, int>();
            frontier.Enqueue(s, 0);

            // Un nœud peut être empilé plusieurs fois (avec des coûts qui baissent) ;
            // « settled » retient ceux dont le coût est définitivement fixé, pour ne
            // les traiter qu'une seule fois.
            var settled = new HashSet<int>();

            while (frontier.Count > 0)
            {
                var u = frontier.Dequeue();

                // Déjà traité via une meilleure extraction précédente : on ignore.
                if (!settled.Add(u)) continue;

                // Cible atteinte : comme Dijkstra fige les nœuds par coût croissant,
                // ce coût est optimal — on peut reconstruire et s'arrêter.
                if (u == t) return BuildForwardPath(t, prev);

                if (settled.Count > MaxVisited) break; // garde-fou mémoire

                var costU = dist[u];
                if (costU >= maxCost) continue; // au-delà du plafond : inutile d'aller plus loin

                // « Relâchement » des arêtes sortantes : si passer par u donne un
                // meilleur coût pour v, on met à jour et on ré-empile v.
                foreach (var v in Successors(u))
                {
                    var newCost = costU + EdgeWeight;
                    if (newCost < dist.GetValueOrDefault(v, int.MaxValue))
                    {
                        dist[v] = newCost;
                        prev[v] = u;
                        frontier.Enqueue(v, newCost);
                    }
                }
            }

            return new ShortestPathResult(new List<string>(), false);
        }

        // Reconstruit source -> ... -> target en remontant la chaîne prev[] puis
        // en la retournant (Dijkstra n'a qu'un seul front, contrairement au BFS
        // bidirectionnel qui a besoin de BuildPath).
        private ShortestPathResult BuildForwardPath(int target, Dictionary<int, int> prev)
        {
            var path = new List<string>();
            for (var cur = target; cur != -1; cur = prev[cur])
                path.Add(_names[cur]);
            path.Reverse();
            return new ShortestPathResult(path, true);
        }

        // =====================================================================
        // Variante DIJKSTRA BIDIRECTIONNEL.
        //
        // Comme le BFS bidirectionnel : deux fronts, un qui part de la source en
        // suivant les successeurs, un qui part de la cible en suivant les
        // prédécesseurs. Mais chaque front est un Dijkstra (file de priorité), donc
        // ça reste correct sur un graphe PONDÉRÉ.
        //
        // Subtilité : on ne peut pas s'arrêter au premier nœud vu des deux côtés
        // (contrairement au BFS non pondéré). On garde le meilleur chemin complet
        // rencontré (« best ») et on s'arrête seulement quand la somme des deux
        // plus petits coûts encore en file ne peut plus le battre :
        //     topF + topB >= best   =>   fini.
        // =====================================================================
        public ShortestPathResult ShortestPathDijkstraBi(string sourceId, string targetId, int maxCost = 20)
        {
            if (!_index.TryGetValue(sourceId, out var s) || !_index.TryGetValue(targetId, out var t))
                return new ShortestPathResult(new List<string>(), false);

            if (s == t)
                return new ShortestPathResult(new List<string> { _names[s] }, true);

            var distF = new Dictionary<int, int> { [s] = 0 };   // coût source -> u
            var distB = new Dictionary<int, int> { [t] = 0 };   // coût u -> cible
            var prevF = new Dictionary<int, int> { [s] = -1 };
            var nextB = new Dictionary<int, int> { [t] = -1 };
            var settledF = new HashSet<int>();
            var settledB = new HashSet<int>();
            var pqF = new PriorityQueue<int, int>();
            var pqB = new PriorityQueue<int, int>();
            pqF.Enqueue(s, 0);
            pqB.Enqueue(t, 0);

            var best = int.MaxValue;   // coût du meilleur chemin complet trouvé
            var meeting = -1;          // nœud de jonction de ce meilleur chemin

            while (pqF.Count > 0 && pqB.Count > 0)
            {
                // Condition d'arrêt : plus aucun espoir de battre « best ».
                if (pqF.TryPeek(out _, out var topF) && pqB.TryPeek(out _, out var topB)
                    && (long)topF + topB >= best)
                    break;

                if (settledF.Count + settledB.Count > MaxVisited) break;

                // On développe le front qui a le moins de nœuds figés (le plus « en retard »).
                if (settledF.Count <= settledB.Count)
                {
                    var u = pqF.Dequeue();
                    if (!settledF.Add(u)) continue;
                    var du = distF[u];
                    if (du >= maxCost) continue;

                    foreach (var v in Successors(u))
                    {
                        var nd = du + EdgeWeight;
                        if (nd < distF.GetValueOrDefault(v, int.MaxValue))
                        {
                            distF[v] = nd;
                            prevF[v] = u;
                            pqF.Enqueue(v, nd);
                        }
                        // v est-il déjà atteint par l'autre front ? -> chemin complet.
                        if (distB.TryGetValue(v, out var db) && nd + db < best)
                        {
                            best = nd + db;
                            meeting = v;
                        }
                    }
                }
                else
                {
                    var u = pqB.Dequeue();
                    if (!settledB.Add(u)) continue;
                    var du = distB[u];
                    if (du >= maxCost) continue;

                    foreach (var w in Predecessors(u))
                    {
                        var nd = du + EdgeWeight;
                        if (nd < distB.GetValueOrDefault(w, int.MaxValue))
                        {
                            distB[w] = nd;
                            nextB[w] = u;
                            pqB.Enqueue(w, nd);
                        }
                        if (distF.TryGetValue(w, out var df) && df + nd < best)
                        {
                            best = df + nd;
                            meeting = w;
                        }
                    }
                }
            }

            if (meeting < 0) return new ShortestPathResult(new List<string>(), false);

            // Reconstruction : source -> ... -> meeting (via prevF), puis
            // meeting -> ... -> cible (via nextB).
            var path = new List<string> { _names[meeting] };
            for (var cur = prevF[meeting]; cur != -1; cur = prevF[cur]) path.Insert(0, _names[cur]);
            for (var cur = nextB[meeting]; cur != -1; cur = nextB[cur]) path.Add(_names[cur]);
            return new ShortestPathResult(path, true);
        }

        // =====================================================================
        // Variante A* (« A star »).
        //
        // A* = Dijkstra + une estimation h(n) du coût restant de n jusqu'à la
        // cible. On classe les nœuds par g(n) + h(n) au lieu de g(n) seul, ce qui
        // « aspire » la recherche vers la cible.
        //
        // Pour que le chemin trouvé reste optimal, h doit être ADMISSIBLE : ne
        // jamais surestimer le vrai coût restant. Ici les nœuds n'ont ni
        // coordonnées ni poids géographiques : impossible de faire une distance à
        // vol d'oiseau. On utilise donc l'heuristique ALT (A*, Landmarks,
        // Triangle inequality) : on choisit quelques « repères », on précalcule
        // leur distance à tous les nœuds (PrepareLandmarks), et l'inégalité
        // triangulaire donne une borne inférieure valable de dist(n, cible).
        //
        // Tant que PrepareLandmarks n'a pas été appelé, h = 0 et A* == Dijkstra.
        // =====================================================================
        public ShortestPathResult ShortestPathAStar(string sourceId, string targetId, int maxCost = 20)
        {
            if (!_index.TryGetValue(sourceId, out var s) || !_index.TryGetValue(targetId, out var t))
                return new ShortestPathResult(new List<string>(), false);

            if (s == t)
                return new ShortestPathResult(new List<string> { _names[s] }, true);

            var g = new Dictionary<int, int> { [s] = 0 };   // coût réel source -> u
            var prev = new Dictionary<int, int> { [s] = -1 };
            var settled = new HashSet<int>();
            var open = new PriorityQueue<int, int>();        // priorité = g + h
            open.Enqueue(s, Heuristic(s, t));

            while (open.Count > 0)
            {
                var u = open.Dequeue();
                if (!settled.Add(u)) continue;
                if (u == t) return BuildForwardPath(t, prev);
                if (settled.Count > MaxVisited) break;

                var gu = g[u];
                if (gu >= maxCost) continue;

                foreach (var v in Successors(u))
                {
                    var ng = gu + EdgeWeight;
                    if (ng < g.GetValueOrDefault(v, int.MaxValue))
                    {
                        g[v] = ng;
                        prev[v] = u;
                        open.Enqueue(v, ng + Heuristic(v, t)); // f = g + h
                    }
                }
            }

            return new ShortestPathResult(new List<string>(), false);
        }

        // -------------------------------------------------------------------
        // Heuristique ALT : borne inférieure (jamais surestimée) de dist(n, cible)
        // déduite des repères par inégalité triangulaire.
        //
        //   Pour un repère L :
        //     dist(n, cible) >= dist(L, cible) - dist(L, n)      [via _lmDistFrom]
        //     dist(n, cible) >= dist(n, L)     - dist(cible, L)  [via _lmDistTo]
        //   On prend le plus grand minorant sur tous les repères.
        // -------------------------------------------------------------------
        private int Heuristic(int n, int t)
        {
            if (_lmDistFrom == null || _lmDistTo == null) return 0; // pas de repères

            var h = 0;
            for (var k = 0; k < _lmDistFrom.Length; k++)
            {
                var fromN = _lmDistFrom[k][n];
                var fromT = _lmDistFrom[k][t];
                if (fromN != int.MaxValue && fromT != int.MaxValue)
                {
                    var lb = fromT - fromN;
                    if (lb > h) h = lb;
                }

                var toN = _lmDistTo[k][n];
                var toT = _lmDistTo[k][t];
                if (toN != int.MaxValue && toT != int.MaxValue)
                {
                    var lb = toN - toT;
                    if (lb > h) h = lb;
                }
            }
            return h;
        }

        // -------------------------------------------------------------------
        // Choisit `count` repères bien étalés (heuristique « farthest-first » :
        // chaque nouveau repère est le nœud le plus loin de tous les précédents),
        // puis précalcule, pour chacun, sa distance BFS vers tous les nœuds et
        // depuis tous les nœuds. Coût mémoire : 2 · count · NodeCount entiers
        // (~5 Mo pour 6 repères et 100 000 nœuds).
        //
        // À appeler UNE fois après Build (voir InMemoryGraphService.Reload).
        // -------------------------------------------------------------------
        public void PrepareLandmarks(int count = 6)
        {
            var n = NodeCount;
            if (n == 0) return;
            count = Math.Clamp(count, 1, n);

            var picked = new List<int>();

            // 1er repère : le nœud le plus loin du nœud 0 (bon point de départ).
            var spread = BfsDistances(0, true);
            picked.Add(ArgMaxFinite(spread));

            // spread[i] = distance de i au repère le plus proche déjà choisi.
            spread = BfsDistances(picked[0], true);

            while (picked.Count < count)
            {
                var next = -1;
                var far = 0;
                for (var i = 0; i < n; i++)
                {
                    var d = spread[i];
                    if (d != int.MaxValue && d > far) { far = d; next = i; }
                }
                if (next < 0) break; // plus rien d'utile à couvrir

                picked.Add(next);
                var d2 = BfsDistances(next, true);
                for (var i = 0; i < n; i++)
                    if (d2[i] != int.MaxValue && (spread[i] == int.MaxValue || d2[i] < spread[i]))
                        spread[i] = d2[i];
            }

            _landmarks = picked.ToArray();
            _lmDistFrom = new int[_landmarks.Length][];
            _lmDistTo = new int[_landmarks.Length][];
            for (var k = 0; k < _landmarks.Length; k++)
            {
                _lmDistFrom[k] = BfsDistances(_landmarks[k], true);   // repère -> v
                _lmDistTo[k] = BfsDistances(_landmarks[k], false);    // v -> repère
            }
        }

        // BFS simple (arêtes de poids 1) depuis `start`. forward=true suit les
        // successeurs, forward=false suit les prédécesseurs. int.MaxValue = non
        // atteint.
        private int[] BfsDistances(int start, bool forward)
        {
            var dist = new int[NodeCount];
            Array.Fill(dist, int.MaxValue);
            dist[start] = 0;

            var queue = new Queue<int>();
            queue.Enqueue(start);
            while (queue.Count > 0)
            {
                var u = queue.Dequeue();
                var nd = dist[u] + 1;
                var neighbours = forward ? Successors(u) : Predecessors(u);
                foreach (var v in neighbours)
                    if (dist[v] == int.MaxValue)
                    {
                        dist[v] = nd;
                        queue.Enqueue(v);
                    }
            }
            return dist;
        }

        private static int ArgMaxFinite(int[] values)
        {
            var best = -1;
            var idx = 0;
            for (var i = 0; i < values.Length; i++)
                if (values[i] != int.MaxValue && values[i] > best) { best = values[i]; idx = i; }
            return idx;
        }
    }
}
