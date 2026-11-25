/* ==================================================================
   Visualiseur de graphe ORIENTÉ NON PONDÉRÉ (source : fichier Excel .xlsx)
   ==================================================================

   - Aucune dépendance à installer : cytoscape + dagre + xlsx (SheetJS)
     sont chargés en local, en version minifiée (voir les <script> dans
     index.html). La disposition hiérarchique est faite par dagre.
   - Aucun serveur : le fichier .xlsx est lu directement dans le
     navigateur (FileReader -> ArrayBuffer -> XLSX.read).

   ------------------------------------------------------------------
   GUIDE DE LECTURE (le fichier est découpé en 10 sections)
   ------------------------------------------------------------------
   Faciles (commence par là) :
     3. Références DOM         - on récupère les éléments HTML par leur id
     4. LAYOUT_CONFIGS         - réglages de mise en page (simple objet)
     8. loadGraph / loadFile   - l'enchaînement quand on charge un fichier
     9. Câblage des événements - « quand on clique X, faire Y »
    10. Démarrage             - attend que la page soit prête (DOMContentLoaded)
     renderStats               - fabrique le HTML du panneau statistiques

   Un peu plus techniques :
     2. rowsToGraph            - transforme l'onglet « Arc » en {nodes, edges}
     2 bis. noeudRowsToCara    - lit l'onglet « Noeud » (caractère de chaque nœud)
     2 ter. buildGraph         - assemble les deux onglets
     workbookBufferToGraph     - ouvre le .xlsx et trouve les deux onglets
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
   1. Exemples embarqués (= contenu de exemple_parcours.xlsx et
      exemple_adjacent.xlsx sous forme de lignes)
   ------------------------------------------------------------------
   Les boutons « Exemple parcours » et « Exemple adjacent » réutilisent ces
   lignes : pas besoin de télécharger un fichier. Les deux objets entre
   les repères ci-dessous sont RÉÉCRITS par `node generer-exemple.mjs`
   (qui produit aussi les deux .xlsx) : ne pas les modifier à la main.

   Chaque exemple a DEUX tableaux, un par onglet du fichier Excel :
     arcs   = onglet « Arc »   (dta_*, edg_dir, edg_*, txn_dta)
     noeuds = onglet « Noeud » (Nœud_1..Nœud_4, Cara_vis)
   Dans chaque tableau : 1re sous-liste = en-têtes, puis une sous-liste
   par ligne de données.
------------------------------------------------------------------ */
// <exemples-debut>
const EXEMPLE_PARCOURS = {
  arcs: [
    ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta"],
    ["DA1", "DA2", "DA3", "DA4", "I", "EA1", "EA2", "EA3", "EA4", "filtre"],
    ["DB1", "DB2", "DB3", "DB4", "O", "EA1", "EA2", "EA3", "EA4", "agrégation"],
    ["DB1", "DB2", "DB3", "DB4", "I", "EB1", "EB2", "EB3", "EB4", ""],
    ["DC1", "DC2", "DC3", "DC4", "O", "EB1", "EB2", "EB3", "EB4", "jointure"],
    ["DC1", "DC2", "DC3", "DC4", "I", "EC1", "EC2", "EC3", "EC4", "tri"],
    ["DD1", "DD2", "DD3", "DD4", "O", "EC1", "EC2", "EC3", "EC4", ""],
    ["DD1", "DD2", "DD3", "DD4", "I", "ED1", "ED2", "ED3", "ED4", "calcul"],
    ["DE1", "DE2", "DE3", "DE4", "O", "ED1", "ED2", "ED3", "ED4", "normalisation"],
    ["DE1", "DE2", "DE3", "DE4", "I", "EE1", "EE2", "EE3", "EE4", ""],
    ["DF1", "DF2", "DF3", "DF4", "O", "EE1", "EE2", "EE3", "EE4", "déduplication"],
  ],
  noeuds: [
    ["Nœud_1", "Nœud_2", "Nœud_3", "Nœud_4", "Cara_vis"],
    ["DA1", "DA2", "DA3", "DA4", "V"],
    ["EA1", "EA2", "EA3", "EA4", "C"],
    ["DB1", "DB2", "DB3", "DB4", "R"],
    ["EB1", "EB2", "EB3", "EB4", "U"],
    ["DC1", "DC2", "DC3", "DC4", "C"],
    ["EC1", "EC2", "EC3", "EC4", "V"],
    ["DD1", "DD2", "DD3", "DD4", "U"],
    ["ED1", "ED2", "ED3", "ED4", "R"],
    ["DE1", "DE2", "DE3", "DE4", "V"],
    ["EE1", "EE2", "EE3", "EE4", "C"],
    ["DF1", "DF2", "DF3", "DF4", "R"],
  ],
};

const EXEMPLE_ADJACENT = {
  arcs: [
    ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta"],
    ["DB1", "DB2", "DB3", "DB4", "O", "DA1", "DA2", "DA3", "DA4", "filtre"],
    ["DC1", "DC2", "DC3", "DC4", "O", "DB1", "DB2", "DB3", "DB4", ""],
    ["DD1", "DD2", "DD3", "DD4", "O", "DC1", "DC2", "DC3", "DC4", "jointure"],
    ["DE1", "DE2", "DE3", "DE4", "O", "DD1", "DD2", "DD3", "DD4", "calcul"],
    ["DF1", "DF2", "DF3", "DF4", "O", "DE1", "DE2", "DE3", "DE4", ""],
    ["DA1", "DA2", "DA3", "DA4", "O", "EA1", "EA2", "EA3", "EA4", "chargement"],
    ["DB1", "DB2", "DB3", "DB4", "I", "EB1", "EB2", "EB3", "EB4", ""],
    ["DC1", "DC2", "DC3", "DC4", "I", "EC1", "EC2", "EC3", "EC4", "copie"],
    ["DD1", "DD2", "DD3", "DD4", "O", "ED1", "ED2", "ED3", "ED4", ""],
    ["DE1", "DE2", "DE3", "DE4", "I", "EE1", "EE2", "EE3", "EE4", "tri"],
    ["DF1", "DF2", "DF3", "DF4", "I", "EF1", "EF2", "EF3", "EF4", "export"],
  ],
  noeuds: [
    ["Nœud_1", "Nœud_2", "Nœud_3", "Nœud_4", "Cara_vis"],
    ["DB1", "DB2", "DB3", "DB4", "V"],
    ["DA1", "DA2", "DA3", "DA4", "U"],
    ["DC1", "DC2", "DC3", "DC4", "R"],
    ["DD1", "DD2", "DD3", "DD4", "V"],
    ["DE1", "DE2", "DE3", "DE4", "G"],
    ["DF1", "DF2", "DF3", "DF4", "V"],
    ["EA1", "EA2", "EA3", "EA4", "U"],
    ["EB1", "EB2", "EB3", "EB4", "U"],
    ["EC1", "EC2", "EC3", "EC4", "V"],
    ["ED1", "ED2", "ED3", "ED4", "V"],
    ["EE1", "EE2", "EE3", "EE4", "G"],
    ["EF1", "EF2", "EF3", "EF4", "V"],
  ],
};
// <exemples-fin>

/* ------------------------------------------------------------------
   1 bis. Caractère d'un nœud (colonne Cara_vis de l'onglet « Noeud »)
   ------------------------------------------------------------------
   Le caractère est une valeur courte (V, R, C, U, G…). La liste n'est
   PAS figée : la liste déroulante « Caractère » et la légende sont
   remplies avec les caractères réellement présents dans le fichier
   (voir refreshCaraUi, section 5 ter).

   CARA_COULEURS : couleur de fond d'un nœud pour les caractères connus.
   Pour en changer une, modifier la valeur ici (la légende suit toute
   seule). Un caractère inconnu reçoit une couleur de CARA_COULEURS_EN_PLUS,
   dans l'ordre (le 1er inconnu la 1re couleur, etc.).
------------------------------------------------------------------ */
const CARA_COULEURS = {
  V: "#22c55e", // vert
  R: "#ef4444", // rouge
  C: "#9ca3af", // gris
  U: "#3b82f6", // bleu
  G: "#b45309", // ocre / brun
};
const CARA_COULEURS_EN_PLUS = ["#14b8a6", "#e879f9", "#84cc16", "#a8a29e", "#0ea5e9", "#fb7185"];

// caraColors(caras) : pour une liste de caractères, renvoie un objet
// { caractère: couleur }. Les connus prennent leur couleur de CARA_COULEURS,
// les autres se partagent CARA_COULEURS_EN_PLUS (on recommence au début
// s'il y en a plus que de couleurs).
//   ex. caraColors(["V", "X"]) -> { V: "#22c55e", X: "#14b8a6" }
function caraColors(caras) {
  const couleurs = {};
  let k = 0; // prochaine couleur « en plus » à donner
  caras.forEach((c) => {
    if (CARA_COULEURS[c]) couleurs[c] = CARA_COULEURS[c];
    else couleurs[c] = CARA_COULEURS_EN_PLUS[k++ % CARA_COULEURS_EN_PLUS.length];
  });
  return couleurs;
}

