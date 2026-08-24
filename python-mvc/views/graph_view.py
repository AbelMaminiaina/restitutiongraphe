"""View (MVC) : transforme un GraphModel en structure de présentation.

Ne modifie jamais le modèle, se contente de le lire et de le mettre en
forme pour l'affichage — ici une structure JSON-compatible consommée côté
navigateur par Cytoscape.js en layout "preset" (positions déjà calculées
par networkx côté serveur, pas de layout recalculé côté client).
"""

from __future__ import annotations

from models.graph_model import GraphModel


def build_render_data(model: GraphModel) -> dict:
    positions = model.layered_positions()

    nodes = [
        {"data": {"id": node, "label": node}, "position": {"x": x, "y": y}}
        for node, (x, y) in positions.items()
    ]
    edges = [
        {"data": {"id": f"{source}->{target}", "source": source, "target": target}}
        for source, target in model.graph.edges()
    ]

    return {
        "elements": nodes + edges,
        "stats": {
            "nodeCount": model.node_count,
            "edgeCount": model.edge_count,
            "hasCycle": model.has_cycle,
        },
    }
