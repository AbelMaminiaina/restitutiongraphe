/* ==================================================================
   Application de SAISIE et de CARTOGRAPHIE du LIGNAGE de données
   (data lineage) — HTML + JavaScript, 100 % navigateur, hors ligne
   ==================================================================

   Objectif : cartographier le cycle de vie de la donnée en retraçant son
   origine, ses transformations et sa destination finale.
     - Transparence      : d'où viennent les données, comment sont-elles calculées
     - Analyse d'impact  : quels rapports sont touchés si une source change
     - Conformité, audit : traçabilité des données sensibles (RGPD, BCBS 239)
     - Confiance         : validation manuelle du lignage par un Data Steward

   Librairies (en local dans vendor/, voir index.html) :
     cytoscape (+ dagre) pour dessiner le graphe, xlsx (SheetJS) pour lire
     et écrire les fichiers Excel.

   ------------------------------------------------------------------
   GUIDE DE LECTURE
   ------------------------------------------------------------------
     1. Référentiels       - types, criticités, statuts, rôles et droits
     2. Modèle de données  - assets + relations + historique, sauvegarde
     3. Import Excel       - rowsToGraph (format d'origine) + feuilles assets/historique
     4. Export Excel       - réécrit les 3 feuilles (ré-importables)
     5. Références DOM
     6. Éléments cytoscape - niveau micro / macro, regroupement par table, couleurs
     7. Rendu du graphe    - renderGraph (complet) / syncGraph (après une saisie)
     8. Sélection, lignage amont / aval, analyse d'impact
     9. Fiche descriptive  - d'un asset, d'une relation, d'une table (macro)
    10. Saisie manuelle    - formulaires asset et relation (création / modification)
    11. Validation, suppression
    12. Panneaux           - critiques, validation, historique, statistiques
    13. Filtres, légende
    14. Chargement (import / exemple / sauvegarde)
    15. Câblage des événements

   ------------------------------------------------------------------
   VOCABULAIRE
   ------------------------------------------------------------------
   - asset       : un élément de données (table, colonne, fichier, rapport,
                   API…) OU un traitement (job ETL, calcul). = un NŒUD du graphe.
   - relation    : un lien Parent -> Enfant entre deux assets, avec sa règle
                   de transformation. = une ARÊTE (flèche) du graphe.
   - amont       : tout ce dont un asset dépend (upstream, ses ancêtres)
   - aval        : tout ce qui dépend d'un asset (downstream, ses descendants)
   - micro/macro : lignage colonne à colonne / table à table
   ================================================================== */

/* ------------------------------------------------------------------
   0. Mode débogage
   ------------------------------------------------------------------
   Mettre DEBUG = true (ou ouvrir index.html?debug=1) pour activer les
   points d'arrêt `debugger;` quand les outils de développement (F12) sont
   ouverts. Laisser DEBUG = false en usage normal.
------------------------------------------------------------------ */
const DEBUG =
  false ||
  (typeof location !== "undefined" && /[?&]debug=1\b/.test(location.search));

function brk(label) {
  if (!DEBUG) return;
  console.log("[debug] " + label);
  debugger; // eslint-disable-line no-debugger
}

/* ------------------------------------------------------------------
   1. Référentiels : listes de valeurs autorisées, couleurs, droits
------------------------------------------------------------------ */
const TYPES = ["Colonne", "Table", "Fichier", "Rapport", "API", "Base de données", "Traitement"];
// Niveaux de criticité, du moins au plus critique (l'ordre compte : voir critRank).
const CRITICITES = ["Faible", "Moyenne", "Haute", "Critique"];
const STATUTS = ["À valider", "Validé", "Rejeté"];

// Rôles et droits. Pour savoir si l'utilisateur courant peut faire X : can("X").
//   edit     : créer / modifier un asset ou une relation
//   validate : valider / rejeter
//   remove   : supprimer, vider la base
//   importer : remplacer la base par un fichier Excel ou l'exemple
const ROLES = {
  admin: { label: "Administrateur", edit: true, validate: true, remove: true, importer: true },
  steward: { label: "Data Steward / Data Analyst", edit: true, validate: true, remove: false, importer: true },
  consommateur: { label: "Consommateur (métier)", edit: false, validate: false, remove: false, importer: false },
};

// Couleurs de remplissage des nœuds selon le mode choisi dans « Couleur ».
const TYPE_COLORS = {
  Colonne: "#a78bfa",
  Table: "#c4b5fd",
  Fichier: "#f0abfc",
  Rapport: "#5eead4",
  API: "#fdba74",
  "Base de données": "#cbd5e1",
  Traitement: "#6ea8fe",
};
const CRIT_COLORS = { Faible: "#94a3b8", Moyenne: "#60a5fa", Haute: "#fb923c", Critique: "#ef4444" };
const STATUT_COLORS = { "À valider": "#fbbf24", Validé: "#34d399", Rejeté: "#f87171" };

// Forme du nœud selon son type (formes proposées par cytoscape).
const TYPE_SHAPES = {
  Colonne: "round-rectangle",
  Table: "rectangle",
  Fichier: "cut-rectangle",
  Rapport: "round-tag",
  API: "tag",
  "Base de données": "barrel",
  Traitement: "hexagon",
};

// Position d'une criticité dans la liste : Faible=0 … Critique=3.
function critRank(c) {
  return Math.max(0, CRITICITES.indexOf(c));
}

// Une donnée est « critique » si sa criticité est Haute ou Critique, ou si
// c'est une donnée personnelle (PII / RGPD).
function isCritical(a) {
  return critRank(a.criticite) >= 2 || !!a.pii;
}

/* ------------------------------------------------------------------
   2. Modèle de données (la « base » de l'application)
   ------------------------------------------------------------------
   model = {
     assets:    { "<id>": { id, nature, type, owner, description, criticite,
                            pii, statut, creePar, creeLe, modifiePar,
                            modifieLe, validePar, valideLe } },
     relations: { "<source>=><target>": { id, source, target, txn, statut, …audit } },
     history:   [ { date, user, role, action, cibleType, cible, detail } ],
     source:    "nom du fichier d'origine"
   }
   Il est sauvegardé dans le navigateur (localStorage) après chaque
   changement : on le retrouve en rouvrant la page. Pour le partager ou
   l'archiver : bouton « Exporter .xlsx ».
------------------------------------------------------------------ */
const STORAGE_KEY = "saisie-lineage-v1";
const PREFS_KEY = "saisie-lineage-prefs-v1";

let model = emptyModel();

function emptyModel() {
  return { assets: {}, relations: {}, history: [], source: "" };
}

function relId(source, target) {
  return source + "=>" + target;
}

function saveModel() {
  // try/catch : le stockage peut être bloqué (navigation privée, disque plein…).
  // L'application continue de fonctionner, seule la sauvegarde est perdue.
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(model));
  } catch (err) {
    console.warn("Sauvegarde locale impossible :", err);
  }
}

function loadSavedModel() {
  try {
    const txt = localStorage.getItem(STORAGE_KEY);
    if (!txt) return null;
    const m = JSON.parse(txt);
    return m && m.assets && m.relations ? m : null;
  } catch (err) {
    return null;
  }
}

function nowIso() {
  return new Date().toISOString();
}

// Utilisateur courant (nom saisi en haut + rôle choisi).
function currentUser() {
  return { name: userInput.value.trim() || "anonyme", role: roleSelect.value };
}

function can(perm) {
  const role = ROLES[roleSelect.value] || ROLES.consommateur;
  return !!role[perm];
}

// Ajoute une ligne au journal (Historique et versioning : qui, quand, quoi).
function logChange(action, cibleType, cible, detail) {
  const u = currentUser();
  model.history.push({
    date: nowIso(),
    user: u.name,
    role: ROLES[u.role].label,
    action,
    cibleType,
    cible,
    detail: detail || "",
  });
}

// Petit outil pour insérer du texte dans du HTML sans risque (<, >, & …).
function esc(v) {
  return String(v == null ? "" : v)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// "2026-10-25T14:03:00Z" -> "25/10/2026 15:03" (heure locale)
function fmtDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d)) return String(iso);
  return d.toLocaleDateString("fr-FR") + " " + d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
}

/* ------------------------------------------------------------------
   3. Import Excel
   ------------------------------------------------------------------
   Le classeur peut contenir jusqu'à 3 feuilles, reconnues par leurs EN-TÊTES
   (le nom de la feuille n'a pas d'importance) :

   a) lineage (obligatoire, format d'origine du projet javascript/) :
        dta_1..dta_4 | edg_dir | edg_1..edg_4 | txn_dta | statut (optionnel)
      nœud « données » = dta_4.dta_3.dta_2.dta_1, nœud « edg » (traitement)
      = edg_4.edg_3.edg_2.edg_1, et edg_dir donne le sens :
        I -> données -> edg     O -> edg -> données
   b) assets (optionnelle) : id | nature | type | proprietaire | description
      | criticite | pii | statut   -> la fiche descriptive de chaque asset
   c) historique (optionnelle) : date | utilisateur | role | action |
      type_cible | cible | detail

   Un ancien fichier (une seule feuille lineage) s'importe donc toujours :
   tous les assets prennent alors les valeurs par défaut (criticité Faible,
   statut Validé).
------------------------------------------------------------------ */

/* rowsToGraph : identique au projet javascript/ (+ colonne statut).
   Transforme le tableau de lignes de la feuille lineage en { nodes, edges }. */
