# -*- coding: utf-8 -*-
"""Genere les schemas PNG du diaporama « Recherche d'existence d'un chemin ».
Sortie : docs/img/ppt/*.png
"""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Circle
import numpy as np
import networkx as nx

OUT = Path(__file__).resolve().parent / "img" / "ppt"
OUT.mkdir(parents=True, exist_ok=True)

NODE = "#4C72B0"
EDGE = "#94a3b8"
SRC = "#0ea5e9"
TGT = "#f59e0b"
HL = "#16a34a"
FWD = "#93c5fd"
BWD = "#fdba74"
RED = "#dc2626"


def save(fig, name):
    fig.savefig(OUT / name, dpi=150, facecolor="white", bbox_inches="tight")
    plt.close(fig)
    print("OK ", name)


def box(ax, x, y, text, w=1.15, h=0.5, fc=NODE, tc="white", fs=10):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                 boxstyle="round,pad=0.04,rounding_size=0.12",
                 fc=fc, ec="none", zorder=3))
    ax.text(x, y, text, ha="center", va="center", color=tc, fontsize=fs, zorder=4)


def arrow(ax, p1, p2, color=EDGE, lw=2.0, sa=20, sb=20):
    ax.annotate("", xy=p2, xytext=p1,
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw,
                                shrinkA=sa, shrinkB=sb))


# ---------------------------------------------------------------- direction
def fig_direction():
    fig, ax = plt.subplots(figsize=(7.2, 2.7))
    ax.set_xlim(-0.3, 8.7)
    ax.set_ylim(-0.2, 2.2)
    ax.axis("off")

    for y, dirlabel, a, b, res in [
        (1.6, "Direction = 'predecesseur'", "Nodes", "NodesLie", "arête  Nodes → NodesLie"),
        (0.4, "Direction = 'successeur'", "NodesLie", "Nodes", "arête  NodesLie → Nodes"),
    ]:
        ax.text(-0.2, y, dirlabel, ha="left", va="center", fontsize=10, style="italic")
        box(ax, 2.7, y, a)
        box(ax, 4.6, y, b)
        arrow(ax, (2.7, y), (4.6, y), color="#475569", lw=2.2, sa=34, sb=34)
        ax.text(5.5, y, "⟹", ha="center", va="center", fontsize=13)
        ax.text(5.9, y, res, ha="left", va="center", fontsize=10, color=HL, weight="bold")

    save(fig, "direction.png")


# ------------------------------------------------------------ graphe oriente
def fig_graphe_oriente():
    g = nx.DiGraph()
    g.add_edges_from([("A", "B"), ("B", "C"), ("C", "D"), ("D", "E"),
                      ("E", "F"), ("F", "A"), ("B", "E"), ("A", "D")])
    pos = nx.circular_layout(g)
    fig, ax = plt.subplots(figsize=(4.2, 3.6))
    nx.draw_networkx_edges(g, pos, ax=ax, edge_color=EDGE, width=1.8,
                           arrows=True, arrowstyle="-|>", arrowsize=16,
                           node_size=900, min_source_margin=12, min_target_margin=12)
    nx.draw_networkx_nodes(g, pos, ax=ax, node_color=NODE, node_size=900)
    nx.draw_networkx_labels(g, pos, ax=ax, font_color="white", font_size=11)
    ax.set_title("orienté · non pondéré", fontsize=10, color="#475569")
    ax.axis("off")
    ax.margins(0.12)
    save(fig, "graphe-oriente.png")


# ---------------------------------------------------------------- bfs bidi
def fig_bfs_bidi():
    fig, ax = plt.subplots(figsize=(7.6, 3.4))
    ax.set_xlim(-0.6, 10.2)
    ax.set_ylim(-1.7, 1.9)
    ax.axis("off")

    cols = {
        0: [(0, "S", SRC)],
        1.6: [(0.9, "", FWD), (-0.9, "", FWD)],
        3.2: [(1.0, "", FWD), (0, "", FWD), (-1.0, "", FWD)],
        4.8: [(0, "M", HL)],
        6.4: [(0.9, "", BWD), (-0.9, "", BWD)],
        8.0: [(0, "", BWD)],
        9.6: [(0, "T", TGT)],
    }
    P = {}
    for x, nodes in cols.items():
        for (y, lab, c) in nodes:
            P[(x, y)] = (x, y)
            ax.add_patch(Circle((x, y), 0.32, fc=c, ec="white", lw=1.5, zorder=3))
            if lab:
                ax.text(x, y, lab, ha="center", va="center", color="white",
                        fontsize=11, weight="bold", zorder=4)

    def link(a, b, color=EDGE, lw=1.6):
        arrow(ax, a, b, color=color, lw=lw, sa=15, sb=15)

    # trame d'aretes
    for a, b in [((0, 0), (1.6, 0.9)), ((0, 0), (1.6, -0.9)),
                 ((1.6, 0.9), (3.2, 1.0)), ((1.6, 0.9), (3.2, 0.0)),
                 ((1.6, -0.9), (3.2, -1.0)), ((1.6, -0.9), (3.2, 0.0)),
                 ((3.2, 1.0), (4.8, 0)), ((3.2, -1.0), (4.8, 0)),
                 ((4.8, 0), (6.4, 0.9)), ((4.8, 0), (6.4, -0.9)),
                 ((6.4, 0.9), (8.0, 0)), ((6.4, -0.9), (8.0, 0)),
                 ((8.0, 0), (9.6, 0))]:
        link(a, b)
    # chemin trouve
    for a, b in [((0, 0), (1.6, 0.0)) if False else ((0, 0), (3.2, 0.0)),
                 ((3.2, 0.0), (4.8, 0)), ((4.8, 0), (8.0, 0)), ((8.0, 0), (9.6, 0))]:
        pass
    for a, b in [((0, 0), (3.2, 0.0)), ((3.2, 0.0), (4.8, 0)),
                 ((4.8, 0), (8.0, 0)), ((8.0, 0), (9.6, 0))]:
        link(a, b, color=HL, lw=3.0)

    ax.annotate("front avant  →", xy=(1.6, 1.55), ha="center", fontsize=10,
                color=SRC, weight="bold")
    ax.annotate("←  front arrière", xy=(8.0, 1.55), ha="center", fontsize=10,
                color=TGT, weight="bold")
    ax.annotate("rencontre", xy=(4.8, 0.42), xytext=(4.8, 1.45), ha="center",
                fontsize=10, color=HL, weight="bold",
                arrowprops=dict(arrowstyle="-|>", color=HL, lw=1.6))
    ax.text(4.8, -1.5, "chemin = (source → rencontre)  +  (rencontre → cible)",
            ha="center", fontsize=9.5, color=HL, style="italic")
    save(fig, "bfs-bidi.png")


