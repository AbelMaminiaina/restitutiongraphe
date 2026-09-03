/* ==================================================================
   Visualiseur de graphe ORIENTÉ NON PONDÉRÉ
   ------------------------------------------------------------------
   - Aucune dépendance à installer : on utilise cytoscape + dagre via CDN
     (voir les <script> dans index.html).
   - Aucun serveur : le fichier .txt est lu directement dans le navigateur
     avec l'API FileReader.
   ================================================================== */

/* ------------------------------------------------------------------
   1. Contenu de exemple.txt embarqué en dur.
   ------------------------------------------------------------------
   Pourquoi ? Quand on ouvre index.html en double-cliquant (protocole
   file://), les navigateurs interdisent `fetch("exemple.txt")`.
   On garde donc une copie ici pour que le bouton « Charger l'exemple »
   fonctionne hors ligne. C'est exactement le contenu de exemple.txt.
------------------------------------------------------------------ */
const EXEMPLE_TXT = `NOEUDS
A
B
C
D
E
ARETES
A B
A C
B D
C D
D E
E A
`;

/* En-têtes de section acceptés (insensible à la casse et aux accents). */
const NODE_HEADERS = new Set(["noeuds", "nœuds", "nodes"]);
const EDGE_HEADERS = new Set(["aretes", "arêtes", "edges"]);

/* ------------------------------------------------------------------
   2. Analyse (parsing) du fichier texte -> { nodes, edges }
   ------------------------------------------------------------------
   Format attendu :

       NOEUDS
       A
       B
       ...
       ARETES
       A B        <- arête orientée A -> B
       B C
       ...

   Les lignes vides et les lignes commençant par # sont ignorées.
------------------------------------------------------------------ */
function parseGraphText(text) {
  const nodes = [];
  const seen = new Set();      // pour ne pas ajouter deux fois le même nœud
  const edges = [];
  let section = null;          // "nodes" | "edges" | null

  const lines = text.split(/\r?\n/); // gère les fins de ligne Windows et Unix

  lines.forEach((rawLine, index) => {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) return;

    const header = line.toLowerCase();
    if (NODE_HEADERS.has(header)) {
      section = "nodes";
      return;
    }
    if (EDGE_HEADERS.has(header)) {
      section = "edges";
      return;
    }

    if (section === "nodes") {
      addNode(line);
    } else if (section === "edges") {
      // Une arête = deux identifiants séparés par un ou plusieurs espaces.
      const parts = line.split(/\s+/);
      if (parts.length < 2) {
        throw new Error(
          `Ligne ${index + 1} : arête invalide « ${rawLine} » (attendu « source cible »).`
        );
      }
      const [source, target] = parts;
      addNode(source);
      addNode(target);
      edges.push({ source, target });
    } else {
      throw new Error(
        `Ligne ${index + 1} : contenu avant toute section. ` +
          `Commencez le fichier par « NOEUDS » ou « ARETES ».`
      );
    }
  });

  if (nodes.length === 0) {
    throw new Error("Aucun nœud trouvé. Vérifiez le format du fichier.");
  }

  return { nodes, edges };

  // petite fonction interne : ajoute un nœud s'il est nouveau
  function addNode(id) {
    if (!seen.has(id)) {
      seen.add(id);
      nodes.push({ id });
    }
  }
}

/* ------------------------------------------------------------------
   3. Références vers les éléments du DOM (le HTML)
------------------------------------------------------------------ */
const stage = document.getElementById("stage");
const dropzone = document.getElementById("dropzone");
const stageError = document.getElementById("stage-error");
const legend = document.getElementById("legend");
const fileInput = document.getElementById("file-input");
const exampleBtn = document.getElementById("example-btn");
const fileNameEl = document.getElementById("file-name");
const layoutSelect = document.getElementById("layout-select");
const fitBtn = document.getElementById("fit-btn");
const pngBtn = document.getElementById("png-btn");

const selectionHint = document.getElementById("selection-hint");
const selectionDetail = document.getElementById("selection-detail");
const selIdEl = document.getElementById("sel-id");
const succCountEl = document.getElementById("succ-count");
const predCountEl = document.getElementById("pred-count");
const succChipsEl = document.getElementById("succ-chips");
const predChipsEl = document.getElementById("pred-chips");