function rowsToGraph(rows) {
  brk("rowsToGraph — entrée. Regarde: rows");

  if (!rows || rows.length < 2) {
    throw new Error("La feuille lineage doit contenir une ligne d'en-tête + au moins une ligne de données.");
  }

  // En-têtes normalisés : texte, sans espaces au bord, en minuscules.
  const header = rows[0].map((h) => String(h == null ? "" : h).trim().toLowerCase());

  // Dans quelle colonne se trouve chaque champ ?
  const dtaCol = {};
  const edgCol = {};
  let dirCol = -1;
  let txnCol = -1;
  let statutCol = -1;

  header.forEach((name, idx) => {
    let m;
    // "dta_3", "dta3", "dta 03" -> morceau n°3 des données
    if ((m = name.match(/^dta[ _-]?0*([1-4])$/))) dtaCol[m[1]] = idx;
    else if ((m = name.match(/^edg[ _-]?0*([1-4])$/))) edgCol[m[1]] = idx;
    else if (name.includes("dir")) dirCol = idx; // edg_dir, direction…
    else if (name.includes("txn")) txnCol = idx; // txn_dta…
    else if (name.includes("statut") || name === "status") statutCol = idx;
  });

  if (Object.keys(dtaCol).length === 0 || Object.keys(edgCol).length === 0) {
    throw new Error(
      "Colonnes attendues introuvables : il faut au moins une colonne dta_* et une colonne edg_* " +
        "(en-têtes lus : " + header.join(", ") + ")."
    );
  }

  // Recolle "morceau4.morceau3.morceau2.morceau1" (morceaux vides ignorés).
  const joinParts = (row, cols) =>
    ["4", "3", "2", "1"]
      .map((k) => (cols[k] == null ? "" : row[cols[k]]))
      .map((v) => String(v == null ? "" : v).trim())
      .filter((v) => v !== "")
      .join(".");

  const nodeKind = new Map(); // nom du nœud -> ensemble de types ("dta" et/ou "edg")
  const edgeSet = new Set();  // couples déjà vus (évite les doublons)
  const edges = [];

  const noteKind = (id, kind) => {
    if (!nodeKind.has(id)) nodeKind.set(id, new Set());
    nodeKind.get(id).add(kind);
  };

  for (let r = 1; r < rows.length; r++) {
    const row = rows[r] || [];
    if (row.every((c) => String(c == null ? "" : c).trim() === "")) continue; // ligne vide

    const dtaNode = joinParts(row, dtaCol);
    const edgNode = joinParts(row, edgCol);
    if (!dtaNode && !edgNode) continue;

    if (dtaNode) noteKind(dtaNode, "dta");
    if (edgNode) noteKind(edgNode, "edg");
    if (!dtaNode || !edgNode) continue; // un seul côté rempli : nœud isolé

    const txn = String(row[txnCol] == null ? "" : row[txnCol]).trim();
    const statut = String(row[statutCol] == null ? "" : row[statutCol]).trim();
    const dir = String(row[dirCol] == null ? "" : row[dirCol]).trim().toUpperCase();

    let source, target;
    if (dir.startsWith("I")) {
      source = dtaNode; // la donnée ENTRE dans le traitement
      target = edgNode;
    } else if (dir.startsWith("O")) {
      source = edgNode; // le traitement PRODUIT la donnée
      target = dtaNode;
    } else {
      console.warn(`Ligne ${r + 1} : sens « ${row[dirCol] == null ? "" : row[dirCol]} » non reconnu -> pas d'arête.`);
      continue;
    }

    const key = source + "\n" + target;
    if (!edgeSet.has(key)) {
      edgeSet.add(key);
      edges.push({ source, target, txn, statut });
    }
  }

  const nodes = [...nodeKind.entries()].map(([id, kinds]) => ({
    id,
    kind: kinds.has("dta") && kinds.has("edg") ? "both" : kinds.has("edg") ? "edg" : "dta",
  }));

  brk("rowsToGraph — sortie. Regarde: nodes, edges");
  return { nodes, edges };
}

// Texte sans accents, en minuscules : "Criticité " -> "criticite".
function norm(v) {
  return String(v == null ? "" : v)
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toLowerCase();
}

// Retrouve une valeur d'une liste de référence sans tenir compte des
// accents ni de la casse ("critique" -> "Critique"). Sinon : valeur par défaut.
function matchRef(list, v, fallback) {
  const n = norm(v);
  if (!n) return fallback;
  const found = list.find((x) => norm(x) === n);
  return found || fallback;
}

function normCriticite(v) {
  const n = norm(v);
  if (n === "elevee" || n === "eleve" || n === "high") return "Haute";
  return matchRef(CRITICITES, v, "Faible");
}

function normStatut(v, fallback) {
  const n = norm(v);
  if (!n) return fallback;
  if (n.startsWith("valid")) return "Validé"; // "validé", "valide", "validated"
  if (n.startsWith("rejet") || n.startsWith("refus")) return "Rejeté";
  if (n.includes("valider") || n.includes("attente") || n.includes("brouillon")) return "À valider";
  return fallback;
}

function normBool(v) {
  return ["oui", "o", "yes", "y", "true", "vrai", "1", "x"].includes(norm(v));
}

// Repère dans une ligne d'en-tête la colonne dont le nom vérifie test(nom).
function findCol(header, test) {
  return header.findIndex((h) => test(norm(h)));
}

// Feuille « assets » -> liste d'objets { id, nature, type, … }
function parseAssetsRows(rows) {
  const h = rows[0];
  const c = {
    id: findCol(h, (n) => n === "id" || n === "identifiant" || n === "asset"),
    nature: findCol(h, (n) => n.includes("nature")),
    type: findCol(h, (n) => n === "type" || n === "type_asset"),
    owner: findCol(h, (n) => n.includes("proprietaire") || n.includes("owner")),
    description: findCol(h, (n) => n.includes("descr")),
    criticite: findCol(h, (n) => n.includes("critic")),
    pii: findCol(h, (n) => n.includes("pii") || n.includes("rgpd") || n.includes("personnel")),
    statut: findCol(h, (n) => n.includes("statut") || n === "status"),
    creePar: findCol(h, (n) => n === "cree_par"),
    creeLe: findCol(h, (n) => n === "cree_le"),
    modifiePar: findCol(h, (n) => n === "modifie_par"),
    modifieLe: findCol(h, (n) => n === "modifie_le"),
    validePar: findCol(h, (n) => n === "valide_par"),
    valideLe: findCol(h, (n) => n === "valide_le"),
  };
  // cell(row, "owner") : valeur texte de la colonne demandée ("" si absente)
  const cell = (row, key) => (c[key] < 0 ? "" : String(row[c[key]] == null ? "" : row[c[key]]).trim());

  return rows
    .slice(1)
    .filter((row) => cell(row, "id") !== "")
    .map((row) => ({
      id: cell(row, "id"),
      nature: cell(row, "nature"),
      type: cell(row, "type"),
      owner: cell(row, "owner"),
      description: cell(row, "description"),
      criticite: cell(row, "criticite"),
      pii: cell(row, "pii"),
      statut: cell(row, "statut"),
      creePar: cell(row, "creePar"),
      creeLe: cell(row, "creeLe"),
      modifiePar: cell(row, "modifiePar"),
      modifieLe: cell(row, "modifieLe"),
      validePar: cell(row, "validePar"),
      valideLe: cell(row, "valideLe"),
    }));
}

// Feuille « historique » -> liste d'entrées du journal
function parseHistoryRows(rows) {
  const h = rows[0];
  const c = {
    date: findCol(h, (n) => n === "date"),
    user: findCol(h, (n) => n.includes("utilisateur") || n === "user"),
    role: findCol(h, (n) => n === "role"),
    action: findCol(h, (n) => n === "action"),
    cibleType: findCol(h, (n) => n.includes("type")),
    cible: findCol(h, (n) => n === "cible"),
    detail: findCol(h, (n) => n.includes("detail")),
  };
  const cell = (row, key) => (c[key] < 0 ? "" : String(row[c[key]] == null ? "" : row[c[key]]).trim());
  return rows
    .slice(1)
    .filter((row) => cell(row, "action") !== "")
    .map((row) => ({
      date: cell(row, "date"),
      user: cell(row, "user"),
      role: cell(row, "role"),
      action: cell(row, "action"),
      cibleType: cell(row, "cibleType"),
      cible: cell(row, "cible"),
      detail: cell(row, "detail"),
    }));
}

/* modelFromSheets : construit le modèle à partir des feuilles déjà lues.
   sheets = liste de tableaux de lignes (une par feuille, 1re ligne = en-têtes). */
function modelFromSheets(sheets, label) {
  let lineageRows = null;
  let assetsRows = null;
  let historyRows = null;

  // On reconnaît chaque feuille à ses en-têtes.
  sheets.forEach((rows) => {
    if (!rows || rows.length === 0) return;
    const h = rows[0].map(norm);
    if (h.some((n) => /^dta[ _-]?0*[1-4]$/.test(n))) lineageRows = lineageRows || rows;
    else if (h.includes("action")) historyRows = historyRows || rows;
    else if (h.includes("id") || h.includes("identifiant")) assetsRows = assetsRows || rows;
  });

  if (!lineageRows && !assetsRows) {
    throw new Error("Aucune feuille reconnue : il faut une feuille lineage (colonnes dta_*, edg_dir, edg_*) ou une feuille assets (colonne id).");
  }

  const m = emptyModel();
  m.source = label;
  const date = nowIso();

  // a) feuille lineage -> assets par défaut + relations
  if (lineageRows) {
    const g = rowsToGraph(lineageRows);
    g.nodes.forEach((n) => {
      const traitement = n.kind === "edg";
      m.assets[n.id] = {
        id: n.id,
        nature: traitement ? "traitement" : "donnee",
        type: traitement ? "Traitement" : "Colonne",
        owner: "",
        description: "",
        criticite: "Faible",
        pii: false,
        statut: "Validé",
        creePar: "import",
        creeLe: date,
      };
    });
    g.edges.forEach((e) => {
      const id = relId(e.source, e.target);
      m.relations[id] = {
        id,
        source: e.source,
        target: e.target,
        txn: e.txn,
        statut: normStatut(e.statut, "Validé"),
        creePar: "import",
        creeLe: date,
      };
    });
  }

  // b) feuille assets -> complète (ou crée) la fiche de chaque asset
  if (assetsRows) {
    parseAssetsRows(assetsRows).forEach((r) => {
      const a = m.assets[r.id] || { id: r.id, creePar: "import", creeLe: date };
      const nat = norm(r.nature);
      if (nat) a.nature = nat.startsWith("trait") ? "traitement" : "donnee";
      a.type = matchRef(TYPES, r.type, a.type || (a.nature === "traitement" ? "Traitement" : "Colonne"));
      if (!a.nature) a.nature = a.type === "Traitement" ? "traitement" : "donnee";
      a.owner = r.owner;
      a.description = r.description;
      a.criticite = normCriticite(r.criticite);
      a.pii = normBool(r.pii);
      a.statut = normStatut(r.statut, "Validé");
      ["creePar", "creeLe", "modifiePar", "modifieLe", "validePar", "valideLe"].forEach((k) => {
        if (r[k]) a[k] = r[k];
      });
      m.assets[r.id] = a;
    });
  }

  // c) feuille historique -> journal (sinon vide)
  if (historyRows) m.history = parseHistoryRows(historyRows);

  return m;
}

/* Lit un fichier .xlsx (ArrayBuffer) et renvoie le modèle. */
function workbookBufferToModel(buffer, label) {
  const wb = XLSX.read(new Uint8Array(buffer), { type: "array" });
  if (!wb.SheetNames.length) throw new Error("Le classeur Excel ne contient aucune feuille.");
  // Chaque feuille -> tableau de lignes (header:1 = une sous-liste par ligne).
  const sheets = wb.SheetNames.map((name) =>
    XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, blankrows: false, defval: "" })
  );
  return modelFromSheets(sheets, label);
}

/* ------------------------------------------------------------------
   4. Export Excel : 3 feuilles, ré-importables telles quelles
------------------------------------------------------------------ */

