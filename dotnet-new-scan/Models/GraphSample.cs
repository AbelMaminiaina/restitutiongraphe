// Modèle de données pour la galerie « Types de graphes ».
//
// Un GraphSample est un petit graphe d'exemple (quelques nœuds, quelques
// arêtes) qui illustre une notion : connexe, complet, pondéré, cyclique…
// Le rendu en image (SVG) est fait par Services/SvgGraphRenderer.
//
// C# 8.0 : pas de `record` — GraphEdge et GraphSample sont des classes
// classiques (constructeur + propriétés en lecture seule).

using System.Collections.Generic;

namespace PathFinder.ScanMvc.Models
{
    // Comment disposer les nœuds sur l'image.
    public enum GraphLayout
    {
        Circular, // nœuds répartis sur un cercle (une composante = un cercle)
        Layered,  // nœuds empilés par niveaux (arbres, graphes orientés sans cycle)
    }

    // Une arête. Weight n'est renseigné que pour les graphes pondérés.
    public sealed class GraphEdge
    {
        public string From { get; }
        public string To { get; }
        public int? Weight { get; }

        public GraphEdge(string from, string to, int? weight = null)
        {
            From = from;
            To = to;
            Weight = weight;
        }
    }

    public sealed class GraphSample
    {
        public string Slug { get; }          // identifiant URL, ex. "non-pondere"
        public string Name { get; }          // libellé affiché
        public string Description { get; }    // explication de la notion
        public IReadOnlyList<string> Nodes { get; }
        public IReadOnlyList<GraphEdge> Edges { get; }
        public bool Directed { get; }         // arêtes fléchées ?
        public bool Weighted { get; }         // arêtes avec un poids affiché ?
        public GraphLayout Layout { get; }

        public GraphSample(
            string slug,
            string name,
            string description,
            IReadOnlyList<string> nodes,
            IReadOnlyList<GraphEdge> edges,
            bool directed,
            bool weighted,
            GraphLayout layout)
        {
            Slug = slug;
            Name = name;
            Description = description;
            Nodes = nodes;
            Edges = edges;
            Directed = directed;
            Weighted = weighted;
            Layout = layout;
        }

        public int NodeCount => Nodes.Count;
        public int EdgeCount => Edges.Count;
    }
}