const statsEl = document.getElementById("stats");

/* État global de l'application */
let cy = null;            // instance cytoscape en cours
let currentData = null;   // dernier graphe analysé { nodes, edges }

/* ------------------------------------------------------------------
   4. Configuration des dispositions (layouts) cytoscape
   ------------------------------------------------------------------
   La clé correspond à la <option> du <select> dans index.html.
------------------------------------------------------------------ */
const LAYOUT_CONFIGS = {
  dagre: { name: "dagre", rankDir: "TB", nodeSep: 45, rankSep: 90, animate: true },
  breadthfirst: { name: "breadthfirst", directed: true, spacingFactor: 1.3, animate: true },
  circle: { name: "circle", animate: true },
  concentric: {
    name: "concentric",
    animate: true,
    // rayon = degré : les nœuds les plus connectés au centre
    concentric: (node) => node.degree(),
    levelWidth: () => 1,
  },
  grid: { name: "grid", animate: true },
  cose: { name: "cose", animate: true, idealEdgeLength: 100, nodeRepulsion: 9000 },
};

/* ------------------------------------------------------------------
   5. Rendu du graphe avec cytoscape
------------------------------------------------------------------ */
function renderGraph(data) {
  // On repart de zéro à chaque nouveau fichier.
  if (cy) {
    cy.destroy();
    cy = null;
  }

  const elements = [
    ...data.nodes.map((n) => ({ data: { id: n.id, label: n.id } })),
    ...data.edges.map((e) => ({
      data: {
        id: `${e.source}=>${e.target}`,
        source: e.source,
        target: e.target,
      },
    })),
  ];

  cy = cytoscape({
    container: document.getElementById("cy"),
    elements,
    // wheelSensitivity < 1 : zoom molette moins brutal
    wheelSensitivity: 0.25,
    style: [
      {
        selector: "node",
        style: {
          "background-color": "#6ea8fe",
          label: "data(label)",
          color: "#0b1220",
          "font-size": 13,
          "font-weight": 600,
          "text-valign": "center",
          "text-halign": "center",
          width: 40,
          height: 40,
          "border-width": 2,
          "border-color": "#0f1420",
        },
      },
      {
        selector: "edge",
        style: {
          width: 2,
          "line-color": "#4a5a7a",
          // La flèche indique le SENS de l'arête (graphe orienté).
          "target-arrow-color": "#4a5a7a",
          "target-arrow-shape": "triangle",
          "arrow-scale": 1.1,
          "curve-style": "bezier",
        },
      },
      // Nœud cliqué
      {
        selector: "node.selected",
        style: {
          "background-color": "#4f8cff",
          "border-color": "#dbe6ff",
          "border-width": 3,
          width: 46,
          height: 46,
        },
      },
      // Successeurs du nœud cliqué (arêtes sortantes)
      {
        selector: "node.succ",
        style: { "background-color": "#34d399", "border-color": "#065f46" },
      },
      {
        selector: "edge.succ",
        style: {
          "line-color": "#34d399",
          "target-arrow-color": "#34d399",
          width: 3.5,
        },
      },
      // Prédécesseurs du nœud cliqué (arêtes entrantes)
      {
        selector: "node.pred",
        style: { "background-color": "#fbbf24", "border-color": "#78350f" },
      },
      {
        selector: "edge.pred",
        style: {
          "line-color": "#fbbf24",
          "target-arrow-color": "#fbbf24",
          width: 3.5,
        },
      },
      // Éléments mis en retrait quand une sélection est active
      {
        selector: ".faded",
        style: { opacity: 0.12 },
      },
    ],
    layout: LAYOUT_CONFIGS[layoutSelect.value] || LAYOUT_CONFIGS.dagre,
  });

  // Clic sur un nœud -> on met en évidence ses voisins
  cy.on("tap", "node", (evt) => selectNode(evt.target.id()));
  // Clic dans le vide -> on efface la sélection
  cy.on("tap", (evt) => {
    if (evt.target === cy) clearSelection();
  });
}

