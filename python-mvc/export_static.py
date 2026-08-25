#!/usr/bin/env python3
"""Génère un fichier .html autonome à partir d'un .txt — pas de serveur.

Réutilise le même Model (GraphModel, networkx) et la même View
(build_render_data) que le reste de python-mvc/, mais écrit un fichier
.html complet et indépendant (CSS et données du graphe intégrés) : ouvrable
directement en double-clic, comme web/index.html, sans IP ni port.

Le HTML est un simple gabarit Python (pas de dépendance Flask/Jinja2) : ce
script est la seule "vue serveur" de python-mvc/, il n'y a plus de dossier
templates/ ni d'app web à lancer.

Usage :
    python export_static.py exemple.txt -o graphe.html
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from models.graph_model import GraphModel
from views.graph_view import build_render_data

BASE_DIR = Path(__file__).resolve().parent

# Gabarit HTML : des jetons __XXX__ (jamais utilisés ailleurs dans la page)
# sont remplacés par str.replace(), plutôt qu'un moteur de template — le
# JS/CSS ci-dessous utilise déjà massivement les accolades {}, qu'un
# .format()/f-string obligerait à échapper partout.
_HTML_TEMPLATE = r"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Restitution de graphe orienté — __FILENAME__</title>
  <script src="https://unpkg.com/cytoscape@3.30.2/dist/cytoscape.min.js"></script>
  <script src="https://unpkg.com/dagre@0.8.5/dist/dagre.min.js"></script>
  <script src="https://unpkg.com/cytoscape-dagre@2.5.0/cytoscape-dagre.js"></script>
  <style>
__CSS__
  </style>
</head>
<body>
  <div class="app">
    <header class="app-header">
      <h1>Restitution de graphe orienté — Python MVC (export autonome)</h1>
      <label class="file-button">
        Choisir un fichier .txt
        <input type="file" id="file-input" accept=".txt" hidden />
      </label>
      <span class="file-name" id="file-name">Généré depuis __FILENAME__</span>
    </header>

    <p class="interaction-hint">
      Clique un nœud pour surligner ses prédécesseurs/successeurs directs,
      double-clique pour voir son détail. Reclique le nœud sélectionné (ou
      le fond) pour désélectionner.
    </p>

    <main class="canvas" id="canvas">
      <p class="hint" id="hint" style="display: none"></p>
      <div id="cy"></div>
    </main>

    <footer class="app-footer" id="stats">
      __STATS_LINE__
    </footer>
  </div>

  <aside class="detail-panel" id="detail-panel">
    <button class="detail-close" id="detail-close" type="button" aria-label="Fermer">×</button>
    <h2 id="detail-title"></h2>
    <div class="detail-section">
      <h3>Prédécesseurs</h3>
      <ul id="detail-predecessors"></ul>
    </div>
    <div class="detail-section">
      <h3>Successeurs</h3>
      <ul id="detail-successors"></ul>
    </div>
  </aside>

  <script>
    // Graphe initial : calculé par networkx (Python) à la génération de cette
    // page, positions déjà figées (layout "preset", rien à recalculer).
    const INITIAL_ELEMENTS = __ELEMENTS_JSON__;

    const hint = document.getElementById("hint");
    const fileInput = document.getElementById("file-input");
    const fileName = document.getElementById("file-name");
    const stats = document.getElementById("stats");
    const cyContainer = document.getElementById("cy");
    const detailPanel = document.getElementById("detail-panel");
    const detailClose = document.getElementById("detail-close");
    const detailTitle = document.getElementById("detail-title");
    const detailPredecessors = document.getElementById("detail-predecessors");
    const detailSuccessors = document.getElementById("detail-successors");

    let cy = null;
    let selectedNodeId = null;

    const CY_STYLE = [
      {
        selector: "node",
        style: {
          "background-color": "#4C72B0",
          label: "data(label)",
          color: "#fff",
          "text-valign": "center",
          "text-halign": "center",
          "font-size": 12,
          width: 42,
          height: 42,
        },
      },
      {
        selector: "edge",
        style: {
          width: 2,
          "line-color": "#94a3b8",
          "target-arrow-color": "#94a3b8",
          "target-arrow-shape": "triangle",
          "curve-style": "bezier",
        },
      },
      { selector: "node.rg-selected", style: { "background-color": "#f59e0b" } },
      { selector: "node.rg-predecessor", style: { "background-color": "#0ea5e9" } },
      { selector: "node.rg-successor", style: { "background-color": "#16a34a" } },
      { selector: ".rg-dimmed", style: { opacity: 0.2 } },
      {
        selector: "edge.rg-highlighted",
        style: { "line-color": "#f59e0b", "target-arrow-color": "#f59e0b", width: 3, opacity: 1 },
      },
    ];

    /* ---------- Clic = voisinage direct, double-clic = détail ---------- */

    function clearHighlight() {
      if (!cy) return;
      cy.elements().removeClass("rg-selected rg-predecessor rg-successor rg-dimmed rg-highlighted");
      selectedNodeId = null;
    }

    function highlightNode(nodeId) {
      clearHighlight();
      const node = cy.$id(nodeId);
      const predecessors = node.incomers("node");
      const successors = node.outgoers("node");

      cy.elements().addClass("rg-dimmed");
      node.removeClass("rg-dimmed").addClass("rg-selected");
      predecessors.removeClass("rg-dimmed").addClass("rg-predecessor");
      successors.removeClass("rg-dimmed").addClass("rg-successor");
      node.connectedEdges().removeClass("rg-dimmed").addClass("rg-highlighted");

      selectedNodeId = nodeId;
    }

    function renderIdList(container, ids) {
      container.innerHTML = ids.length
        ? ids.map((id) => `<li>${id}</li>`).join("")
        : `<li class="empty">Aucun</li>`;
    }

    function showDetail(nodeId) {
      const node = cy.$id(nodeId);
      const predecessors = node.incomers("node").map((n) => n.id()).sort();
      const successors = node.outgoers("node").map((n) => n.id()).sort();

      detailTitle.textContent = `Nœud ${nodeId}`;
      renderIdList(detailPredecessors, predecessors);
      renderIdList(detailSuccessors, successors);
      detailPanel.classList.add("visible");
    }

    detailClose.addEventListener("click", () => detailPanel.classList.remove("visible"));

    function wireInteractions() {
      cy.on("tap", "node", (evt) => {
        const id = evt.target.id();
        if (selectedNodeId === id) {
          clearHighlight();
        } else {
          highlightNode(id);
        }
      });
      cy.on("tap", (evt) => {
        if (evt.target === cy) clearHighlight();
      });
      cy.on("dbltap", "node", (evt) => showDetail(evt.target.id()));
    }

    // Rendu initial : positions déjà calculées par networkx, aucun layout
    // recalculé côté client.
    cy = cytoscape({
      container: cyContainer,
      elements: INITIAL_ELEMENTS,
      style: CY_STYLE,
      layout: { name: "preset" },
    });
    wireInteractions();

    /* ---------- Upload d'un nouveau fichier : pas de serveur ici (page
       ouverte en file://), donc parsing + layout + détection de cycle
       réimplémentés en JS (mirroir de models/graph_model.py), layout via
       le plugin dagre plutôt que l'algorithme networkx. ---------- */

    const NODE_HEADERS = new Set(["noeuds", "nœuds", "nodes"]);
    const EDGE_HEADERS = new Set(["aretes", "arêtes", "edges"]);

    function parseGraphText(text) {
      const nodes = [];
      const seenNodes = new Set();
      const edges = [];
      let section = null;

      for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith("#")) continue;

        const header = line.toLowerCase();
        if (NODE_HEADERS.has(header)) {
          section = "nodes";
          continue;
        }
        if (EDGE_HEADERS.has(header)) {
          section = "edges";
          continue;
        }

        if (section === "nodes") {
          if (!seenNodes.has(line)) {
            seenNodes.add(line);
            nodes.push({ id: line });
          }
        } else if (section === "edges") {
          const parts = line.split(/\s+/);
          if (parts.length < 2) {
            throw new Error(`Ligne d'arête invalide (attendu "source cible"): "${rawLine}"`);
          }
          const [source, target] = parts;
          for (const id of [source, target]) {
            if (!seenNodes.has(id)) {
              seenNodes.add(id);
              nodes.push({ id });
            }
          }
          edges.push({ source, target });
        } else {
          throw new Error(`Ligne hors section (attendu NOEUDS/ARETES avant tout contenu): "${rawLine}"`);
        }
      }

      if (nodes.length === 0) {
        throw new Error("Aucun noeud trouvé dans le fichier.");
      }

      return { nodes, edges };
    }

    function detectCycle(data) {
      const adjacency = {};
      data.nodes.forEach((n) => (adjacency[n.id] = []));
      data.edges.forEach((e) => adjacency[e.source].push(e.target));

      const color = {};
      data.nodes.forEach((n) => (color[n.id] = 0));
      let cyclic = false;

      function visit(u) {
        color[u] = 1;
        for (const v of adjacency[u] || []) {
          if (color[v] === 1) {
            cyclic = true;
            return;
          }
          if (color[v] === 0) {
            visit(v);
            if (cyclic) return;
          }
        }
        color[u] = 2;
      }

      for (const n of data.nodes) {
        if (color[n.id] === 0) visit(n.id);
        if (cyclic) break;
      }
      return cyclic;
    }

    function setHint(message, isError = false) {
      hint.textContent = message;
      hint.className = isError ? "error" : "hint";
      hint.style.display = message ? "block" : "none";
    }

    function renderGraph(data) {
      if (cy) cy.destroy();

      const elements = [
        ...data.nodes.map((n) => ({ data: { id: n.id, label: n.id } })),
        ...data.edges.map((e) => ({
          data: { id: `${e.source}->${e.target}`, source: e.source, target: e.target },
        })),
      ];

      cy = cytoscape({
        container: cyContainer,
        elements,
        style: CY_STYLE,
        layout: { name: "dagre", rankDir: "TB", nodeSep: 40, rankSep: 80 },
      });
      wireInteractions();
      detailPanel.classList.remove("visible");
    }

    function loadFile(file) {
      fileName.textContent = file.name;
      setHint("Chargement…");

      const reader = new FileReader();
      reader.onload = () => {
        try {
          const data = parseGraphText(String(reader.result));
          setHint("");
          renderGraph(data);
          const cycle = detectCycle(data);
          stats.innerHTML =
            `${data.nodes.length} nœuds · ${data.edges.length} arêtes` +
            (cycle ? " · cycle détecté" : "") +
            ` — layout calculé en JavaScript (dagre) pour ce fichier chargé localement`;
        } catch (err) {
          setHint(err.message ?? String(err), true);
        }
      };
      reader.onerror = () => setHint("Impossible de lire le fichier.", true);
      reader.readAsText(file, "utf-8");
    }

    fileInput.addEventListener("change", (e) => {
      const file = e.target.files?.[0];
      if (file) loadFile(file);
    });
  </script>
</body>
</html>
"""