// caraList(nodes) : les caractères présents parmi les nœuds, sans doublon,
// triés : d'abord ceux de CARA_COULEURS (dans leur ordre), puis les autres
// par ordre alphabétique.   ex. -> ["V", "R", "U", "G"]
function caraList(nodes) {
  const connus = Object.keys(CARA_COULEURS);
  const presents = [...new Set(nodes.map((n) => n.cara).filter((c) => c))];
  const rangDe = (c) => (connus.includes(c) ? connus.indexOf(c) : connus.length);
  return presents.sort((a, b) => rangDe(a) - rangDe(b) || a.localeCompare(b));
}

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

   Cas particulier : une ligne où UN SEUL côté est rempli (par ex. seulement
   dta_1..dta_4, sans edg_* ni edg_dir) décrit un nœud ISOLÉ : il apparaît
   dans le graphe mais n'a aucune arête.

   En-têtes reconnus de façon tolérante : dta_1..dta_4 / edg_1..edg_4
   (avec ou sans « _ », « edg4 » accepté) ; colonne de sens = tout
   en-tête contenant « dir » (edg_dir, edr_dir, direction…) ; colonne de
   transformation = tout en-tête contenant « txn » (txn_dta…).

   La colonne de sens (edg_dir) est OPTIONNELLE : si elle manque, ou si
   elle est vide sur une ligne où dta et edg sont tous deux remplis, on ne
   crée pas d'arête pour cette ligne (les deux nœuds restent dans le graphe).

   La colonne txn_dta est OPTIONNELLE elle aussi : c'est la TRANSFORMATION
   appliquée sur l'arête (données <-> edg) décrite par la ligne. Si elle est
   absente ou vide, la transformation de l'arête reste une chaîne vide "".

   rowsToGraph ne lit QUE l'onglet « Arc ». Le CARACTÈRE des nœuds vient
   de l'autre onglet, « Noeud » (voir noeudRowsToCara et buildGraph
   juste après) : rowsToGraph renvoie donc des nœuds avec cara = "".
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
  let txnCol = -1;

  header.forEach((name, idx) => {
    // idx = position de la colonne (0, 1, 2...). name = l'en-tête normalisé.
    let m;
    // /^dta[ _-]?0*([1-4])$/ : "dta", puis éventuellement _ - ou espace, d'éventuels
    // zéros, puis un chiffre 1-4 (récupéré dans m[1]). "dta_3", "dta3", "dta 03" -> ok.
    if ((m = name.match(/^dta[ _-]?0*([1-4])$/))) dtaCol[m[1]] = idx;
    else if ((m = name.match(/^edg[ _-]?0*([1-4])$/))) edgCol[m[1]] = idx;
    // Colonne de sens : n'importe quel en-tête qui contient "dir" (edg_dir, edr_dir...).
    else if (name.includes("dir")) dirCol = idx;
    // Colonne de transformation : n'importe quel en-tête qui contient "txn" (txn_dta...).
    else if (name.includes("txn")) txnCol = idx;
  });

  if (Object.keys(dtaCol).length === 0 || Object.keys(edgCol).length === 0) {
    throw new Error(
      "Colonnes attendues introuvables : il faut au moins une colonne dta_* et une colonne edg_* " +
        "(en-têtes lus : " + header.join(", ") + ")."
    );
  }
  // La colonne de sens (edg_dir) est OPTIONNELLE. Si elle est absente
  // (dirCol reste -1), ou vide sur une ligne donnée, on ne pourra pas
  // orienter l'arête de cette ligne : on enregistrera alors les deux nœuds
  // SANS créer d'arête entre eux (voir la boucle plus bas).

  // Point d'arrêt : vérifier le repérage des colonnes (dtaCol, edgCol, dirCol).
  brk("rowsToGraph — colonnes repérées. Regarde: header, dtaCol, edgCol, dirCol");

  // (joinParts, qui reconstitue le nom "4.3.2.1" d'un nœud, est définie
  //  juste après rowsToGraph : l'onglet « Noeud » s'en sert aussi.)

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

    if (!dtaNode && !edgNode) {
      // les DEUX côtés sont vides : rien à faire, on prévient et on passe.
      console.warn(`Ligne ${r + 1} ignorée : nœud « données » ET « edg » vides.`);
      continue;
    }

    // On enregistre le type de chaque nœud présent (il peut n'y en avoir qu'un).
    if (dtaNode) noteKind(dtaNode, "dta");
    if (edgNode) noteKind(edgNode, "edg");

    // Un seul côté rempli (ex. une ligne avec dta_1..dta_4 mais pas de edg_*
    // ni de edg_dir) : c'est un nœud ISOLÉ. On le garde dans la liste des
    // nœuds, mais il n'y a AUCUNE arête à créer, donc on s'arrête là.
    if (!dtaNode || !edgNode) {
      brk(`rowsToGraph — ligne ${r + 1} : nœud isolé « ${dtaNode || edgNode} »`);
      continue;
    }

    // Transformation portée par cette ligne (colonne txn_dta). "" si la
    // colonne est absente ou vide sur cette ligne.
    const txn = String(row[txnCol] == null ? "" : row[txnCol]).trim();

    // À partir d'ici : les deux côtés sont remplis. Il faut un sens pour
    // orienter l'arête. Le sens : colonne dir en majuscules, 1re lettre seule.
    // (row[dirCol] vaut undefined si la colonne edg_dir n'existe pas -> "".)
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
      // Sens absent ou non reconnu : on garde les deux nœuds (déjà notés
      // plus haut) mais on NE crée PAS d'arête. Si une autre ligne les relie,
      // ils ne seront pas comptés comme isolés (le compteur « isolés » se
      // base sur le degré réel, arêtes de toutes les lignes confondues).
      console.warn(
        `Ligne ${r + 1} : sens « ${row[dirCol] == null ? "" : row[dirCol]} » ` +
          `absent ou non reconnu (attendu I ou O) -> aucune arête créée pour cette ligne.`
      );
      continue;
    }

    // Point d'arrêt (une fois par ligne de données) : voir ce qu'on a extrait.
    brk(`rowsToGraph — ligne ${r + 1}. Regarde: dtaNode, edgNode, dir, source, target`);

    // On ajoute l'arête, sauf si ce couple (source, target) a déjà été rencontré.
    // "\n" comme séparateur de clé : il n'apparaît jamais dans un nom de nœud.
    const key = source + "\n" + target;
    if (!edgeSet.has(key)) {
      edgeSet.add(key);
      edges.push({ source, target, txn });
    }
  }

  if (nodeKind.size === 0) {
    throw new Error("Aucune ligne de données exploitable dans le fichier.");
  }

  // --- 2.4  On transforme la Map des nœuds en liste finale ---------------
  // Pour chaque nœud : son id + son "kind" (utilisé par renderGraph pour la couleur)
  // + son caractère "cara", vide ici : il est rempli ensuite par buildGraph
  // à partir de l'onglet « Noeud ».
  const nodes = [...nodeKind.entries()].map(([id, kinds]) => ({
    id,
    // "both" si le nœud est à la fois donnée et edg, sinon l'un des deux.
    kind: kinds.has("dta") && kinds.has("edg") ? "both" : kinds.has("edg") ? "edg" : "dta",
    cara: "",
  }));

  // Point d'arrêt : le graphe final avant affichage.
  brk("rowsToGraph — sortie. Regarde: nodes, edges");

  return { nodes, edges };
}

/* joinParts : reconstituer le nom d'un nœud.
   À partir d'une ligne et d'un plan de colonnes (dtaCol, edgCol, ou les
   colonnes Nœud_1..Nœud_4), recolle "morceau4.morceau3.morceau2.morceau1".
     Ex. row = ["DA1","DA2","DA3","DA4", ...], cols = {1:0, 2:1, 3:2, 4:3}
         -> row[3],row[2],row[1],row[0] = "DA4","DA3","DA2","DA1" -> "DA4.DA3.DA2.DA1"
   C'est la MÊME règle pour les deux onglets : c'est ce qui permet de
   retrouver, dans l'onglet « Noeud », le nœud dessiné depuis l'onglet « Arc ». */
function joinParts(row, cols) {
  return ["4", "3", "2", "1"] // ordre voulu : 4 puis 3 puis 2 puis 1
    .map((k) => (cols[k] == null ? "" : row[cols[k]])) // valeur du morceau k ("" si colonne absente)
    .map((v) => String(v == null ? "" : v).trim()) // en texte, sans espaces au bord
    .filter((v) => v !== "") // on jette les morceaux vides
    .join("."); // on recolle avec des points
}

