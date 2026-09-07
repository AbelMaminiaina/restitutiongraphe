// Controller (MVC) : une seule action, Index, qui rend la page unique du
// visualiseur (Views/Home/Index.cshtml).
//
// Aucune donnee n'est passee a la vue : tout le travail (lecture du .xlsx,
// construction du graphe, rendu Cytoscape, statistiques) est fait cote
// navigateur par /javascript/app.js.

using Microsoft.AspNetCore.Mvc;

namespace PathFinder.JavaScriptMvc.Controllers
{
    public class HomeController : Controller
    {
        [HttpGet]
        public IActionResult Index()
        {
            return View();
        }
    }
}
