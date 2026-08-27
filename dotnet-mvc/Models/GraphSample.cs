// Modèle de données pour la galerie « Types de graphes ».
//
// Un GraphSample est un petit graphe d'exemple (quelques nœuds, quelques
// arêtes) qui illustre une notion : connexe, complet, pondéré, cyclique…
// Le rendu en image (SVG) est fait par Services/SvgGraphRenderer.

namespace PathFinder.RazorMvc.Models;

// Comment disposer les nœuds sur l'image.
public enum GraphLayout
{
    Circular, // nœuds répartis sur un cercle (une composante = un cercle)
    Layered,  // nœuds empilés par niveaux (arbres, graphes orientés sans cycle)
}

// Une arête. Weight n'est renseigné que pour les graphes pondérés.
public record GraphEdge(string From, string To, int? Weight = null);

public record GraphSample(
    string Slug,           // identifiant URL, ex. "non-pondere"
    string Name,           // libellé affiché
    string Description,    // explication de la notion
    IReadOnlyList<string> Nodes,
    IReadOnlyList<GraphEdge> Edges,
    bool Directed,         // arêtes fléchées ?
    bool Weighted,         // arêtes avec un poids affiché ?
    GraphLayout Layout)
{
    public int NodeCount => Nodes.Count;
    public int EdgeCount => Edges.Count;
}