def render_html(graph: dict, filename: str, css: str) -> str:
    stats = graph["stats"]
    stats_line = f"{stats['nodeCount']} nœuds · {stats['edgeCount']} arêtes"
    if stats["hasCycle"]:
        stats_line += " · cycle détecté"
    stats_line += " — layout calculé par networkx (positions figées à la génération)"

    return (
        _HTML_TEMPLATE.replace("__FILENAME__", filename)
        .replace("__CSS__", css)
        .replace("__STATS_LINE__", stats_line)
        .replace("__ELEMENTS_JSON__", json.dumps(graph["elements"]))
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", type=Path, help="Fichier texte NOEUDS/ARETES")
    parser.add_argument(
        "-o", "--output", type=Path, default=Path("graphe.html"), help="Fichier .html à générer"
    )
    args = parser.parse_args()

    try:
        text = args.input.read_text(encoding="utf-8")
        model = GraphModel.from_text(text)
    except (OSError, ValueError) as exc:
        print(f"Erreur : {exc}", file=sys.stderr)
        sys.exit(1)

    graph = build_render_data(model)
    css = (BASE_DIR / "static" / "style.css").read_text(encoding="utf-8")

    html = render_html(graph, args.input.name, css)
    args.output.write_text(html, encoding="utf-8")

    print(f"Page autonome générée : {args.output}")
    print("Ouvre-la directement (double-clic) — aucun serveur, aucune IP nécessaire.")


if __name__ == "__main__":
    main()
