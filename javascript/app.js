/* ==================================================================
   Visualiseur de graphe ORIENTÉ NON PONDÉRÉ (source : fichier Excel .xlsx)
   ==================================================================

   - Aucune dépendance à installer : cytoscape + dagre + xlsx (SheetJS)
     sont chargés en local (voir les <script> dans index.html).
   - Aucun serveur : le fichier .xlsx est lu directement dans le
     navigateur (FileReader -> ArrayBuffer -> XLSX.read).

   ------------------------------------------------------------------
   GUIDE DE LECTURE (le fichier est découpé en 9 sections)
   ------------------------------------------------------------------
   Faciles (commence par là) :
     3. Références DOM         - on récupère les éléments HTML par leur id
     4. LAYOUT_CONFIGS         - réglages de mise en page (simple objet)
     8. loadGraph / loadFile   - l'enchaînement quand on charge un fichier
     9. Câblage des événements - « quand on clique X, faire Y »
     renderStats               - fabrique le HTML du panneau statistiques

   Un peu plus techniques :
     2. rowsToGraph            - transforme le tableau Excel en {nodes, edges}
     5. renderGraph            - crée le dessin cytoscape (surtout du style)
     6. selectNode             - surligne les voisins d'un nœud cliqué
     7. computeStats           - compte nœuds / arêtes / degrés

   Les 2 algorithmes classiques (les plus denses, commentés ligne à ligne) :
     detectCycle          - parcours en PROFONDEUR (DFS) avec coloriage
     countWeakComponents  - parcours en LARGEUR (BFS) avec une file

   ------------------------------------------------------------------
   VOCABULAIRE
   ------------------------------------------------------------------
   - graphe ORIENTÉ    : une arête va de A VERS B (flèche) ; A->B ≠ B->A
   - NON PONDÉRÉ       : les arêtes n'ont pas de poids / coût
   - successeur de A   : un nœud B tel qu'il existe une arête A -> B
   - prédécesseur de A : un nœud B tel qu'il existe une arête B -> A
   - degré d'un nœud   : nombre d'arêtes qui le touchent (entrantes + sortantes)
   - cycle             : un chemin qui, en suivant les flèches, revient à son départ
   ================================================================== */

/* ------------------------------------------------------------------
   0. Mode débogage
   ------------------------------------------------------------------
   Mettre DEBUG = true pour activer les points d'arrêt (`debugger;`) placés
   aux étapes clés du programme. Quand les outils de développement du
   navigateur (touche F12) sont ouverts, l'exécution s'arrête à chaque
   `debugger;` : on peut alors inspecter les variables, avancer pas à pas
   (F10), entrer dans une fonction (F11), continuer (F8).

   Laisser DEBUG = false en usage normal.
   (Astuce : on peut aussi forcer le mode via l'URL ...index.html?debug=1)
------------------------------------------------------------------ */
const DEBUG =
  false ||
  (typeof location !== "undefined" && /[?&]debug=1\b/.test(location.search));

// brk("étiquette") : point d'arrêt qui ne se déclenche QUE si DEBUG est vrai.
// L'étiquette est juste affichée dans la console pour se repérer.
function brk(label) {
  if (!DEBUG) return;
  console.log("[debug] " + label); // repère dans la console
  debugger; // eslint-disable-line no-debugger
}