/* ------------------------------------------------------------------
   2 bis. Onglet « Noeud » : le CARACTÈRE de chaque nœud
   ------------------------------------------------------------------
   Une ligne par nœud :

     | Nœud_1 | Nœud_2 | Nœud_3 | Nœud_4 | Cara_vis |
     | DA1    | DA2    | DA3    | DA4    | U        |

     - nœud     = concaténation Nœud_4.Nœud_3.Nœud_2.Nœud_1 (même règle que
                  les dta_* / edg_* de l'onglet « Arc ») -> "DA4.DA3.DA2.DA1"
     - Cara_vis = son caractère (V, R, C, U, G… en majuscules ; "v" = "V").

   En-têtes reconnus de façon tolérante : Nœud_1, Noeud_1, noeud1, node_1…
   pour les morceaux ; tout en-tête contenant « cara » pour le caractère.

   Renvoie une Map  nom du nœud -> caractère.
   Un nœud écrit sur plusieurs lignes garde le 1er caractère rencontré
   (avertissement dans la console F12 si une autre ligne en donne un autre).
------------------------------------------------------------------ */
function noeudRowsToCara(rows) {
  brk("noeudRowsToCara — entrée. Regarde: rows");
  const nodeCara = new Map();
  if (!rows || rows.length < 2) return nodeCara; // onglet vide : aucun caractère

  // En-têtes normalisés : texte, sans espaces au bord, en minuscules.
  const header = rows[0].map((h) => String(h == null ? "" : h).trim().toLowerCase());

  const partCol = {}; // { "1": 0, "2": 1, ... } -> le morceau n°1 est en colonne 0
  let caraCol = -1;   // colonne Cara_vis, -1 tant qu'on ne l'a pas trouvée
  header.forEach((name, idx) => {
    let m;
    // "nœud", "noeud", "noud" ou "node", puis éventuellement _ - ou espace,
    // d'éventuels zéros, puis un chiffre 1-4 (récupéré dans m[1]).
    if ((m = name.match(/^(?:n(?:œ|oe|o)ud|node)[ _-]?0*([1-4])$/))) partCol[m[1]] = idx;
    else if (name.includes("cara")) caraCol = idx;
  });

  if (Object.keys(partCol).length === 0 || caraCol < 0) {
    throw new Error(
      "Onglet « Noeud » : il faut au moins une colonne Nœud_1..Nœud_4 et une colonne Cara_vis " +
        "(en-têtes lus : " + header.join(", ") + ")."
    );
  }

  for (let r = 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const id = joinParts(row, partCol);
    const cara = String(row[caraCol] == null ? "" : row[caraCol]).trim().toUpperCase();
    if (!id) {
      if (cara) console.warn(`Onglet Noeud, ligne ${r + 1} ignorée : nom du nœud vide.`);
      continue;
    }
    if (!cara) continue; // pas de caractère pour ce nœud : il restera neutre

    const before = nodeCara.get(id);
    if (!before) nodeCara.set(id, cara);
    else if (before !== cara) {
      console.warn(
        `Onglet Noeud, ligne ${r + 1} : le nœud « ${id} » a déjà le caractère ${before}, ` +
          `${cara} ignoré.`
      );
    }
  }

  brk("noeudRowsToCara — sortie. Regarde: nodeCara");
  return nodeCara;
}

/* ------------------------------------------------------------------
   2 ter. Assemblage des deux onglets -> graphe { nodes, edges }
   ------------------------------------------------------------------
   1. l'onglet « Arc » donne les nœuds et les arêtes (rowsToGraph) ;
   2. l'onglet « Noeud » donne le caractère de chaque nœud (noeudRowsToCara) ;
   3. on recopie ce caractère sur les nœuds du graphe.
   Un nœud de l'onglet « Noeud » qui n'apparaît dans AUCUN arc est ajouté
   comme nœud ISOLÉ (sans arête), avec son caractère.
   noeudRows peut être absent (fichier sans onglet « Noeud ») : les nœuds
   sont alors tous sans caractère.
------------------------------------------------------------------ */
function buildGraph(arcRows, noeudRows) {
  const graph = rowsToGraph(arcRows);
  const nodeCara = noeudRows ? noeudRowsToCara(noeudRows) : new Map();

  const dejaLa = new Set(); // ids des nœuds venant de l'onglet « Arc »
  graph.nodes.forEach((n) => {
    n.cara = nodeCara.get(n.id) || "";
    dejaLa.add(n.id);
  });

  nodeCara.forEach((cara, id) => {
    if (dejaLa.has(id)) return;
    console.warn(`Onglet Noeud : « ${id} » n'apparaît dans aucun arc -> ajouté comme nœud isolé.`);
    graph.nodes.push({ id, kind: "dta", cara });
  });

  brk("buildGraph — sortie. Regarde: graph.nodes (avec cara), graph.edges");
  return graph;
}

/* findSheet : retrouve un onglet du classeur par son nom.
   - motifs  : morceaux de nom acceptés, ex. ["arc"] ou ["noeud", "node"] ;
     le nom de l'onglet est comparé en minuscules et sans accents
     ("Nœud" -> "noeud"), donc "Arc", "ARCS", "Noeud", "Nœuds" marchent ;
   - secours : position (0 = 1er onglet) à prendre si aucun nom ne convient.
   Renvoie le NOM de l'onglet, ou undefined. */
function findSheet(wb, motifs, secours) {
  const simplifie = (s) =>
    String(s)
      .toLowerCase()
      .replace(/œ/g, "oe")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, ""); // enlève les accents (é -> e)
  const trouve = wb.SheetNames.find((nom) => motifs.some((m) => simplifie(nom).includes(m)));
  return trouve !== undefined ? trouve : wb.SheetNames[secours];
}

/* Lit un fichier .xlsx (ArrayBuffer) et renvoie le graphe { nodes, edges }.
   C'est le pont entre la librairie XLSX (SheetJS) et buildGraph.
   Le classeur a DEUX onglets :
     - « Arc »   (sinon le 1er onglet)  : les arcs ;
     - « Noeud » (sinon le 2e onglet)   : le caractère de chaque nœud.
   S'il n'y a qu'un onglet, on le lit comme « Arc » et les nœuds n'ont
   pas de caractère. */
function workbookBufferToGraph(buffer) {
  // XLSX.read : décode le fichier binaire en "classeur" (workbook) en mémoire.
  const wb = XLSX.read(new Uint8Array(buffer), { type: "array" });
  if (wb.SheetNames.length === 0) throw new Error("Le classeur Excel ne contient aucune feuille.");

  const nomArc = findSheet(wb, ["arc"], 0);
  let nomNoeud = findSheet(wb, ["noeud", "node"], 1);
  if (nomNoeud === nomArc) nomNoeud = undefined; // un seul onglet : pas d'onglet « Noeud »
  if (!nomNoeud) console.warn("Pas d'onglet « Noeud » : les nœuds n'auront pas de caractère.");

  // sheet_to_json({header:1}) : convertit une feuille en tableau de tableaux
  // (une sous-liste par ligne), exactement la forme attendue par buildGraph.
  const lire = (nom) =>
    XLSX.utils.sheet_to_json(wb.Sheets[nom], { header: 1, blankrows: false, defval: "" });

  brk(`workbookBufferToGraph — onglets : Arc = « ${nomArc} », Noeud = « ${nomNoeud} »`);
  return buildGraph(lire(nomArc), nomNoeud ? lire(nomNoeud) : null);
}

/* ------------------------------------------------------------------
   3. Références vers les éléments du DOM (le HTML)
   ------------------------------------------------------------------
   app.js est chargé dans le <head> : quand il s'exécute, le <body> n'est
   PAS ENCORE construit (les boutons, le <div id="cy">... n'existent pas).
   On déclare donc les variables ici (vides), et on les remplit plus tard
   dans getDomRefs(), appelée au démarrage (voir la section 10 tout en bas)
   une fois la page entièrement construite.
------------------------------------------------------------------ */
let stage, dropzone, stageError, legend, fileInput,
  exampleParcoursBtn, exampleAdjacentBtn, fileNameEl, layoutSelect, fitBtn,
  pngBtn, selectionHint, selectionDetail, selIdEl, succCountEl,
  predCountEl, succTableBodyEl, predTableBodyEl, statsEl, caraSelect, legendCara,
  // panneau « Pagination »
  pagerCard, pagerInfo, pageInput, pageTotalEl, pageFirstBtn, pagePrevBtn,
  pageNextBtn, pageLastBtn, nodeSearchInput, nodeSearchBtn, pageSizeSelect;

function getDomRefs() {
  stage = document.getElementById("stage");
  dropzone = document.getElementById("dropzone");
  stageError = document.getElementById("stage-error");
  legend = document.getElementById("legend");
  fileInput = document.getElementById("file-input");
  exampleParcoursBtn = document.getElementById("example-parcours-btn");
  exampleAdjacentBtn = document.getElementById("example-adjacent-btn");
  fileNameEl = document.getElementById("file-name");
  layoutSelect = document.getElementById("layout-select");
  fitBtn = document.getElementById("fit-btn");
  pngBtn = document.getElementById("png-btn");
  selectionHint = document.getElementById("selection-hint");
  selectionDetail = document.getElementById("selection-detail");
  selIdEl = document.getElementById("sel-id");
  succCountEl = document.getElementById("succ-count");
  predCountEl = document.getElementById("pred-count");
  succTableBodyEl = document.getElementById("succ-table-body");
  predTableBodyEl = document.getElementById("pred-table-body");
  statsEl = document.getElementById("stats");
  caraSelect = document.getElementById("cara-select");
  legendCara = document.getElementById("legend-cara");
  pagerCard = document.getElementById("pager-card");
  pagerInfo = document.getElementById("pager-info");
  pageInput = document.getElementById("page-input");
  pageTotalEl = document.getElementById("page-total");
  pageFirstBtn = document.getElementById("page-first");
  pagePrevBtn = document.getElementById("page-prev");
  pageNextBtn = document.getElementById("page-next");
  pageLastBtn = document.getElementById("page-last");
  nodeSearchInput = document.getElementById("node-search");
  nodeSearchBtn = document.getElementById("node-search-btn");
  pageSizeSelect = document.getElementById("page-size");
}

