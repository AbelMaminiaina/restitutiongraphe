const NODE_HEADERS = new Set(["noeuds", "nœuds", "nodes"]);
const EDGE_HEADERS = new Set(["aretes", "arêtes", "edges"]);

/** Miroir JS de restitution.models.graph.GraphModel.from_text (Python), pour éviter tout serveur. */
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

const canvas = document.getElementById("canvas");
const hint = document.getElementById("hint");
const fileInput = document.getElementById("file-input");
const fileName = document.getElementById("file-name");
const cyContainer = document.getElementById("cy");
const statsPanel = document.getElementById("stats-panel");
const pathSourceSelect = document.getElementById("path-source");
const pathTargetSelect = document.getElementById("path-target");
const pathFindBtn = document.getElementById("path-find");
const pathClearBtn = document.getElementById("path-clear");
const pathResult = document.getElementById("path-result");

let cy = null;
let currentData = null;
let adjacency = {};
let pathSource = null;
let pathTarget = null;

function setHint(message, isError = false) {
  hint.textContent = message;
  hint.className = isError ? "error" : "hint";
  hint.style.display = message ? "block" : "none";
}

function loadFile(file) {
  fileName.textContent = file.name;
  statsPanel.innerHTML = "";
  setHint("Chargement…");

  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = parseGraphText(String(reader.result));
      setHint("");
      currentData = data;
      renderGraph(data);
      buildAdjacency(data);
      populatePathSelectors(data.nodes);
      resetPathSelection();
      renderStats(computeStats(data));
    } catch (err) {
      setHint(err.message ?? String(err), true);
    }
  };
  reader.onerror = () => setHint("Impossible de lire le fichier.", true);
  reader.readAsText(file, "utf-8");
}

function renderGraph(data) {
  if (cy) {
    cy.destroy();
  }

  const elements = [
    ...data.nodes.map((n) => ({ data: { id: n.id, label: n.id } })),
    ...data.edges.map((e) => ({
      data: { id: `${e.source}->${e.target}`, source: e.source, target: e.target },
    })),
  ];

  cy = cytoscape({
    container: cyContainer,
    elements,
    style: [
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
      {
        selector: "node:selected",
        style: { "background-color": "#DD8452", "border-width": 2, "border-color": "#7c2d12" },
      },
      {
        selector: ".dimmed",
        style: { opacity: 0.15 },
      },
      {
        selector: "node.path-node",
        style: {
          "background-color": "#16a34a",
          opacity: 1,
          "border-width": 2,
          "border-color": "#14532d",
        },
      },
      {
        selector: "edge.path-edge",
        style: {
          "line-color": "#16a34a",
          "target-arrow-color": "#16a34a",
          width: 3,
          opacity: 1,
        },
      },
      {
        selector: "node.start-node",
        style: {
          "background-color": "#0ea5e9",
          opacity: 1,
          "border-width": 3,
          "border-color": "#075985",
        },
      },
      {
        selector: "node.end-node",
        style: {
          "background-color": "#f59e0b",
          opacity: 1,
          "border-width": 3,
          "border-color": "#92400e",
        },
      },
    ],
    layout: { name: "dagre", rankDir: "TB", nodeSep: 40, rankSep: 80 },
  });

  cy.on("tap", "node", (evt) => handleNodeTap(evt.target.id()));
  cy.on("dbltap", "node", (evt) => {
    window.location.href = `node.html?id=${encodeURIComponent(evt.target.id())}`;
  });
}

/* ---------- Plus court chemin (BFS, non pondéré) ---------- */

function buildAdjacency(data) {
  adjacency = {};
  data.nodes.forEach((n) => {
    adjacency[n.id] = [];
  });
  data.edges.forEach((e) => {
    adjacency[e.source].push(e.target);
  });
}

function shortestPath(sourceId, targetId) {
  if (sourceId === targetId) return [sourceId];

  const visited = new Set([sourceId]);
  const prev = new Map();
  const queue = [sourceId];
  let head = 0;

  while (head < queue.length) {
    const current = queue[head++];
    for (const next of adjacency[current] || []) {
      if (visited.has(next)) continue;
      visited.add(next);
      prev.set(next, current);
      if (next === targetId) {
        const path = [next];
        let cursor = next;
        while (cursor !== sourceId) {
          cursor = prev.get(cursor);
          path.push(cursor);
        }
        return path.reverse();
      }
      queue.push(next);
    }
  }
  return null;
}

function populatePathSelectors(nodes) {
  const options = ['<option value="">—</option>']
    .concat(nodes.map((n) => `<option value="${n.id}">${n.id}</option>`))
    .join("");
  pathSourceSelect.innerHTML = options;
  pathTargetSelect.innerHTML = options;
}

