# -*- coding: utf-8 -*-
"""Genere les images PNG des types de graphes pour la specification Word.

Le catalogue reproduit celui de dotnet-mvc/Models/GraphSamples.cs (memes
noeuds, memes aretes) : les illustrations du document et celles produites par
l'application MVC (SvgGraphRenderer) montrent donc les memes graphes.

Sortie : docs/img/<slug>.png
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # rendu fichier, pas de fenetre
import matplotlib.pyplot as plt
import networkx as nx

OUT = Path(__file__).resolve().parent / "img"
OUT.mkdir(exist_ok=True)

NODE_COLOR = "#4C72B0"
EDGE_COLOR = "#94a3b8"

# --- catalogue : (slug, oriente, pondere, layout, noeuds, aretes) ---------
# aretes pondere : (u, v, poids) ; sinon (u, v)
CATALOG = [
    ("connexe", False, False, "circular",
     ["A", "B", "C", "D", "E", "F"],
     [("A", "B"), ("B", "C"), ("C", "D"), ("D", "E"), ("E", "F"), ("F", "A"), ("B", "E")]),

    ("non-connexe", False, False, "spring",
     ["A", "B", "C", "D", "E", "F", "G"],
     [("A", "B"), ("B", "C"), ("C", "A"), ("D", "E"), ("F", "G")]),

    ("complet", False, False, "circular",
     ["A", "B", "C", "D", "E"],
     [(a, b) for i, a in enumerate("ABCDE") for b in "ABCDE"[i + 1:]]),

    ("compact", False, False, "circular",
     ["A", "B", "C", "D", "E", "F"],
     [("A", "B"), ("A", "C"), ("A", "D"), ("A", "E"), ("B", "C"), ("B", "D"),
      ("B", "F"), ("C", "D"), ("C", "E"), ("C", "F"), ("D", "E"), ("E", "F")]),

    ("creux", False, False, "circular",
     ["A", "B", "C", "D", "E", "F", "G"],
     [("A", "B"), ("B", "C"), ("C", "D"), ("D", "E"), ("E", "F"), ("F", "G")]),

    ("non-pondere", False, False, "circular",
     ["A", "B", "C", "D", "E"],
     [("A", "B"), ("A", "C"), ("B", "D"), ("C", "D"), ("D", "E")]),

    ("pondere", False, True, "circular",
     ["A", "B", "C", "D", "E"],
     [("A", "B", 4), ("A", "C", 2), ("B", "D", 5), ("C", "D", 8), ("C", "E", 3), ("D", "E", 1)]),

    ("oriente-dag", True, False, "layered",
     ["A", "B", "C", "D", "E"],
     [("A", "B"), ("A", "C"), ("B", "D"), ("C", "D"), ("D", "E")]),

    ("cyclique", True, False, "circular",
     ["A", "B", "C", "D"],
     [("A", "B"), ("B", "C"), ("C", "A"), ("C", "D")]),

    ("arbre", False, False, "layered",
     ["A", "B", "C", "D", "E", "F", "G"],
     [("A", "B"), ("A", "C"), ("B", "D"), ("B", "E"), ("C", "F"), ("C", "G")]),
]


def _layers(graph: nx.Graph, directed: bool) -> dict:
    """Niveau de chaque noeud : distance depuis les racines (in-degree 0 pour
    un graphe oriente, le premier noeud pour un arbre)."""
    if directed:
        roots = [n for n in graph.nodes if graph.in_degree(n) == 0]
    else:
        roots = [next(iter(graph.nodes))]
    layer = {r: 0 for r in roots}
    frontier = list(roots)
    while frontier:
        nxt = []
        for u in frontier:
            neighbors = graph.successors(u) if directed else graph.neighbors(u)
            for v in neighbors:
                cand = layer[u] + 1
                if directed:
                    # DAG : on garde le niveau le plus profond (plus long chemin)
                    if v not in layer or cand > layer[v]:
                        layer[v] = cand
                        nxt.append(v)
                else:
                    # arbre : BFS simple, un noeud n'est visite qu'une fois
                    if v not in layer:
                        layer[v] = cand
                        nxt.append(v)
        frontier = nxt
    for n in graph.nodes:
        layer.setdefault(n, 0)
    return layer


def _position(graph, nodes, layout, directed):
    if layout == "circular":
        return nx.circular_layout(graph)
    if layout == "spring":
        return nx.spring_layout(graph, seed=3, k=1.4)

    # layout par niveaux, calcule a la main (racine en haut, y descend)
    layer = _layers(graph, directed)
    by_layer = {}
    for n in nodes:  # ordre stable = ordre de declaration
        by_layer.setdefault(layer[n], []).append(n)

    pos = {}
    for lvl, members in by_layer.items():
        for i, n in enumerate(members):
            x = i - (len(members) - 1) / 2.0
            pos[n] = (x, -lvl)
    return pos


def build(slug, directed, weighted, layout, nodes, edges):
    graph = nx.DiGraph() if directed else nx.Graph()
    graph.add_nodes_from(nodes)
    if weighted:
        graph.add_weighted_edges_from(edges)
    else:
        graph.add_edges_from(edges)

    pos = _position(graph, nodes, layout, directed)

    fig, ax = plt.subplots(figsize=(3.4, 3.0))
    if directed:
        nx.draw_networkx_edges(
            graph, pos, ax=ax, edge_color=EDGE_COLOR, width=1.6,
            arrows=True, arrowstyle="-|>", arrowsize=16,
            node_size=850, min_source_margin=12, min_target_margin=12,
        )
    else:
        nx.draw_networkx_edges(graph, pos, ax=ax, edge_color=EDGE_COLOR, width=1.6)
    nx.draw_networkx_nodes(graph, pos, ax=ax, node_color=NODE_COLOR, node_size=850)
    nx.draw_networkx_labels(graph, pos, ax=ax, font_color="white", font_size=10)
    if weighted:
        labels = nx.get_edge_attributes(graph, "weight")
        nx.draw_networkx_edge_labels(
            graph, pos, ax=ax, edge_labels=labels, font_size=9,
            font_color="#374151", bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="#e5e7eb"),
        )

    ax.set_axis_off()
    ax.margins(0.12)
    fig.tight_layout(pad=0.2)
    path = OUT / f"{slug}.png"
    fig.savefig(path, dpi=150, facecolor="white")
    plt.close(fig)
    return path


if __name__ == "__main__":
    for entry in CATALOG:
        p = build(*entry)
        print(f"OK  {p.name}")
