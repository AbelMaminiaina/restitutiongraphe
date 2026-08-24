#!/usr/bin/env python3
"""Restitution d'un graphe orienté avec networkx — script unique, autonome.

Charge un fichier texte (format NOEUDS/ARETES), construit un graphe orienté
avec networkx, calcule un layout hiérarchique par niveaux (façon Sugiyama,
sans dépendance Graphviz) et l'affiche avec matplotlib.

Format attendu :

    NOEUDS
    A
    B
    C
    ARETES
    A B
    B C
    A C

Usage :
    python restitution_graphe.py exemple.txt              # affiche à l'écran
    python restitution_graphe.py exemple.txt -o graphe.png  # enregistre dans un fichier
    python restitution_graphe.py exemple.txt --link-template "https://example.com/nodes/{node}"
        # simple clic = sélectionner un nœud (prédécesseurs/successeurs) ;
        # double-clic = ouvrir ce lien dans le navigateur, {node} remplacé
        # par l'identifiant du nœud cliqué
"""

from __future__ import annotations

import argparse
import sys
import webbrowser
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import networkx as nx

NODE_HEADERS = {"noeuds", "nœuds", "nodes"}
EDGE_HEADERS = {"aretes", "arêtes", "edges"}


def parse_graph(text: str) -> nx.DiGraph:
    """Parse le format NOEUDS/ARETES et construit un graphe orienté networkx."""
    graph = nx.DiGraph()
    section: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        header = line.lower()
        if header in NODE_HEADERS:
            section = "nodes"
            continue
        if header in EDGE_HEADERS:
            section = "edges"
            continue

        if section == "nodes":
            graph.add_node(line)
        elif section == "edges":
            parts = line.split()
            if len(parts) < 2:
                raise ValueError(f"Ligne d'arête invalide (attendu 'source cible'): {raw_line!r}")
            graph.add_edge(parts[0], parts[1])
        else:
            raise ValueError(f"Ligne hors section (attendu NOEUDS/ARETES avant tout contenu): {raw_line!r}")

    if graph.number_of_nodes() == 0:
        raise ValueError("Aucun noeud trouvé dans le fichier.")

    return graph


def find_back_edges(graph: nx.DiGraph) -> set[tuple[str, str]]:
    """DFS classique : une arête vers un nœud déjà sur la pile d'appel referme un cycle."""
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


def layered_positions(graph: nx.DiGraph) -> dict[str, tuple[float, float]]:
    """Layout hiérarchique par niveaux : les arêtes de retour (cycles) sont
    exclues du calcul des niveaux via nx.topological_sort, mais restent
    dessinées dans le graphe final."""
    back_edges = find_back_edges(graph)

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


_DEFAULT_COLOR = "#4C72B0"
_SELECTED_COLOR = "#f59e0b"
_SUCCESSOR_COLOR = "#16a34a"
_PREDECESSOR_COLOR = "#0ea5e9"
_DIMMED_COLOR = "#94a3b8"
_DEFAULT_EDGE_COLOR = "#94a3b8"
_DIMMED_EDGE_COLOR = "#cbd5e1"