function clearPathHighlight() {
  if (!cy) return;
  cy.elements().removeClass("dimmed path-node path-edge start-node end-node");
}

function resetPathSelection() {
  pathSource = null;
  pathTarget = null;
  pathSourceSelect.value = "";
  pathTargetSelect.value = "";
  pathResult.textContent = "";
  pathResult.classList.remove("error");
  clearPathHighlight();
}

function showPathMessage(message, isError = false) {
  pathResult.textContent = message;
  pathResult.classList.toggle("error", isError);
}

function runPathSearch(sourceId, targetId) {
  clearPathHighlight();

  if (!sourceId || !targetId) {
    showPathMessage("Choisis un nœud source et un nœud cible.", true);
    return;
  }
  if (!(sourceId in adjacency) || !(targetId in adjacency)) {
    showPathMessage("Nœud inconnu dans le graphe courant.", true);
    return;
  }

  const path = shortestPath(sourceId, targetId);

  cy.$id(sourceId).addClass("start-node");
  cy.$id(targetId).addClass("end-node");

  if (!path) {
    cy.elements().not(cy.$id(sourceId)).not(cy.$id(targetId)).addClass("dimmed");
    showPathMessage(`Aucun chemin de "${sourceId}" vers "${targetId}" (sens des arêtes).`, true);
    return;
  }

  const nodeIds = new Set(path);
  const edgeIds = new Set();
  for (let i = 0; i < path.length - 1; i++) {
    edgeIds.add(`${path[i]}->${path[i + 1]}`);
  }

  cy.nodes().forEach((n) => {
    if (!nodeIds.has(n.id())) n.addClass("dimmed");
  });
  cy.edges().forEach((e) => {
    if (edgeIds.has(e.id())) e.addClass("path-edge");
    else e.addClass("dimmed");
  });
  cy.nodes().filter((n) => nodeIds.has(n.id())).addClass("path-node");
  cy.$id(sourceId).addClass("start-node");
  cy.$id(targetId).addClass("end-node");

  const hops = path.length - 1;
  showPathMessage(`Chemin trouvé (${hops} arête${hops > 1 ? "s" : ""}) : ${path.join(" → ")}`, false);
}

function handleNodeTap(id) {
  if (!pathSource || pathTarget) {
    pathSource = id;
    pathTarget = null;
    pathSourceSelect.value = id;
    pathTargetSelect.value = "";
    clearPathHighlight();
    cy.$id(id).addClass("start-node");
    showPathMessage("Clique un second nœud pour la cible.");
    return;
  }

  if (id === pathSource) return;

  pathTarget = id;
  pathTargetSelect.value = id;
  runPathSearch(pathSource, pathTarget);
}

pathFindBtn.addEventListener("click", () => {
  pathSource = pathSourceSelect.value || null;
  pathTarget = pathTargetSelect.value || null;
  runPathSearch(pathSource, pathTarget);
});

pathClearBtn.addEventListener("click", () => {
  resetPathSelection();
});

/* ---------- Statistiques (restitution) ---------- */

function computeStats(data) {
  const n = data.nodes.length;
  const m = data.edges.length;

  const degree = {};
  data.nodes.forEach((nd) => {
    degree[nd.id] = { in: 0, out: 0 };
  });
  data.edges.forEach((e) => {
    degree[e.source].out += 1;
    degree[e.target].in += 1;
  });

  let totalDegree = 0;
  let maxDeg = -1;
  let maxDegNode = null;
  let isolated = 0;
  data.nodes.forEach((nd) => {
    const d = degree[nd.id].in + degree[nd.id].out;
    totalDegree += d;
    if (d > maxDeg) {
      maxDeg = d;
      maxDegNode = nd.id;
    }
    if (d === 0) isolated += 1;
  });
  const avgDegree = n ? (totalDegree / n).toFixed(2) : "0";
  const density = n > 1 ? (m / (n * (n - 1))).toFixed(3) : "0";

  return {
    n,
    m,
    density,
    components: countWeakComponents(data),
    avgDegree,
    maxDeg: Math.max(maxDeg, 0),
    maxDegNode,
    isolated,
    hasCycle: detectCycle(data),
  };
}

function countWeakComponents(data) {
  const undirected = {};
  data.nodes.forEach((nd) => {
    undirected[nd.id] = new Set();
  });
  data.edges.forEach((e) => {
    undirected[e.source].add(e.target);
    undirected[e.target].add(e.source);
  });

  const visited = new Set();
  let count = 0;
  for (const nd of data.nodes) {
    if (visited.has(nd.id)) continue;
    count += 1;
    const queue = [nd.id];
    visited.add(nd.id);
    let head = 0;
    while (head < queue.length) {
      const current = queue[head++];
      for (const next of undirected[current]) {
        if (!visited.has(next)) {
          visited.add(next);
          queue.push(next);
        }
      }
    }
  }
  return count;
}