# ---------------------------------------------------------------- exemple
def fig_exemple():
    g = nx.DiGraph()
    g.add_edges_from([("N1", "N2"), ("N2", "N3"), ("N3", "N4"),
                      ("N1", "N9"), ("N9", "N3")])
    pos = {"N1": (0, 1), "N2": (1, 2), "N9": (1, 0), "N3": (2, 1), "N4": (3, 1)}
    path_edges = [("N1", "N2"), ("N2", "N3"), ("N3", "N4")]
    other = [e for e in g.edges if e not in path_edges]

    fig, ax = plt.subplots(figsize=(5.0, 3.0))
    nx.draw_networkx_edges(g, pos, ax=ax, edgelist=other, edge_color=EDGE, width=1.8,
                           arrows=True, arrowstyle="-|>", arrowsize=16,
                           node_size=1100, min_source_margin=14, min_target_margin=14)
    nx.draw_networkx_edges(g, pos, ax=ax, edgelist=path_edges, edge_color=HL, width=3.4,
                           arrows=True, arrowstyle="-|>", arrowsize=18,
                           node_size=1100, min_source_margin=14, min_target_margin=14)
    colors = [SRC if n == "N1" else TGT if n == "N4" else HL if n == "N3" else NODE
              for n in g.nodes]
    nx.draw_networkx_nodes(g, pos, ax=ax, node_color=colors, node_size=1100)
    nx.draw_networkx_labels(g, pos, ax=ax, font_color="white", font_size=10)
    ax.set_title("Recherche N1 → N4   ·   chemin trouvé : N1 → N2 → N3 → N4",
                 fontsize=9.5, color="#475569")
    ax.axis("off")
    ax.margins(0.15)
    save(fig, "exemple.png")


# ---------------------------------------------------------------- complexite
def fig_complexite():
    R = np.arange(2, 13)
    d = 4
    y1 = d ** R.astype(float)
    y2 = 2 * d ** (R / 2)
    fig, ax = plt.subplots(figsize=(5.4, 3.2))
    ax.semilogy(R, y1, "o-", color=RED, lw=2, label="BFS 1 sens  ≈ dᴿ")
    ax.semilogy(R, y2, "s-", color=HL, lw=2, label="BFS bidirectionnel  ≈ 2·d^(R/2)")
    ax.set_xlabel("longueur du chemin  R")
    ax.set_ylabel("nœuds visités (échelle log)")
    ax.set_title("degré moyen d = 4", fontsize=10, color="#475569")
    ax.grid(True, which="both", ls=":", alpha=0.5)
    ax.legend(fontsize=9)
    save(fig, "complexite.png")


# ---------------------------------------------------------------- composantes
def fig_composantes():
    fig, ax = plt.subplots(figsize=(6.8, 3.0))
    ax.set_xlim(-0.6, 6.6)
    ax.set_ylim(-1.1, 3.1)
    ax.axis("off")

    comp1 = {"A": (0.3, 1.4), "B": (1.3, 2.1), "C": (1.3, 0.7)}
    comp2 = {"D": (4.3, 1.4), "E": (5.3, 2.1), "F": (5.3, 0.7)}
    for comp, edges in [(comp1, [("A", "B"), ("B", "C"), ("C", "A")]),
                        (comp2, [("D", "E"), ("E", "F"), ("F", "D")])]:
        for a, b in edges:
            ax.plot([comp[a][0], comp[b][0]], [comp[a][1], comp[b][1]],
                    color=EDGE, lw=1.8, zorder=1)
        for n, (x, y) in comp.items():
            c = SRC if n == "A" else TGT if n == "E" else NODE
            ax.add_patch(Circle((x, y), 0.3, fc=c, ec="white", lw=1.5, zorder=3))
            ax.text(x, y, n, ha="center", va="center", color="white",
                    fontsize=11, weight="bold", zorder=4)

    ax.plot([3.0, 3.0], [0.2, 2.6], color=RED, lw=2, ls="--")
    ax.text(3.0, 2.85, "✗", ha="center", va="center", fontsize=20, color=RED)
    ax.text(0.8, -0.45, "ComponentId = 1", ha="center", fontsize=10, color="#475569")
    ax.text(4.8, -0.45, "ComponentId = 2", ha="center", fontsize=10, color="#475569")
    ax.text(3.0, -0.95, "1 ≠ 2  →  aucun chemin,  réponse en O(1)  (sans BFS)",
            ha="center", fontsize=10, color=RED, weight="bold")
    save(fig, "composantes.png")


if __name__ == "__main__":
    fig_direction()
    fig_graphe_oriente()
    fig_bfs_bidi()
    fig_exemple()
    fig_complexite()
    fig_composantes()