def draw_graph(
    graph: nx.DiGraph, pos: dict[str, tuple[float, float]], link_template: str | None = None
) -> plt.Figure:
    """Dessine le graphe avec un layout déjà calculé, et rend chaque nœud
    cliquable : cliquer un nœud surligne ses prédécesseurs (bleu) et
    successeurs (vert) directement dans la fenêtre matplotlib, sans web.

    Si `link_template` est fourni (ex: "https://example.com/nodes/{node}"),
    un double-clic sur un nœud ouvre ce lien dans le navigateur par défaut,
    `{node}` étant remplacé par l'identifiant du nœud cliqué."""
    xs = [x for x, _ in pos.values()]
    ys = [y for _, y in pos.values()]
    x_span = max(xs) - min(xs) if xs else 0
    y_span = max(ys) - min(ys) if ys else 0

    node_count = graph.number_of_nodes()
    node_size = max(150, min(1200, 15000 / node_count))
    font_size = max(5, min(9, 90 / node_count**0.5))

    figsize = (max(8.0, x_span * 0.8 + 2), max(6.0, y_span * 1.2 + 2))
    fig, ax = plt.subplots(figsize=figsize)

    node_list = list(graph.nodes())
    edge_list = list(graph.edges())

    node_collection = ax.scatter(
        [pos[n][0] for n in node_list],
        [pos[n][1] for n in node_list],
        s=node_size,
        c=_DEFAULT_COLOR,
        zorder=3,
        picker=True,
        pickradius=8,
    )
    nx.draw_networkx_labels(graph, pos, ax=ax, font_color="white", font_size=font_size)
    edge_artists = nx.draw_networkx_edges(
        graph,
        pos,
        ax=ax,
        edgelist=edge_list,
        arrows=True,
        arrowstyle="-|>",
        arrowsize=max(6, min(15, font_size + 2)),
        connectionstyle="arc3,rad=0.12",
        node_size=node_size,
        width=0.8,
    )
    for patch in edge_artists:
        patch.set_zorder(1)

    cycle = len(find_back_edges(graph)) > 0
    base_title = f"{graph.number_of_nodes()} nœuds · {graph.number_of_edges()} arêtes"
    if cycle:
        base_title += " · cycle détecté"
    title_suffix = " — clique un nœud pour voir ses prédécesseurs/successeurs"
    if link_template:
        title_suffix += ", double-clique pour ouvrir son lien"
    ax.set_title(base_title + title_suffix, fontsize=9)
    ax.set_axis_off()
    fig.tight_layout()

    selected: dict[str, str | None] = {"node": None}

    def refresh() -> None:
        sel = selected["node"]
        if sel is None:
            node_collection.set_facecolor(_DEFAULT_COLOR)
            for patch in edge_artists:
                patch.set_color(_DEFAULT_EDGE_COLOR)
                patch.set_alpha(1.0)
            ax.set_title(base_title + title_suffix, fontsize=9)
        else:
            successors = set(graph.successors(sel))
            predecessors = set(graph.predecessors(sel))

            colors = []
            for n in node_list:
                if n == sel:
                    colors.append(_SELECTED_COLOR)
                elif n in successors:
                    colors.append(_SUCCESSOR_COLOR)
                elif n in predecessors:
                    colors.append(_PREDECESSOR_COLOR)
                else:
                    colors.append(_DIMMED_COLOR)
            node_collection.set_facecolor(colors)

            for patch, (u, v) in zip(edge_artists, edge_list):
                if u == sel or v == sel:
                    patch.set_color(_SELECTED_COLOR)
                    patch.set_alpha(1.0)
                else:
                    patch.set_color(_DIMMED_EDGE_COLOR)
                    patch.set_alpha(0.35)

            ax.set_title(
                f"{sel} — {len(predecessors)} prédécesseur(s), {len(successors)} successeur(s)"
                " (reclique dessus pour désélectionner)",
                fontsize=9,
            )

        fig.canvas.draw_idle()

    def on_pick(event) -> None:
        if event.artist is not node_collection or not event.ind:
            return
        clicked = node_list[event.ind[0]]

        if link_template and event.mouseevent.dblclick:
            url = link_template.format(node=clicked)
            print(f"Ouverture du lien pour {clicked} : {url}")
            webbrowser.open(url)
            return

        if selected["node"] == clicked:
            selected["node"] = None
            print("Sélection effacée.")
        else:
            selected["node"] = clicked
            successors = sorted(graph.successors(clicked))
            predecessors = sorted(graph.predecessors(clicked))
            print(f"{clicked} — prédécesseurs: {predecessors} · successeurs: {successors}")

        refresh()

    fig.canvas.mpl_connect("pick_event", on_pick)

    return fig


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", type=Path, help="Fichier texte NOEUDS/ARETES")
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="Enregistre l'image dans ce fichier au lieu de l'afficher (PNG/SVG/PDF selon l'extension)",
    )
    parser.add_argument(
        "--link-template", type=str, default=None,
        help='URL ouverte dans le navigateur au double-clic sur un nœud, ex: '
             '"https://example.com/nodes/{node}" ({node} remplacé par l\'identifiant du nœud)',
    )
    args = parser.parse_args()

    try:
        text = args.input.read_text(encoding="utf-8")
        graph = parse_graph(text)
    except (OSError, ValueError) as exc:
        print(f"Erreur : {exc}", file=sys.stderr)
        sys.exit(1)

    pos = layered_positions(graph)
    fig = draw_graph(graph, pos, link_template=args.link_template)

    if args.output:
        fig.savefig(args.output, dpi=150)
        print(f"Graphe enregistré dans {args.output}")
    else:
        plt.show()


if __name__ == "__main__":
    main()