/* ------------------------------------------------------------------
   6. Sélection d'un nœud : successeurs / prédécesseurs
   ------------------------------------------------------------------
   - successeur  d'un nœud X : tout nœud Y tel qu'il existe une arête X -> Y
   - prédécesseur d'un nœud X : tout nœud Y tel qu'il existe une arête Y -> X
   (Rappel : dans un graphe orienté, le sens compte.)
------------------------------------------------------------------ */
function selectNode(id) {
  if (!cy) return;

  const node = cy.$id(id);
  const outgoers = node.outgoers();        // arêtes sortantes + nœuds successeurs
  const incomers = node.incomers();        // arêtes entrantes + nœuds prédécesseurs

  const successors = outgoers.nodes();
  const predecessors = incomers.nodes();

  // 1) on nettoie les classes précédentes
  cy.elements().removeClass("selected succ pred faded");

  // 2) tout le monde en retrait, puis on "rallume" la sélection
  cy.elements().addClass("faded");
  node.removeClass("faded").addClass("selected");
  outgoers.removeClass("faded");
  incomers.removeClass("faded");
  successors.addClass("succ");
  predecessors.addClass("pred");
  outgoers.edges().addClass("succ");
  incomers.edges().addClass("pred");

  // 3) mise à jour du panneau latéral
  selectionHint.hidden = true;
  selectionDetail.hidden = false;
  selIdEl.textContent = id;

  fillChips(succChipsEl, succCountEl, successors.map((n) => n.id()).sort());
  fillChips(predChipsEl, predCountEl, predecessors.map((n) => n.id()).sort());
}

function clearSelection() {
  if (cy) cy.elements().removeClass("selected succ pred faded");
  selectionHint.hidden = false;
  selectionDetail.hidden = true;
}

/* Remplit une liste de "chips" cliquables (chaque chip = un nœud voisin). */
function fillChips(container, countEl, ids) {
  countEl.textContent = ids.length;
  container.innerHTML = "";

  if (ids.length === 0) {
    const span = document.createElement("span");
    span.className = "chip-empty";
    span.textContent = "aucun";
    container.appendChild(span);
    return;
  }

  ids.forEach((id) => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "chip";
    btn.textContent = id;
    // Cliquer un voisin recentre la sélection sur lui.
    btn.addEventListener("click", () => {
      selectNode(id);
      cy.animate({ center: { eles: cy.$id(id) }, duration: 250 });
    });
    container.appendChild(btn);
  });
}

/* ------------------------------------------------------------------
   7. Statistiques du graphe
------------------------------------------------------------------ */
function computeStats(data) {
  const n = data.nodes.length;
  const m = data.edges.length;

  // Degré entrant / sortant de chaque nœud
  const deg = {};
  data.nodes.forEach((nd) => (deg[nd.id] = { in: 0, out: 0 }));
  data.edges.forEach((e) => {
    deg[e.source].out += 1;
    deg[e.target].in += 1;
  });

  let isolated = 0;
  let maxDeg = 0;
  let maxDegNode = null;
  data.nodes.forEach((nd) => {
    const total = deg[nd.id].in + deg[nd.id].out;
    if (total === 0) isolated += 1;
    if (total > maxDeg) {
      maxDeg = total;
      maxDegNode = nd.id;
    }
  });

  // Densité d'un graphe orienté simple : m / (n * (n - 1))
  const density = n > 1 ? (m / (n * (n - 1))).toFixed(3) : "0";
  const avgOut = n ? (m / n).toFixed(2) : "0";

  return {
    n,
    m,
    density,
    avgOut,
    isolated,
    maxDeg,
    maxDegNode,
    hasCycle: detectCycle(data),
    components: countWeakComponents(data),
  };
}

/* Détection de cycle par coloriage (DFS) : blanc(0) / gris(1) / noir(2).
   Un arc vers un nœud "gris" (en cours d'exploration) = cycle. */
