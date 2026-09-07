// ViewModel : les données que le contrôleur passe à la vue Razor Index.cshtml.
// Aucune logique ici, juste un sac de propriétés remplies par HomeController.

using System.Collections.Generic;

namespace PathFinder.ScanMvc.Models
{
    public class PathViewModel
    {
        // Ce qui a été saisi dans le formulaire (réaffiché dans les champs).
        public string Source { get; set; } = "";
        public string Target { get; set; } = "";

        // Algorithme choisi dans le menu déroulant : "bfs" (défaut), "dijkstra",
        // "dijkstra-bi" ou "astar". Réaffiché pour garder l'option sélectionnée.
        public string Algo { get; set; } = "bfs";

        // Phrase « Source : … » (SQL Server ou graphe généré), affichée en tête.
        public string SourceDescription { get; set; } = "";

        // true dès qu'une recherche a été lancée (source ET cible fournies).
        // Sert à la vue pour décider d'afficher ou non un bloc de résultat.
        public bool Searched { get; set; }

        // Message d'erreur de saisie (champ vide...), affiché tel quel.
        public string? InputError { get; set; }

        // Résultat de la recherche (valides seulement si Searched == true).
        public bool Found { get; set; }
        public IReadOnlyList<string> Path { get; set; } = new List<string>();
        public IReadOnlyList<PathEdge> Edges { get; set; } = new List<PathEdge>();

        // true quand « aucun chemin » a été tranché par la condensation SCC
        // (§ 11.5) : verdict EXACT d'atteignabilité orientée, sans BFS.
        public bool SkippedByScc { get; set; }

        // true quand « aucun chemin » a été tranché par le scan des composantes
        // faibles (§ 11.4) : nœuds dans des îles différentes, sans BFS.
        public bool SkippedByScan { get; set; }

        // true si le résultat provenait du cache applicatif (5 min).
        public bool FromCache { get; set; }

        // true si le parcours a été résolu sur le graphe en mémoire (§ 11.7)
        // plutôt que par des requêtes SQL palier par palier.
        public bool SolvedInMemory { get; set; }

        // Clé de l'algorithme qui a effectivement résolu le chemin en mémoire
        // ("bfs", "dijkstra", "dijkstra-bi", "astar").
        public string SolvedWith { get; set; } = "bfs";

        // Libellé lisible de l'algorithme, pour la bannière de résultat.
        public string AlgoLabel => (SolvedInMemory ? SolvedWith : Algo) switch
        {
            "dijkstra" => "Dijkstra (file de priorité)",
            "dijkstra-bi" => "Dijkstra bidirectionnel",
            "astar" => "A* (heuristique ALT)",
            _ => "BFS bidirectionnel",
        };

        // Nombre d'arêtes du chemin (0 si source == cible).
        public int HopCount => Path.Count > 0 ? Path.Count - 1 : 0;
    }
}