function detectCycle(data) {
  const color = {};
  data.nodes.forEach((nd) => {
    color[nd.id] = 0;
  });
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

  for (const nd of data.nodes) {
    if (color[nd.id] === 0) visit(nd.id);
    if (cyclic) break;
  }
  return cyclic;
}

/* ---------- Base de données (sous-graphes récupérés via l'API) ---------- */

// 127.0.0.1 plutôt que localhost : sur Windows, la résolution de "localhost"
// tente d'abord ::1 (IPv6) avant de retomber sur IPv4, ce qui ajoute un délai
// perceptible à chaque requête.
const API_BASE = "http://127.0.0.1:8000";

const dbStatus = document.getElementById("db-status");
const dbGlobalStats = document.getElementById("db-global-stats");
const dbSearchInput = document.getElementById("db-search-input");
const dbSearchBtn = document.getElementById("db-search-btn");
const dbSearchResults = document.getElementById("db-search-results");
const dbDepthSelect = document.getElementById("db-depth");
const dbPathSourceInput = document.getElementById("db-path-source");
const dbPathTargetInput = document.getElementById("db-path-target");
const dbPathFindBtn = document.getElementById("db-path-find");
const dbPathResult = document.getElementById("db-path-result");

async function apiGet(path) {
  const res = await fetch(`${API_BASE}${path}`);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || `Erreur API (${res.status})`);
  }
  return res.json();
}

function loadSubgraph(data, label) {
  currentData = data;
  fileName.textContent = label;
  setHint("");
  renderGraph(data);
  buildAdjacency(data);
  populatePathSelectors(data.nodes);
  resetPathSelection();
  renderStats(computeStats(data));
}

async function initDbPanel() {
  try {
    const stats = await apiGet("/api/stats/global");
    dbStatus.textContent = "Connecté — vue d'ensemble de toute la base :";
    dbGlobalStats.innerHTML = [
      `<div class="stat"><span class="stat-label">Nœuds (total)</span><span class="stat-value">${stats.nodeCount.toLocaleString("fr-FR")}</span></div>`,
      `<div class="stat"><span class="stat-label">Arêtes (total)</span><span class="stat-value">${stats.edgeCount.toLocaleString("fr-FR")}</span></div>`,
      `<div class="stat"><span class="stat-label">Densité</span><span class="stat-value">${stats.density}</span></div>`,
      `<div class="stat"><span class="stat-label">Degré moyen</span><span class="stat-value">${stats.avgDegree}</span></div>`,
    ].join("");
  } catch (err) {
    dbStatus.textContent =
      "API indisponible. Lance-la avec : uvicorn restitution.api:app --port 8000 --app-dir src";
    dbStatus.classList.add("error");
  }
}

async function loadNeighborhoodFromDb(nodeId) {
  const depth = Number(dbDepthSelect.value);
  dbStatus.textContent = `Chargement du voisinage de "${nodeId}" (profondeur ${depth})…`;
  dbStatus.classList.remove("error");
  try {
    const data = await apiGet(`/api/neighborhood?node=${encodeURIComponent(nodeId)}&depth=${depth}&limit=500`);
    loadSubgraph(data, `Base — voisinage de ${nodeId} (profondeur ${depth})`);
    dbStatus.textContent = data.truncated
      ? `Voisinage tronqué à 500 nœuds (le graphe complet en contient davantage autour de "${nodeId}").`
      : `Voisinage complet de "${nodeId}" chargé : ${data.nodes.length} nœuds, ${data.edges.length} arêtes.`;
  } catch (err) {
    dbStatus.textContent = err.message;
    dbStatus.classList.add("error");
  }
}

dbSearchBtn.addEventListener("click", async () => {
  const q = dbSearchInput.value.trim();
  if (!q) return;
  dbSearchResults.innerHTML = "";
  try {
    const { results } = await apiGet(`/api/search?q=${encodeURIComponent(q)}&limit=20`);
    if (results.length === 0) {
      dbSearchResults.innerHTML = `<span class="panel-hint">Aucun résultat.</span>`;
      return;
    }
    dbSearchResults.innerHTML = results
      .map((id) => `<button type="button" class="chip" data-node-id="${id}">${id}</button>`)
      .join("");
  } catch (err) {
    dbStatus.textContent = err.message;
    dbStatus.classList.add("error");
  }
});

dbSearchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") dbSearchBtn.click();
});

