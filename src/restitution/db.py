"""Accès à la base SQL Server RestitutionGraphe.

La table `dbo.LINE_VIS_EDG` est la source de vérité : il n'y a pas de table
de nœuds séparée, un nœud est simplement une valeur qui apparaît en colonne
`Nodes` ou `NodesLie`. Chaque ligne relie `Nodes` à `NodesLie` ; `Direction`
indique le rôle de `Nodes` par rapport à `NodesLie` :

- Direction = 'predecesseur' -> Nodes précède NodesLie -> arête Nodes -> NodesLie
- Direction = 'successeur'   -> Nodes suit NodesLie     -> arête NodesLie -> Nodes

`Nodes`/`NodesLie` sont des colonnes VARCHAR(8000). pyodbc lie par défaut les
paramètres Python `str` en NVARCHAR ; comparer une colonne VARCHAR à un
littéral NVARCHAR force SQL Server à convertir la colonne (donc un balayage
complet au lieu d'une recherche d'index, catastrophique à cette échelle). Le
correctif : caster le *paramètre* en VARCHAR(8000) dans le texte SQL plutôt
que de laisser convertir la colonne — voir `_ph()`/`_phs()`.

La base est la source de vérité pour les gros volumes : on n'y récupère
jamais tout le graphe, seulement des sous-graphes bornés (recherche,
voisinage à N sauts, plus court chemin).
"""

import os
from contextlib import contextmanager

import pyodbc

DEFAULT_SERVER = r"localhost\SQLEXPRESS01"
DEFAULT_DATABASE = "RestitutionGraphe"

_PARAM_BATCH = 1000  # SQL Server plafonne à ~2100 paramètres par requête
_NODE_SQL_TYPE = "VARCHAR(8000)"  # doit correspondre au type de Nodes/NodesLie


def _connection_string() -> str:
    server = os.environ.get("RESTITUTION_DB_SERVER", DEFAULT_SERVER)
    database = os.environ.get("RESTITUTION_DB_NAME", DEFAULT_DATABASE)
    return (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        f"SERVER={server};DATABASE={database};Trusted_Connection=yes;"
    )


@contextmanager
def get_connection():
    conn = pyodbc.connect(_connection_string())
    try:
        yield conn
    finally:
        conn.close()


def _ph() -> str:
    """Un placeholder pour un paramètre comparé à Nodes/NodesLie (cast explicite)."""
    return f"CAST(? AS {_NODE_SQL_TYPE})"


def _phs(n: int) -> str:
    """`n` placeholders castés, séparés par des virgules (pour un IN (...))."""
    return ",".join(_ph() for _ in range(n))


def _chunks(items: list[str], size: int):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _to_edge(row) -> tuple[str, str]:
    """Dérive (source, cible) d'une ligne LINE_VIS_EDG selon sa Direction."""
    if row.Direction == "predecesseur":
        return row.Nodes, row.NodesLie
    return row.NodesLie, row.Nodes


def search_nodes(query: str, limit: int = 20) -> list[str]:
    """Recherche par sous-chaîne dans l'identifiant du nœud (colonnes Nodes/NodesLie)."""
    pattern = f"%{query}%"
    sql = f"""
        SELECT DISTINCT TOP (?) Id FROM (
            SELECT Nodes AS Id FROM dbo.LINE_VIS_EDG WHERE Nodes LIKE {_ph()}
            UNION
            SELECT NodesLie AS Id FROM dbo.LINE_VIS_EDG WHERE NodesLie LIKE {_ph()}
        ) AS Matches
        ORDER BY Id
    """
    with get_connection() as conn:
        rows = conn.execute(sql, limit, pattern, pattern).fetchall()
    return [row.Id for row in rows]