/* État global de l'application */
let cy = null;            // instance cytoscape en cours
let currentData = null;   // graphe de la PAGE affichée { nodes, edges } (avec ses nœuds fantômes)
let fullData = null;      // graphe COMPLET lu dans le fichier (toutes les pages)
let currentMode = "";     // mode du fichier : "parcours", "adjacent" ou ""

/* État de la pagination (voir section 4 ter) */
let pages = [];           // pages[p] = liste des ids des nœuds de la page p (p commence à 0)
let pageOf = new Map();   // id d'un nœud -> numéro de sa page
let currentPage = 0;      // page affichée

/* ------------------------------------------------------------------
   4. Configuration des dispositions (layouts) cytoscape
   ------------------------------------------------------------------
   La clé correspond à la <option> du <select> dans index.html.
------------------------------------------------------------------ */
const LAYOUT_CONFIGS = {
  // Disposition hiérarchique faite par dagre (vendor/dagre.min.js, branché
  // sur cytoscape par vendor/cytoscape-dagre.min.js) : name: "dagre".
  // rankDir : sens de la hiérarchie. "TB" = Top->Bottom (de haut en bas),
  //           "LR" = Left->Right (de gauche à droite, comme un arbre couché).
  // nodeSep : espace entre deux nœuds d'un même niveau ; rankSep : espace entre niveaux.
  dagre: { name: "dagre", rankDir: "TB", nodeSep: 45, rankSep: 90, animate: true },
  dagreLR: { name: "dagre", rankDir: "LR", nodeSep: 45, rankSep: 90, animate: true },
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

// Au-delà de SEUIL_ANIMATION éléments (nœuds + arcs) visibles, la mise en page
// est faite SANS animation : faire glisser 2000 nœuds à l'écran est lent et
// n'apporte rien. En dessous, on garde l'animation comme avant.
const SEUIL_ANIMATION = 600;

// layoutConfig(nbElements, animer) : les réglages de la disposition choisie
// dans la liste « Mise en page », avec l'animation coupée si le graphe est
// gros (nbElements > SEUIL_ANIMATION) ou si animer vaut false.
//   ...base = on recopie tous les réglages de base, puis on remplace "animate".
function layoutConfig(nbElements, animer = true) {
  const base = LAYOUT_CONFIGS[layoutSelect.value] || LAYOUT_CONFIGS.dagre;
  return { ...base, animate: base.animate && animer && nbElements <= SEUIL_ANIMATION };
}

/* ------------------------------------------------------------------
   4 ter. Pagination : le graphe découpé en pages de taillePage nœuds
   ------------------------------------------------------------------
   Un fichier peut contenir des centaines de milliers de nœuds : trop pour
   cytoscape (et illisible). On ne dessine donc qu'UNE page à la fois.

   Comment on découpe (buildPages) :
     1. on cherche les COMPOSANTES CONNEXES du graphe : les « morceaux »
        de nœuds reliés entre eux (en ignorant le sens des flèches) ;
     2. on range ces morceaux dans les pages, du plus gros au plus petit,
        sans dépasser taillePage nœuds par page. Un morceau n'est JAMAIS
        coupé en deux s'il tient dans une page => aucun arc perdu ;
     3. seul un morceau PLUS GROS qu'une page est coupé, en tranches de
        taillePage nœuds prises dans l'ordre d'un parcours en largeur
        (BFS) : chaque tranche reste un bloc de nœuds voisins.

   Les arcs coupés (cas 3 seulement) : quand un arc relie un nœud de la
   page à un nœud d'une AUTRE page, l'autre bout est dessiné comme un
   NŒUD FANTÔME (gris, bordure pointillée, libellé « → p.12 nom »).
   Cliquer un nœud fantôme ouvre la page où se trouve le vrai nœud
   (voir goToNode).
------------------------------------------------------------------ */
// Nombre maximum de nœuds par page : la valeur choisie dans la liste
// « Taille de page » du panneau Pagination (500 / 1000 / 2000).
// Plus petit = changement de page plus rapide (dagre est ~3 fois plus
// rapide sur 1000 nœuds que sur 2000).
let taillePage = 2000;

// Positions des nœuds des pages déjà mises en page (voir runLayout) :
// clé (cleCache) -> { idNœud: { x, y } }. Vidé à chaque nouveau fichier.
let positionsCache = new Map();
// Dernières statistiques calculées (graphe complet) : réaffichées sans
// recalcul quand on change la taille de page.
let dernieresStats = null;
// Préfixe de l'id d'un nœud fantôme : "fantome:" + id du vrai nœud.
// (Le vrai nœud et son fantôme ne sont jamais sur la même page, mais les
//  ids restent ainsi distincts et on sait reconnaître un fantôme.)
const PREFIXE_FANTOME = "fantome:";

function buildPages(data, taille) {
  // a) Voisins de chaque nœud DANS LES DEUX SENS (le sens des flèches ne
  //    compte pas pour savoir si deux nœuds sont dans le même morceau).
  const voisins = new Map();
  data.nodes.forEach((n) => voisins.set(n.id, []));
  data.edges.forEach((e) => {
    voisins.get(e.source).push(e.target);
    voisins.get(e.target).push(e.source);
  });

  // b) Composantes connexes par parcours en LARGEUR (BFS).
  //    Astuce de vitesse : au lieu de retirer le 1er élément de la file
  //    (file.shift(), lent sur une grande liste), on avance un index i.
  //    La liste « comp » sert à la fois de file d'attente et de résultat,
  //    et elle est dans l'ordre BFS (utile pour couper un gros morceau).
  const vu = new Set();
  const composantes = [];
  for (const n of data.nodes) {
    if (vu.has(n.id)) continue; // déjà rangé dans un morceau
    const comp = [n.id];
    vu.add(n.id);
    for (let i = 0; i < comp.length; i++) {
      for (const v of voisins.get(comp[i])) {
        if (!vu.has(v)) {
          vu.add(v);
          comp.push(v);
        }
      }
    }
    composantes.push(comp);
  }

  // c) Du plus gros morceau au plus petit : les petits viennent à la fin
  //    et comblent bien les pages.
  composantes.sort((a, b) => b.length - a.length);

  // d) Remplissage des pages.
  const resultat = [];
  let page = [];
  const fermerPage = () => {
    if (page.length) resultat.push(page);
    page = [];
  };
  for (const comp of composantes) {
    if (comp.length > taille) {
      // Morceau trop gros : tranches de `taille` nœuds (ordre BFS).
      fermerPage();
      for (let i = 0; i < comp.length; i += taille) resultat.push(comp.slice(i, i + taille));
      continue;
    }
    // Le morceau ne tient plus dans la page en cours : on en ouvre une autre.
    if (page.length + comp.length > taille) fermerPage();
    for (const id of comp) page.push(id);
  }
  fermerPage();
  return resultat;
}

/* decouperEnPages : (re)découpe fullData en pages de taillePage nœuds et
   remplit la table pageOf (id d'un nœud -> numéro de sa page). */
function decouperEnPages() {
  pages = buildPages(fullData, taillePage);
  pageOf = new Map();
  pages.forEach((ids, p) => ids.forEach((id) => pageOf.set(id, p)));
}

/* changerTaillePage : appelée quand on choisit une autre « Taille de page ».
   On redécoupe, puis on rouvre la page qui contient le 1er nœud de la page
   qu'on regardait (pour ne pas être renvoyé au début). */
function changerTaillePage() {
  taillePage = parseInt(pageSizeSelect.value, 10) || 2000;
  if (!fullData) return; // aucun fichier chargé : la valeur servira au prochain
  const repere = pages[currentPage] ? pages[currentPage][0] : undefined;
  decouperEnPages();
  showPage(repere !== undefined ? pageOf.get(repere) : 0);
  if (dernieresStats) renderStats(dernieresStats); // met à jour le nombre de pages
}

/* pageData(p) : le petit graphe { nodes, edges } de la page p, prêt à
   dessiner. Il contient :
     - les nœuds de la page ;
     - les arcs dont les DEUX bouts sont dans la page ;
     - pour chaque arc qui SORT de la page : un nœud fantôme à la place du
       bout extérieur (un seul fantôme par nœud extérieur, même s'il est
       touché par plusieurs arcs). */
function pageData(p) {
  const dansPage = new Set(pages[p]);
  const nodes = fullData.nodes.filter((n) => dansPage.has(n.id));
  const fantomes = new Map(); // id du vrai nœud extérieur -> son nœud fantôme
  const edges = [];

  fullData.edges.forEach((e) => {
    const s = dansPage.has(e.source);
    const t = dansPage.has(e.target);
    if (s && t) {
      edges.push(e); // arc entièrement dans la page : tel quel
    } else if (s || t) {
      // Un seul bout dans la page : l'autre est remplacé par un fantôme.
      const dehors = s ? e.target : e.source;
      const idFantome = PREFIXE_FANTOME + dehors;
      if (!fantomes.has(dehors)) {
        fantomes.set(dehors, {
          id: idFantome,
          kind: "fantome",
          cara: "",
          fantome: true,
          realId: dehors,              // le vrai nœud
          page: pageOf.get(dehors),    // sa page (numéro à partir de 0)
        });
      }
      edges.push({
        source: s ? e.source : idFantome,
        target: t ? e.target : idFantome,
        txn: e.txn,
      });
    }
    // aucun bout dans la page : l'arc n'est pas dessiné sur cette page
  });

  return { nodes: [...nodes, ...fantomes.values()], edges, nbFantomes: fantomes.size };
}

/* showPage(p, animer) : dessine la page p.
   animer = false quand on veut que les nœuds soient à leur place tout de
   suite (par ex. pour centrer ensuite la vue sur un nœud, voir goToNode). */
function showPage(p, animer = true) {
  if (!fullData || pages.length === 0) return;
  currentPage = Math.max(0, Math.min(p, pages.length - 1)); // reste entre 1re et dernière page
  currentData = pageData(currentPage);
  renderGraph(currentData, currentMode, animer);
  clearSelection();
  refreshPagerUi();
}

/* goToNode(id) : ouvre la page du nœud `id`, le sélectionne et centre la
   vue dessus. Utilisée par un clic sur un nœud fantôme, et par le champ
   « Chercher un nœud » du panneau Pagination. */
function goToNode(id) {
  const p = pageOf.get(id);
  if (p === undefined) {
    showError(`Nœud « ${id} » introuvable.`);
    return;
  }
  hideError();
  if (p !== currentPage) showPage(p, false); // false : positions finales tout de suite
  selectNode(id);
  // On zoome au moins à 100 % (sur 2000 nœuds la vue d'ensemble est très
  // dézoomée), puis on centre sur le nœud.
  cy.zoom(Math.max(cy.zoom(), 1));
  cy.center(cy.$id(id));
}

/* findNodeId(texte) : l'id du nœud qui correspond au texte tapé.
   D'abord un nom EXACT ; sinon le 1er nom qui CONTIENT le texte (sans
   tenir compte des majuscules). Renvoie undefined si rien ne correspond. */
function findNodeId(texte) {
  const t = String(texte || "").trim();
  if (!t) return undefined;
  if (pageOf.has(t)) return t;
  const bas = t.toLowerCase();
  const trouve = fullData.nodes.find((n) => n.id.toLowerCase().includes(bas));
  return trouve ? trouve.id : undefined;
}

/* refreshPagerUi : met à jour le panneau « Pagination » (numéro de page,
   boutons actifs ou grisés, résumé de la page). */
function refreshPagerUi() {
  const total = pages.length;
  pagerCard.hidden = total === 0;
  if (total === 0) return;

  pageInput.max = total;
  pageInput.value = currentPage + 1; // affiché à partir de 1, rangé à partir de 0
  pageTotalEl.textContent = total.toLocaleString("fr-FR");
  pageFirstBtn.disabled = pagePrevBtn.disabled = currentPage === 0;
  pageLastBtn.disabled = pageNextBtn.disabled = currentPage === total - 1;

  const nbNoeuds = pages[currentPage].length;
  const nbArcs = currentData.edges.length;
  const f = currentData.nbFantomes;
  pagerInfo.textContent =
    `${nbNoeuds.toLocaleString("fr-FR")} nœuds, ${nbArcs.toLocaleString("fr-FR")} arcs sur cette page` +
    (f ? ` — ${f.toLocaleString("fr-FR")} nœud(s) fantôme(s) vers d'autres pages` : "");
}

/* ------------------------------------------------------------------
   4 bis. Mode de présentation déduit du NOM du fichier importé
   ------------------------------------------------------------------
   Le nom du fichier se termine par un suffixe qui dit comment l'afficher :
     ..._parcours.xlsx  -> mode "parcours" : TOUS les nœuds sont des parcours
                           => tous en JAUNE ;
     ..._adjacent.xlsx  -> mode "adjacent" : seuls les nœuds « données »
                           (dta_1..dta_4) sont des parcours => JAUNE ;
                           les nœuds edg_1..edg_4 restent neutres (BLEU).
     autre nom          -> mode ""  : couleurs normales (bleu / violet / rose).
   La casse est ignorée ("Parcours", "PARCOURS"... marchent), et le séparateur
   avant le suffixe n'a pas d'importance ("x_parcours", "x-parcours", "xparcours").
   Les arcs suivent la même règle dans tous les modes : trait plein si une
   transformation (txn_dta) est renseignée, pointillé sinon.
------------------------------------------------------------------ */
function modeFromFileName(fileName) {
  // On enlève l'extension (".xlsx", ".xls"...) puis on passe en minuscules.
  //   "Lineage_Parcours.xlsx" -> "lineage_parcours"
  const base = String(fileName || "").replace(/\.[^.]*$/, "").trim().toLowerCase();
  if (base.endsWith("parcours")) return "parcours";
  if (base.endsWith("adjacent")) return "adjacent";
  return ""; // pas de suffixe reconnu
}

// Un nœud est-il « parcours » (donc jaune) dans ce mode ?
//   - mode parcours : oui, toujours ;
//   - mode adjacent : oui s'il vient des colonnes dta_* (kind "dta" ou "both") ;
//   - sinon         : non.
function isParcoursNode(node, mode) {
  if (mode === "parcours") return true;
  if (mode === "adjacent") return node.kind === "dta" || node.kind === "both";
  return false;
}

/* ------------------------------------------------------------------
   5. Rendu du graphe avec cytoscape
------------------------------------------------------------------ */
// data = la page à dessiner (voir pageData) ; animer = false pour placer
// les nœuds sans animation (voir layoutConfig).
function renderGraph(data, mode = "", animer = true) {
  // Point d'arrêt : `data` = { nodes, edges } sur le point d'être dessiné.
  brk("renderGraph — entrée. Regarde: data, mode, layoutSelect.value");

  // On repart de zéro à chaque nouveau fichier.
  if (cy) {
    cy.destroy();
    cy = null;
  }

  // Ensemble (Set) des nœuds « parcours » : sert à savoir, pour chaque arc,
  // si ses DEUX bouts sont des nœuds parcours (=> arc de parcours, avec halo).
  // Un nœud fantôme n'est jamais « parcours » : il reste gris (voir son style).
  const estParcours = (n) => !n.fantome && isParcoursNode(n, mode);
  const parcoursIds = new Set(data.nodes.filter(estParcours).map((n) => n.id));

  // Couleur de chaque caractère présent dans ce fichier ({ V: "#22c55e", ... }).
  const couleurDe = caraColors(caraList(data.nodes));

  // cytoscape veut UNE seule liste mêlant nœuds et arêtes, chacun sous la
  // forme { data: {...} }. Le "..." (spread) déverse le contenu d'un tableau
  // dans un autre : ici, tous les nœuds puis toutes les arêtes.
  const elements = [
    // un objet par nœud : id + label affiché + kind (pour la couleur)
    // + parcours ("oui" / "non") : "oui" => nœud colorié en jaune (voir le style)
    // + cara : le caractère V / R / C / U / G... ("" si non renseigné)
    // + caraColor : la couleur de fond de ce caractère ("" si pas de caractère).
    // Le label affiché commence par le caractère entre crochets quand il existe :
    //   cara "V" -> "[V] DA4.DA3.DA2.DA1" ; pas de caractère -> "DA4.DA3.DA2.DA1".
    // Nœud FANTÔME (bout d'un arc qui part vers une autre page, voir pageData) :
    //   fantome "oui", realId = le vrai nœud, page = sa page (0 = 1re),
    //   label « → p.12 DA4.DA3.DA2.DA1 » (numéro de page affiché à partir de 1).
    ...data.nodes.map((n) => ({
      data: {
        id: n.id,
        label: n.fantome
          ? `→ p.${n.page + 1} ${n.realId}`
          : n.cara ? `[${n.cara}] ${n.id}` : n.id,
        kind: n.kind || "dta",
        parcours: estParcours(n) ? "oui" : "non",
        cara: n.cara || "",
        caraColor: n.cara ? couleurDe[n.cara] : "",
        fantome: n.fantome ? "oui" : "non",
        realId: n.realId || n.id,
        page: n.fantome ? n.page : currentPage,
      },
    })),
    // un objet par arête : un id unique + les deux extrémités source/target
    ...data.edges.map((e) => ({
      data: {
        id: `${e.source}=>${e.target}`,
        source: e.source,
        target: e.target,
        txn: e.txn || "",
        // "oui" si l'arc relie DEUX nœuds parcours (source ET cible) => halo.
        parcours: parcoursIds.has(e.source) && parcoursIds.has(e.target) ? "oui" : "non",
      },
    })),
  ];

  // Grosse page ? (au-delà de SEUIL_ANIMATION nœuds + arcs) -> réglages de vitesse.
  const gros = elements.length > SEUIL_ANIMATION;

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
          // Sous 6 px à l'écran (graphe très dézoomé), le libellé n'est plus
          // dessiné : sinon 2000 libellés se chevauchent et c'est plus lent.
          // Il réapparaît dès qu'on zoome.
          "min-zoomed-font-size": 8,
        },
      },
      // Couleur selon le type de nœud (toutes de même forme : ronde/ellipse)
      // edg_* (bleu) vs données dta_* (violet) vs les deux (rose)
      { selector: 'node[kind = "edg"]', style: { "background-color": "#6ea8fe" } },
      { selector: 'node[kind = "dta"]', style: { "background-color": "#a78bfa" } },
      { selector: 'node[kind = "both"]', style: { "background-color": "#f472b6" } },
      // Nœuds « parcours » (mode déduit du nom du fichier) : JAUNE.
      // Placé APRÈS les règles "kind" pour les écraser, mais AVANT les règles
      // de sélection (selected / succ / pred) pour que le clic reste visible.
      {
        selector: 'node[parcours = "oui"]',
        style: {
          "background-color": "#fde047",
          "border-color": "#713f12",
          "border-width": 3,
          // HALO : une couleur jaune dessinée AUTOUR du nœud (« underlay » =
          // sous-couche plus grande que le nœud, derrière lui).
          //   underlay-padding : de combien le halo dépasse (en pixels) ;
          //   underlay-opacity : 0 = invisible, 1 = opaque ;
          //   underlay-shape   : même forme ronde que le nœud.
          "underlay-color": "#fde047",
          "underlay-padding": 9,
          "underlay-opacity": 0.35,
          "underlay-shape": "ellipse",
        },
      },
      // Couleur de FOND selon le CARACTÈRE du nœud (onglet « Noeud », Cara_vis) :
      //   V -> vert, R -> rouge, C -> gris, U -> bleu, G -> ocre (CARA_COULEURS).
      // "data(caraColor)" = « prends la couleur rangée dans le nœud »
      // (calculée plus haut). [caraColor != ""] = seulement s'il en a une.
      // Placé APRÈS la règle parcours : le fond jaune d'un nœud parcours est
      // remplacé par la couleur de son caractère, mais son HALO jaune et sa
      // bordure restent (ils ne sont pas redéfinis ici).
      // Un nœud SANS caractère garde l'ancienne couleur (bleu/violet/rose,
      // ou jaune s'il est parcours).
      // Placé AVANT les règles de sélection : le clic reste visible.
      { selector: 'node[caraColor != ""]', style: { "background-color": "data(caraColor)" } },
      // Nœud FANTÔME (vers une autre page) : gris foncé, bordure en pointillé,
      // libellé gris clair. Un clic dessus ouvre sa page (voir onNodeTap).
      {
        selector: 'node[fantome = "oui"]',
        style: {
          "background-color": "#334155",
          "border-color": "#94a3b8",
          "border-style": "dashed",
          "border-width": 2,
          color: "#cbd5e1",
          "font-size": 11,
          "text-valign": "bottom",
          "text-margin-y": 4,
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
          // Arcs courbes (bezier) sur une petite page ; arcs DROITS sur une
          // grosse page : beaucoup plus rapides à dessiner.
          "curve-style": gros ? "straight" : "bezier",
          // Par défaut (pas de transformation) : arc en POINTILLÉ.
          "line-style": "dashed",
        },
      },
      // Arc qui porte une transformation (txn_dta renseigné) : trait PLEIN,
      // plus épais et d'une couleur vive. [txn != ""] = « txn non vide ».
      {
        selector: 'edge[txn != ""]',
        style: {
          width: 3,
          "line-color": "#f43f5e",
          "target-arrow-color": "#f43f5e",
          "line-style": "solid",
        },
      },
      // Arc qui relie DEUX nœuds parcours : même HALO jaune autour de l'arc.
      // Le trait lui-même ne change pas (plein rouge ou pointillé gris,
      // selon txn_dta) : on ajoute seulement la couleur « aux alentours ».
      // Un arc dont un bout n'est pas parcours reste comme avant (sans halo).
      {
        selector: 'edge[parcours = "oui"]',
        style: {
          "underlay-color": "#fde047",
          "underlay-padding": 6,
          "underlay-opacity": 0.35,
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
        style: { "background-color": "#22d3ee", "border-color": "#155e75" },
      },
      {
        selector: "edge.succ",
        style: {
          "line-color": "#22d3ee",
          "target-arrow-color": "#22d3ee",
          width: 3.5,
        },
      },
      // Prédécesseurs du nœud cliqué (arêtes entrantes)
      {
        selector: "node.pred",
        style: { "background-color": "#f97316", "border-color": "#7c2d12" },
      },
      {
        selector: "edge.pred",
        style: {
          "line-color": "#f97316",
          "target-arrow-color": "#f97316",
          width: 3.5,
        },
      },
      // Éléments mis en retrait quand une sélection est active
      {
        selector: ".faded",
        style: { opacity: 0.12 },
      },
      // Filtre « Caractère » (voir applyCaraFilter, section 5 bis) :
      // - .cara-hidden : nœuds et arcs d'origine MASQUÉS (display none =
      //   plus dessinés du tout, et ignorés par la mise en page) ;
      // - .cara-edge   : arcs ajoutés entre deux nœuds du caractère choisi.
      //   Pas de flèche (arc sans orientation), trait plein gris clair, et
      //   pas de transformation (data txn = "").
      {
        selector: ".cara-hidden",
        style: { display: "none" },
      },
      {
        selector: "edge.cara-edge",
        style: {
          width: 2.5,
          "line-color": "#94a3b8",
          "line-style": "solid",
          "target-arrow-shape": "none",
        },
      },
    ],
    // Pas de mise en page ici : elle est lancée juste après (cache ou dagre,
    // voir plus bas), pour pouvoir réutiliser les positions déjà calculées.
    layout: { name: "preset" },
    // Réglages de VITESSE pour une grosse page (gros = plus de SEUIL_ANIMATION éléments) :
    //  - textureOnViewport : pendant un déplacement / zoom, cytoscape bouge une
    //    simple « photo » de la vue au lieu de tout redessiner ;
    //  - hideEdgesOnViewport : les arcs sont cachés pendant le déplacement / zoom
    //    (ils réapparaissent dès qu'on lâche la souris) ;
    //  - pixelRatio 1 : sur un écran haute résolution (ex. 150 %), on dessine
    //    2 à 4 fois moins de pixels (image un peu moins fine, bien plus rapide).
    textureOnViewport: gros,
    hideEdgesOnViewport: gros,
    pixelRatio: gros ? 1 : "auto",
  });

  // Clic sur un nœud -> voisins mis en évidence (ou, pour un fantôme, sa page)
  cy.on("tap", "node", (evt) => onNodeTap(evt.target.id()));
  // Clic dans le vide -> on efface la sélection
  cy.on("tap", (evt) => {
    if (evt.target === cy) clearSelection();
  });

  // Mise en page :
  //  - filtre « Tous » et page DÉJÀ VUE avec cette disposition : on remet les
  //    positions gardées en mémoire (layout "preset" = instantané) ;
  //  - filtre « Tous » et page nouvelle : vraie mise en page (dagre…), dont
  //    runLayout garde les positions pour la prochaine fois ;
  //  - un caractère choisi : c'est applyCaraFilter qui relance la mise en page
  //    sur les nœuds restants (pas de cache dans ce cas).
  if (!caraSelect.value) {
    const gardees = positionsCache.get(cleCache());
    if (gardees) cy.layout({ name: "preset", positions: (n) => gardees[n.id()], fit: true, padding: 30 }).run();
    else runLayout(animer);
  }
  // Le filtre « Caractère » choisi avant s'applique tout de suite
  // (false = pas de 2e mise en page si le filtre est « Tous » : faite juste au-dessus).
  applyCaraFilter(false);
}

