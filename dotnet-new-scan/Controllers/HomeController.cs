// Controller (MVC) : une seule action, Index, qui sert le formulaire vide
// (GET / sans paramètre) et le résultat d'une recherche
// (GET /?source=...&target=...). Toute la mise en forme est faite par la vue.
//
// Ordre des vérifications, du plus précis au plus fragile, avant le parcours :
//   1. condensation SCC (§ 11.5) : verdict d'existence orientée EXACT.
//        NotReachable -> « aucun chemin », sans parcours.
//   2. sinon (SCC pas calculée) : scan des composantes faibles (§ 11.4).
//        composantes différentes -> « aucun chemin », sans parcours.
//   3. sinon : plus court chemin, selon le menu déroulant « algo » —
//        - "bfs" (défaut)   : BFS bidirectionnel ;
//        - "dijkstra"       : Dijkstra (file de priorité) ;
//        - "dijkstra-bi"    : Dijkstra bidirectionnel ;
//        - "astar"          : A* avec heuristique ALT (repères).
//        Tout se joue sur le GRAPHE EN MÉMOIRE (§ 11.7) ; s'il n'est pas encore
//        chargé, repli sur le BFS SQL palier par palier (comme dotnet-mvc/).
//        Les arêtes ayant toutes le même poids, les quatre donnent le même
//        chemin — seul le temps d'exécution change (voir docs/algorithmes-chemin).

using System;
using System.Collections.Generic;

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Controllers
{
    public class HomeController : Controller
    {
        private readonly LineVisEdgRepository _repository;
        private readonly GraphScanService _scan;
        private readonly SccCondensationService _sccService;
        private readonly InMemoryGraphService _graph;
        private readonly IMemoryCache _cache;

        public HomeController(
            LineVisEdgRepository repository,
            GraphScanService scan,
            SccCondensationService sccService,
            InMemoryGraphService graph,
            IMemoryCache cache)
        {
            _repository = repository;
            _scan = scan;
            _sccService = sccService;
            _graph = graph;
            _cache = cache;
        }

        [HttpGet]
        public IActionResult Index(string? source, string? target, string? algo, int maxDepth = 12)
        {
            // algo vient du menu déroulant du formulaire. On normalise sur l'une
            // des quatre valeurs connues (défaut : "bfs").
            var algoKey = (algo ?? "").Trim().ToLowerInvariant() switch
            {
                "dijkstra" => "dijkstra",
                "dijkstra-bi" => "dijkstra-bi",
                "astar" => "astar",
                _ => "bfs",
            };

            var model = new PathViewModel
            {
                Source = (source ?? "").Trim(),
                Target = (target ?? "").Trim(),
                Algo = algoKey,
            };

            if (model.Source.Length == 0 && model.Target.Length == 0)
                return View(model);

            model.Searched = true;

            if (model.Source.Length == 0 || model.Target.Length == 0)
            {
                model.InputError = "Renseigne un nœud source ET un nœud cible.";
                return View(model);
            }

            var effectiveMaxDepth = Math.Min(maxDepth, 20);

            // Pré-calculs : condensation SCC (exacte) puis composantes faibles.
            var sccReach = _sccService.Reachable(model.Source, model.Target);
            var weakVerdict = sccReach == SccReach.Unavailable
                ? _scan.Compare(model.Source, model.Target)
                : ComponentVerdict.ScanUnavailable;

            // La clé de cache inclut l'algo : chaque algorithme est mémorisé
            // séparément (même si, à poids uniformes, ils donnent le même chemin).
            var cacheKey = $"path:{model.Algo}:{model.Source}:{model.Target}:{effectiveMaxDepth}";
            model.FromCache = _cache.TryGetValue(cacheKey, out _);

            var solvedInMemory = false;
            var solvedWith = "bfs";

            var result = _cache.GetOrCreate(cacheKey, entry =>
            {
                entry.Size = 1;
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);

                if (sccReach == SccReach.NotReachable)
                    return new ShortestPathResult(new List<string>(), false);

                if (weakVerdict == ComponentVerdict.DifferentComponents)
                    return new ShortestPathResult(new List<string>(), false);

                // Algorithme demandé, sur le graphe en mémoire (§ 11.7).
                ShortestPathResult? inMemory;
                switch (algoKey)
                {
                    case "dijkstra":
                        inMemory = _graph.ShortestPathDijkstra(model.Source, model.Target, effectiveMaxDepth);
                        break;
                    case "dijkstra-bi":
                        inMemory = _graph.ShortestPathDijkstraBi(model.Source, model.Target, effectiveMaxDepth);
                        break;
                    case "astar":
                        inMemory = _graph.ShortestPathAStar(model.Source, model.Target, effectiveMaxDepth);
                        break;
                    default:
                        inMemory = _graph.ShortestPath(model.Source, model.Target, effectiveMaxDepth);
                        break;
                }

                if (inMemory != null)
                {
                    solvedInMemory = true;
                    solvedWith = algoKey;
                    return inMemory;
                }

                // Graphe pas encore chargé : repli sur le BFS SQL palier par palier
                // (poids uniformes -> même chemin de toute façon).
                return _repository.ShortestPath(model.Source, model.Target, effectiveMaxDepth);
            })!;

            model.Found = result.Found;
            model.Path = result.Path;
            model.SolvedInMemory = solvedInMemory;
            model.SolvedWith = solvedWith;
            model.SkippedByScc = !result.Found && sccReach == SccReach.NotReachable;
            model.SkippedByScan = !result.Found && sccReach != SccReach.NotReachable
                                  && weakVerdict == ComponentVerdict.DifferentComponents;

            if (result.Found && result.Path.Count > 1)
                model.Edges = _repository.DescribePath(result.Path);

            return View(model);
        }
    }
}
