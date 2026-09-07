// Controller (MVC) : la page des optimisations.
//
// GET  /Scan             -> statut des trois optimisations + boutons.
// POST /Scan/Run         -> composantes connexes faibles (§ 11.4)   [mode SQL]
// POST /Scan/RunScc      -> condensation SCC              (§ 11.5)   [mode SQL]
// POST /Scan/ReloadGraph -> (re)charge le graphe en mémoire (§ 11.7) [tous modes]
//
// Les deux pré-calculs § 11.4 / § 11.5 écrivent des tables SQL et n'ont
// d'intérêt que sur le grand graphe SQL. En mode « graphe généré » ils sont
// refusés (message) : le graphe est petit, la recherche est déjà instantanée.

using Microsoft.AspNetCore.Mvc;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Controllers
{
    public class ScanController : Controller
    {
        private readonly GraphDataProvider _data;
        private readonly GraphScanService _scan;
        private readonly SccCondensationService _scc;
        private readonly InMemoryGraphService _graph;

        public ScanController(
            GraphDataProvider data,
            GraphScanService scan,
            SccCondensationService scc,
            InMemoryGraphService graph)
        {
            _data = data;
            _scan = scan;
            _scc = scc;
            _graph = graph;
        }

        [HttpGet]
        public IActionResult Index() => View(new ScanPageViewModel
        {
            SourceDescription = _data.Description,
            ScanAvailable = _data.ScanAvailable,
            Weak = _scan.Last,
            Scc = _scc.Last,
            Graph = _graph.Status,
        });

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult Run()
        {
            if (!_data.ScanAvailable)
            {
                TempData["ScanMessage"] =
                    "Pré-calcul réservé au mode SQL (grand graphe). En mode graphe généré, "
                    + "la recherche est déjà instantanée sans pré-calcul.";
                return RedirectToAction(nameof(Index));
            }

            var s = _scan.Run();
            TempData["ScanMessage"] =
                $"Composantes faibles : {s.DurationMs} ms — {s.NodeCount:N0} nœuds, "
                + $"{s.EdgeCount:N0} arêtes, {s.ComponentCount:N0} composantes.";
            return RedirectToAction(nameof(Index));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult RunScc()
        {
            if (!_data.ScanAvailable)
            {
                TempData["ScanMessage"] =
                    "Pré-calcul réservé au mode SQL (grand graphe). En mode graphe généré, "
                    + "la recherche est déjà instantanée sans pré-calcul.";
                return RedirectToAction(nameof(Index));
            }

            var s = _scc.Run();
            TempData["ScanMessage"] =
                $"Condensation SCC : {s.DurationMs} ms — {s.SccCount:N0} SCC, "
                + $"graphe condensé {s.CondensedEdgeCount:N0} arêtes, plus grande SCC "
                + $"{s.LargestSccSize:N0} nœuds.";
            return RedirectToAction(nameof(Index));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult ReloadGraph()
        {
            var s = _graph.Reload();
            TempData["ScanMessage"] =
                $"Graphe en mémoire : {s.DurationMs} ms — {s.NodeCount:N0} nœuds, "
                + $"{s.EdgeCount:N0} arêtes, ~{s.ApproximateBytes / (1024 * 1024):N0} Mo.";
            return RedirectToAction(nameof(Index));
        }
    }
}