// "DWH.DM.FAIT_VENTES.MONTANT_TTC" -> ["MONTANT_TTC","FAIT_VENTES","DM","DWH"]
// (ordre des colonnes x_1..x_4). Au-delà de 4 morceaux, les premiers sont
// regroupés dans x_4 pour que la concaténation redonne exactement l'id.
function splitId(id) {
  const p = id.split(".");
  while (p.length > 4) p.splice(0, 2, p[0] + "." + p[1]);
  while (p.length < 4) p.unshift("");
  return [p[3], p[2], p[1], p[0]];
}

function exportExcel() {
  // a) lineage : une ligne par relation. Le format d'origine relie toujours
  //    une « donnée » (dta) à un « traitement » (edg) :
  //    - parent = traitement -> le traitement PRODUIT l'enfant : sens O
  //    - sinon                -> le parent ENTRE dans l'enfant : sens I
  const lineage = [["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta", "statut"]];
  Object.values(model.relations).forEach((r) => {
    const src = model.assets[r.source];
    if (src && src.nature === "traitement") {
      lineage.push([...splitId(r.target), "O", ...splitId(r.source), r.txn, r.statut]);
    } else {
      lineage.push([...splitId(r.source), "I", ...splitId(r.target), r.txn, r.statut]);
    }
  });

  // b) assets : la fiche descriptive complète
  const assets = [["id", "nature", "type", "proprietaire", "description", "criticite", "pii", "statut",
    "cree_par", "cree_le", "modifie_par", "modifie_le", "valide_par", "valide_le"]];
  Object.values(model.assets).forEach((a) => {
    assets.push([a.id, a.nature === "traitement" ? "Traitement" : "Donnée", a.type, a.owner, a.description,
      a.criticite, a.pii ? "Oui" : "Non", a.statut, a.creePar || "", a.creeLe || "", a.modifiePar || "",
      a.modifieLe || "", a.validePar || "", a.valideLe || ""]);
  });

  // c) historique
  const hist = [["date", "utilisateur", "role", "action", "type_cible", "cible", "detail"]];
  model.history.forEach((h) => hist.push([h.date, h.user, h.role, h.action, h.cibleType, h.cible, h.detail]));

  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(lineage), "lineage");
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(assets), "assets");
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(hist), "historique");

  // XLSX.write -> octets du fichier ; on les propose au téléchargement.
  const bytes = XLSX.write(wb, { type: "array", bookType: "xlsx" });
  const blob = new Blob([bytes], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "lineage-" + new Date().toISOString().slice(0, 10) + ".xlsx";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/* ------------------------------------------------------------------
   5. Références vers les éléments du DOM (le HTML)
------------------------------------------------------------------ */
const $ = (id) => document.getElementById(id);

const stage = $("stage");
const dropzone = $("dropzone");
const stageError = $("stage-error");
const toastEl = $("toast");
const legend = $("legend");
const fileInput = $("file-input");
const importLabel = $("import-label");
const exampleBtn = $("example-btn");
const exportBtn = $("export-btn");
const userInput = $("user-input");
const roleSelect = $("role-select");

const searchInput = $("search-input");
const searchDatalist = $("search-datalist");
const levelSelect = $("level-select");
const groupCheck = $("group-check");
const colorSelect = $("color-select");
const filterSelect = $("filter-select");
const txnCheck = $("txn-check");
const layoutSelect = $("layout-select");

const ficheHint = $("fiche-hint");
const ficheEl = $("fiche");

const assetsDatalist = $("assets-datalist");
const readonlyNotice = $("readonly-notice");
const tabSaisie = $("tab-saisie");
const af = {
  title: $("asset-form-title"),
  form: $("asset-form"),
  sys: $("af-sys"),
  schema: $("af-schema"),
  objet: $("af-objet"),
  col: $("af-col"),
  preview: $("af-id-preview"),
  nature: $("af-nature"),
  type: $("af-type"),
  owner: $("af-owner"),
  crit: $("af-crit"),
  desc: $("af-desc"),
  pii: $("af-pii"),
  reset: $("af-reset"),
};
const rf = {
  title: $("rel-form-title"),
  form: $("rel-form"),
  source: $("rf-source"),
  target: $("rf-target"),
  txn: $("rf-txn"),
  reset: $("rf-reset"),
};
const adminCard = $("admin-card");
const resetBtn = $("reset-btn");

const critTiles = $("crit-tiles");
const critList = $("crit-list");
const critBadge = $("crit-badge");
const critFilterBtn = $("crit-filter-btn");
const validList = $("valid-list");
const validBadge = $("valid-badge");
const histFilter = $("hist-filter");
const histList = $("hist-list");
const fileNameEl = $("file-name");
const statsEl = $("stats");

/* État de l'interface */
let cy = null;            // instance cytoscape en cours
let selection = null;     // { kind: "node" | "edge" | "group", id, mode }
let editingAssetId = null;    // id de l'asset en cours de modification (null = création)
let editingRelId = null;      // id de la relation en cours de modification

/* Dispositions (layouts) cytoscape — la clé = <option> de layout-select */
const LAYOUT_CONFIGS = {
  dagre: { name: "dagre", rankDir: "TB", nodeSep: 30, rankSep: 80, animate: true },
  dagreLR: { name: "dagre", rankDir: "LR", nodeSep: 18, rankSep: 90, animate: true },
  breadthfirst: { name: "breadthfirst", directed: true, spacingFactor: 1.2, animate: true },
  circle: { name: "circle", animate: true },
  concentric: { name: "concentric", animate: true, concentric: (n) => n.degree(), levelWidth: () => 1 },
  grid: { name: "grid", animate: true },
  cose: { name: "cose", animate: true, idealEdgeLength: 100, nodeRepulsion: 9000 },
};

/* ------------------------------------------------------------------
   6. Construction des éléments cytoscape à partir du modèle
   ------------------------------------------------------------------
   - niveau MICRO : un nœud par asset (colonne à colonne). Option
     « Regrouper par table » : les colonnes d'une même table sont dessinées
     dans une boîte (nœud « parent » cytoscape, dit « compound »).
   - niveau MACRO : un nœud par table (= id sans son dernier morceau) ;
     les relations entre colonnes sont additionnées en relations entre tables.
------------------------------------------------------------------ */

// Id de la table qui contient un asset : "DWH.DM.FAIT_VENTES.MONTANT_TTC" -> "DWH.DM.FAIT_VENTES"
function tableOf(id) {
  const p = id.split(".");
  return p.length > 1 ? p.slice(0, -1).join(".") : id;
}

// Texte affiché dans le nœud : les 2 derniers morceaux (ou le dernier seul
// si le nœud est déjà dans la boîte de sa table).
function shortLabel(id, onlyLast) {
  const p = id.split(".");
  return onlyLast ? p[p.length - 1] : p.slice(-2).join(".");
}

// Couleur de remplissage d'un nœud selon le mode « Couleur » choisi.
function colorFor(d) {
  const mode = colorSelect.value;
  if (mode === "criticite") return CRIT_COLORS[d.criticite] || "#94a3b8";
  if (mode === "statut") return STATUT_COLORS[d.statut] || "#94a3b8";
  return TYPE_COLORS[d.type] || "#a78bfa";
}

// Données communes à tout nœud (micro ou macro) : forme, taille, couleur…
function nodeData(id, label, info) {
  const text = (info.pii ? "🔒 " : "") + label;
  const d = {
    id,
    label: text,
    type: info.type,
    nature: info.nature,
    criticite: info.criticite,
    pii: !!info.pii,
    statut: info.statut,
    critical: isCritical(info),
    shape: TYPE_SHAPES[info.type] || "round-rectangle",
  };
  // Largeur calculée d'après la longueur du texte (≈ 7 px par caractère).
  // Les formes à pointes (hexagone, étiquette…) ont besoin d'un peu plus de
  // place pour que le texte ne déborde pas sur les pointes.
  const pointues = ["hexagon", "tag", "round-tag", "cut-rectangle", "barrel"];
  d.w = Math.max(60, Math.round(text.length * 7.2 + 26 + (pointues.includes(d.shape) ? 28 : 0)));
  d.color = colorFor(d);
  return d;
}

function buildElements() {
  return levelSelect.value === "macro" ? buildMacroElements() : buildMicroElements();
}

function buildMicroElements() {
  const grouped = groupCheck.checked;
  const groups = [];
  const nodes = [];
  const edges = [];
  const seenGroups = new Set();

  Object.values(model.assets).forEach((a) => {
    const d = nodeData(a.id, shortLabel(a.id, grouped), a);
    const table = tableOf(a.id);
    if (grouped && table !== a.id) {
      d.parent = "grp::" + table; // la boîte de sa table
      if (!seenGroups.has(table)) {
        seenGroups.add(table);
        groups.push({ data: { id: "grp::" + table, label: table, isGroup: true } });
      }
    }
    nodes.push({ data: d, classes: d.critical ? "critique" : "" });
  });

  Object.values(model.relations).forEach((r) => {
    if (!model.assets[r.source] || !model.assets[r.target]) return; // extrémité supprimée
    edges.push({
      data: { id: r.id, source: r.source, target: r.target, txn: r.txn || "", statut: r.statut, width: 2 },
    });
  });

  // L'ordre compte pour cytoscape : boîtes, puis nœuds, puis arêtes.
  return [...groups, ...nodes, ...edges];
}

function buildMacroElements() {
  // 1) on range chaque asset dans sa table
  const tables = new Map(); // id table -> liste d'assets
  Object.values(model.assets).forEach((a) => {
    const t = tableOf(a.id);
    if (!tables.has(t)) tables.set(t, []);
    tables.get(t).push(a);
  });

  // 2) un nœud par table, avec des valeurs « résumées » de ses colonnes
  const nodes = [...tables.entries()].map(([t, list]) => {
    const info = {
      // Rapport s'il contient au moins un champ de rapport, sinon le type de la 1re colonne
      type: list.some((a) => a.type === "Rapport") ? "Rapport" : list[0].type,
      nature: list.every((a) => a.nature === "traitement") ? "traitement" : "donnee",
      // criticité la plus haute de ses colonnes
      criticite: CRITICITES[Math.max(...list.map((a) => critRank(a.criticite)))],
      pii: list.some((a) => a.pii),
      // tout validé -> Validé ; sinon le « pire » statut présent
      statut: list.every((a) => a.statut === "Validé")
        ? "Validé"
        : list.some((a) => a.statut === "À valider") ? "À valider" : "Rejeté",
    };
    const d = nodeData(t, shortLabel(t, false), info);
    d.children = list.map((a) => a.id);
    return { data: d, classes: d.critical ? "critique" : "" };
  });

  // 3) relations entre colonnes -> relations entre tables (cumulées)
  const agg = new Map();
  Object.values(model.relations).forEach((r) => {
    if (!model.assets[r.source] || !model.assets[r.target]) return;
    const s = tableOf(r.source);
    const t = tableOf(r.target);
    if (s === t) return; // relation interne à une table : invisible au niveau macro
    const id = relId(s, t);
    if (!agg.has(id)) agg.set(id, { id, source: s, target: t, rels: [] });
    agg.get(id).rels.push(r);
  });
  const edges = [...agg.values()].map((e) => {
    const txns = [...new Set(e.rels.map((r) => r.txn).filter(Boolean))];
    return {
      data: {
        id: e.id,
        source: e.source,
        target: e.target,
        relIds: e.rels.map((r) => r.id),
        txn: e.rels.length + " lien(s)" + (txns.length ? " : " + txns.slice(0, 2).join(" ; ") + (txns.length > 2 ? "…" : "") : ""),
        statut: e.rels.every((r) => r.statut === "Validé") ? "Validé" : e.rels.some((r) => r.statut === "À valider") ? "À valider" : "Rejeté",
        width: Math.min(8, 2 + Math.log2(e.rels.length) * 1.5), // plus de liens = trait plus épais
      },
    };
  });

  return [...nodes, ...edges];
}

/* ------------------------------------------------------------------
   7. Rendu du graphe
   ------------------------------------------------------------------
   - renderGraph : recrée tout le dessin et recalcule la disposition
                   (nouveau fichier, changement de niveau / regroupement).
   - syncGraph   : après une saisie, ajoute / retire / met à jour seulement
                   ce qui a changé, SANS bouger les nœuds déjà placés.
------------------------------------------------------------------ */
const CY_STYLE = [
  {
    // [!isGroup] : uniquement les vrais assets (pas les boîtes de tables)
    selector: "node[!isGroup]",
    style: {
      shape: "data(shape)",
      "background-color": "data(color)",
      label: "data(label)",
      color: "#0b1220",
      "font-size": 12,
      "font-weight": 600,
      "text-valign": "center",
      "text-halign": "center",
      width: "data(w)",
      height: 30,
      "border-width": 1.5,
      "border-color": "#0f1420",
    },
  },
  // Boîte d'une table (mode « Regrouper par table »)
  {
    selector: "node[?isGroup]",
    style: {
      shape: "round-rectangle",
      "background-color": "#1e2536",
      "background-opacity": 0.65,
      "border-color": "#2a3348",
      "border-width": 1,
      label: "data(label)",
      color: "#93a0b8",
      "font-size": 11,
      "font-weight": 600,
      "text-valign": "top",
      "text-halign": "center",
      "text-margin-y": -4,
      padding: 12,
    },
  },
  // Statut : à valider = bordure tiretée, rejeté = pâle et pointillé
  { selector: 'node[statut = "À valider"]', style: { "border-style": "dashed", "border-width": 2.5, "border-color": "#fbbf24" } },
  { selector: 'node[statut = "Rejeté"]', style: { "background-opacity": 0.35, "border-style": "dotted", "border-width": 2.5, "border-color": "#f87171" } },
  // Donnée critique : bordure rouge épaisse (toujours visible)
  { selector: "node.critique", style: { "border-width": 3.5, "border-color": "#ef4444" } },
  {
    selector: "edge",
    style: {
      width: "data(width)",
      "line-color": "#4a5a7a",
      "target-arrow-color": "#4a5a7a",
      "target-arrow-shape": "triangle",
      "arrow-scale": 1.1,
      "curve-style": "bezier",
    },
  },
  { selector: 'edge[statut = "À valider"]', style: { "line-style": "dashed", "line-color": "#b7913a", "target-arrow-color": "#b7913a" } },
  { selector: 'edge[statut = "Rejeté"]', style: { "line-style": "dotted", "line-color": "#f87171", "target-arrow-color": "#f87171" } },
  // Règle de transformation écrite sur la flèche (case « Règles sur les flèches »)
  {
    selector: "edge.show-txn",
    style: {
      label: "data(txn)",
      "font-size": 9,
      color: "#cbd5e1",
      "text-background-color": "#0f1420",
      "text-background-opacity": 0.85,
      "text-background-padding": 2,
      "text-wrap": "ellipsis",
      "text-max-width": 160,
    },
  },
  // Sélection et lignage
  { selector: "node.selected", style: { "background-color": "#4f8cff", "border-color": "#dbe6ff", "border-width": 3.5 } },
  { selector: "node.up", style: { "background-color": "#fbbf24" } },
  { selector: "edge.up", style: { "line-color": "#fbbf24", "target-arrow-color": "#fbbf24", width: 3.5 } },
  { selector: "node.down", style: { "background-color": "#34d399" } },
  { selector: "edge.down", style: { "line-color": "#34d399", "target-arrow-color": "#34d399", width: 3.5 } },
  { selector: "edge.selected", style: { "line-color": "#4f8cff", "target-arrow-color": "#4f8cff", width: 4.5 } },
  { selector: ".faded", style: { opacity: 0.12 } },
  // Masqué par le filtre « Afficher »
  { selector: ".filtered", style: { display: "none" } },
];

function renderGraph() {
  brk("renderGraph — entrée");
  if (cy) {
    cy.destroy();
    cy = null;
  }
  if (Object.keys(model.assets).length === 0) {
    dropzone.classList.remove("hidden");
    legend.hidden = true;
    return;
  }
  dropzone.classList.add("hidden");

  cy = cytoscape({
    container: $("cy"),
    elements: buildElements(),
    style: CY_STYLE,
  });

  // Clic sur un nœud : fiche + voisins directs. Sur une boîte : fiche de la table.
  // Attention : dans cytoscape, un clic sur une colonne « remonte » aussi à la
  // boîte qui la contient (propagation). On mémorise l'instant du clic sur la
  // colonne pour ignorer ce second appel venant de la boîte.
  let lastNodeTap = -1;
  cy.on("tap", "node", (evt) => {
    const n = evt.target;
    if (n.data("isGroup")) {
      if (evt.timeStamp === lastNodeTap) return; // clic déjà traité par la colonne
      selectGroup(n.id().slice(5)); // "grp::" = 5 caractères
    } else {
      lastNodeTap = evt.timeStamp;
      selectNode(n.id(), "voisins");
    }
  });
  cy.on("tap", "edge", (evt) => selectEdge(evt.target.id()));
  cy.on("tap", (evt) => {
    if (evt.target === cy) clearSelection();
  });

  applyTxnLabels();
  applyFilter(false);
  runLayout();
  buildLegend();
  restoreSelection();
}

function syncGraph() {
  if (!cy) {
    renderGraph();
    return;
  }
  if (Object.keys(model.assets).length === 0) {
    renderGraph(); // base vidée -> retour à la zone de dépôt
    return;
  }

  const wanted = buildElements();
  const wantedIds = new Set(wanted.map((e) => e.data.id));
  const added = [];

  cy.batch(() => {
    // 1) on retire ce qui n'existe plus
    cy.elements().forEach((ele) => {
      if (!ele.removed() && !wantedIds.has(ele.id())) ele.remove();
    });
    // 2) on met à jour ce qui existe, on ajoute le reste
    wanted.forEach((e) => {
      const ex = cy.getElementById(e.data.id);
      if (ex.nonempty()) {
        ex.data(e.data);
        if (ex.isNode()) ex.classes(e.classes || "");
      } else {
        added.push(cy.add(e));
      }
    });
  });

  // 3) les nouveaux nœuds sont posés à côté d'un voisin déjà placé (ou au
  //    centre de la vue) pour ne pas bouleverser le dessin existant.
  const addedIds = new Set(added.map((e) => e.id()));
  const ext = cy.extent();
  added.forEach((ele) => {
    if (!ele.isNode() || ele.data("isGroup")) return;
    const placed = ele.neighborhood("node").filter((n) => !addedIds.has(n.id()));
    const jitter = () => (Math.random() - 0.5) * 60;
    if (placed.nonempty()) {
      const p = placed[0].position();
      ele.position({ x: p.x + 160, y: p.y + jitter() });
    } else {
      ele.position({ x: (ext.x1 + ext.x2) / 2 + jitter(), y: (ext.y1 + ext.y2) / 2 + jitter() });
    }
  });

  applyTxnLabels();
  applyFilter(false);
  buildLegend();
  restoreSelection();
}

function runLayout() {
  if (!cy) return;
  const config = LAYOUT_CONFIGS[layoutSelect.value] || LAYOUT_CONFIGS.dagreLR;
  // On ne dispose que les éléments visibles (le filtre peut en masquer).
  cy.elements().not(".filtered").layout({ ...config, fit: true, padding: 30 }).run();
}

function applyTxnLabels() {
  if (!cy) return;
  if (txnCheck.checked) cy.edges().addClass("show-txn");
  else cy.edges().removeClass("show-txn");
}

// Recolorie les nœuds quand on change le mode « Couleur ».
function applyColors() {
  if (!cy) return;
  cy.nodes().forEach((n) => {
    if (!n.data("isGroup")) n.data("color", colorFor(n.data()));
  });
  buildLegend();
}

/* ------------------------------------------------------------------
   8. Sélection, lignage amont / aval, analyse d'impact
   ------------------------------------------------------------------
   mode :
     "voisins" : prédécesseurs / successeurs DIRECTS (1 flèche)
     "amont"   : TOUS les ancêtres (cytoscape : node.predecessors())
     "aval"    : TOUS les descendants (cytoscape : node.successors())
     "deux"    : amont + aval
------------------------------------------------------------------ */
function selectNode(id, mode, opts) {
  if (!cy) return;
  const node = cy.getElementById(id);
  if (node.empty() || node.data("isGroup")) return;
  brk("selectNode — id = " + id + ", mode = " + mode);

  let up, down;
  if (mode === "voisins") {
    up = node.incomers();   // arêtes entrantes + nœuds d'origine
    down = node.outgoers(); // arêtes sortantes + nœuds au bout
  } else {
    up = mode === "aval" ? cy.collection() : node.predecessors();
    down = mode === "amont" ? cy.collection() : node.successors();
  }

  cy.elements().removeClass("selected up down faded");
  cy.elements().addClass("faded");
  node.removeClass("faded").addClass("selected");
  up.removeClass("faded").addClass("up");
  down.removeClass("faded").addClass("down");
  // les boîtes (tables) qui contiennent un élément allumé restent visibles
  node.union(up).union(down).parents().removeClass("faded");

  selection = { kind: "node", id, mode };
  renderNodeFiche(node, mode);
  if (!(opts && opts.quiet)) {
    showTab("fiche");
    if (mode !== "voisins") cy.animate({ fit: { eles: node.union(up).union(down), padding: 50 }, duration: 300 });
  }
}

function selectEdge(id, opts) {
  if (!cy) return;
  const edge = cy.getElementById(id);
  if (edge.empty()) return;
  cy.elements().removeClass("selected up down faded");
  cy.elements().addClass("faded");
  edge.removeClass("faded").addClass("selected");
  edge.source().removeClass("faded").addClass("up");
  edge.target().removeClass("faded").addClass("down");
  edge.connectedNodes().parents().removeClass("faded");
  selection = { kind: "edge", id };
  renderEdgeFiche(edge);
  if (!(opts && opts.quiet)) showTab("fiche");
}

// Clic sur la boîte d'une table (mode regroupé) : fiche résumée de la table.
function selectGroup(table, opts) {
  if (!cy) return;
  const box = cy.getElementById("grp::" + table);
  cy.elements().removeClass("selected up down faded");
  if (box.nonempty()) {
    cy.elements().addClass("faded");
    box.removeClass("faded");
    box.children().removeClass("faded").addClass("selected");
  }
  selection = { kind: "group", id: table };
  renderTableFiche(table, Object.keys(model.assets).filter((id) => tableOf(id) === table));
  if (!(opts && opts.quiet)) showTab("fiche");
}

function clearSelection() {
  if (cy) cy.elements().removeClass("selected up down faded");
  selection = null;
  ficheHint.hidden = false;
  ficheEl.innerHTML = "";
}

// Après une modification, on réaffiche la sélection en cours (si elle existe encore).
function restoreSelection() {
  if (!selection || !cy) return clearSelection();
  const s = selection;
  if (s.kind === "group") {
    if (Object.keys(model.assets).some((id) => tableOf(id) === s.id)) selectGroup(s.id, { quiet: true });
    else clearSelection();
  } else if (cy.getElementById(s.id).nonempty()) {
    if (s.kind === "node") selectNode(s.id, s.mode, { quiet: true });
    else selectEdge(s.id, { quiet: true });
  } else clearSelection();
}

// Rechercher un asset (barre d'outils) puis afficher son lignage.
function searchAndShow(mode) {
  if (!cy) return showError("Chargez ou saisissez d'abord des données.");
  const q = searchInput.value.trim();
  let target = null;
  if (q) {
    const nodes = cy.nodes().filter((n) => !n.data("isGroup"));
    // 1) correspondance exacte, 2) sinon le 1er id qui CONTIENT le texte
    target = nodes.filter((n) => n.id() === q)[0] ||
      nodes.filter((n) => n.id().toLowerCase().includes(q.toLowerCase()))[0];
    if (!target) return showError(`Aucun asset ne correspond à « ${q} ».`);
  } else if (selection && selection.kind === "node") {
    target = cy.getElementById(selection.id); // pas de texte : on prend le nœud sélectionné
  } else {
    return showError("Tapez un nom d'asset dans la recherche (ou cliquez un nœud).");
  }
  hideError();
  // Si le filtre masque cet asset, on revient à « tout » pour pouvoir l'afficher.
  if (target.hasClass("filtered")) {
    filterSelect.value = "tout";
    applyFilter(true);
  }
  selectNode(target.id(), mode);
}

/* Analyse d'impact d'un nœud :
   - origines        : ancêtres sans parent (les sources premières)
   - rapports impactés : descendants de type Rapport
   - données personnelles en amont : ancêtres PII (d'où vient la donnée sensible) */
function impactOf(node) {
  const ups = node.predecessors().nodes();
  const downs = node.successors().nodes();
  return {
    ups,
    downs,
    origines: ups.filter((n) => n.indegree(false) === 0),
    rapports: downs.filter((n) => n.data("type") === "Rapport"),
    piiAmont: ups.filter((n) => n.data("pii")),
  };
}

/* ------------------------------------------------------------------
   9. Fiche descriptive (onglet « Fiche »)
------------------------------------------------------------------ */
function badgeCriticite(c) {
  return `<span class="badge crit-${critRank(c)}">Criticité : ${esc(c)}</span>`;
}

function statutBadge(s) {
  const cls = s === "Validé" ? "st-ok" : s === "Rejeté" ? "st-ko" : "st-wait";
  return `<span class="badge ${cls}">${esc(s)}</span>`;
}

// Liste de boutons « puces » cliquables (un par nœud) ; clic -> on le sélectionne.
function chipList(ids, emptyText) {
  if (!ids.length) return `<p class="chip-empty">${esc(emptyText || "aucun")}</p>`;
  return `<div class="chips">${ids
    .map((id) => {
      const a = model.assets[id];
      const crit = a && isCritical(a) ? " crit" : "";
      return `<button type="button" class="chip${crit}" data-goto="${esc(id)}" title="${esc(id)}">${esc(id)}</button>`;
    })
    .join("")}</div>`;
}

// Tableau voisin + règle de transformation (comme dans le projet d'origine).
function neighbourTable(rows, title) {
  const body = rows.length
    ? rows
        .map((r) => `<tr><td><button type="button" class="chip" data-goto="${esc(r.id)}">${esc(r.id)}</button></td><td class="sel-table-txn rule">${esc(r.txn || "—")}</td></tr>`)
        .join("")
    : `<tr><td colspan="2" class="chip-empty">aucun</td></tr>`;
  return `<div class="sel-block">
      <span class="sel-label">${title} <b>${rows.length}</b></span>
      <table class="sel-table"><thead><tr><th>Asset</th><th>Transformation</th></tr></thead><tbody>${body}</tbody></table>
    </div>`;
}

// Historique d'un asset : ses propres entrées + celles des relations qui le touchent.
function historyTable(entries) {
  if (!entries.length) return `<p class="chip-empty">aucune modification enregistrée</p>`;
  return `<table class="hist-table"><tbody>${entries
    .slice()
    .reverse()
    .map(
      (h) => `<tr>
        <td class="when">${esc(fmtDate(h.date))}<br>${esc(h.user)}</td>
        <td><span class="hist-action">${esc(h.action)}</span> ${h.cibleType === "relation" ? "relation " : ""}<span class="muted">${esc(h.cible)}</span>${h.detail ? "<br>" + esc(h.detail) : ""}</td>
      </tr>`
    )
    .join("")}</tbody></table>`;
}

function auditBlock(o) {
  const line = (label, who, when) => (who ? `<dt>${label}</dt><dd>${esc(who)} — ${esc(fmtDate(when))}</dd>` : "");
  return line("Créé par", o.creePar, o.creeLe) + line("Modifié par", o.modifiePar, o.modifieLe) + line("Validé par", o.validePar, o.valideLe);
}

// Boutons d'action selon les droits du rôle courant.
function actionButtons(kind, o) {
  const b = [];
  if (can("edit")) b.push(`<button type="button" class="btn btn-sm" data-act="edit-${kind}" data-id="${esc(o.id)}">Modifier</button>`);
  if (can("validate") && o.statut !== "Validé") b.push(`<button type="button" class="btn btn-sm btn-ok" data-act="valider-${kind}" data-id="${esc(o.id)}">Valider</button>`);
  if (can("validate") && o.statut === "À valider") b.push(`<button type="button" class="btn btn-sm" data-act="rejeter-${kind}" data-id="${esc(o.id)}">Rejeter</button>`);
  if (can("remove")) b.push(`<button type="button" class="btn btn-sm btn-danger" data-act="suppr-${kind}" data-id="${esc(o.id)}">Supprimer</button>`);
  return b.length ? `<div class="btn-row">${b.join("")}</div>` : "";
}

function renderNodeFiche(node, mode) {
  ficheHint.hidden = true;
  const id = node.id();
  const macro = levelSelect.value === "macro";
  const a = macro ? null : model.assets[id];
  const d = node.data();

  // Voisins directs + règle de transformation
  const succRows = node.outgoers().edges().map((e) => ({ id: e.target().id(), txn: e.data("txn") }));
  const predRows = node.incomers().edges().map((e) => ({ id: e.source().id(), txn: e.data("txn") }));
  const imp = impactOf(node);
  const ids = (col) => col.map((n) => n.id()).sort();

  let html = `<div class="card">
    <p class="fiche-title">${d.pii ? "🔒 " : ""}${esc(id)}</p>
    <div class="badges">
      <span class="badge">${esc(d.type)}</span>
      <span class="badge">${d.nature === "traitement" ? "Traitement" : "Donnée"}</span>
      ${badgeCriticite(d.criticite)}
      ${d.pii ? '<span class="badge pii">Donnée personnelle (PII / RGPD)</span>' : ""}
      ${statutBadge(d.statut)}
    </div>`;

  if (a) {
    html += `<dl class="meta">
        <dt>Propriétaire</dt><dd>${esc(a.owner || "—")}</dd>
        <dt>Description</dt><dd>${esc(a.description || "—")}</dd>
        ${auditBlock(a)}
      </dl>${actionButtons("asset", a)}`;
  } else {
    html += `<p class="muted small">Vue macro : table regroupant ${d.children.length} élément(s). Cliquez-en un pour le voir au niveau micro.</p>
      ${chipList(d.children)}`;
  }

  html += `<div class="btn-row">
      <button type="button" class="btn btn-sm" data-act="lineage" data-mode="amont" data-id="${esc(id)}">↑ Amont</button>
      <button type="button" class="btn btn-sm" data-act="lineage" data-mode="aval" data-id="${esc(id)}">↓ Aval</button>
      <button type="button" class="btn btn-sm" data-act="lineage" data-mode="deux" data-id="${esc(id)}">↕ Les deux</button>
    </div></div>`;

  // Analyse d'impact
  html += `<div class="card"><h2>Analyse d'impact</h2>
      <span class="sel-label">Rapports impactés en aval <b>${imp.rapports.length}</b></span>
      ${chipList(ids(imp.rapports), "aucun rapport en aval")}
      <span class="sel-label" style="margin-top:.6rem">Origines (sources premières) <b>${imp.origines.length}</b></span>
      ${chipList(ids(imp.origines), "aucune : c'est une source")}
      <span class="sel-label" style="margin-top:.6rem">Données personnelles en amont <b>${imp.piiAmont.length}</b></span>
      ${chipList(ids(imp.piiAmont), "aucune")}
      <p class="muted small" style="margin-top:.6rem">${imp.ups.length} élément(s) en amont, ${imp.downs.length} en aval.</p>
    </div>`;

  html += `<div class="card"><h2>${mode === "voisins" ? "Voisins directs" : "Voisins directs (lignage complet surligné)"}</h2>
      ${neighbourTable(predRows, "Parents (amont direct)")}
      ${neighbourTable(succRows, "Enfants (aval direct)")}
    </div>`;

  if (a) {
    const hist = model.history.filter(
      (h) => h.cible === id || (h.cibleType === "relation" && String(h.cible).split("=>").includes(id))
    );
    html += `<div class="card"><h2>Historique</h2>${historyTable(hist)}</div>`;
  }

  ficheEl.innerHTML = html;
}

function renderEdgeFiche(edge) {
  ficheHint.hidden = true;
  const macro = levelSelect.value === "macro";
  let html;
  if (!macro) {
    const r = model.relations[edge.id()];
    if (!r) return clearSelection();
    const hist = model.history.filter((h) => h.cible === r.id);
    html = `<div class="card">
        <h2>Relation Parent → Enfant</h2>
        <p class="fiche-title">${esc(r.source)}<br>→ ${esc(r.target)}</p>
        <div class="badges">${statutBadge(r.statut)}</div>
        <dl class="meta">
          <dt>Règle</dt><dd class="rule">${esc(r.txn || "—")}</dd>
          ${auditBlock(r)}
        </dl>
        ${actionButtons("rel", r)}
        <div class="btn-row">
          <button type="button" class="btn btn-sm" data-goto="${esc(r.source)}">Voir le parent</button>
          <button type="button" class="btn btn-sm" data-goto="${esc(r.target)}">Voir l'enfant</button>
        </div>
      </div>
      <div class="card"><h2>Historique</h2>${historyTable(hist)}</div>`;
  } else {
    // Au niveau macro, une flèche = plusieurs relations entre colonnes.
    const rels = (edge.data("relIds") || []).map((id) => model.relations[id]).filter(Boolean);
    html = `<div class="card">
        <h2>Relations entre tables</h2>
        <p class="fiche-title">${esc(edge.source().id())}<br>→ ${esc(edge.target().id())}</p>
        <div class="badges">${statutBadge(edge.data("statut"))}<span class="badge">${rels.length} lien(s)</span></div>
        <table class="sel-table"><thead><tr><th>Colonne → colonne</th><th>Règle</th></tr></thead><tbody>
        ${rels.map((r) => `<tr><td>${esc(shortLabel(r.source))}<br>→ ${esc(shortLabel(r.target))}</td><td class="sel-table-txn rule">${esc(r.txn || "—")}</td></tr>`).join("")}
        </tbody></table>
      </div>`;
  }
  ficheEl.innerHTML = html;
}

function renderTableFiche(table, children) {
  ficheHint.hidden = true;
  const list = children.map((id) => model.assets[id]).filter(Boolean);
  const maxCrit = CRITICITES[Math.max(0, ...list.map((a) => critRank(a.criticite)))];
  ficheEl.innerHTML = `<div class="card">
      <h2>Table / objet</h2>
      <p class="fiche-title">${esc(table)}</p>
      <div class="badges">${badgeCriticite(maxCrit)}${list.some((a) => a.pii) ? '<span class="badge pii">contient des PII</span>' : ""}<span class="badge">${list.length} élément(s)</span></div>
      ${chipList(children.sort())}
    </div>`;
}

// Un seul écouteur pour tous les boutons de la fiche et des listes
// (« délégation d'événements ») : on regarde data-goto / data-act du bouton cliqué.
function onPanelClick(evt) {
  const btn = evt.target.closest("button");
  if (!btn) return;
  const goto = btn.getAttribute("data-goto");
  const act = btn.getAttribute("data-act");
  const id = btn.getAttribute("data-id");

  if (goto) return gotoAsset(goto);
  if (!act) return;
  if (act === "lineage") return selectNode(id, btn.getAttribute("data-mode"));
  if (act === "edit-asset") return startEditAsset(id);
  if (act === "edit-rel") return startEditRelation(id);
  if (act === "valider-asset") return setStatut("asset", id, true);
  if (act === "rejeter-asset") return setStatut("asset", id, false);
  if (act === "valider-rel") return setStatut("rel", id, true);
  if (act === "rejeter-rel") return setStatut("rel", id, false);
  if (act === "suppr-asset") return deleteAsset(id);
  if (act === "suppr-rel") return deleteRelation(id);
  if (act === "voir-rel") return gotoRelation(id);
  if (act === "trace") return gotoAsset(id, "aval");
}

// Aller à un asset (depuis une puce) : bascule au niveau micro si besoin,
// retire un filtre qui le masquerait, puis le sélectionne.
function gotoAsset(id, mode) {
  if (!model.assets[id] && levelSelect.value === "micro") return;
  if (levelSelect.value === "macro" && model.assets[id]) {
    levelSelect.value = "micro";
    renderGraph();
  }
  if (cy && cy.getElementById(id).hasClass("filtered")) {
    filterSelect.value = "tout";
    applyFilter(true);
  }
  selectNode(id, mode || "voisins");
  if (cy) cy.animate({ center: { eles: cy.getElementById(id) }, duration: 250 });
}

function gotoRelation(id) {
  if (levelSelect.value === "macro") {
    levelSelect.value = "micro";
    renderGraph();
  }
  if (cy && cy.getElementById(id).hasClass("filtered")) {
    filterSelect.value = "tout";
    applyFilter(true);
  }
  selectEdge(id);
}

/* ------------------------------------------------------------------
   10. Saisie manuelle (onglet « Saisie »)
   ------------------------------------------------------------------
   - Formulaire asset : déclarer un asset (Table, Colonne, Fichier,
     Rapport, API…) avec sa fiche descriptive et sa criticité.
   - Formulaire relation : définir un lien Parent -> Enfant entre deux
     assets et sa règle de transformation (ex. Montant_TTC = Montant_HT * 1.2).
   Chaque création / modification passe au statut « À valider » et est
   tracée dans l'historique.
------------------------------------------------------------------ */
function fillSelect(sel, values) {
  sel.innerHTML = values.map((v) => `<option value="${esc(v)}">${esc(v)}</option>`).join("");
}

function assetIdFromForm() {
  return [af.sys, af.schema, af.objet, af.col].map((i) => i.value.trim()).filter(Boolean).join(".");
}

function updateIdPreview() {
  af.preview.textContent = editingAssetId || assetIdFromForm() || "—";
}

function resetAssetForm() {
  editingAssetId = null;
  af.form.reset();
  [af.sys, af.schema, af.objet, af.col].forEach((i) => (i.disabled = false));
  af.type.value = "Colonne";
  af.crit.value = "Faible";
  af.title.textContent = "Déclarer un asset";
  updateIdPreview();
}

function startEditAsset(id) {
  const a = model.assets[id];
  if (!a || !can("edit")) return;
  editingAssetId = id;
  // on remet l'id dans les 4 cases (désactivées : l'identifiant ne change pas)
  const [c1, c2, c3, c4] = splitId(id); // ordre : colonne, objet, schéma, système
  af.col.value = c1;
  af.objet.value = c2;
  af.schema.value = c3;
  af.sys.value = c4;
  [af.sys, af.schema, af.objet, af.col].forEach((i) => (i.disabled = true));
  af.nature.value = a.nature;
  af.type.value = a.type;
  af.owner.value = a.owner || "";
  af.crit.value = a.criticite;
  af.desc.value = a.description || "";
  af.pii.checked = !!a.pii;
  af.title.textContent = "Modifier l'asset";
  updateIdPreview();
  showTab("saisie");
  af.owner.focus();
}

function saveAsset(evt) {
  evt.preventDefault(); // le formulaire ne doit pas recharger la page
  if (!can("edit")) return;
  const u = currentUser();

  const fields = {
    nature: af.nature.value,
    type: af.type.value,
    owner: af.owner.value.trim(),
    description: af.desc.value.trim(),
    criticite: af.crit.value,
    pii: af.pii.checked,
  };

  if (!editingAssetId) {
    // --- Création ---
    const parts = [af.sys, af.schema, af.objet, af.col].map((i) => i.value.trim()).filter(Boolean);
    if (!parts.length) return showError("Renseignez au moins un morceau de l'identifiant (ex. objet + colonne).");
    if (parts.some((p) => p.includes(".") || p.includes("=>"))) return showError("Un morceau d'identifiant ne doit contenir ni « . » ni « => ».");
    const id = parts.join(".");
    if (model.assets[id]) return showError(`L'asset « ${id} » existe déjà : cliquez-le puis « Modifier ».`);

    model.assets[id] = { id, ...fields, statut: "À valider", creePar: u.name, creeLe: nowIso() };
    logChange("CRÉATION", "asset", id, `type : ${fields.type} ; criticité : ${fields.criticite}${fields.pii ? " ; PII" : ""}`);
    afterChange(`Asset « ${id} » créé (à valider).`);
    resetAssetForm();
    selectNode(id, "voisins", { quiet: true });
  } else {
    // --- Modification : on note chaque champ changé (ancienne -> nouvelle valeur) ---
    const a = model.assets[editingAssetId];
    if (!a) return resetAssetForm();
    const labels = { nature: "nature", type: "type", owner: "propriétaire", description: "description", criticite: "criticité", pii: "PII" };
    const show = (k, v) => (k === "pii" ? (v ? "oui" : "non") : v || "∅");
    const diff = Object.keys(fields)
      .filter((k) => (k === "pii" ? !!a[k] !== fields[k] : (a[k] || "") !== fields[k]))
      .map((k) => `${labels[k]} : ${show(k, a[k])} → ${show(k, fields[k])}`);
    if (!diff.length) return toast("Aucune modification.");

    Object.assign(a, fields, { statut: "À valider", modifiePar: u.name, modifieLe: nowIso() });
    logChange("MODIFICATION", "asset", a.id, diff.join(" ; "));
    const id = a.id;
    resetAssetForm();
    afterChange(`Asset « ${id} » modifié (à revalider).`);
  }
}

// Y a-t-il un chemin from -> … -> to en suivant les relations ? (parcours en largeur)
function canReach(from, to) {
  const next = {};
  Object.values(model.relations).forEach((r) => (next[r.source] = next[r.source] || []).push(r.target));
  const seen = new Set([from]);
  const queue = [from];
  while (queue.length) {
    const cur = queue.shift();
    if (cur === to) return true;
    for (const n of next[cur] || []) {
      if (!seen.has(n)) {
        seen.add(n);
        queue.push(n);
      }
    }
  }
  return false;
}

function resetRelForm() {
  editingRelId = null;
  rf.form.reset();
  rf.source.disabled = false;
  rf.target.disabled = false;
  rf.title.textContent = "Déclarer une relation Parent → Enfant";
}

function startEditRelation(id) {
  const r = model.relations[id];
  if (!r || !can("edit")) return;
  editingRelId = id;
  rf.source.value = r.source;
  rf.target.value = r.target;
  rf.source.disabled = true;
  rf.target.disabled = true;
  rf.txn.value = r.txn || "";
  rf.title.textContent = "Modifier la règle de transformation";
  showTab("saisie");
  rf.txn.focus();
}

function saveRelation(evt) {
  evt.preventDefault();
  if (!can("edit")) return;
  const u = currentUser();
  const txn = rf.txn.value.trim();

  if (editingRelId) {
    const r = model.relations[editingRelId];
    if (!r) return resetRelForm();
    if ((r.txn || "") === txn) return toast("Aucune modification.");
    logChange("MODIFICATION", "relation", r.id, `règle : ${r.txn || "∅"} → ${txn || "∅"}`);
    Object.assign(r, { txn, statut: "À valider", modifiePar: u.name, modifieLe: nowIso() });
    resetRelForm();
    afterChange("Règle modifiée (à revalider).");
    return;
  }

  const source = rf.source.value.trim();
  const target = rf.target.value.trim();
  if (!model.assets[source]) return showError(`Parent inconnu : « ${source} ». Déclarez d'abord l'asset.`);
  if (!model.assets[target]) return showError(`Enfant inconnu : « ${target} ». Déclarez d'abord l'asset.`);
  if (source === target) return showError("Le parent et l'enfant doivent être différents.");
  const id = relId(source, target);
  if (model.relations[id]) return showError("Cette relation existe déjà : cliquez la flèche puis « Modifier ».");
  // Un lignage ne devrait pas boucler : on prévient si la relation crée un cycle.
  if (canReach(target, source) && !confirm("Attention : cette relation crée un cycle (l'enfant alimente déjà le parent). Continuer ?")) return;

  model.relations[id] = { id, source, target, txn, statut: "À valider", creePar: u.name, creeLe: nowIso() };
  logChange("CRÉATION", "relation", id, txn ? "règle : " + txn : "");
  resetRelForm();
  afterChange("Relation créée (à valider).");
  selectEdge(id, { quiet: true });
}

/* ------------------------------------------------------------------
   11. Validation, rejet, suppression
------------------------------------------------------------------ */
function setStatut(kind, id, ok) {
  if (!can("validate")) return;
  const o = kind === "asset" ? model.assets[id] : model.relations[id];
  if (!o) return;
  const u = currentUser();
  const cible = kind === "asset" ? "asset" : "relation";
  if (ok) {
    Object.assign(o, { statut: "Validé", validePar: u.name, valideLe: nowIso() });
    logChange("VALIDATION", cible, id, "");
    afterChange("Validé.");
  } else {
    const motif = prompt("Motif du rejet :");
    if (motif === null) return; // « Annuler »
    o.statut = "Rejeté";
    logChange("REJET", cible, id, motif.trim());
    afterChange("Rejeté.");
  }
}

function deleteAsset(id) {
  if (!can("remove") || !model.assets[id]) return;
  const rels = Object.values(model.relations).filter((r) => r.source === id || r.target === id);
  if (!confirm(`Supprimer l'asset « ${id} » et ses ${rels.length} relation(s) ?`)) return;
  rels.forEach((r) => delete model.relations[r.id]);
  delete model.assets[id];
  logChange("SUPPRESSION", "asset", id, `${rels.length} relation(s) supprimée(s)`);
  if (editingAssetId === id) resetAssetForm();
  afterChange("Asset supprimé.");
}

function deleteRelation(id) {
  if (!can("remove") || !model.relations[id]) return;
  if (!confirm("Supprimer cette relation ?")) return;
  delete model.relations[id];
  logChange("SUPPRESSION", "relation", id, "");
  if (editingRelId === id) resetRelForm();
  afterChange("Relation supprimée.");
}

// À appeler après TOUTE modification du modèle : sauvegarde + redessin + panneaux.
function afterChange(message) {
  hideError();
  saveModel();
  syncGraph();
  renderPanels();
  if (message) toast(message);
}

/* ------------------------------------------------------------------
   12. Panneaux : critiques, validation, historique, statistiques
------------------------------------------------------------------ */
function renderPanels() {
  renderDatalists();
  renderCritiques();
  renderValidation();
  renderHistory();
  renderStats();
  fileNameEl.textContent = model.source ? "Source : " + model.source : "Saisie manuelle";
}

function renderDatalists() {
  const opts = (ids) => ids.sort().map((id) => `<option value="${esc(id)}"></option>`).join("");
  assetsDatalist.innerHTML = opts(Object.keys(model.assets));
  // la recherche porte sur ce qui est affiché (colonnes en micro, tables en macro)
  searchDatalist.innerHTML = cy ? opts(cy.nodes().filter((n) => !n.data("isGroup")).map((n) => n.id())) : "";
}

/* Données critiques : criticité Haute/Critique ou PII. Pour chacune on
   indique combien d'éléments en dépendent (aval) : c'est la traçabilité
   demandée par la conformité (RGPD, BCBS 239). */
function renderCritiques() {
  const all = Object.values(model.assets);
  const crit = all.filter(isCritical).sort((a, b) => critRank(b.criticite) - critRank(a.criticite) || Number(b.pii) - Number(a.pii) || a.id.localeCompare(b.id));
  const count = (f) => all.filter(f).length;

  critBadge.textContent = crit.length || "";
  critTiles.innerHTML = [
    tile("Critique", count((a) => a.criticite === "Critique"), "danger"),
    tile("Haute", count((a) => a.criticite === "Haute"), "warn"),
    tile("Données personnelles", count((a) => a.pii), "danger"),
    tile("Rapports critiques", count((a) => a.type === "Rapport" && isCritical(a)), ""),
  ].join("");

  // Nombre de descendants (aval) de chaque asset, calculé sur le modèle.
  const next = {};
  Object.values(model.relations).forEach((r) => (next[r.source] = next[r.source] || []).push(r.target));
  const downstreamCount = (id) => {
    const seen = new Set(); // descendants déjà comptés
    const stack = [id];     // nœuds dont il reste à explorer les enfants
    while (stack.length) {
      const cur = stack.pop();
      for (const child of next[cur] || []) {
        if (!seen.has(child)) {
          seen.add(child);
          stack.push(child);
        }
      }
    }
    return seen.size;
  };

  critList.innerHTML = crit.length
    ? crit
        .map(
          (a) => `<div class="row-item">
        <button type="button" class="chip crit" data-goto="${esc(a.id)}">${a.pii ? "🔒 " : ""}${esc(a.id)}</button>
        <div class="badges">${badgeCriticite(a.criticite)}${a.pii ? '<span class="badge pii">PII / RGPD</span>' : ""}<span class="badge">${esc(a.type)}</span>${statutBadge(a.statut)}</div>
        <span class="muted small">Propriétaire : ${esc(a.owner || "—")} · ${downstreamCount(a.id)} élément(s) en aval</span>
        <div class="btn-row"><button type="button" class="btn btn-sm" data-act="trace" data-id="${esc(a.id)}">Tracer la propagation (aval)</button></div>
      </div>`
        )
        .join("")
    : `<p class="muted">Aucune donnée critique. Renseignez la criticité dans la fiche des assets (onglet « Saisie »).</p>`;
}

function tile(label, value, cls) {
  return `<div class="stat"><span class="stat-label">${esc(label)}</span><span class="stat-value ${cls}">${esc(value)}</span></div>`;
}

function renderValidation() {
  const assets = Object.values(model.assets).filter((a) => a.statut === "À valider");
  const rels = Object.values(model.relations).filter((r) => r.statut === "À valider");
  validBadge.textContent = assets.length + rels.length || "";

  const btns = (kind, id) =>
    can("validate")
      ? `<div class="btn-row">
          <button type="button" class="btn btn-sm btn-ok" data-act="valider-${kind}" data-id="${esc(id)}">Valider</button>
          <button type="button" class="btn btn-sm" data-act="rejeter-${kind}" data-id="${esc(id)}">Rejeter</button>
        </div>`
      : "";
  const who = (o) => `<span class="muted small">${esc(o.modifiePar || o.creePar || "?")} — ${esc(fmtDate(o.modifieLe || o.creeLe))}</span>`;

  let html = `<div class="card"><h2>Assets à valider (${assets.length})</h2>`;
  html += assets.length
    ? assets.map((a) => `<div class="row-item"><button type="button" class="chip" data-goto="${esc(a.id)}">${esc(a.id)}</button>${who(a)}${btns("asset", a.id)}</div>`).join("")
    : `<p class="chip-empty">rien à valider</p>`;
  html += `</div><div class="card"><h2>Relations à valider (${rels.length})</h2>`;
  html += rels.length
    ? rels
        .map(
          (r) => `<div class="row-item">
          <button type="button" class="chip" data-act="voir-rel" data-id="${esc(r.id)}">${esc(r.source)} → ${esc(r.target)}</button>
          <span class="rule small">${esc(r.txn || "—")}</span>${who(r)}${btns("rel", r.id)}</div>`
        )
        .join("")
    : `<p class="chip-empty">rien à valider</p>`;
  html += `</div>`;
  if (!can("validate")) html += `<p class="muted small">Seuls le Data Steward et l'Administrateur peuvent valider.</p>`;
  validList.innerHTML = html;
}

function renderHistory() {
  const q = histFilter.value.trim().toLowerCase();
  const rows = model.history.filter((h) => !q || [h.user, h.role, h.action, h.cible, h.detail].join(" ").toLowerCase().includes(q));
  // les 300 plus récentes suffisent à l'écran (l'export Excel contient tout)
  histList.innerHTML = `<p class="muted small">${rows.length} entrée(s)</p>` + historyTable(rows.slice(-300));
}

/* Statistiques du graphe (reprises du projet d'origine) */
function computeStats(data) {
  const n = data.nodes.length;
  const m = data.edges.length;
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
  return {
    n,
    m,
    density: n > 1 ? (m / (n * (n - 1))).toFixed(3) : "0",
    isolated,
    maxDeg,
    maxDegNode,
    hasCycle: detectCycle(data),
    components: countWeakComponents(data),
  };
}

/* detectCycle : parcours en PROFONDEUR (DFS) avec 3 couleurs
   (0 = pas visité, 1 = en cours, 2 = terminé). Retomber sur un nœud
   « en cours » = on a bouclé = cycle. */
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

/* countWeakComponents : nombre de « morceaux » séparés du graphe, sans
   tenir compte du sens des flèches. Parcours en LARGEUR (BFS). */
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

function renderStats() {
  const assets = Object.values(model.assets);
  if (!assets.length) {
    statsEl.innerHTML = `<p class="muted">—</p>`;
    return;
  }
  const rels = Object.values(model.relations).filter((r) => model.assets[r.source] && model.assets[r.target]);
  const s = computeStats({ nodes: assets.map((a) => ({ id: a.id })), edges: rels });
  const count = (list, f) => list.filter(f).length;
  statsEl.innerHTML = [
    tile("Assets", s.n, ""),
    tile("Relations", s.m, ""),
    tile("Tables / objets", new Set(assets.map((a) => tableOf(a.id))).size, ""),
    tile("Traitements", count(assets, (a) => a.nature === "traitement"), ""),
    tile("Rapports", count(assets, (a) => a.type === "Rapport"), ""),
    tile("Données critiques", count(assets, isCritical), "danger"),
    tile("À valider", count(assets, (a) => a.statut === "À valider") + count(rels, (r) => r.statut === "À valider"), "warn"),
    tile("Rejetés", count(assets, (a) => a.statut === "Rejeté") + count(rels, (r) => r.statut === "Rejeté"), ""),
    tile("Densité", s.density, ""),
    tile("Assets isolés", s.isolated, ""),
    tile("Composantes", s.components, ""),
    tile("Cycle", s.hasCycle ? "Oui" : "Non", s.hasCycle ? "warn" : "ok"),
    tile("Degré max", s.maxDegNode ? `${s.maxDeg} (${shortLabel(s.maxDegNode)})` : s.maxDeg, ""),
  ].join("");
}

/* ------------------------------------------------------------------
   13. Filtre « Afficher » et légende
------------------------------------------------------------------ */
function applyFilter(relayout) {
  if (!cy) return;
  cy.elements().removeClass("filtered");
  const mode = filterSelect.value;
  if (mode !== "tout") {
    const nodes = cy.nodes().filter((n) => !n.data("isGroup"));
    let keep;
    if (mode === "critiques") {
      // les données critiques + tout leur lignage (amont et aval)
      const crit = nodes.filter((n) => n.data("critical"));
      keep = crit.union(crit.predecessors()).union(crit.successors());
    } else if (mode === "pii") {
      // les données personnelles + partout où elles se propagent (aval)
      const pii = nodes.filter((n) => n.data("pii"));
      keep = pii.union(pii.successors());
    } else {
      // éléments à valider + les nœuds au bout des relations à valider
      const n = nodes.filter((x) => x.data("statut") === "À valider");
      const e = cy.edges().filter((x) => x.data("statut") === "À valider");
      keep = n.union(e).union(e.connectedNodes());
    }
    keep = keep.union(keep.parents()); // garder les boîtes des tables concernées
    cy.elements().not(keep).addClass("filtered");
    // une flèche n'est visible que si ses deux bouts le sont
    cy.edges().filter((e) => e.source().hasClass("filtered") || e.target().hasClass("filtered")).addClass("filtered");
  }
  if (relayout) runLayout();
}

function buildLegend() {
  if (!cy) {
    legend.hidden = true;
    return;
  }
  const mode = colorSelect.value;
  const palette = mode === "criticite" ? CRIT_COLORS : mode === "statut" ? STATUT_COLORS : TYPE_COLORS;
  const sw = (color, text, extra) => `<span><i class="swatch" style="background:${color};${extra || ""}"></i>${esc(text)}</span>`;
  legend.innerHTML =
    Object.entries(palette).map(([k, c]) => sw(c, k)).join("") +
    sw("transparent", "donnée critique", "border:2px solid #ef4444") +
    `<span>🔒 donnée personnelle</span>` +
    sw("transparent", "à valider", "border:2px dashed #fbbf24") +
    sw("#fbbf24", "amont") +
    sw("#34d399", "aval");
  legend.hidden = false;
}

/* ------------------------------------------------------------------
   14. Chargement : fichier Excel, exemple, sauvegarde du navigateur
------------------------------------------------------------------ */

// Remplace toute la base par un nouveau modèle (import ou exemple).
function replaceModel(newModel, label) {
  if (!can("importer")) return showError("Votre rôle ne permet pas de remplacer la base.");
  const n = Object.keys(model.assets).length;
  if (n && !confirm(`Remplacer la base actuelle (${n} assets, ${Object.keys(model.relations).length} relations) par « ${label} » ?\nPensez à l'exporter avant si besoin.`)) return;
  model = newModel;
  logChange("IMPORT", "base", label, `${Object.keys(model.assets).length} assets, ${Object.keys(model.relations).length} relations`);
  saveModel();
  selection = null;
  resetAssetForm();
  resetRelForm();
  hideError();
  renderGraph();
  renderPanels();
  toast(`« ${label} » chargé.`);
}

function loadFile(file) {
  if (!file) return; // boîte de dialogue annulée
  if (!can("importer")) return showError("Votre rôle ne permet pas d'importer.");
  // FileReader lit le fichier de façon ASYNCHRONE : on dit d'abord quoi faire
  // quand c'est prêt (onload), puis on lance la lecture.
  const reader = new FileReader();
  reader.onload = () => {
    brk("loadFile — fichier lu : " + file.name);
    try {
      replaceModel(workbookBufferToModel(reader.result, file.name), file.name);
    } catch (err) {
      showError(err.message || String(err));
    }
  };
  reader.onerror = () => showError("Impossible de lire le fichier.");
  reader.readAsArrayBuffer(file);
}

let errorTimer = null;
function showError(message) {
  stageError.textContent = message;
  stageError.hidden = false;
  clearTimeout(errorTimer);
  errorTimer = setTimeout(hideError, 7000);
}

function hideError() {
  stageError.hidden = true;
}

let toastTimer = null;
function toast(message) {
  toastEl.textContent = message;
  toastEl.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toastEl.hidden = true), 2500);
}

