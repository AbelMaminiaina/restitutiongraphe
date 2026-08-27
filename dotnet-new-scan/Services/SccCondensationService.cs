// La CONDENSATION SCC (chapitre 11 de la spécification, § 11.5).
//
// Le scan de GraphScanService (§ 11.4) ne donne qu'un « non » certain quand
// les nœuds sont dans des composantes connexes FAIBLES différentes. Il ne
// tranche pas le cas « même composante faible » : il faut alors un BFS.
//
// La condensation SCC va plus loin : elle donne un OUI/NON EXACT pour
// l'existence d'un chemin ORIENTÉ, sans BFS.
//
//   1. Calculer les composantes fortement connexes (SCC) — algorithme de
//      Kosaraju, deux parcours en profondeur (itératifs), O(n + m).
//      Dans une SCC, tout nœud atteint tout autre : elles se contractent
//      chacune en un « super-nœud ».
//   2. Le graphe des super-nœuds — le « graphe condensé » — est TOUJOURS un
//      DAG (aucun cycle), et beaucoup plus petit.
//   3. Existence d'un chemin u -> v  <=>  SccId(v) est atteignable depuis
//      SccId(u) dans le graphe condensé (ou SccId(u) == SccId(v)).
//
// Ce service ne contient AUCUNE requête SQL : les arêtes viennent de
// LineVisEdgRepository, la persistance et les lectures de SccRepository.

using System.Diagnostics;

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services;

public record SccStatus(
    DateTime CompletedAtUtc,
    long NodeCount,
    long EdgeCount,
    int SccCount,
    int CondensedEdgeCount,
    int LargestSccSize,
    long DurationMs);

public enum SccReach
{
    Reachable,     // un chemin orienté existe, certain
    NotReachable,  // aucun chemin orienté, certain
    Unavailable,   // condensation pas encore faite, ou nœud inconnu
}

public class SccCondensationService
{
    private readonly LineVisEdgRepository _edges;
    private readonly SccRepository _scc;

    private volatile SccStatus? _last;
    public SccStatus? Last => _last;

    // Cache du graphe condensé (petit). Rechargé à chaque condensation.
    private volatile Dictionary<int, List<int>>? _condensed;

    public SccCondensationService(LineVisEdgRepository edges, SccRepository scc)
    {
        _edges = edges;
        _scc = scc;
    }

    // --------------------------------------------------------------------
    // Exécution de la condensation.
    // --------------------------------------------------------------------
    public SccStatus Run()
    {
        var sw = Stopwatch.StartNew();

        // 0. Charger les arêtes ORIENTÉES en mémoire, en indexant les nœuds
        //    par un entier (0..n-1) pour des parcours rapides.
        var index = new Dictionary<string, int>();
        var names = new List<string>();
        var edgeList = new List<(int From, int To)>();

        int IndexOf(string node)
        {
            if (index.TryGetValue(node, out var i)) return i;
            i = names.Count;
            index[node] = i;
            names.Add(node);
            return i;
        }

        foreach (var (from, to) in _edges.StreamAllDirectedEdges())
            edgeList.Add((IndexOf(from), IndexOf(to)));

        var n = names.Count;
        var adj = BuildAdjacency(n, edgeList, reverse: false);
        var radj = BuildAdjacency(n, edgeList, reverse: true);

        // 1. Kosaraju — passe 1 : ordre de fin de parcours (post-ordre) sur adj.
        var order = PostOrder(n, adj);

        // 2. Kosaraju — passe 2 : parcours de radj dans l'ordre inverse ;
        //    chaque arbre de parcours est une SCC.
        var sccId = new int[n];
        var sccSize = new List<int>();
        var visited = new bool[n];
        var sccCount = 0;

        for (var i = order.Count - 1; i >= 0; i--)
        {
            var start = order[i];
            if (visited[start]) continue;

            var size = 0;
            var stack = new Stack<int>();
            stack.Push(start);
            visited[start] = true;
            while (stack.Count > 0)
            {
                var u = stack.Pop();
                sccId[u] = sccCount;
                size++;
                foreach (var w in radj[u])
                    if (!visited[w]) { visited[w] = true; stack.Push(w); }
            }
            sccSize.Add(size);
            sccCount++;
        }

        // 3. Graphe condensé : une arête (sccId[u] -> sccId[v]) par arête du
        //    graphe d'origine dont les deux extrémités sont dans des SCC
        //    différentes (dédupliquée).
        var condensedEdges = new HashSet<(int, int)>();
        foreach (var (from, to) in edgeList)
            if (sccId[from] != sccId[to])
                condensedEdges.Add((sccId[from], sccId[to]));

        // 4. Persister (repository).
        _scc.ReplaceAll(
            names.Select((name, i) => (name, sccId[i])),
            condensedEdges);

        _condensed = ToAdjacency(condensedEdges);

        sw.Stop();

        var status = new SccStatus(
            CompletedAtUtc: DateTime.UtcNow,
            NodeCount: n,
            EdgeCount: edgeList.Count,
            SccCount: sccCount,
            CondensedEdgeCount: condensedEdges.Count,
            LargestSccSize: sccSize.Count == 0 ? 0 : sccSize.Max(),
            DurationMs: sw.ElapsedMilliseconds);

        _last = status;
        return status;
    }