/* ------------------------------------------------------------------
   5 ter. Liste « Caractère » et légende, remplies d'après le fichier
   ------------------------------------------------------------------
   Appelée par loadGraph à chaque chargement, AVANT renderGraph.
     - la liste déroulante reçoit « Tous » + un choix par caractère présent
       dans l'onglet « Noeud » (ex. Tous, V, R, U, G) ;
     - si le caractère choisi avant existe encore, il reste choisi ;
       sinon on revient sur « Tous » ;
     - la légende reçoit une pastille de couleur par caractère.
------------------------------------------------------------------ */
function refreshCaraUi(data) {
  const caras = caraList(data.nodes);
  const couleurs = caraColors(caras);

  // a) Liste déroulante
  const avant = caraSelect.value;
  caraSelect.innerHTML = "";
  ["", ...caras].forEach((c) => {
    const opt = document.createElement("option");
    opt.value = c;                 // "" = Tous
    opt.textContent = c || "Tous"; // texte visible
    caraSelect.appendChild(opt);
  });
  caraSelect.value = caras.includes(avant) ? avant : "";
  caraSelect.disabled = caras.length === 0; // aucun caractère : rien à filtrer

  // b) Légende : « [V] caractère du nœud : ■ V ■ R ... »
  legendCara.innerHTML = "";
  legendCara.hidden = caras.length === 0;
  const titre = document.createElement("span");
  titre.innerHTML = "<b>[V]</b> caractère du nœud :";
  legendCara.appendChild(titre);
  caras.forEach((c) => {
    const span = document.createElement("span");
    const pastille = document.createElement("i");
    pastille.className = "swatch";
    pastille.style.background = couleurs[c];
    span.appendChild(pastille);
    span.appendChild(document.createTextNode(" " + c));
    legendCara.appendChild(span);
  });
}