/* ------------------------------------------------------------------
   1. Exemple embarqué (= contenu de exemple.xlsx sous forme de lignes)
   ------------------------------------------------------------------
   Le bouton « Charger l'exemple » réutilise ces lignes : pas besoin de
   télécharger un fichier. Régénéré par `node generer-exemple.mjs`
   (qui produit aussi exemple.xlsx à partir des mêmes données).
   1re sous-liste = en-têtes, puis une sous-liste par ligne de données.
------------------------------------------------------------------ */
const EXEMPLE_ROWS = [
  ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4"],
  ["DA1", "DA2", "DA3", "DA4", "O", "EA1", "EA2", "EA3", "EA4"],
  ["DB1", "DB2", "DB3", "DB4", "I", "EA1", "EA2", "EA3", "EA4"],
  ["DC1", "DC2", "DC3", "DC4", "I", "EA1", "EA2", "EA3", "EA4"],
  ["DA1", "DA2", "DA3", "DA4", "I", "EB1", "EB2", "EB3", "EB4"],
  ["DD1", "DD2", "DD3", "DD4", "O", "EB1", "EB2", "EB3", "EB4"],
  ["DE1", "DE2", "DE3", "DE4", "O", "EB1", "EB2", "EB3", "EB4"],
  ["DD1", "DD2", "DD3", "DD4", "I", "EC1", "EC2", "EC3", "EC4"],
  ["DF1", "DF2", "DF3", "DF4", "O", "EC1", "EC2", "EC3", "EC4"],
  ["DE1", "DE2", "DE3", "DE4", "I", "ED1", "ED2", "ED3", "ED4"],
  ["DG1", "DG2", "DG3", "DG4", "O", "ED1", "ED2", "ED3", "ED4"],
  ["DF1", "DF2", "DF3", "DF4", "I", "EE1", "EE2", "EE3", "EE4"],
  ["DH1", "DH2", "DH3", "DH4", "O", "EE1", "EE2", "EE3", "EE4"],
  ["DG1", "DG2", "DG3", "DG4", "I", "EF1", "EF2", "EF3", "EF4"],
  ["DH1", "DH2", "DH3", "DH4", "I", "EF1", "EF2", "EF3", "EF4"],
  ["DC1", "DC2", "DC3", "DC4", "O", "EF1", "EF2", "EF3", "EF4"],
  ["DB1", "DB2", "DB3", "DB4", "O", "EC1", "EC2", "EC3", "EC4"],
  ["DA1", "DA2", "DA3", "DA4", "I", "EE1", "EE2", "EE3", "EE4"],
  ["DH1", "DH2", "DH3", "DH4", "O", "EA1", "EA2", "EA3", "EA4"],
  ["DF1", "DF2", "DF3", "DF4", "I", "EB1", "EB2", "EB3", "EB4"],
  ["DG1", "DG2", "DG3", "DG4", "I", "EA1", "EA2", "EA3", "EA4"],
];

