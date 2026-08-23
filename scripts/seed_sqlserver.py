"""Génère un graphe orienté non pondéré de démonstration dans RestitutionGraphe
(table dbo.LINE_VIS_EDG : Nodes, Direction, NodesLie, Transformation).

100 000 nœuds, plusieurs arêtes sortantes par nœud (2 à 6), insertion en
masse via pyodbc.fast_executemany. Chaque arête source -> cible est stockée
en une seule ligne : Nodes = source, Direction = 'predecesseur',
NodesLie = cible (source précède cible).

Usage : python scripts/seed_sqlserver.py
"""

import random
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from restitution.db import get_connection  # noqa: E402

NODE_COUNT = 100_000
MIN_OUT_DEGREE = 2
MAX_OUT_DEGREE = 6
BATCH_SIZE = 5000

TRANSFORMATIONS = [
    "SELECT",
    "JOIN",
    "FILTER",
    "AGGREGATE",
    "MERGE",
    "CAST",
    "PIVOT",
    "UNION_ALL",
]


def generate_edges(node_ids: list[str]) -> list[tuple[str, str]]:
    edges: set[tuple[str, str]] = set()
    for node_id in node_ids:
        idx = int(node_id[1:])
        out_degree = random.randint(MIN_OUT_DEGREE, MAX_OUT_DEGREE)
        for _ in range(out_degree):
            target_idx = random.randint(1, NODE_COUNT)
            if target_idx == idx:
                continue
            edges.add((node_id, f"N{target_idx}"))
    return list(edges)


def insert_batches(cursor, sql: str, rows: list[tuple], label: str) -> None:
    t0 = time.time()
    for i in range(0, len(rows), BATCH_SIZE):
        cursor.executemany(sql, rows[i : i + BATCH_SIZE])
    print(f"  {len(rows)} {label} insérées en {time.time() - t0:.1f}s")


def main() -> None:
    node_ids = [f"N{i}" for i in range(1, NODE_COUNT + 1)]

    with get_connection() as conn:
        conn.execute("SET NOCOUNT ON")
        conn.execute("TRUNCATE TABLE dbo.LINE_VIS_EDG")
        conn.commit()

        cursor = conn.cursor()
        cursor.fast_executemany = True

        print("Génération des arêtes (2 à 6 par nœud, dédupliquées)...")
        edges = generate_edges(node_ids)
        rows = [
            (source, "predecesseur", target, random.choice(TRANSFORMATIONS))
            for source, target in edges
        ]
        print(f"Insertion de {len(rows)} lignes dans LINE_VIS_EDG...")
        insert_batches(
            cursor,
            "INSERT INTO dbo.LINE_VIS_EDG (Nodes, Direction, NodesLie, Transformation) "
            "VALUES (?, ?, ?, ?)",
            rows,
            "lignes",
        )
        conn.commit()

    print("Terminé.")


if __name__ == "__main__":
    main()
