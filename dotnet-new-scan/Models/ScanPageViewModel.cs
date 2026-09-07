// ViewModel de la page /Scan : le statut des trois optimisations.

using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc.Models
{
    public class ScanPageViewModel
    {
        // Phrase « Source : … » (SQL Server ou graphe généré).
        public string SourceDescription { get; set; } = "";

        // true en mode SQL : les pré-calculs § 11.4 / § 11.5 sont utilisables.
        public bool ScanAvailable { get; set; }

        // § 11.4 — composantes connexes faibles (GraphScanService).
        public ScanStatus? Weak { get; set; }

        // § 11.5 — condensation en composantes fortement connexes (SccCondensationService).
        public SccStatus? Scc { get; set; }

        // § 11.7 — graphe orienté chargé en mémoire (InMemoryGraphService).
        public GraphStatus? Graph { get; set; }
    }
}
