"""Présentation image (PNG/SVG/PDF) d'un GraphModel, via matplotlib.

Utilise un layout hiérarchique par niveaux (façon Sugiyama/dagre) plutôt
qu'un layout force-directed : les nœuds sont rangés en niveaux selon le
sens des arêtes, ce qui donne un rendu lisible pour un graphe orienté sans
dépendre de Graphviz.
"""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # rendu sans interface graphique

import matplotlib.pyplot as plt
import networkx as nx

from restitution.models.graph import GraphModel


def _find_back_edges(graph: nx.DiGraph) -> set[tuple[str, str]]:
    """DFS classique : une arête vers un noeud déjà sur la pile d'appel referme un cycle."""
    back_edges: set[tuple[str, str]] = set()
    visited: set[str] = set()
    on_stack: set[str] = set()

    def dfs(node: str) -> None:
        visited.add(node)
        on_stack.add(node)
        for succ in graph.successors(node):
            if succ in on_stack:
                back_edges.add((node, succ))
            elif succ not in visited:
                dfs(succ)
        on_stack.discard(node)

    for node in graph.nodes:
        if node not in visited:
            dfs(node)

    return back_edges


def _layered_positions(graph: nx.DiGraph) -> dict[str, tuple[float, float]]:
    back_edges = _find_back_edges(graph)

    dag = nx.DiGraph()
    dag.add_nodes_from(graph.nodes)
    dag.add_edges_from(e for e in graph.edges if e not in back_edges)

    layer: dict[str, int] = {}
    for node in nx.topological_sort(dag):
        preds = list(dag.predecessors(node))
        layer[node] = 0 if not preds else 1 + max(layer[p] for p in preds)

    nodes_by_layer: dict[int, list[str]] = defaultdict(list)
    for node, lvl in layer.items():
        nodes_by_layer[lvl].append(node)

    pos: dict[str, tuple[float, float]] = {}
    for lvl, nodes in nodes_by_layer.items():
        nodes.sort()
        for i, node in enumerate(nodes):
            pos[node] = (i - (len(nodes) - 1) / 2, -lvl)

    return pos


def render_to_file(model: GraphModel, output_path: str | Path) -> Path:
    output_path = Path(output_path)
    graph = model.graph

    pos = _layered_positions(graph)
    xs = [x for x, _ in pos.values()]
    ys = [y for _, y in pos.values()]
    x_span = max(xs) - min(xs) if xs else 0
    y_span = max(ys) - min(ys) if ys else 0

    node_count = graph.number_of_nodes()
    node_size = max(150, min(1200, 15000 / node_count))
    font_size = max(5, min(9, 90 / node_count**0.5))

    figsize = (max(8.0, x_span * 0.8 + 2), max(6.0, y_span * 1.2 + 2))
    fig, ax = plt.subplots(figsize=figsize)

    nx.draw_networkx_nodes(graph, pos, ax=ax, node_color="#4C72B0", node_size=node_size)
    nx.draw_networkx_labels(graph, pos, ax=ax, font_color="white", font_size=font_size)
    nx.draw_networkx_edges(
        graph,
        pos,
        ax=ax,
        arrows=True,
        arrowstyle="-|>",
        arrowsize=max(6, min(15, font_size + 2)),
        connectionstyle="arc3,rad=0.12",
        node_size=node_size,
        width=0.8,
    )

    ax.set_axis_off()
    fig.tight_layout()
    fig.savefig(output_path, dpi=150)
    plt.close(fig)

    return output_path
