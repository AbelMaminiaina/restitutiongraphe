// Controller (MVC) : la page des pré-calculs.
//
// GET  /Scan          -> statut des deux pré-calculs + boutons pour (re)lancer.
// POST /Scan/Run      -> composantes connexes faibles (§ 11.4, GraphScanService)
// POST /Scan/RunScc   -> condensation SCC              (§ 11.5, SccCondensationService)
//
// Ce n'est pas une API : Index renvoie une vue Razor, les Run* redirigent
// (POST-redirect-GET). Le déclenchement est en POST parce qu'il modifie la base.

using Microsoft.AspNetCore.Mvc;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Controllers;

public class ScanController : Controller
{
    private readonly GraphScanService _scan;
    private readonly SccCondensationService _scc;

    public ScanController(GraphScanService scan, SccCondensationService scc)
    {
        _scan = scan;
        _scc = scc;
    }

    [HttpGet]
    public IActionResult Index() => View(new ScanPageViewModel
    {
        Weak = _scan.Last,
        Scc = _scc.Last,
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
}