function showTab(name) {
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === name));
  document.querySelectorAll(".tab-panel").forEach((p) => (p.hidden = p.id !== "tab-" + name));
}

// Adapte l'interface au rôle choisi (lecture seule pour le consommateur…).
function applyRole() {
  const readonly = !can("edit");
  tabSaisie.classList.toggle("readonly", readonly);
  readonlyNotice.hidden = !readonly;
  adminCard.hidden = !can("remove");
  importLabel.classList.toggle("disabled", !can("importer"));
  fileInput.disabled = !can("importer");
  exampleBtn.disabled = !can("importer");
  if (readonly) {
    resetAssetForm();
    resetRelForm();
  }
  savePrefs();
  renderPanels();
  restoreSelection(); // la fiche affiche ou masque les boutons d'action
}

function savePrefs() {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify({ user: userInput.value, role: roleSelect.value }));
  } catch (err) {
    /* stockage indisponible : sans conséquence */
  }
}

function loadPrefs() {
  try {
    const p = JSON.parse(localStorage.getItem(PREFS_KEY) || "{}");
    if (p.user) userInput.value = p.user;
    if (p.role && ROLES[p.role]) roleSelect.value = p.role;
  } catch (err) {
    /* rien */
  }
}

/* ------------------------------------------------------------------
   15. Câblage des événements de l'interface
------------------------------------------------------------------ */