/* ------------------------------------------------------------------
   5 bis. Filtre « Caractère » (liste déroulante V / R / U / G…)
   ------------------------------------------------------------------
   caraSelect.value vaut "" (= Tous) ou l'un des caractères du fichier.
     - "" : le graphe complet est affiché normalement ;
     - "V" (par ex.) : on n'affiche QUE les nœuds de caractère V. Les autres
       nœuds sont masqués. Pour les arcs, deux cas :
         a) deux nœuds V qui SE SUIVENT (arc direct A -> B dans le fichier) :
            on GARDE l'arc d'origine, avec son ORIENTATION (flèche) et sa
            TRANSFORMATION (txn_dta, trait plein ou pointillé comme avant) ;
         b) deux nœuds V reliés en passant par des nœuds NON V : on les
            relie par un arc SANS ORIENTATION (pas de flèche) et SANS
            TRANSFORMATION (perdue, car le chemin en contenait plusieurs).
       Ex. (exemple parcours) : DA(V) -> EA -> DB -> EB -> DC -> EC(V)
           devient un seul arc  DA — EC  (cas b).
       Ex. (exemple_vert_adjacent.xlsx, tous V) : tous les nœuds se suivent,
           donc tous les arcs restent comme dans le graphe complet (cas a).
   Pour déclencher : choisir une valeur dans la liste « Caractère » du
   panneau latéral (événement "change", câblé dans wireEvents, section 9 g).
------------------------------------------------------------------ */
function applyCaraFilter(relayout = true) {
  if (!cy || !caraSelect) return; // aucun graphe affiché : rien à filtrer
  const choix = caraSelect.value;

  // 1) On repart de zéro : on retire la sélection, les arcs ajoutés par un
  //    filtre précédent, et on ré-affiche tout ce qui avait été masqué.
  clearSelection();
  cy.remove(".cara-edge");
  cy.elements().removeClass("cara-hidden");

  if (!choix) {
    // « Tous » : graphe complet, mise en page normale.
    if (relayout) runLayout();
    return;
  }

  // 2) Les nœuds à garder = ceux qui ont le caractère choisi.
  const garde = new Set(currentData.nodes.filter((n) => n.cara === choix).map((n) => n.id));

  // 3) Liste d'adjacence du graphe COMPLET : pour chaque nœud, ses successeurs.
  const succ = {};
  currentData.nodes.forEach((n) => (succ[n.id] = []));
  currentData.edges.forEach((e) => succ[e.source].push(e.target));

  // cle(A, B) : clé d'une paire SANS tenir compte du sens (A—B = B—A),
  // obtenue en rangeant les deux noms par ordre alphabétique.
  const cle = (a, b) => (a < b ? a + "\n" + b : b + "\n" + a);

  // 4a) Cas a : les arcs d'origine dont les DEUX bouts sont gardés (les
  //     nœuds se suivent). On note leur paire pour ne pas les doubler
  //     ensuite par un arc sans orientation.
  const directes = new Set();
  currentData.edges.forEach((e) => {
    if (garde.has(e.source) && garde.has(e.target)) directes.add(cle(e.source, e.target));
  });

  // 4b) Cas b : pour chaque nœud gardé A, parcours en largeur (BFS) en
  //     suivant les flèches. On traverse les nœuds NON gardés ; dès qu'on
  //     tombe sur un nœud gardé B, on note la paire (A, B) et on ne va PAS
  //     plus loin derrière B (B fera lui-même son propre parcours).
  //     Si B est un successeur DIRECT de A (cur === a), c'est le cas a :
  //     l'arc d'origine est gardé, rien à ajouter.
  const paires = new Map(); // clé "A\nB" (ordre alphabétique) -> [A, B]
  garde.forEach((a) => {
    const vus = new Set([a]);
    const file = [a];
    while (file.length) {
      const cur = file.shift();
      for (const next of succ[cur]) {
        if (vus.has(next)) continue;
        vus.add(next);
        if (garde.has(next)) {
          const k = cle(a, next);
          // Pas d'arc sans orientation si un arc d'origine relie déjà A et B
          // (dans un sens ou dans l'autre) : il est affiché tel quel.
          if (cur !== a && !directes.has(k)) paires.set(k, a < next ? [a, next] : [next, a]);
        } else {
          file.push(next); // nœud non gardé : on continue à travers lui
        }
      }
    }
  });

  // 5) On masque les nœuds non gardés, et les arcs d'origine SAUF ceux du
  //    cas a (les deux bouts gardés : flèche et transformation conservées)...
  cy.nodes().filter((n) => !garde.has(n.id())).addClass("cara-hidden");
  cy.edges()
    .filter((e) => !(garde.has(e.source().id()) && garde.has(e.target().id())))
    .addClass("cara-hidden");

  // ...et on ajoute les arcs du cas b (classe cara-edge : sans flèche, sans txn).
  cy.add(
    [...paires.values()].map(([x, y]) => ({
      group: "edges",
      classes: "cara-edge",
      data: {
        id: `cara:${x}<->${y}`,
        source: x,
        target: y,
        txn: "", // la transformation est perdue dans cette vue
        // halo jaune si les deux bouts sont des nœuds parcours (comme les autres arcs)
        parcours:
          cy.$id(x).data("parcours") === "oui" && cy.$id(y).data("parcours") === "oui" ? "oui" : "non",
      },
    }))
  );

  // 6) Mise en page recalculée sur ce qui reste visible.
  runLayout();
}

