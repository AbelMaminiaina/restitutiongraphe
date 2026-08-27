// Le SCAN (chapitre 11 de la spécification, § 11.4).
//
// Idée : faire UNE fois un balayage complet de dbo.LINE_VIS_EDG pour
// regrouper les nœuds par composante connexe (au sens FAIBLE : on ignore le
// sens des arêtes), via une structure Union-Find en mémoire. Le résultat est
// écrit dans dbo.NODE_COMPONENT (NodeId -> ComponentId).
//
// Ensuite, la recherche d'existence d'un chemin (HomeController) commence par
// comparer ComponentId(source) et ComponentId(cible) :
//   - différents  -> il n'existe AUCUN chemin (même non orienté) : réponse
//                    immédiate en O(1), sans lancer de BFS ;
//   - identiques  -> un chemin orienté est possible : on lance le BFS.
//
// La connexité faible est une condition NÉCESSAIRE d'existence d'un chemin :
// le scan donne donc un « non » certain, jamais un faux « non ».
//
// CE SERVICE NE CONTIENT AUCUNE REQUÊTE SQL. Toutes les requêtes sont dans
// les repositories :
//   - LineVisEdgRepository.StreamAllEdges()      : lecture des arêtes ;
//   - NodeComponentRepository.ReplaceAll(...)     : écriture de NODE_COMPONENT ;
//   - NodeComponentRepository.GetComponentIds(...): lecture des composantes.

using System.Diagnostics;

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services;

// Statut du dernier scan exécuté (gardé en mémoire par le singleton).
public record ScanStatus(
    DateTime CompletedAtUtc,
    long NodeCount,
    long EdgeCount,
    int ComponentCount,
    long DurationMs,
    int LargestComponentSize);

// Verdict de la comparaison de composantes pour un couple (source, cible).
public enum ComponentVerdict
{
    DifferentComponents, // aucun chemin, certain
    SameComponent,       // un chemin est possible -> lancer le BFS
    ScanUnavailable,     // scan jamais exécuté, ou un des nœuds absent de NODE_COMPONENT
}

public class GraphScanService
{
    private readonly LineVisEdgRepository _edges;
    private readonly NodeComponentRepository _components;

    // volatile : le statut est écrit par l'action Run (un thread) et lu par
    // les recherches (d'autres threads).
    private volatile ScanStatus? _last;
    public ScanStatus? Last => _last;

    public GraphScanService(LineVisEdgRepository edges, NodeComponentRepository components)
    {
        _edges = edges;
        _components = components;
    }

    // --------------------------------------------------------------------
    // Exécution du scan. Étapes 1-2 : algorithme pur (Union-Find) sur les
    // arêtes fournies par le repository. Étape 3 : persistance déléguée au
    // repository.
    // --------------------------------------------------------------------
    public ScanStatus Run()
    {
        var sw = Stopwatch.StartNew();

        // 1. Balayer toutes les arêtes (repository) et fusionner les îles.
        //    Le sens ne compte pas : deux nœuds reliés par une arête, quel que
        //    soit son sens, sont dans la même composante faible.
        var uf = new UnionFind();
        long edgeCount = 0;
        foreach (var (from, to) in _edges.StreamAllEdges())
        {
            uf.Union(from, to);
            edgeCount++;
        }

        // 2. Attribuer un identifiant de composante (0, 1, 2, …) par racine.
        var componentOfRoot = new Dictionary<string, int>();
        var componentSize = new Dictionary<int, int>();
        var rows = new List<(string NodeId, int ComponentId)>(uf.Nodes.Count);

        foreach (var node in uf.Nodes)
        {
            var root = uf.Find(node);
            if (!componentOfRoot.TryGetValue(root, out var id))
            {
                id = componentOfRoot.Count;
                componentOfRoot[root] = id;
            }

            componentSize[id] = componentSize.GetValueOrDefault(id) + 1;
            rows.Add((node, id));
        }

        // 3. Persister (repository).
        _components.ReplaceAll(rows);

        sw.Stop();

        var status = new ScanStatus(
            CompletedAtUtc: DateTime.UtcNow,
            NodeCount: uf.Nodes.Count,
            EdgeCount: edgeCount,
            ComponentCount: componentOfRoot.Count,
            DurationMs: sw.ElapsedMilliseconds,
            LargestComponentSize: componentSize.Count == 0 ? 0 : componentSize.Values.Max());

        _last = status;
        return status;
    }

    // --------------------------------------------------------------------
    // Comparaison des composantes de deux nœuds, utilisée avant le BFS.
    // --------------------------------------------------------------------
    public ComponentVerdict Compare(string source, string target)
    {
        var (cs, ct) = _components.GetComponentIds(source, target);

        if (cs is null || ct is null)
            return ComponentVerdict.ScanUnavailable;

        return cs.Value != ct.Value
            ? ComponentVerdict.DifferentComponents
            : ComponentVerdict.SameComponent;
    }

    // --------------------------------------------------------------------
    // Union-Find (« disjoint set ») sur des identifiants de nœuds (chaînes).
    // Compression de chemin + union par rang : quasi O(1) amorti par opération.
    // Structure purement en mémoire, aucun accès base.
    // --------------------------------------------------------------------
    private sealed class UnionFind
    {
        private readonly Dictionary<string, string> _parent = new();
        private readonly Dictionary<string, int> _rank = new();

        public IReadOnlyCollection<string> Nodes => _parent.Keys;

        private void Ensure(string x)
        {
            if (_parent.ContainsKey(x)) return;
            _parent[x] = x;
            _rank[x] = 0;
        }

        public string Find(string x)
        {
            Ensure(x);
            while (_parent[x] != x)
            {
                _parent[x] = _parent[_parent[x]]; // compression de chemin (halving)
                x = _parent[x];
            }
            return x;
        }

        public void Union(string a, string b)
        {
            var ra = Find(a);
            var rb = Find(b);
            if (ra == rb) return;

            if (_rank[ra] < _rank[rb])
                (ra, rb) = (rb, ra);
            _parent[rb] = ra;
            if (_rank[ra] == _rank[rb])
                _rank[ra]++;
        }
    }
}