// Listes déroulantes des formulaires
fillSelect(af.type, TYPES);
fillSelect(af.crit, CRITICITES);

// a) Import / exemple / export
fileInput.addEventListener("change", (e) => {
  loadFile(e.target.files && e.target.files[0]);
  fileInput.value = ""; // permet de recharger le même fichier ensuite
});
exampleBtn.addEventListener("click", () => {
  try {
    replaceModel(modelFromSheets([EXEMPLE.lineage, EXEMPLE.assets, EXEMPLE.historique], "exemple.xlsx (intégré)"), "exemple.xlsx (intégré)");
  } catch (err) {
    showError(err.message || String(err));
  }
});
exportBtn.addEventListener("click", () => {
  if (!Object.keys(model.assets).length) return showError("Rien à exporter.");
  exportExcel();
});

// b) Glisser-déposer un .xlsx sur la scène
stage.addEventListener("dragover", (e) => {
  e.preventDefault();
  stage.classList.add("drag-over");
});
stage.addEventListener("dragleave", (e) => {
  if (!stage.contains(e.relatedTarget)) stage.classList.remove("drag-over");
});
stage.addEventListener("drop", (e) => {
  e.preventDefault();
  stage.classList.remove("drag-over");
  loadFile(e.dataTransfer.files && e.dataTransfer.files[0]);
});

