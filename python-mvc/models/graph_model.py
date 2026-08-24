"""Model (MVC) : un graphe orienté, chargé depuis un texte structuré, via networkx.

Format attendu (identique au CLI historique du projet) :

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

from collections import defaultdict
from functools import cached_property

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

    @property
    def node_count(self) -> int:
        return self.graph.number_of_nodes()

    @property
    def edge_count(self) -> int:
        return self.graph.number_of_edges()

    @cached_property
    def _back_edges(self) -> set[tuple[str, str]]:
        """DFS classique : une arête vers un nœud déjà sur la pile d'appel
        referme un cycle. Mis en cache : has_cycle et layered_positions()
        en ont besoin tous les deux, pas de raison de refaire le DFS deux fois."""
        back_edges: set[tuple[str, str]] = set()
        visited: set[str] = set()
        on_stack: set[str] = set()

        def dfs(node: str) -> None:
            visited.add(node)
            on_stack.add(node)
            for succ in self.graph.successors(node):
                if succ in on_stack:
                    back_edges.add((node, succ))
                elif succ not in visited:
                    dfs(succ)
            on_stack.discard(node)

        for node in self.graph.nodes:
            if node not in visited:
                dfs(node)

        return back_edges

    @property
    def has_cycle(self) -> bool:
        return len(self._back_edges) > 0

    def layered_positions(self, x_scale: float = 120.0, y_scale: float = 120.0) -> dict[str, tuple[float, float]]:
        """Layout hiérarchique par niveaux (façon Sugiyama), calculé via
        networkx.topological_sort sur une copie acyclique du graphe (les
        arêtes "de retour" détectées par DFS sont exclues du calcul des
        niveaux, mais restent dans le graphe rendu)."""
        dag = nx.DiGraph()
        dag.add_nodes_from(self.graph.nodes)
        dag.add_edges_from(e for e in self.graph.edges if e not in self._back_edges)

        layer: dict[str, int] = {}
        for node in nx.topological_sort(dag):
            preds = list(dag.predecessors(node))
            layer[node] = 0 if not preds else 1 + max(layer[p] for p in preds)

        nodes_by_layer: dict[int, list[str]] = defaultdict(list)
        for node, lvl in layer.items():
            nodes_by_layer[lvl].append(node)

        positions: dict[str, tuple[float, float]] = {}
        for lvl, nodes in nodes_by_layer.items():
            nodes.sort()
            for i, node in enumerate(nodes):
                positions[node] = ((i - (len(nodes) - 1) / 2) * x_scale, lvl * y_scale)

        return positions
