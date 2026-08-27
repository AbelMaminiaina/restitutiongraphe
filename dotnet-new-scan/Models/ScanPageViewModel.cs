// ViewModel de la page /Scan : le statut des deux pré-calculs.

using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Models;

public class ScanPageViewModel
{
    // § 11.4 — composantes connexes faibles (GraphScanService).
    public ScanStatus? Weak { get; set; }

    // § 11.5 — condensation en composantes fortement connexes (SccCondensationService).
    public SccStatus? Scc { get; set; }
}
