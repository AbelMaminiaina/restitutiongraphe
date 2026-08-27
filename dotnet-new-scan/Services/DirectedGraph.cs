// Graphe orienté chargé INTÉGRALEMENT en mémoire (§ 11.7 de la spécification).
//
// Représentation CSR (Compressed Sparse Row) : compacte et rapide à parcourir.
//   _fwdOffset[u].._fwdOffset[u+1]  -> tranche de _fwdTarget = successeurs de u
//   _revOffset[u].._revOffset[u+1]  -> tranche de _revSource = prédécesseurs de u
// Pour n nœuds et m arêtes : 2·(n+1) + 2·m entiers, plus les noms des nœuds.
// Ex. 2 000 000 nœuds / 8 000 000 arêtes ≈ 80 Mo pour les tableaux CSR.
//
// Le BFS bidirectionnel s'exécute ici SANS aucun accès base : plus d'aller-
// retour SQL par palier. Aucune requête SQL dans ce fichier.

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services;

public sealed class DirectedGraph
{
    // Garde-fou : nombre max de nœuds visités par sens. En mémoire on peut
    // être bien plus généreux qu'avec le BFS SQL (30 000) car il n'y a plus de
    // latence par palier — seulement de la RAM transitoire.
    private const int MaxVisitedPerSide = 300_000;

    private readonly Dictionary<string, int> _index;
    private readonly string[] _names;
    private readonly int[] _fwdOffset;
    private readonly int[] _fwdTarget;
    private readonly int[] _revOffset;
    private readonly int[] _revSource;

    public int NodeCount => _names.Length;
    public int EdgeCount => _fwdTarget.Length;

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
            return new ShortestPathResult([], false); // nœud inconnu

        if (s == t)
            return new ShortestPathResult([_names[s]], true);

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

        return new ShortestPathResult([], false);
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
}