dbSearchResults.addEventListener("click", (e) => {
  const btn = e.target.closest(".chip");
  if (!btn) return;
  dbSearchResults.querySelectorAll(".chip").forEach((c) => c.classList.remove("active"));
  btn.classList.add("active");
  loadNeighborhoodFromDb(btn.dataset.nodeId);
});

dbPathFindBtn.addEventListener("click", async () => {
  const source = dbPathSourceInput.value.trim();
  const target = dbPathTargetInput.value.trim();
  if (!source || !target) {
    dbPathResult.textContent = "Renseigne un nœud source et un nœud cible.";
    dbPathResult.classList.add("error");
    return;
  }
  dbPathResult.textContent = "Recherche en cours…";
  dbPathResult.classList.remove("error");
  try {
    const { path } = await apiGet(
      `/api/path?source=${encodeURIComponent(source)}&target=${encodeURIComponent(target)}`
    );
    const data = {
      nodes: path.map((id) => ({ id })),
      edges: path.slice(0, -1).map((id, i) => ({ source: id, target: path[i + 1] })),
    };
    loadSubgraph(data, `Base — chemin ${source} → ${target}`);
    runPathSearch(source, target);
    dbPathResult.textContent = `Chemin trouvé (${path.length - 1} arêtes) : ${path.join(" → ")}`;
  } catch (err) {
    dbPathResult.textContent = err.message;
    dbPathResult.classList.add("error");
  }
});

initDbPanel();

/* ---------- Graphe de navigation (à partir de l'historique de node.html) ---------- */

const NAV_HISTORY_KEY = "restitution.nodeHistory"; // même clé que node.js

function loadNavigationHistoryGraph() {
  let history = [];
  try {
    const raw = JSON.parse(sessionStorage.getItem(NAV_HISTORY_KEY) || "[]");
    // Compat avec un ancien historique enregistré avant l'ajout de "via" (simple string).
    history = raw.map((entry) => (typeof entry === "string" ? { id: entry, via: null } : entry));
  } catch {
    history = [];
  }

  if (history.length === 0) {
    setHint(
      "Aucun historique de navigation trouvé. Visite quelques nœuds depuis \"Nœuds & transformations\" puis reviens ici.",
      true
    );
    return;
  }

  const nodeIds = [...new Set(history.map((h) => h.id))];
  const edgeKeys = new Set();
  const edges = [];
  for (let i = 1; i < history.length; i++) {
    const prev = history[i - 1].id;
    const curr = history[i].id;
    if (prev === curr) continue;

    // "predecesseur" : curr précède prev -> curr -> prev.
    // "successeur", ou orientation inconnue (retour depuis l'historique, liste,
    // double-clic sur le graphe...) : on suppose l'ordre chronologique -> prev -> curr.
    const [source, target] = history[i].via === "predecesseur" ? [curr, prev] : [prev, curr];

    const key = `${source}->${target}`;
    if (edgeKeys.has(key)) continue;
    edgeKeys.add(key);
    edges.push({ source, target });
  }

  const data = { nodes: nodeIds.map((id) => ({ id })), edges };
  loadSubgraph(data, `Historique de navigation (${history.length} étapes, ${nodeIds.length} nœuds distincts)`);
}

if (new URLSearchParams(window.location.search).get("history")) {
  loadNavigationHistoryGraph();
}

function renderStats(stats) {
  const cell = (label, value, cls = "") =>
    `<div class="stat"><span class="stat-label">${label}</span><span class="stat-value ${cls}">${value}</span></div>`;

  statsPanel.innerHTML = [
    cell("Nœuds", stats.n),
    cell("Arêtes", stats.m),
    cell("Densité", stats.density),
    cell("Composantes connexes", stats.components),
    cell("Degré moyen", stats.avgDegree),
    cell("Degré max", `${stats.maxDeg}${stats.maxDegNode ? ` (${stats.maxDegNode})` : ""}`),
    cell("Nœuds isolés", stats.isolated),
    cell("Cycle détecté", stats.hasCycle ? "Oui" : "Non", stats.hasCycle ? "warn" : "ok"),
  ].join("");
}

fileInput.addEventListener("change", (e) => {
  const file = e.target.files?.[0];
  if (file) loadFile(file);
});

canvas.addEventListener("dragover", (e) => {
  e.preventDefault();
  canvas.classList.add("drag-over");
});

canvas.addEventListener("dragleave", () => {
  canvas.classList.remove("drag-over");
});

canvas.addEventListener("drop", (e) => {
  e.preventDefault();
  canvas.classList.remove("drag-over");
  const file = e.dataTransfer.files?.[0];
  if (file) loadFile(file);
});
