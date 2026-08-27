// Controller (MVC) : la page des optimisations.
//
// GET  /Scan             -> statut des trois optimisations + boutons.
// POST /Scan/Run         -> composantes connexes faibles (§ 11.4)
// POST /Scan/RunScc      -> condensation SCC              (§ 11.5)
// POST /Scan/ReloadGraph -> (re)charge le graphe en mémoire (§ 11.7)
//
// Ce n'est pas une API : Index renvoie une vue Razor, les actions redirigent
// (POST-redirect-GET).

using Microsoft.AspNetCore.Mvc;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Controllers;

public class ScanController : Controller
{
    private readonly GraphScanService _scan;
    private readonly SccCondensationService _scc;
    private readonly InMemoryGraphService _graph;

    public ScanController(GraphScanService scan, SccCondensationService scc, InMemoryGraphService graph)
    {
        _scan = scan;
        _scc = scc;
        _graph = graph;
    }

    [HttpGet]
    public IActionResult Index() => View(new ScanPageViewModel
    {
        Weak = _scan.Last,
        Scc = _scc.Last,
        Graph = _graph.Status,
    });

    [HttpPost]
    [ValidateAntiForgeryToken]
    public IActionResult Run()
    {
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