function detectCycle(data) {
  const adj = {};
  data.nodes.forEach((nd) => (adj[nd.id] = []));
  data.edges.forEach((e) => adj[e.source].push(e.target));

  const color = {};
  data.nodes.forEach((nd) => (color[nd.id] = 0));
  let cyclic = false;

  function visit(u) {
    color[u] = 1;
    for (const v of adj[u]) {
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

/* Nombre de composantes faiblement connexes
   (on ignore le sens des arêtes, parcours en largeur). */
function countWeakComponents(data) {
  const adj = {};
  data.nodes.forEach((nd) => (adj[nd.id] = new Set()));
  data.edges.forEach((e) => {
    adj[e.source].add(e.target);
    adj[e.target].add(e.source);
  });

  const visited = new Set();
  let count = 0;

  for (const nd of data.nodes) {
    if (visited.has(nd.id)) continue;
    count += 1;
    const queue = [nd.id];
    visited.add(nd.id);
    while (queue.length) {
      const cur = queue.shift();
      for (const next of adj[cur]) {
        if (!visited.has(next)) {
          visited.add(next);
          queue.push(next);
        }
      }
    }
  }
  return count;
}

function renderStats(s) {
  const cell = (label, value, cls = "") =>
    `<div class="stat">
       <span class="stat-label">${label}</span>
       <span class="stat-value ${cls}">${value}</span>
     </div>`;

  statsEl.innerHTML = [
    cell("Nœuds", s.n),
    cell("Arêtes", s.m),
    cell("Densité", s.density),
    cell("Arcs sortants / nœud", s.avgOut),
    cell("Degré max", s.maxDegNode ? `${s.maxDeg} (${s.maxDegNode})` : s.maxDeg),
    cell("Nœuds isolés", s.isolated),
    cell("Composantes", s.components),
    cell("Cycle", s.hasCycle ? "Oui" : "Non", s.hasCycle ? "warn" : "ok"),
  ].join("");
}

/* ------------------------------------------------------------------
   8. Point d'entrée : charger un texte de graphe
------------------------------------------------------------------ */
function loadGraphFromText(text, label) {
  try {
    const data = parseGraphText(text);
    currentData = data;

    hideError();
    dropzone.classList.add("hidden");
    legend.hidden = false;
    fileNameEl.textContent = label;

    renderGraph(data);
    renderStats(computeStats(data));
    clearSelection();
  } catch (err) {
    showError(err.message || String(err));
  }
}

function loadFile(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => loadGraphFromText(String(reader.result), file.name);
  reader.onerror = () => showError("Impossible de lire le fichier.");
  reader.readAsText(file, "utf-8");
}

function showError(message) {
  stageError.textContent = message;
  stageError.hidden = false;
}

function hideError() {
  stageError.hidden = true;
}

/* ------------------------------------------------------------------
   9. Câblage des événements de l'interface
------------------------------------------------------------------ */

// a) Bouton « Importer un .txt »
fileInput.addEventListener("change", (e) => {
  loadFile(e.target.files && e.target.files[0]);
  fileInput.value = ""; // permet de recharger le même fichier ensuite
});

// b) Bouton « Charger l'exemple »
exampleBtn.addEventListener("click", () => {
  loadGraphFromText(EXEMPLE_TXT, "exemple.txt (intégré)");
});

// c) Glisser-déposer sur la scène
stage.addEventListener("dragover", (e) => {
  e.preventDefault();
  stage.classList.add("drag-over");
});
stage.addEventListener("dragleave", (e) => {
  // on ne retire la surbrillance que si on quitte vraiment la scène
  if (!stage.contains(e.relatedTarget)) stage.classList.remove("drag-over");
});
stage.addEventListener("drop", (e) => {
  e.preventDefault();
  stage.classList.remove("drag-over");
  loadFile(e.dataTransfer.files && e.dataTransfer.files[0]);
});

// d) Changement de disposition
layoutSelect.addEventListener("change", () => {
  if (!cy) return;
  const config = LAYOUT_CONFIGS[layoutSelect.value] || LAYOUT_CONFIGS.dagre;
  cy.layout(config).run();
});

// e) Recentrer le graphe
fitBtn.addEventListener("click", () => {
  if (cy) cy.animate({ fit: { padding: 40 }, duration: 250 });
});

// f) Export PNG
pngBtn.addEventListener("click", () => {
  if (!cy) return;
  const png = cy.png({ full: true, scale: 2, bg: "#0f1420" });
  const a = document.createElement("a");
  a.href = png;
  a.download = "graphe.png";
  a.click();
});
