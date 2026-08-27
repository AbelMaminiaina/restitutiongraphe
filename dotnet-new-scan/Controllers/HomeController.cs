// Controller (MVC) : une seule action, Index, qui sert le formulaire vide
// (GET / sans paramètre) et le résultat d'une recherche
// (GET /?source=...&target=...). Toute la mise en forme est faite par la vue.
//
// Ordre des vérifications, du plus précis au plus fragile, avant le BFS :
//   1. condensation SCC (§ 11.5) : verdict d'existence orientée EXACT.
//        NotReachable -> « aucun chemin », sans BFS.
//   2. sinon (SCC pas calculée) : scan des composantes faibles (§ 11.4).
//        composantes différentes -> « aucun chemin », sans BFS.
//   3. sinon : BFS bidirectionnel —
//        sur le GRAPHE EN MÉMOIRE (§ 11.7) s'il est chargé,
//        sinon par requêtes SQL palier par palier (comme dotnet-mvc/).

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Controllers;

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
    public IActionResult Index(string? source, string? target, int maxDepth = 12)
    {
        var model = new PathViewModel
        {
            Source = (source ?? "").Trim(),
            Target = (target ?? "").Trim(),
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

        var cacheKey = $"path:{model.Source}:{model.Target}:{effectiveMaxDepth}";
        model.FromCache = _cache.TryGetValue(cacheKey, out _);

        var solvedInMemory = false;

        var result = _cache.GetOrCreate(cacheKey, entry =>
        {
            entry.Size = 1;
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);

            if (sccReach == SccReach.NotReachable)
                return new ShortestPathResult([], false);

            if (weakVerdict == ComponentVerdict.DifferentComponents)
                return new ShortestPathResult([], false);

            // BFS : graphe en mémoire (§ 11.7) si chargé, sinon SQL.
            var inMemory = _graph.ShortestPath(model.Source, model.Target, effectiveMaxDepth);
            if (inMemory is not null)
            {
                solvedInMemory = true;
                return inMemory;
            }

            return _repository.ShortestPath(model.Source, model.Target, effectiveMaxDepth);
        })!;

        model.Found = result.Found;
        model.Path = result.Path;
        model.SolvedInMemory = solvedInMemory;
        model.SkippedByScc = !result.Found && sccReach == SccReach.NotReachable;
        model.SkippedByScan = !result.Found && sccReach != SccReach.NotReachable
                              && weakVerdict == ComponentVerdict.DifferentComponents;

        if (result.Found && result.Path.Count > 1)
            model.Edges = _repository.DescribePath(result.Path);

        return View(model);
    }
}