/* Relance la mise en page choisie dans « Mise en page », uniquement sur les
   éléments visibles (les éléments masqués par le filtre sont ignorés). */
function runLayout(animer = true) {
  if (!cy) return;
  // Clé choisie dans la liste (ex. "dagre") -> ses réglages ; dagre par défaut.
  const visibles = cy.elements().not(".cara-hidden");
  const config = layoutConfig(visibles.length, animer);

  // Filtre « Tous » : à la fin de la mise en page (stop), on garde les
  // positions de tous les nœuds de la page dans positionsCache. Revenir sur
  // cette page sera alors instantané (voir la fin de renderGraph).
  if (!caraSelect.value) {
    const cyDeDepart = cy;   // si on change de page pendant une animation,
    const cle = cleCache();  // cy aura changé : on ne garde alors rien.
    config.stop = () => {
      if (cy !== cyDeDepart) return;
      const positions = {};
      cy.nodes().forEach((n) => {
        const p = n.position();
        positions[n.id()] = { x: p.x, y: p.y }; // copie (pas l'objet interne de cytoscape)
      });
      positionsCache.set(cle, positions);
    };
  }
  visibles.layout(config).run();
}

/* cleCache : la « clé » des positions gardées en mémoire = taille de page +
   numéro de page + disposition choisie (ex. "2000|3|dagre"). Changer l'une
   des trois donne une autre clé, donc une nouvelle mise en page. */
function cleCache() {
  return `${taillePage}|${currentPage}|${layoutSelect.value}`;
}

/* onNodeTap(id) : clic sur un nœud (dans le graphe ou dans les tableaux
   de voisins du panneau).
     - nœud fantôme -> on ouvre la page du vrai nœud (goToNode) ;
     - nœud normal  -> on surligne ses voisins (selectNode). */
function onNodeTap(id) {
  if (id.startsWith(PREFIXE_FANTOME)) goToNode(id.slice(PREFIXE_FANTOME.length));
  else selectNode(id);
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
  successors.addClass("succ");                    // successeurs en cyan (pas vert : vert = caractère V)
  predecessors.addClass("pred");                  // prédécesseurs en jaune
  outgoers.edges().addClass("succ");              // arêtes sortantes en cyan
  incomers.edges().addClass("pred");              // arêtes entrantes en jaune

  // 3) panneau latéral : on affiche l'id et les deux tableaux de voisins
  //    (voisin + transformation portée par l'arête qui les relie à `id`).
  selectionHint.hidden = true;
  selectionDetail.hidden = false;
  // Titre : l'id, suivi du caractère du nœud s'il en a un (ex. « … — caractère V »).
  const cara = node.data("cara");
  selIdEl.textContent = cara ? `${id} — caractère ${cara}` : id;

  // outgoers.edges() : les arêtes id -> successeur. Pour chacune, .target()
  // donne le nœud successeur et .data("txn") la transformation de la ligne
  // Excel qui a créé cette arête.
  const succRows = outgoers
    .edges()
    .map((e) => ({ id: e.target().id(), txn: e.data("txn") || "" }))
    .sort((a, b) => a.id.localeCompare(b.id));
  // incomers.edges() : les arêtes prédécesseur -> id. .source() donne le
  // nœud prédécesseur.
  const predRows = incomers
    .edges()
    .map((e) => ({ id: e.source().id(), txn: e.data("txn") || "" }))
    .sort((a, b) => a.id.localeCompare(b.id));

  fillTable(succTableBodyEl, succCountEl, succRows);
  fillTable(predTableBodyEl, predCountEl, predRows);
}

function clearSelection() {
  if (cy) cy.elements().removeClass("selected succ pred faded");
  selectionHint.hidden = false;
  selectionDetail.hidden = true;
}

/* Remplit un tableau <tbody> de voisins cliquables : 1re colonne = id du
   voisin (successeur ou prédécesseur), 2e colonne = transformation (txn_dta)
   portée par l'arête qui le relie au nœud sélectionné. */
