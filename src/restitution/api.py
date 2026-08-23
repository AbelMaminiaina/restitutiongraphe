"""API FastAPI : sert des sous-graphes bornés de RestitutionGraphe au frontend web/.

Lancer avec : uvicorn restitution.api:app --reload --port 8000
"""

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from . import db

app = FastAPI(title="Restitution — API graphe")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/stats/global")
def stats_global():
    return db.global_stats()


@app.get("/api/search")
def search(q: str = Query(..., min_length=1), limit: int = 20):
    return {"results": db.search_nodes(q, limit=min(limit, 100))}


@app.get("/api/neighborhood")
def api_neighborhood(node: str, depth: int = 1, limit: int = 500):
    result = db.neighborhood(node, depth=depth, limit=min(limit, 2000))
    if not result["found"]:
        raise HTTPException(status_code=404, detail=f"Nœud '{node}' introuvable.")
    return result


@app.get("/api/nodes")
def api_list_nodes(page: int = 1, pageSize: int = 100, q: str | None = None):
    return db.list_nodes(page=page, page_size=pageSize, query=q)


@app.get("/api/node")
def api_node_detail(id: str):
    result = db.node_detail(id)
    if result is None:
        raise HTTPException(status_code=404, detail=f"Nœud '{id}' introuvable.")
    return result


@app.get("/api/path")
def api_path(source: str, target: str, max_depth: int = 12):
    result = db.shortest_path(source, target, max_depth=min(max_depth, 20))
    if not result["found"]:
        raise HTTPException(
            status_code=404, detail=f"Aucun chemin de '{source}' vers '{target}'."
        )
    return result
