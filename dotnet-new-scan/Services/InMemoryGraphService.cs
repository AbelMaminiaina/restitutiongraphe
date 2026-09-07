// § 11.7 — le graphe orienté chargé en mémoire au démarrage.
//
// Une fois chargé, les quatre algorithmes de plus court chemin tournent
// entièrement en RAM (voir DirectedGraph). Les arêtes viennent de
// GraphDataProvider (SQL Server ou graphe généré — l'un ou l'autre selon le
// poste, voir GraphDataProvider). Ce service ne contient AUCUNE requête SQL.
//
// C# 8.0 : pas de `record` (GraphStatus est une classe), pas d'async — le
// préchargement se fait sur un Thread d'arrière-plan. EnsureLoaded() construit
// le graphe de façon synchrone (sous verrou) si une requête arrive avant que
// le Thread ait fini.

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
        public string SourceDescription { get; }

        public GraphStatus(DateTime loadedAtUtc, int nodeCount, int edgeCount,
            long durationMs, long approximateBytes, int landmarkCount, long landmarkMs,
            string sourceDescription)
        {
            LoadedAtUtc = loadedAtUtc;
            NodeCount = nodeCount;
            EdgeCount = edgeCount;
            DurationMs = durationMs;
            ApproximateBytes = approximateBytes;
            LandmarkCount = landmarkCount;
            LandmarkMs = landmarkMs;
            SourceDescription = sourceDescription;
        }
    }

    public class InMemoryGraphService
    {
        private readonly GraphDataProvider _data;
        private readonly ILogger<InMemoryGraphService> _logger;
        private readonly object _loadLock = new object();

        private volatile DirectedGraph? _graph;
        private volatile GraphStatus? _status;

        public InMemoryGraphService(GraphDataProvider data, ILogger<InMemoryGraphService> logger)
        {
            _data = data;
            _logger = logger;
        }

        public bool IsLoaded => _graph != null;
        public GraphStatus? Status => _status;

        // Renvoie le graphe, en le construisant maintenant (sous verrou) s'il
        // n'est pas encore prêt. Appelé par HomeController avant chaque
        // recherche : le préchargement en tâche de fond n'est qu'une
        // optimisation, ceci garantit qu'une recherche marche toujours.
        public DirectedGraph EnsureLoaded()
        {
            var g = _graph;
            if (g != null) return g;

            lock (_loadLock)
            {
                if (_graph == null) Reload();
                return _graph!;
            }
        }

        // (Re)charge le graphe complet en mémoire. Appelé au démarrage
        // (GraphPreloader), par EnsureLoaded(), et par POST /Scan/ReloadGraph.
        public GraphStatus Reload()
        {
            var sw = Stopwatch.StartNew();
            var graph = DirectedGraph.Build(_data.StreamAllDirectedEdges());
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
                swLm.ElapsedMilliseconds,
                _data.Description);

            _graph = graph;
            _status = status;

            _logger.LogInformation(
                "Graphe en mémoire chargé : {Nodes:N0} nœuds, {Edges:N0} arêtes, {Ms} ms, ~{Mb:N0} Mo "
                + "(+ {Lm} repères A* en {LmMs} ms) — source : {Source}",
                status.NodeCount, status.EdgeCount, status.DurationMs,
                status.ApproximateBytes / (1024 * 1024), status.LandmarkCount, status.LandmarkMs,
                status.SourceDescription);

            return status;
        }

        // Une méthode par algorithme. Le graphe est garanti chargé (l'appelant
        // fait EnsureLoaded()), donc ces méthodes ne renvoient jamais null en
        // pratique — le `?` couvre seulement le cas théorique « pas encore
        // chargé ». Toutes donnent le même chemin (poids uniformes), seul le
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
    // serveur accepte les requêtes tout de suite. Pas de Task.Run : un Thread
    // dédié (IsBackground = true pour ne pas empêcher l'arrêt du processus).
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
                _graph.EnsureLoaded();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex,
                    "Préchargement du graphe échoué — il sera construit à la première recherche");
            }
        }

        public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
    }
}
