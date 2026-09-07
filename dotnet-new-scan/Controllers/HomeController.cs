// Controller (MVC) : une seule action, Index, qui sert le formulaire vide
// (GET / sans paramètre) et le résultat d'une recherche
// (GET /?source=...&target=...). Toute la mise en forme est faite par la vue.
//
// Ordre des vérifications, avant le parcours :
//   1. (mode SQL seulement) condensation SCC (§ 11.5, si calculée) : verdict
//        d'existence orientée EXACT. NotReachable -> « aucun chemin », sans parcours.
//   2. (mode SQL seulement) sinon : scan des composantes faibles (§ 11.4, si
//        calculé). Composantes différentes -> « aucun chemin », sans parcours.
//   3. cache applicatif (5 min).
//   4. sinon : l'algorithme choisi (?algo=), sur le GRAPHE EN MÉMOIRE (§ 11.7).
//        EnsureLoaded() garantit qu'il est construit (préchargement = simple
//        optimisation).
//
// En mode « graphe généré » (aucune base), les étapes 1-2 sont sautées : le
// graphe est petit, tout algorithme est sous la milliseconde.

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
        private readonly GraphDataProvider _data;
        private readonly GraphScanService _scan;
        private readonly SccCondensationService _sccService;
        private readonly InMemoryGraphService _graph;
        private readonly IMemoryCache _cache;

        public HomeController(
            GraphDataProvider data,
            GraphScanService scan,
            SccCondensationService sccService,
            InMemoryGraphService graph,
            IMemoryCache cache)
        {
            _data = data;
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
                SourceDescription = _data.Description,
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

            // Pré-calculs : uniquement en mode SQL (grand graphe). En mode
            // graphe généré, on va directement au parcours.
            var sccReach = SccReach.Unavailable;
            var weakVerdict = ComponentVerdict.ScanUnavailable;
            if (_data.ScanAvailable)
            {
                sccReach = _sccService.Reachable(model.Source, model.Target);
                weakVerdict = sccReach == SccReach.Unavailable
                    ? _scan.Compare(model.Source, model.Target)
                    : ComponentVerdict.ScanUnavailable;
            }

            // La clé de cache inclut l'algo : chaque algorithme est mémorisé
            // séparément (même si, à poids uniformes, ils donnent le même chemin).
            var cacheKey = $"path:{model.Algo}:{model.Source}:{model.Target}:{effectiveMaxDepth}";
            model.FromCache = _cache.TryGetValue(cacheKey, out _);

            var solvedWith = algoKey;

            var result = _cache.GetOrCreate(cacheKey, entry =>
            {
                entry.Size = 1;
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);

                if (sccReach == SccReach.NotReachable)
                    return new ShortestPathResult(new List<string>(), false);

                if (weakVerdict == ComponentVerdict.DifferentComponents)
                    return new ShortestPathResult(new List<string>(), false);

                // Le graphe en mémoire est garanti prêt (le construit maintenant
                // si le préchargement n'a pas encore fini).
                _graph.EnsureLoaded();

                switch (algoKey)
                {
                    case "dijkstra":
                        return _graph.ShortestPathDijkstra(model.Source, model.Target, effectiveMaxDepth)!;
                    case "dijkstra-bi":
                        return _graph.ShortestPathDijkstraBi(model.Source, model.Target, effectiveMaxDepth)!;
                    case "astar":
                        return _graph.ShortestPathAStar(model.Source, model.Target, effectiveMaxDepth)!;
                    default:
                        return _graph.ShortestPath(model.Source, model.Target, effectiveMaxDepth)!;
                }
            })!;

            model.Found = result.Found;
            model.Path = result.Path;
            model.SolvedInMemory = true;
            model.SolvedWith = solvedWith;
            model.SkippedByScc = !result.Found && sccReach == SccReach.NotReachable;
            model.SkippedByScan = !result.Found && sccReach != SccReach.NotReachable
                                  && weakVerdict == ComponentVerdict.DifferentComponents;

            if (result.Found && result.Path.Count > 1)
                model.Edges = _data.DescribePath(result.Path);

            return View(model);
        }
    }
}
