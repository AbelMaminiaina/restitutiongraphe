"""Modèle métier : un graphe orienté, chargé depuis un texte structuré.

Format attendu :

    NOEUDS
    A
    B
    C
    ARETES
    A B
    B C
    A C

Les lignes vides et celles commençant par '#' sont ignorées. Les en-têtes
de section sont insensibles à la casse et aux accents (NOEUDS/NŒUDS,
ARETES/ARÊTES).
"""

from __future__ import annotations

from pathlib import Path

import networkx as nx

_NODE_HEADERS = {"noeuds", "nœuds", "nodes"}
_EDGE_HEADERS = {"aretes", "arêtes", "edges"}


class GraphModel:
    def __init__(self, graph: nx.DiGraph | None = None) -> None:
        self.graph: nx.DiGraph = graph if graph is not None else nx.DiGraph()

    @classmethod
    def from_text(cls, text: str) -> GraphModel:
        graph = nx.DiGraph()
        section: str | None = None

        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            header = line.lower()
            if header in _NODE_HEADERS:
                section = "nodes"
                continue
            if header in _EDGE_HEADERS:
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
                raise ValueError(
                    f"Ligne hors section (attendu NOEUDS/ARETES avant tout contenu): {raw_line!r}"
                )

        if graph.number_of_nodes() == 0:
            raise ValueError("Aucun noeud trouvé dans le fichier.")

        return cls(graph)

    @classmethod
    def from_file(cls, path: str | Path) -> GraphModel:
        return cls.from_text(Path(path).read_text(encoding="utf-8"))

    @property
    def node_count(self) -> int:
        return self.graph.number_of_nodes()

    @property
    def edge_count(self) -> int:
        return self.graph.number_of_edges()