def list_nodes(page: int = 1, page_size: int = 100, query: str | None = None) -> dict:
    """Page de nœuds distincts, avec les transformations qui leur sont liées
    (colonnes Nodes/NodesLie de LINE_VIS_EDG, dans les deux rôles)."""
    page = max(1, page)
    page_size = max(1, min(page_size, 500))
    offset = (page - 1) * page_size

    with get_connection() as conn:
        if query:
            pattern = f"%{query}%"
            base = f"""
                SELECT Id FROM (
                    SELECT Nodes AS Id FROM dbo.LINE_VIS_EDG WHERE Nodes LIKE {_ph()}
                    UNION
                    SELECT NodesLie AS Id FROM dbo.LINE_VIS_EDG WHERE NodesLie LIKE {_ph()}
                ) AS AllNodes
            """
            total = conn.execute(f"SELECT COUNT(*) FROM ({base}) AS Counted", pattern, pattern).fetchval()
            rows = conn.execute(
                f"{base} ORDER BY Id OFFSET ? ROWS FETCH NEXT ? ROWS ONLY",
                pattern,
                pattern,
                offset,
                page_size,
            ).fetchall()
        else:
            base = """
                SELECT Id FROM (
                    SELECT Nodes AS Id FROM dbo.LINE_VIS_EDG
                    UNION
                    SELECT NodesLie AS Id FROM dbo.LINE_VIS_EDG
                ) AS AllNodes
            """
            total = conn.execute(f"SELECT COUNT(*) FROM ({base}) AS Counted").fetchval()
            rows = conn.execute(
                f"{base} ORDER BY Id OFFSET ? ROWS FETCH NEXT ? ROWS ONLY", offset, page_size
            ).fetchall()

        node_ids = [row.Id for row in rows]
        transformations: dict[str, set[str]] = {nid: set() for nid in node_ids}

        if node_ids:
            placeholders = _phs(len(node_ids))
            for column in ("Nodes", "NodesLie"):
                sql = (
                    f"SELECT {column} AS NodeId, Transformation FROM dbo.LINE_VIS_EDG "
                    f"WHERE {column} IN ({placeholders}) AND Transformation IS NOT NULL"
                )
                for row in conn.execute(sql, *node_ids).fetchall():
                    transformations[row.NodeId].add(row.Transformation)

    return {
        "nodes": [
            {"id": nid, "transformations": sorted(transformations[nid])} for nid in node_ids
        ],
        "total": total,
        "page": page,
        "pageSize": page_size,
    }


def global_stats() -> dict:
    """Vue d'ensemble (agrégats SQL) de toute la base. Coûteux : à n'appeler
    qu'occasionnellement, pas à chaque requête de sous-graphe."""
    with get_connection() as conn:
        node_count = conn.execute(
            """
            SELECT COUNT(*) FROM (
                SELECT Nodes AS Id FROM dbo.LINE_VIS_EDG
                UNION
                SELECT NodesLie AS Id FROM dbo.LINE_VIS_EDG
            ) AS AllNodes
            """
        ).fetchval()
        edge_count = conn.execute(
            """
            SELECT COUNT(*) FROM (
                SELECT DISTINCT
                    CASE WHEN Direction = 'predecesseur' THEN Nodes ELSE NodesLie END AS SourceId,
                    CASE WHEN Direction = 'predecesseur' THEN NodesLie ELSE Nodes END AS TargetId
                FROM dbo.LINE_VIS_EDG
            ) AS DistinctEdges
            """
        ).fetchval()

    density = edge_count / (node_count * (node_count - 1)) if node_count > 1 else 0
    avg_degree = (2 * edge_count / node_count) if node_count else 0
    return {
        "nodeCount": node_count,
        "edgeCount": edge_count,
        "density": round(density, 6),
        "avgDegree": round(avg_degree, 2),
    }


def _row_exists(conn, node_id: str) -> bool:
    if conn.execute(
        f"SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG WHERE Nodes = {_ph()}", node_id
    ).fetchval():
        return True
    return bool(
        conn.execute(
            f"SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG WHERE NodesLie = {_ph()}", node_id
        ).fetchval()
    )


def _fetch_edges_touching(conn, frontier: list[str]) -> list:
    """Lignes où Nodes OU NodesLie est dans `frontier`, par lots de paramètres.

    Deux requêtes séparées (une par colonne) plutôt qu'un seul `OR` entre
    deux colonnes différentes : chacune peut alors utiliser son propre index
    par une recherche (seek) au lieu de forcer un balayage (scan) complet.
    """
    rows = []
    for chunk in _chunks(frontier, _PARAM_BATCH):
        placeholders = _phs(len(chunk))
        rows.extend(
            conn.execute(
                f"SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG WHERE Nodes IN ({placeholders})",
                *chunk,
            ).fetchall()
        )
        rows.extend(
            conn.execute(
                f"SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG WHERE NodesLie IN ({placeholders})",
                *chunk,
            ).fetchall()
        )
    return rows


def _fetch_edges_from(conn, frontier: list[str]) -> list:
    """Arêtes sortantes des nœuds de `frontier` (sens respecté), par lots de paramètres.

    Une arête sort d'un nœud X de deux façons possibles dans la table brute :
    soit (Nodes = X, Direction = predecesseur) -> X -> NodesLie,
    soit (NodesLie = X, Direction = successeur) -> X -> Nodes.
    Deux requêtes séparées (une par index composite) plutôt qu'un `OR`.
    """
    rows = []
    for chunk in _chunks(frontier, _PARAM_BATCH):
        placeholders = _phs(len(chunk))
        rows.extend(
            conn.execute(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG "
                f"WHERE Nodes IN ({placeholders}) AND Direction = 'predecesseur'",
                *chunk,
            ).fetchall()
        )
        rows.extend(
            conn.execute(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG "
                f"WHERE NodesLie IN ({placeholders}) AND Direction = 'successeur'",
                *chunk,
            ).fetchall()
        )
    return rows