/* ------------------------------------------------------------------
   2. Du tableau Excel vers le graphe { nodes, edges }
   ------------------------------------------------------------------
   Chaque ligne décrit UN couple (nœud « données », nœud « edg ») :

     - nœud « données » = concaténation  dta_4.dta_3.dta_2.dta_1
     - nœud « edg »      = concaténation  edg_4.edg_3.edg_2.edg_1
     - la colonne edg_dir donne le SENS de l'arête entre les deux :
         I (Input)  -> le nœud « données » est PRÉDÉCESSEUR du nœud « edg »
                       => arête   données -> edg
         O (Output) -> le nœud « données » est SUCCESSEUR du nœud « edg »
                       => arête   edg -> données

   Les nœuds du graphe sont donc toutes les concaténations dta_* et edg_*,
   les arêtes sont les couples (données, edg) orientés selon edg_dir.

   En-têtes reconnus de façon tolérante : dta_1..dta_4 / edg_1..edg_4
   (avec ou sans « _ », « edg4 » accepté) ; colonne de sens = tout
   en-tête contenant « dir » (edg_dir, edr_dir, direction…).
------------------------------------------------------------------ */
function rowsToGraph(rows) {
  // Point d'arrêt : inspecter `rows` (le tableau brut lu depuis Excel).
  brk("rowsToGraph — entrée. Regarde: rows");

  if (!rows || rows.length < 2) {
    throw new Error("Le fichier doit contenir une ligne d'en-tête + au moins une ligne de données.");
  }

  // --- 2.1 On lit la ligne d'en-tête et on repère les colonnes utiles --------

  // On normalise chaque en-tête : texte, sans espaces au bord, en minuscules.
  // Ainsi "Edg_Dir", " edg_dir " et "edg_dir" deviennent tous "edg_dir".
  const header = rows[0].map((h) => String(h == null ? "" : h).trim().toLowerCase());

  // Objectif : savoir DANS QUELLE COLONNE se trouve chaque champ.
  //   dtaCol = { "1": 0, "2": 1, ... }  -> "le morceau dta n°1 est en colonne 0"
  //   edgCol = pareil pour les morceaux edg
  //   dirCol = index de la colonne de sens (I / O), -1 tant qu'on ne l'a pas trouvée
  const dtaCol = {};
  const edgCol = {};
  let dirCol = -1;

  header.forEach((name, idx) => {
    // idx = position de la colonne (0, 1, 2...). name = l'en-tête normalisé.
    let m;
    // /^dta[ _-]?0*([1-4])$/ : "dta", puis éventuellement _ - ou espace, d'éventuels
    // zéros, puis un chiffre 1-4 (récupéré dans m[1]). "dta_3", "dta3", "dta 03" -> ok.
    if ((m = name.match(/^dta[ _-]?0*([1-4])$/))) dtaCol[m[1]] = idx;
    else if ((m = name.match(/^edg[ _-]?0*([1-4])$/))) edgCol[m[1]] = idx;
    // Colonne de sens : n'importe quel en-tête qui contient "dir" (edg_dir, edr_dir...).
    else if (name.includes("dir")) dirCol = idx;
  });

  if (Object.keys(dtaCol).length === 0 || Object.keys(edgCol).length === 0) {
    throw new Error(
      "Colonnes attendues introuvables : il faut au moins une colonne dta_* et une colonne edg_* " +
        "(en-têtes lus : " + header.join(", ") + ")."
    );
  }
  if (dirCol === -1) {
    throw new Error("Colonne de sens introuvable : un en-tête doit contenir « dir » (ex. edg_dir).");
  }

  // Point d'arrêt : vérifier le repérage des colonnes (dtaCol, edgCol, dirCol).
  brk("rowsToGraph — colonnes repérées. Regarde: header, dtaCol, edgCol, dirCol");

  // --- 2.2  joinParts : reconstituer le nom d'un nœud ---------------------
  // À partir d'une ligne et d'un plan de colonnes (dtaCol ou edgCol), recolle
  // "morceau4.morceau3.morceau2.morceau1".
  //   Ex. row = ["DA1","DA2","DA3","DA4", ...], cols = {1:0, 2:1, 3:2, 4:3}
  //       -> row[3],row[2],row[1],row[0] = "DA4","DA3","DA2","DA1" -> "DA4.DA3.DA2.DA1"
  const joinParts = (row, cols) =>
    ["4", "3", "2", "1"] // ordre voulu : 4 puis 3 puis 2 puis 1
      .map((k) => (cols[k] == null ? "" : row[cols[k]])) // valeur du morceau k ("" si colonne absente)
      .map((v) => String(v == null ? "" : v).trim()) // en texte, sans espaces au bord
      .filter((v) => v !== "") // on jette les morceaux vides
      .join("."); // on recolle avec des points

  const nodeKind = new Map(); // nom du nœud -> ensemble de types ("dta" et/ou "edg")
  const edgeSet = new Set();  // couples "source target" déjà vus (évite les doublons)
  const edges = [];           // liste finale des arêtes { source, target }

  // noteKind : mémorise qu'un nœud est de type "dta" ou "edg" (il peut être les deux).
  const noteKind = (id, kind) => {
    if (!nodeKind.has(id)) nodeKind.set(id, new Set());
    nodeKind.get(id).add(kind);
  };

  for (let r = 1; r < rows.length; r++) { // r commence à 1 : on saute l'en-tête (rows[0])
    const row = rows[r] || [];

    // Ligne entièrement vide -> on l'ignore.
    const isBlank = row.every((c) => String(c == null ? "" : c).trim() === "");
    if (isBlank) continue;

    // Les deux nœuds décrits par cette ligne.
    const dtaNode = joinParts(row, dtaCol); // ex. "DA4.DA3.DA2.DA1"
    const edgNode = joinParts(row, edgCol); // ex. "EA4.EA3.EA2.EA1"
    if (!dtaNode || !edgNode) {
      // un des deux côtés est vide : on prévient dans la console et on passe.
      console.warn(`Ligne ${r + 1} ignorée : nœud « données » ou « edg » vide.`);
      continue;
    }

    // Le sens : on lit la colonne dir en majuscules, on ne regarde que la 1re lettre.
    const dir = String(row[dirCol] == null ? "" : row[dirCol]).trim().toUpperCase();
    let source, target; // les deux bouts de l'arête, dans l'ordre source -> target
    if (dir.startsWith("I")) {
      // I (Input) : données ENTRENT dans edg -> données est prédécesseur -> données -> edg
      source = dtaNode;
      target = edgNode;
    } else if (dir.startsWith("O")) {
      // O (Output) : edg PRODUIT les données -> données est successeur -> edg -> données
      source = edgNode;
      target = dtaNode;
    } else {
      throw new Error(`Ligne ${r + 1} : sens « ${row[dirCol]} » non reconnu (attendu I ou O).`);
    }

    // Point d'arrêt (une fois par ligne de données) : voir ce qu'on a extrait.
    brk(`rowsToGraph — ligne ${r + 1}. Regarde: dtaNode, edgNode, dir, source, target`);

    // On enregistre les types des deux nœuds.
    noteKind(dtaNode, "dta");
    noteKind(edgNode, "edg");

    // On ajoute l'arête, sauf si ce couple (source, target) a déjà été rencontré.
    // "\n" comme séparateur de clé : il n'apparaît jamais dans un nom de nœud.
    const key = source + "\n" + target;
    if (!edgeSet.has(key)) {
      edgeSet.add(key);
      edges.push({ source, target });
    }
  }

  if (nodeKind.size === 0) {
    throw new Error("Aucune ligne de données exploitable dans le fichier.");
  }

  // --- 2.4  On transforme la Map des nœuds en liste finale ---------------
  // Pour chaque nœud : son id + son "kind" (utilisé par renderGraph pour la couleur).
  const nodes = [...nodeKind.entries()].map(([id, kinds]) => ({
    id,
    // "both" si le nœud est à la fois donnée et edg, sinon l'un des deux.
    kind: kinds.has("dta") && kinds.has("edg") ? "both" : kinds.has("edg") ? "edg" : "dta",
  }));

  // Point d'arrêt : le graphe final avant affichage.
  brk("rowsToGraph — sortie. Regarde: nodes, edges");

  return { nodes, edges };
}