function fillTable(tbody, countEl, rows) {
  countEl.textContent = rows.length;
  tbody.innerHTML = "";

  if (rows.length === 0) {
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 2;
    td.className = "chip-empty";
    td.textContent = "aucun";
    tr.appendChild(td);
    tbody.appendChild(tr);
    return;
  }

  rows.forEach(({ id, txn }) => {
    const tr = document.createElement("tr");

    const tdId = document.createElement("td");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "chip";
    // Voisin fantôme (sur une autre page) : on montre son libellé « → p.12 … ».
    const estFantome = id.startsWith(PREFIXE_FANTOME);
    btn.textContent = estFantome ? cy.$id(id).data("label") : id;
    // Cliquer un voisin recentre la sélection sur lui ;
    // cliquer un voisin fantôme ouvre sa page (onNodeTap -> goToNode).
    btn.addEventListener("click", () => {
      onNodeTap(id);
      if (!estFantome) cy.animate({ center: { eles: cy.$id(id) }, duration: 250 });
    });
    tdId.appendChild(btn);

    const tdTxn = document.createElement("td");
    tdTxn.className = "sel-table-txn";
    tdTxn.textContent = txn || "—";

    tr.appendChild(tdId);
    tr.appendChild(tdTxn);
    tbody.appendChild(tr);
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

  // Version SANS récursion : avec des centaines de milliers de nœuds, une
  // fonction qui s'appelle elle-même des milliers de fois de suite fait
  // déborder la pile du navigateur (« Maximum call stack size exceeded »).
  // On gère donc la pile nous-mêmes : chaque case = [nœud, position du
  // prochain successeur à examiner].
  //
  // Le graphe peut être en plusieurs morceaux : on lance la visite depuis
  // chaque nœud encore blanc.
  for (const nd of data.nodes) {
    if (color[nd.id] !== 0) continue;
    color[nd.id] = 1; // gris : visite commencée
    const pile = [[nd.id, 0]];
    while (pile.length) {
      const haut = pile[pile.length - 1]; // le nœud en cours = le haut de la pile
      const u = haut[0];
      if (haut[1] < adj[u].length) {
        const v = adj[u][haut[1]]; // prochain successeur v de u
        haut[1] += 1;
        if (color[v] === 1) return true; // v est gris => on boucle => cycle
        if (color[v] === 0) {            // v jamais vu => on descend dedans
          color[v] = 1;
          pile.push([v, 0]);
        }
        // si color[v] === 2 (noir) : déjà exploré à fond, rien à faire
      } else {
        color[u] = 2; // tous les successeurs traités => u devient noir
        pile.pop();   // on « remonte »
      }
    }
  }
  return false;
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
    // (on avance un index au lieu de queue.shift(), trop lent sur une
    //  très grande file : shift décale tous les éléments à chaque appel)
    const queue = [nd.id]; // file des nœuds à traiter
    visited.add(nd.id);
    for (let i = 0; i < queue.length; i++) {
      const cur = queue[i];         // le prochain de la file
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
    cell(`Pages (${taillePage} nœuds max)`, pages.length),
  ].join("");
}

/* ------------------------------------------------------------------
   8. Point d'entrée : afficher un graphe déjà analysé
------------------------------------------------------------------ */
// label = texte affiché (nom du fichier) ; mode = "parcours", "adjacent" ou "".
// data = le graphe COMPLET ; on le découpe en pages puis on dessine la 1re.
function loadGraph(data, label, mode = "") {
  try {
    fullData = data;
    currentMode = mode;

    hideError();
    dropzone.classList.add("hidden");
    legend.hidden = false;
    // On affiche le mode détecté à côté du nom, pour que l'utilisateur le voie.
    fileNameEl.textContent = mode ? `${label} — mode ${mode}` : label;

    positionsCache = new Map(); // nouveau fichier : les anciennes positions ne valent plus
    taillePage = parseInt(pageSizeSelect.value, 10) || 2000;
    decouperEnPages();   // découpage en pages (section 4 ter) + table « nœud -> sa page »

    refreshCaraUi(data); // liste « Caractère » + légende, d'après l'onglet « Noeud »
    showPage(0);         // dessine la 1re page (et met à jour le panneau Pagination)
    // Statistiques sur le graphe COMPLET (toutes les pages), pas seulement la page.
    dernieresStats = computeStats(data);
    renderStats(dernieresStats);
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
      // Le mode (parcours / adjacent) vient du suffixe du nom du fichier.
      loadGraph(workbookBufferToGraph(reader.result), file.name, modeFromFileName(file.name));
    } catch (err) {
      showError(err.message || String(err)); // format invalide, colonne manquante...
    }
  };
  reader.onerror = () => showError("Impossible de lire le fichier.");
  // Un gros fichier (100 000+ lignes) met plusieurs secondes à être lu :
  // on prévient l'utilisateur que ça travaille.
  fileNameEl.textContent = `Lecture de ${file.name}… (un gros fichier peut prendre du temps)`;
  reader.readAsArrayBuffer(file); // .xlsx = fichier binaire (un zip) -> ArrayBuffer
}

function showError(message) {
  stageError.textContent = message;
  stageError.hidden = false;
}

function hideError() {
  stageError.hidden = true;
}

// Charge un exemple intégré (utilisée par les boutons, section 9 b).
// exemple = { arcs, noeuds } : les lignes des deux onglets (section 1).
// On passe un nom de fichier « fictif » à modeFromFileName : son suffixe
// (_parcours / _adjacent) choisit le mode, exactement comme pour un import.
function loadExample(exemple, fileName) {
  try {
    loadGraph(buildGraph(exemple.arcs, exemple.noeuds), fileName + " (intégré)", modeFromFileName(fileName));
  } catch (err) {
    showError(err.message || String(err));
  }
}

/* ------------------------------------------------------------------
   9. Câblage des événements de l'interface
------------------------------------------------------------------ */
function wireEvents() {
  // a) Bouton « Importer un .xlsx »
  fileInput.addEventListener("change", (e) => {
    loadFile(e.target.files && e.target.files[0]);
    fileInput.value = ""; // permet de recharger le même fichier ensuite
  });

  // b) Boutons « Exemple parcours » et « Exemple adjacent »
  exampleParcoursBtn.addEventListener("click", () =>
    loadExample(EXEMPLE_PARCOURS, "exemple_parcours.xlsx")
  );
  exampleAdjacentBtn.addEventListener("click", () =>
    loadExample(EXEMPLE_ADJACENT, "exemple_adjacent.xlsx")
  );

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
  // (runLayout ne place que les éléments visibles : le filtre est respecté.)
  layoutSelect.addEventListener("change", () => runLayout());

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

  // g) Filtre « Caractère » (V / R / U / G...) : à chaque choix dans la liste,
  //    on n'affiche plus que les nœuds de ce caractère, reliés par des arcs
  //    sans orientation (voir applyCaraFilter, section 5 bis).
  //    (fonction fléchée : on n'envoie pas l'objet événement en paramètre)
  caraSelect.addEventListener("change", () => applyCaraFilter());

  // h) Pagination (panneau « Pagination ») :
  //    ⏮ 1re page, ◀ page précédente, ▶ page suivante, ⏭ dernière page.
  pageFirstBtn.addEventListener("click", () => showPage(0));
  pagePrevBtn.addEventListener("click", () => showPage(currentPage - 1));
  pageNextBtn.addEventListener("click", () => showPage(currentPage + 1));
  pageLastBtn.addEventListener("click", () => showPage(pages.length - 1));
  //    Champ numéro de page : taper un numéro puis Entrée (ou quitter le
  //    champ). Affiché à partir de 1, rangé à partir de 0, d'où le « - 1 ».
  pageInput.addEventListener("change", () => {
    const n = parseInt(pageInput.value, 10);
    if (Number.isFinite(n)) showPage(n - 1);
    else refreshPagerUi(); // saisie invalide : on remet le numéro actuel
  });
  //    Liste « Taille de page » (500 / 1000 / 2000) : redécoupe le graphe.
  pageSizeSelect.addEventListener("change", changerTaillePage);

  // i) « Chercher un nœud » : bouton « Aller » ou touche Entrée dans le champ.
  //    Ouvre la page du nœud trouvé et le sélectionne (goToNode).
  const chercher = () => {
    if (!fullData) return;
    const id = findNodeId(nodeSearchInput.value);
    if (id) goToNode(id);
    else showError(`Aucun nœud ne contient « ${nodeSearchInput.value.trim()} ».`);
  };
  nodeSearchBtn.addEventListener("click", chercher);
  nodeSearchInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") chercher();
  });
}

/* ------------------------------------------------------------------
   10. Démarrage
   ------------------------------------------------------------------
   « DOMContentLoaded » = l'événement envoyé par le navigateur quand tout
   le HTML a été lu et que les éléments de la page existent. On attend ce
   moment pour récupérer les éléments (getDomRefs) et brancher les clics
   (wireEvents). C'est ce qui permet de mettre <script src="app.js"> dans
   le <head>.
   (Si la page est déjà prête — readyState différent de "loading" — on
   démarre tout de suite.)
------------------------------------------------------------------ */
function startApp() {
  getDomRefs();
  wireEvents();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startApp);
} else {
  startApp();
}
