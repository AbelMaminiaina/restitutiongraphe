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
const stats = document.getElementById("stats");
const cyContainer = document.getElementById("cy");

let cy = null;

function setHint(message, isError = false) {
  hint.textContent = message;
  hint.className = isError ? "error" : "hint";
  hint.style.display = message ? "block" : "none";
}

function loadFile(file) {
  fileName.textContent = file.name;
  stats.textContent = "";
  setHint("Chargement…");

  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = parseGraphText(String(reader.result));
      setHint("");
      renderGraph(data);
      stats.textContent = `${data.nodes.length} noeuds · ${data.edges.length} arêtes`;
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
    ],
    layout: { name: "dagre", rankDir: "TB", nodeSep: 40, rankSep: 80 },
  });
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