// c) Utilisateur et rôle
roleSelect.addEventListener("change", applyRole);
userInput.addEventListener("change", savePrefs);

// d) Barre d'outils du graphe
$("btn-amont").addEventListener("click", () => searchAndShow("amont"));
$("btn-aval").addEventListener("click", () => searchAndShow("aval"));
$("btn-deux").addEventListener("click", () => searchAndShow("deux"));
searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") searchAndShow("deux"); // Entrée = amont + aval
});
levelSelect.addEventListener("change", () => {
  groupCheck.disabled = levelSelect.value === "macro"; // regrouper n'a de sens qu'en micro
  selection = null;
  renderGraph();
  renderDatalists();
});
groupCheck.addEventListener("change", () => {
  renderGraph();
});
colorSelect.addEventListener("change", applyColors);
filterSelect.addEventListener("change", () => {
  applyFilter(true);
  restoreSelection();
});
txnCheck.addEventListener("change", applyTxnLabels);
layoutSelect.addEventListener("change", runLayout);
$("fit-btn").addEventListener("click", () => {
  if (cy) cy.animate({ fit: { eles: cy.elements().not(".filtered"), padding: 40 }, duration: 250 });
});
$("png-btn").addEventListener("click", () => {
  if (!cy) return;
  const a = document.createElement("a");
  a.href = cy.png({ full: true, scale: 2, bg: "#0f1420" });
  a.download = "lineage.png";
  a.click();
});

