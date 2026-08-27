// ViewModel : les données que le contrôleur passe à la vue Razor Index.cshtml.
// Aucune logique ici, juste un sac de propriétés remplies par HomeController.

namespace PathFinder.RazorMvc.Models;

public class PathViewModel
{
    // Ce qui a été saisi dans le formulaire (réaffiché dans les champs).
    public string Source { get; set; } = "";
    public string Target { get; set; } = "";

    // true dès qu'une recherche a été lancée (source ET cible fournies).
    // Sert à la vue pour décider d'afficher ou non un bloc de résultat.
    public bool Searched { get; set; }

    // Message d'erreur de saisie (champ vide...), affiché tel quel.
    public string? InputError { get; set; }

    // Résultat de la recherche (valides seulement si Searched == true).
    public bool Found { get; set; }
    public IReadOnlyList<string> Path { get; set; } = [];
    public IReadOnlyList<PathEdge> Edges { get; set; } = [];

    // Nombre d'arêtes du chemin (0 si source == cible).
    public int HopCount => Path.Count > 0 ? Path.Count - 1 : 0;
}
