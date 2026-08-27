// § 11.7 — le graphe orienté chargé en mémoire au démarrage.
//
// Une fois chargé, le BFS bidirectionnel tourne entièrement en RAM (voir
// DirectedGraph) : plus aucun aller-retour SQL par palier. Latence divisée
// par un à deux ordres de grandeur.
//
// Ce service ne contient AUCUNE requête SQL : les arêtes viennent du
// repository (LineVisEdgRepository.StreamAllDirectedEdges).

using System.Diagnostics;

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services;

public record GraphStatus(
    DateTime LoadedAtUtc,
    int NodeCount,
    int EdgeCount,
    long DurationMs,
    long ApproximateBytes);

public class InMemoryGraphService
{
    private readonly LineVisEdgRepository _edges;
    private readonly ILogger<InMemoryGraphService> _logger;

    private volatile DirectedGraph? _graph;
    private volatile GraphStatus? _status;

    public InMemoryGraphService(LineVisEdgRepository edges, ILogger<InMemoryGraphService> logger)
    {
        _edges = edges;
        _logger = logger;
    }

    public bool IsLoaded => _graph is not null;
    public GraphStatus? Status => _status;

    // (Re)charge le graphe complet en mémoire. Appelé au démarrage
    // (GraphPreloader) et par POST /Scan/ReloadGraph.
    public GraphStatus Reload()
    {
        var sw = Stopwatch.StartNew();
        var graph = DirectedGraph.Build(_edges.StreamAllDirectedEdges());
        sw.Stop();

        var status = new GraphStatus(
            LoadedAtUtc: DateTime.UtcNow,
            NodeCount: graph.NodeCount,
            EdgeCount: graph.EdgeCount,
            DurationMs: sw.ElapsedMilliseconds,
            ApproximateBytes: graph.ApproximateBytes);

        _graph = graph;
        _status = status;

        _logger.LogInformation(
            "Graphe en mémoire chargé : {Nodes:N0} nœuds, {Edges:N0} arêtes, {Ms} ms, ~{Mb:N0} Mo",
            status.NodeCount, status.EdgeCount, status.DurationMs, status.ApproximateBytes / (1024 * 1024));

        return status;
    }

    // Renvoie le résultat du BFS en mémoire, ou null si le graphe n'est pas
    // (encore) chargé : l'appelant retombe alors sur le BFS SQL.
    public ShortestPathResult? ShortestPath(string source, string target, int maxDepth)
        => _graph?.ShortestPath(source, target, maxDepth);
}

// Charge le graphe en tâche de fond au démarrage de l'application : le
// serveur accepte les requêtes tout de suite, et les premières recherches
// utilisent le BFS SQL jusqu'à ce que le graphe soit prêt.
public class GraphPreloader : IHostedService
{
    private readonly InMemoryGraphService _graph;
    private readonly ILogger<GraphPreloader> _logger;

    public GraphPreloader(InMemoryGraphService graph, ILogger<GraphPreloader> logger)
    {
        _graph = graph;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _ = Task.Run(() =>
        {
            try
            {
                _graph.Reload();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex,
                    "Chargement du graphe en mémoire échoué — la recherche utilisera le BFS SQL");
            }
        }, cancellationToken);

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