/* Lit un fichier .xlsx (ArrayBuffer) et renvoie le graphe { nodes, edges }.
   C'est le pont entre la librairie XLSX (SheetJS) et notre rowsToGraph. */
function workbookBufferToGraph(buffer) {
  // XLSX.read : décode le fichier binaire en "classeur" (workbook) en mémoire.
  const wb = XLSX.read(new Uint8Array(buffer), { type: "array" });
  // On prend la 1re feuille du classeur (wb.SheetNames[0] = son nom).
  const ws = wb.Sheets[wb.SheetNames[0]];
  if (!ws) throw new Error("Le classeur Excel ne contient aucune feuille.");
  // sheet_to_json({header:1}) : convertit la feuille en tableau de tableaux
  // (une sous-liste par ligne), exactement la forme attendue par rowsToGraph.
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, blankrows: false, defval: "" });
  return rowsToGraph(rows);
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
  // Point d'arrêt : `data` = { nodes, edges } sur le point d'être dessiné.
  brk("renderGraph — entrée. Regarde: data, layoutSelect.value");

  // On repart de zéro à chaque nouveau fichier.
  if (cy) {
    cy.destroy();
    cy = null;
  }

  // cytoscape veut UNE seule liste mêlant nœuds et arêtes, chacun sous la
  // forme { data: {...} }. Le "..." (spread) déverse le contenu d'un tableau
  // dans un autre : ici, tous les nœuds puis toutes les arêtes.
  const elements = [
    // un objet par nœud : id + label affiché + kind (pour la couleur)
    ...data.nodes.map((n) => ({ data: { id: n.id, label: n.id, kind: n.kind || "dta" } })),
    // un objet par arête : un id unique + les deux extrémités source/target
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
    style: [
      {
        selector: "node",
        style: {
          shape: "ellipse", // tous les nœuds ronds
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
      // Couleur selon le type de nœud (toutes de même forme : ronde/ellipse)
      // edg_* (bleu) vs données dta_* (violet) vs les deux (rose)
      { selector: 'node[kind = "edg"]', style: { "background-color": "#6ea8fe" } },
      { selector: 'node[kind = "dta"]', style: { "background-color": "#a78bfa" } },
      { selector: 'node[kind = "both"]', style: { "background-color": "#f472b6" } },
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
  if (!cy) return; // aucun graphe affiché

  // Point d'arrêt : `id` = nœud cliqué ; ci-dessous outgoers/incomers.
  brk("selectNode — id = " + id);

  // cytoscape manipule des "collections" d'éléments et leur applique des
  // "classes" (comme en CSS). La feuille de style de renderGraph décide
  // ensuite des couleurs en fonction de ces classes.
  const node = cy.$id(id);          // le nœud cliqué
  const outgoers = node.outgoers(); // TOUT ce qui part de node : arêtes sortantes + nœuds au bout
  const incomers = node.incomers(); // TOUT ce qui arrive à node : arêtes entrantes + nœuds d'origine

  const successors = outgoers.nodes();   // .nodes() : ne garder que les nœuds
  const predecessors = incomers.nodes();

  // 1) on enlève les classes posées par une sélection précédente
  cy.elements().removeClass("selected succ pred faded");

  // 2) on met TOUT en retrait (faded), puis on "rallume" la sélection
  cy.elements().addClass("faded");
  node.removeClass("faded").addClass("selected"); // le nœud cliqué (bleu vif)
  outgoers.removeClass("faded");                  // ses voisins/arêtes sortants
  incomers.removeClass("faded");                  // ses voisins/arêtes entrants
  successors.addClass("succ");                    // successeurs en vert
  predecessors.addClass("pred");                  // prédécesseurs en jaune
  outgoers.edges().addClass("succ");              // arêtes sortantes en vert
  incomers.edges().addClass("pred");              // arêtes entrantes en jaune

  // 3) panneau latéral : on affiche l'id et les deux listes de voisins
  selectionHint.hidden = true;
  selectionDetail.hidden = false;
  selIdEl.textContent = id;

  // .map((n) => n.id()) : collection de nœuds -> liste de noms ; .sort() : ordre alpha
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

  // Degré de chaque nœud : on compte les arêtes qui en partent (out) et qui y
  // arrivent (in). Pour chaque arête source -> target : +1 en "out" de source,
  // +1 en "in" de target.
  const deg = {};
  data.nodes.forEach((nd) => (deg[nd.id] = { in: 0, out: 0 })); // tout à zéro au départ
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

/* detectCycle : y a-t-il un cycle dans le graphe orienté ?
   ----------------------------------------------------------
   Méthode = parcours en PROFONDEUR (DFS) avec 3 couleurs :
     0 = blanc : pas encore visité
     1 = gris  : visite en cours (on est "descendu" dedans, pas encore remonté)
     2 = noir  : visite terminée
   Si, en suivant les flèches, on retombe sur un nœud GRIS, c'est qu'on
   est revenu sur nos pas => il y a un cycle. */
function detectCycle(data) {
  // adj = liste d'adjacence : pour chaque nœud, la liste de ses SUCCESSEURS.
  const adj = {};
  data.nodes.forEach((nd) => (adj[nd.id] = []));       // au départ : liste vide
  data.edges.forEach((e) => adj[e.source].push(e.target)); // arête source -> target

  const color = {};
  data.nodes.forEach((nd) => (color[nd.id] = 0)); // tout le monde blanc (0)
  let cyclic = false;                              // passera à true si on trouve un cycle

  // visit(u) : explore u puis, récursivement, tout ce qu'on atteint depuis u.
  function visit(u) {
    color[u] = 1; // u devient gris : visite commencée
    for (const v of adj[u]) { // pour chaque successeur v de u
      if (color[v] === 1) {   // v est gris => on boucle => cycle
        cyclic = true;
        return;
      }
      if (color[v] === 0) {   // v jamais vu => on descend dedans
        visit(v);
        if (cyclic) return;   // cycle déjà trouvé plus bas : on arrête tout
      }
      // si color[v] === 2 (noir) : déjà exploré à fond, rien à faire
    }
    color[u] = 2; // tous les successeurs traités => u devient noir
  }

  // Le graphe peut être en plusieurs morceaux : on lance la visite depuis
  // chaque nœud encore blanc.
  for (const nd of data.nodes) {
    if (color[nd.id] === 0) visit(nd.id);
    if (cyclic) break; // inutile de continuer une fois un cycle trouvé
  }
  return cyclic;
}

/* countWeakComponents : en combien de "morceaux" séparés le graphe se
   divise-t-il ? "Faiblement" connexe = on IGNORE le sens des flèches
   (on peut circuler dans les deux sens sur une arête).
   Méthode = parcours en LARGEUR (BFS) avec une file d'attente. */
function countWeakComponents(data) {
  // adj : pour chaque nœud, l'ensemble de ses voisins DANS LES 2 SENS.
  const adj = {};
  data.nodes.forEach((nd) => (adj[nd.id] = new Set()));
  data.edges.forEach((e) => {
    adj[e.source].add(e.target); // A voisin de B
    adj[e.target].add(e.source); // ...et B voisin de A
  });

  const visited = new Set(); // nœuds déjà rangés dans un morceau
  let count = 0;             // nombre de morceaux trouvés

  for (const nd of data.nodes) {
    if (visited.has(nd.id)) continue; // déjà dans un morceau : on passe
    count += 1;                       // un nœud non visité = un nouveau morceau

    // BFS : depuis ce nœud, on marque tout ce qu'on peut atteindre.
    const queue = [nd.id]; // file des nœuds à traiter
    visited.add(nd.id);
    while (queue.length) {
      const cur = queue.shift();    // on retire le 1er de la file
      for (const next of adj[cur]) { // pour chaque voisin de cur
        if (!visited.has(next)) {    // pas encore vu ?
          visited.add(next);         // on le marque
          queue.push(next);          // et on l'ajoutera à la file
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
   8. Point d'entrée : afficher un graphe déjà analysé
------------------------------------------------------------------ */
function loadGraph(data, label) {
  try {
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
  if (!file) return; // l'utilisateur a annulé la boîte de dialogue

  // FileReader lit le fichier de façon ASYNCHRONE : on décrit d'abord "quoi
  // faire quand c'est prêt" (onload), puis on lance la lecture (readAsArrayBuffer).
  const reader = new FileReader();
  reader.onload = () => {
    // reader.result = le contenu du fichier, ici en binaire (ArrayBuffer).
    // Point d'arrêt : on tient les octets bruts du .xlsx.
    brk("loadFile — fichier lu : " + file.name + " (" + reader.result.byteLength + " octets)");
    try {
      loadGraph(workbookBufferToGraph(reader.result), file.name);
    } catch (err) {
      showError(err.message || String(err)); // format invalide, colonne manquante...
    }
  };
  reader.onerror = () => showError("Impossible de lire le fichier.");
  reader.readAsArrayBuffer(file); // .xlsx = fichier binaire (un zip) -> ArrayBuffer
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

// a) Bouton « Importer un .xlsx »
fileInput.addEventListener("change", (e) => {
  loadFile(e.target.files && e.target.files[0]);
  fileInput.value = ""; // permet de recharger le même fichier ensuite
});

// b) Bouton « Charger l'exemple »
exampleBtn.addEventListener("click", () => {
  try {
    loadGraph(rowsToGraph(EXEMPLE_ROWS), "exemple.xlsx (intégré)");
  } catch (err) {
    showError(err.message || String(err));
  }
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