// e) Onglets du panneau
document.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => showTab(t.dataset.tab)));
document.querySelector(".panel").addEventListener("click", onPanelClick);

// f) Formulaires de saisie
af.form.addEventListener("submit", saveAsset);
af.reset.addEventListener("click", resetAssetForm);
[af.sys, af.schema, af.objet, af.col].forEach((i) => i.addEventListener("input", updateIdPreview));
// Nature et type restent cohérents : un traitement est de type « Traitement ».
af.nature.addEventListener("change", () => {
  if (af.nature.value === "traitement") af.type.value = "Traitement";
  else if (af.type.value === "Traitement") af.type.value = "Colonne";
});
af.type.addEventListener("change", () => {
  af.nature.value = af.type.value === "Traitement" ? "traitement" : "donnee";
});
rf.form.addEventListener("submit", saveRelation);
rf.reset.addEventListener("click", resetRelForm);
histFilter.addEventListener("input", renderHistory);
critFilterBtn.addEventListener("click", () => {
  if (levelSelect.value === "macro") {
    levelSelect.value = "micro";
    groupCheck.disabled = false;
    renderGraph();
  }
  filterSelect.value = "critiques";
  applyFilter(true);
});
resetBtn.addEventListener("click", () => {
  if (!can("remove")) return;
  if (!confirm("Vider toute la base (assets, relations, historique) ? Cette action est définitive.")) return;
  model = emptyModel();
  saveModel();
  selection = null;
  renderGraph();
  renderPanels();
  toast("Base vidée.");
});

/* ------------------------------------------------------------------
   Démarrage : on recharge la dernière base sauvegardée dans le navigateur.
------------------------------------------------------------------ */
loadPrefs();
const saved = loadSavedModel();
if (saved) model = saved;
resetAssetForm();
applyRole(); // appelle aussi renderPanels()
renderGraph();
renderDatalists();
