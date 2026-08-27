// Controller (MVC) : une seule action, Index, qui sert le formulaire vide
// (GET / sans paramètre) et le résultat d'une recherche
// (GET /?source=...&target=...). Toute la mise en forme est faite par la vue.
//
// Ordre des vérifications, du plus précis au plus fragile, avant le BFS :
//   1. condensation SCC (§ 11.5) : verdict d'existence orientée EXACT.
//        NotReachable -> « aucun chemin », sans BFS.
//        Reachable    -> un chemin existe ; on lance quand même le BFS pour
//                        en récupérer le tracé (chaîne de nœuds + tableau).
//   2. sinon (SCC pas calculée) : scan des composantes faibles (§ 11.4).
//        composantes différentes -> « aucun chemin », sans BFS.
//   3. sinon : BFS bidirectionnel sur LINE_VIS_EDG (comme dotnet-mvc/).

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
    private readonly IMemoryCache _cache;

    public HomeController(
        LineVisEdgRepository repository,
        GraphScanService scan,
        SccCondensationService sccService,
        IMemoryCache cache)
    {
        _repository = repository;
        _scan = scan;
        _sccService = sccService;
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

        var result = _cache.GetOrCreate(cacheKey, entry =>
        {
            entry.Size = 1;
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);

            if (sccReach == SccReach.NotReachable)
                return new ShortestPathResult([], false); // NON exact, pas de BFS

            if (weakVerdict == ComponentVerdict.DifferentComponents)
                return new ShortestPathResult([], false); // NON (îles différentes), pas de BFS

            // SCC Reachable / Unavailable, îles identiques ou inconnues :
            // le BFS reste la source de vérité (et fournit le tracé du chemin).
            return _repository.ShortestPath(model.Source, model.Target, effectiveMaxDepth);
        })!;

        model.Found = result.Found;
        model.Path = result.Path;
        model.SkippedByScc = !result.Found && sccReach == SccReach.NotReachable;
        model.SkippedByScan = !result.Found && sccReach != SccReach.NotReachable
                              && weakVerdict == ComponentVerdict.DifferentComponents;

        if (result.Found && result.Path.Count > 1)
            model.Edges = _repository.DescribePath(result.Path);

        return View(model);
    }
}
