// Controller (MVC) : une seule action, Index, qui sert à la fois le
// formulaire vide (GET / sans paramètre) et le résultat d'une recherche
// (GET /?source=...&target=...). Toute la mise en forme est faite par la vue
// Razor associée (Views/Home/Index.cshtml) — le contrôleur se contente de
// remplir un PathViewModel.

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using PathFinder.RazorMvc.Models;

namespace PathFinder.RazorMvc.Controllers;

public class HomeController : Controller
{
    private readonly LineVisEdgRepository _repository;
    private readonly IMemoryCache _cache;

    public HomeController(LineVisEdgRepository repository, IMemoryCache cache)
    {
        _repository = repository;
        _cache = cache;
    }

    // [FromQuery] : les valeurs viennent de la chaîne de requête de l'URL
    // (le formulaire de la vue est un <form method="get">).
    [HttpGet]
    public IActionResult Index(string? source, string? target, int maxDepth = 12)
    {
        var model = new PathViewModel
        {
            Source = (source ?? "").Trim(),
            Target = (target ?? "").Trim(),
        };

        // Aucun des deux champs renseigné : on affiche juste le formulaire vide,
        // sans message d'erreur (première visite de la page).
        if (model.Source.Length == 0 && model.Target.Length == 0)
            return View(model);

        model.Searched = true;

        if (model.Source.Length == 0 || model.Target.Length == 0)
        {
            model.InputError = "Renseigne un nœud source ET un nœud cible.";
            return View(model);
        }

        var effectiveMaxDepth = Math.Min(maxDepth, 20);
        var cacheKey = $"path:{model.Source}:{model.Target}:{effectiveMaxDepth}";

        // Cache applicatif : mémorise le résultat par (source, cible, maxDepth),
        // y compris les « aucun chemin » (les recherches les plus coûteuses).
        var result = _cache.GetOrCreate(cacheKey, entry =>
        {
            entry.Size = 1;
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            return _repository.ShortestPath(model.Source, model.Target, effectiveMaxDepth);
        })!;

        model.Found = result.Found;
        model.Path = result.Path;

        // Chemin trouvé et non trivial : on relit la transformation de chaque
        // arête pour le tableau détaillé de la vue.
        if (result.Found && result.Path.Count > 1)
            model.Edges = _repository.DescribePath(result.Path);

        return View(model);
    }
}
