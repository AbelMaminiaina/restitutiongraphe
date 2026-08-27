// Le catalogue des graphes d'exemple affichés dans la galerie « Types de
// graphes ». Rien de dynamique : ce sont des constantes.

namespace PathFinder.RazorMvc.Models;

public static class GraphSamples
{
    public static IReadOnlyList<GraphSample> All { get; } = Build();

    public static GraphSample? BySlug(string? slug) =>
        All.FirstOrDefault(g => g.Slug == slug);

    // Raccourci pour écrire une arête.
    private static GraphEdge E(string a, string b, int? w = null) => new(a, b, w);

    private static IReadOnlyList<string> N(params string[] nodes) => nodes;

    // Toutes les arêtes possibles entre nodes (graphe complet).
    private static GraphEdge[] Complete(params string[] nodes)
    {
        var list = new List<GraphEdge>();
        for (var i = 0; i < nodes.Length; i++)
            for (var j = i + 1; j < nodes.Length; j++)
                list.Add(new GraphEdge(nodes[i], nodes[j]));
        return list.ToArray();
    }

    private static List<GraphSample> Build() =>
    [
        new GraphSample("connexe", "Graphe connexe",
            "Tous les nœuds sont reliés entre eux : depuis n'importe quel nœud on "
            + "peut atteindre tous les autres en suivant des arêtes. Le graphe forme "
            + "une seule composante connexe.",
            N("A", "B", "C", "D", "E", "F"),
            [E("A","B"), E("B","C"), E("C","D"), E("D","E"), E("E","F"), E("F","A"), E("B","E")],
            Directed: false, Weighted: false, GraphLayout.Circular),

        new GraphSample("non-connexe", "Graphe non connexe",
            "Le graphe se sépare en plusieurs morceaux (composantes) sans aucune "
            + "arête entre eux : certains nœuds sont impossibles à atteindre depuis "
            + "d'autres. Ici trois composantes : {A,B,C}, {D,E}, {F,G}.",
            N("A", "B", "C", "D", "E", "F", "G"),
            [E("A","B"), E("B","C"), E("C","A"), E("D","E"), E("F","G")],
            Directed: false, Weighted: false, GraphLayout.Circular),

        new GraphSample("complet", "Graphe complet (K5)",
            "Chaque paire de nœuds distincts est reliée par une arête. Pour n nœuds, "
            + "il y a n(n-1)/2 arêtes (ici 5 nœuds → 10 arêtes). C'est le graphe le "
            + "plus dense possible.",
            N("A", "B", "C", "D", "E"),
            Complete("A", "B", "C", "D", "E"),
            Directed: false, Weighted: false, GraphLayout.Circular),

        new GraphSample("compact", "Graphe compact (dense)",
            "Beaucoup d'arêtes par rapport au nombre de nœuds, presque autant que le "
            + "graphe complet. Le nombre d'arêtes croît comme n². Le stocker sous "
            + "forme de matrice d'adjacence devient pertinent.",
            N("A", "B", "C", "D", "E", "F"),
            [E("A","B"), E("A","C"), E("A","D"), E("A","E"), E("B","C"), E("B","D"),
             E("B","F"), E("C","D"), E("C","E"), E("C","F"), E("D","E"), E("E","F")],
            Directed: false, Weighted: false, GraphLayout.Circular),

        new GraphSample("creux", "Graphe creux (sparse)",
            "Peu d'arêtes par rapport au nombre de nœuds : le nombre d'arêtes croît "
            + "comme n. C'est le cas de la base RestitutionGraphe (2 à 6 arêtes par "
            + "nœud). On le stocke en listes d'adjacence, pas en matrice.",
            N("A", "B", "C", "D", "E", "F", "G"),
            [E("A","B"), E("B","C"), E("C","D"), E("D","E"), E("E","F"), E("F","G")],
            Directed: false, Weighted: false, GraphLayout.Circular),

        new GraphSample("non-pondere", "Graphe non pondéré",
            "Les arêtes n'ont pas de valeur : elles indiquent seulement l'existence "
            + "d'un lien. La longueur d'un chemin est son nombre d'arêtes. C'est le "
            + "modèle utilisé par la recherche de chemin de cette application : un "
            + "simple BFS suffit à trouver le plus court chemin.",
            N("A", "B", "C", "D", "E"),
            [E("A","B"), E("A","C"), E("B","D"), E("C","D"), E("D","E")],
            Directed: false, Weighted: false, GraphLayout.Circular),

        new GraphSample("pondere", "Graphe pondéré",
            "Chaque arête porte un poids (distance, coût, durée…). Le plus court "
            + "chemin minimise la somme des poids, pas le nombre d'arêtes : un BFS "
            + "ne suffit plus, il faut un algorithme comme Dijkstra.",
            N("A", "B", "C", "D", "E"),
            [E("A","B",4), E("A","C",2), E("B","D",5), E("C","D",8), E("C","E",3), E("D","E",1)],
            Directed: false, Weighted: true, GraphLayout.Circular),

        new GraphSample("oriente-dag", "Graphe orienté sans cycle (DAG)",
            "Les arêtes ont un sens (A → B n'est pas B → A) et il n'existe aucun "
            + "cycle. On peut ranger les nœuds par niveaux (tri topologique) — c'est "
            + "ce que fait la table LINE_VIS_EDG via sa colonne Direction.",
            N("A", "B", "C", "D", "E"),
            [E("A","B"), E("A","C"), E("B","D"), E("C","D"), E("D","E")],
            Directed: true, Weighted: false, GraphLayout.Layered),

        new GraphSample("cyclique", "Graphe orienté cyclique",
            "Il existe au moins un cycle : en suivant les arêtes dans leur sens on "
            + "revient à son point de départ (ici A → B → C → A). Un parcours doit "
            + "marquer les nœuds déjà visités pour ne pas tourner en rond.",
            N("A", "B", "C", "D"),
            [E("A","B"), E("B","C"), E("C","A"), E("C","D")],
            Directed: true, Weighted: false, GraphLayout.Circular),

        new GraphSample("arbre", "Arbre",
            "Graphe connexe et sans cycle : il y a exactement un chemin entre deux "
            + "nœuds quelconques, et n-1 arêtes pour n nœuds. Un arbre enraciné se "
            + "dessine naturellement par niveaux.",
            N("A", "B", "C", "D", "E", "F", "G"),
            [E("A","B"), E("A","C"), E("B","D"), E("B","E"), E("C","F"), E("C","G")],
            Directed: false, Weighted: false, GraphLayout.Layered),
    ];
}
