// Controller (MVC) : la galerie « Types de graphes ».
//
// Ce n'est PAS une API : GraphesController hérite de Controller (pas de
// [ApiController], pas de route /api/...). Index et Build renvoient des vues
// Razor ; Image renvoie un fichier image (FileResult), ce qui reste du MVC
// classique — le navigateur l'affiche dans une balise <img>.

using System.Text;

using Microsoft.AspNetCore.Mvc;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Controllers;

public class GraphesController : Controller
{
    private readonly SvgGraphRenderer _renderer;
    private readonly IWebHostEnvironment _environment;

    public GraphesController(SvgGraphRenderer renderer, IWebHostEnvironment environment)
    {
        _renderer = renderer;
        _environment = environment;
    }

    // Galerie : une vignette par type de graphe. Chaque image est demandée
    // au serveur via <img src="/Graphes/Image/{slug}">.
    [HttpGet]
    public IActionResult Index() => View(GraphSamples.All);

    // Renvoie l'image SVG d'un type de graphe, construite à la volée.
    // Le paramètre s'appelle `id` pour coller à la route MVC par défaut
    // ({controller}/{action}/{id?}) : l'URL est donc /Graphes/Image/connexe.
    [HttpGet]
    public IActionResult Image(string id)
    {
        var sample = GraphSamples.BySlug(id);
        if (sample is null) return NotFound();

        var svg = _renderer.Render(sample);
        return File(Encoding.UTF8.GetBytes(svg), "image/svg+xml");
    }

    // « Construire les images » au sens fichiers : écrit tous les SVG dans
    // wwwroot/img/graphes/, puis affiche la liste des fichiers produits.
    [HttpGet]
    public IActionResult Build()
    {
        var directory = Path.Combine(_environment.WebRootPath, "img", "graphes");
        Directory.CreateDirectory(directory);

        var written = new List<string>();
        foreach (var sample in GraphSamples.All)
        {
            var path = Path.Combine(directory, sample.Slug + ".svg");
            System.IO.File.WriteAllText(path, _renderer.Render(sample), Encoding.UTF8);
            written.Add($"img/graphes/{sample.Slug}.svg");
        }

        return View(written);
    }
}