def node_detail(node_id: str) -> dict | None:
    """Détail d'un nœud : ses successeurs et ses prédécesseurs directs (1 saut),
    chacun avec la transformation associée. Renvoie None si le nœud n'existe pas.

    Un nœud X a pour successeur Y quand :
      - une ligne (Nodes=X, predecesseur, NodesLie=Y) : X précède Y, ou
      - une ligne (Nodes=Y, successeur, NodesLie=X) : Y suit X.
    Le raisonnement est symétrique pour les prédécesseurs.
    """
    with get_connection() as conn:
        if not _row_exists(conn, node_id):
            return None

        successors = conn.execute(
            "SELECT NodesLie AS Other, Transformation FROM dbo.LINE_VIS_EDG "
            f"WHERE Nodes = {_ph()} AND Direction = 'predecesseur'",
            node_id,
        ).fetchall()
        successors += conn.execute(
            "SELECT Nodes AS Other, Transformation FROM dbo.LINE_VIS_EDG "
            f"WHERE NodesLie = {_ph()} AND Direction = 'successeur'",
            node_id,
        ).fetchall()

        predecessors = conn.execute(
            "SELECT Nodes AS Other, Transformation FROM dbo.LINE_VIS_EDG "
            f"WHERE NodesLie = {_ph()} AND Direction = 'predecesseur'",
            node_id,
        ).fetchall()
        predecessors += conn.execute(
            "SELECT NodesLie AS Other, Transformation FROM dbo.LINE_VIS_EDG "
            f"WHERE Nodes = {_ph()} AND Direction = 'successeur'",
            node_id,
        ).fetchall()

    def _rows_to_list(rows) -> list[dict]:
        seen = set()
        result = []
        for row in sorted(rows, key=lambda r: (r.Other, r.Transformation or "")):
            key = (row.Other, row.Transformation)
            if key in seen:
                continue
            seen.add(key)
            result.append({"id": row.Other, "transformation": row.Transformation})
        return result

    return {
        "id": node_id,
        "successors": _rows_to_list(successors),
        "predecessors": _rows_to_list(predecessors),
    }


def neighborhood(node_id: str, depth: int = 1, limit: int = 500) -> dict:
    """Voisinage (non orienté) d'un nœud, exploré par paliers en SQL.

    Borné en profondeur ET en nombre de nœuds pour rester compatible avec un
    graphe de plusieurs centaines de milliers d'arêtes : on ne rapatrie
    jamais plus que `limit` nœuds.
    """
    depth = max(1, min(depth, 4))

    with get_connection() as conn:
        if not _row_exists(conn, node_id):
            return {"nodes": [], "edges": [], "truncated": False, "found": False}

        visited = {node_id}
        frontier = [node_id]
        raw_edges: list[tuple[str, str]] = []
        truncated = False

        for _ in range(depth):
            if not frontier or len(visited) >= limit:
                break
            rows = _fetch_edges_touching(conn, frontier)
            next_frontier = []
            for row in rows:
                source, target = _to_edge(row)
                raw_edges.append((source, target))
                for nid in (source, target):
                    if nid in visited:
                        continue
                    if len(visited) >= limit:
                        truncated = True
                        continue
                    visited.add(nid)
                    next_frontier.append(nid)
            frontier = next_frontier

    dedup_edges = {(s, t) for s, t in raw_edges if s in visited and t in visited}
    return {
        "nodes": [{"id": nid} for nid in sorted(visited)],
        "edges": [{"source": s, "target": t} for s, t in sorted(dedup_edges)],
        "truncated": truncated,
        "found": True,
    }


def shortest_path(source_id: str, target_id: str, max_depth: int = 12) -> dict:
    """BFS non pondéré, sens des arêtes respecté, exécuté par paliers en SQL."""
    with get_connection() as conn:
        if not (_row_exists(conn, source_id) and _row_exists(conn, target_id)):
            return {"path": [], "found": False}

        if source_id == target_id:
            return {"path": [source_id], "found": True}

        visited = {source_id}
        prev: dict[str, str] = {}
        frontier = [source_id]
        max_visited = 30_000  # garde-fou : au-delà, on considère que ce n'est pas trouvable en temps utile

        for _ in range(max_depth):
            if not frontier or len(visited) >= max_visited:
                break
            rows = _fetch_edges_from(conn, frontier)
            next_frontier = []
            for row in rows:
                source, target = _to_edge(row)
                if source not in visited:
                    continue  # ligne rapatriée dans le lot mais qui ne part pas de la frontière
                if target in visited:
                    continue
                visited.add(target)
                prev[target] = source
                if target == target_id:
                    path = [target_id]
                    cur = target_id
                    while cur != source_id:
                        cur = prev[cur]
                        path.append(cur)
                    path.reverse()
                    return {"path": path, "found": True}
                next_frontier.append(target)
            frontier = next_frontier

    return {"path": [], "found": False}
