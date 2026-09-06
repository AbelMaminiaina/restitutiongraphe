// § 11.7 — le graphe orienté chargé en mémoire au démarrage.
//
// Une fois chargé, les quatre algorithmes de plus court chemin tournent
// entièrement en RAM (voir DirectedGraph) : plus aucun aller-retour SQL par
// palier. Latence divisée par un à deux ordres de grandeur.
//
// Ce service ne contient AUCUNE requête SQL : les arêtes viennent du
// repository (LineVisEdgRepository.StreamAllDirectedEdges).
//
// C# 8.0 : pas de `record` (GraphStatus est une classe), pas d'async — le
// préchargement se fait sur un Thread d'arrière-plan, pas via Task.Run.
// GraphPreloader retourne Task.CompletedTask uniquement parce que l'interface
// IHostedService l'impose : ce n'est ni `async` ni `await`.

using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services
{
    public sealed class GraphStatus
    {
        public DateTime LoadedAtUtc { get; }
        public int NodeCount { get; }
        public int EdgeCount { get; }
        public long DurationMs { get; }
        public long ApproximateBytes { get; }
        public int LandmarkCount { get; }
        public long LandmarkMs { get; }

        public GraphStatus(DateTime loadedAtUtc, int nodeCount, int edgeCount,
            long durationMs, long approximateBytes, int landmarkCount, long landmarkMs)
        {
            LoadedAtUtc = loadedAtUtc;
            NodeCount = nodeCount;
            EdgeCount = edgeCount;
            DurationMs = durationMs;
            ApproximateBytes = approximateBytes;
            LandmarkCount = landmarkCount;
            LandmarkMs = landmarkMs;
        }
    }

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

        public bool IsLoaded => _graph != null;
        public GraphStatus? Status => _status;

        // (Re)charge le graphe complet en mémoire. Appelé au démarrage
        // (GraphPreloader) et par POST /Scan/ReloadGraph.
        public GraphStatus Reload()
        {
            var sw = Stopwatch.StartNew();
            var graph = DirectedGraph.Build(_edges.StreamAllDirectedEdges());
            sw.Stop();

            // Repères ALT pour A* : quelques BFS complets, une seule fois.
            var swLm = Stopwatch.StartNew();
            graph.PrepareLandmarks(6);
            swLm.Stop();

            var status = new GraphStatus(
                DateTime.UtcNow,
                graph.NodeCount,
                graph.EdgeCount,
                sw.ElapsedMilliseconds,
                graph.ApproximateBytes,
                graph.LandmarkCount,
                swLm.ElapsedMilliseconds);

            _graph = graph;
            _status = status;

            _logger.LogInformation(
                "Graphe en mémoire chargé : {Nodes:N0} nœuds, {Edges:N0} arêtes, {Ms} ms, ~{Mb:N0} Mo "
                + "(+ {Lm} repères A* en {LmMs} ms)",
                status.NodeCount, status.EdgeCount, status.DurationMs,
                status.ApproximateBytes / (1024 * 1024), status.LandmarkCount, status.LandmarkMs);

            return status;
        }

        // Renvoie le résultat en mémoire, ou null si le graphe n'est pas (encore)
        // chargé : l'appelant retombe alors sur le BFS SQL. Une méthode par
        // algorithme — toutes donnent le même chemin (poids uniformes), seul le
        // temps d'exécution diffère.
        public ShortestPathResult? ShortestPath(string source, string target, int maxDepth)
            => _graph?.ShortestPath(source, target, maxDepth);

        public ShortestPathResult? ShortestPathDijkstra(string source, string target, int maxCost)
            => _graph?.ShortestPathDijkstra(source, target, maxCost);

        public ShortestPathResult? ShortestPathDijkstraBi(string source, string target, int maxCost)
            => _graph?.ShortestPathDijkstraBi(source, target, maxCost);

        public ShortestPathResult? ShortestPathAStar(string source, string target, int maxCost)
            => _graph?.ShortestPathAStar(source, target, maxCost);
    }

    // Charge le graphe en arrière-plan au démarrage de l'application : le
    // serveur accepte les requêtes tout de suite, et les premières recherches
    // utilisent le BFS SQL jusqu'à ce que le graphe soit prêt.
    //
    // Pas de Task.Run : on lance un Thread dédié (IsBackground = true pour ne
    // pas empêcher l'arrêt du processus).
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
            var thread = new Thread(LoadGraph)
            {
                IsBackground = true,
                Name = "graph-preloader",
            };
            thread.Start();
            return Task.CompletedTask;
        }

        private void LoadGraph()
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
        }

        public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
    }
}