    // --------------------------------------------------------------------
    // Verdict EXACT d'existence d'un chemin orienté, sans BFS sur le graphe
    // d'origine — seulement sur le petit graphe condensé.
    // --------------------------------------------------------------------
    public SccReach Reachable(string source, string target)
    {
        var (s, t) = _scc.GetSccIds(source, target);
        if (s is null || t is null)
            return SccReach.Unavailable;

        if (s.Value == t.Value)
            return SccReach.Reachable; // même SCC = mutuellement atteignables

        var adjacency = _condensed ??= _scc.LoadCondensedAdjacency();

        // BFS sur le graphe condensé (quelques centaines de super-nœuds).
        var seen = new HashSet<int> { s.Value };
        var queue = new Queue<int>();
        queue.Enqueue(s.Value);
        while (queue.Count > 0)
        {
            var u = queue.Dequeue();
            if (u == t.Value)
                return SccReach.Reachable;
            if (adjacency.TryGetValue(u, out var succ))
                foreach (var w in succ)
                    if (seen.Add(w))
                        queue.Enqueue(w);
        }

        return SccReach.NotReachable;
    }

    // --------------------------------------------------------------------
    // Outils : construction d'adjacence + post-ordre itératif.
    // --------------------------------------------------------------------
    private static List<int>[] BuildAdjacency(int n, List<(int From, int To)> edges, bool reverse)
    {
        var adj = new List<int>[n];
        for (var i = 0; i < n; i++) adj[i] = new List<int>();
        foreach (var (from, to) in edges)
        {
            if (reverse) adj[to].Add(from);
            else adj[from].Add(to);
        }
        return adj;
    }

    private static Dictionary<int, List<int>> ToAdjacency(HashSet<(int, int)> edges)
    {
        var adj = new Dictionary<int, List<int>>();
        foreach (var (from, to) in edges)
        {
            if (!adj.TryGetValue(from, out var list))
                adj[from] = list = new List<int>();
            list.Add(to);
        }
        return adj;
    }

    // DFS itératif (pile explicite), renvoie les nœuds dans l'ordre où leur
    // exploration se termine (post-ordre). Évite le débordement de pile sur
    // 100 000 nœuds.
    private static List<int> PostOrder(int n, List<int>[] adj)
    {
        var order = new List<int>(n);
        var visited = new bool[n];
        var finished = new bool[n];
        var stack = new Stack<int>();

        for (var s = 0; s < n; s++)
        {
            if (visited[s]) continue;
            stack.Push(s);
            while (stack.Count > 0)
            {
                var u = stack.Peek();
                if (finished[u]) { stack.Pop(); continue; }
                if (visited[u])
                {
                    // tous les descendants de u ont été traités
                    stack.Pop();
                    finished[u] = true;
                    order.Add(u);
                    continue;
                }
                visited[u] = true;
                foreach (var w in adj[u])
                    if (!visited[w]) stack.Push(w);
            }
        }

        return order;
    }
}
