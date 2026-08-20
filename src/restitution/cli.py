"""CLI : contrôleur pour la génération d'image en ligne de commande."""

from __future__ import annotations

import argparse
from pathlib import Path

from restitution.models.graph import GraphModel
from restitution.views.image_view import render_to_file


def main() -> None:
    parser = argparse.ArgumentParser(description="Génère une image de graphe orienté à partir d'un fichier texte.")
    parser.add_argument("input", type=Path, help="Fichier texte (sections NOEUDS/ARETES)")
    parser.add_argument("-o", "--output", type=Path, default=Path("graphe.png"), help="Image de sortie (.png/.svg/.pdf)")
    args = parser.parse_args()

    model = GraphModel.from_file(args.input)
    output_path = render_to_file(model, args.output)

    print(f"{model.node_count} noeuds, {model.edge_count} arêtes -> {output_path}")


if __name__ == "__main__":
    main()
