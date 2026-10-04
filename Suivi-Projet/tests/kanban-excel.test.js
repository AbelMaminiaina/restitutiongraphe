// Tests de kanban-excel.js (import / export Excel et CSV), avec le lanceur de tests intégré à Node.
//
// Lancer (depuis le dossier Suivi-Projet, Node 18 ou plus récent, rien à installer) :
//   node --test
//
// Chaque test(...) vérifie un comportement ; assert.equal / assert.deepEqual échouent
// (et affichent la différence) si la valeur obtenue n'est pas celle attendue.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const X = require("../kanban-excel.js");

const fixture = name => fs.readFileSync(path.join(__dirname, "fixtures", name));
// Buffer Node -> ArrayBuffer « propre » (ce que fournit file.arrayBuffer() dans le navigateur)
const toArrayBuffer = buf => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);

// Fabrique d'identifiants prévisibles pour les tests
const counterId = () => { let n = 0; return () => "id" + (++n); };

// Garde seulement les champs « métier » d'une tâche (sans id ni date de création)
const fields = t => ({ project: t.project, title: t.title, description: t.description,
  priority: t.priority, label: t.label, due: t.due, column: t.column });

// Lit un fichier (.xlsx ou .csv) comme le fait le bouton « Importer Excel »
async function importer(buffer, defaultProject) {
  const rows = await X.readSpreadsheet(toArrayBuffer(buffer));
  const map = X.mapHeaders(rows[0]);
  return X.rowsToTasks(rows, map, defaultProject, counterId()).map(fields);
}

// Les 5 tâches du fichier modèle (voir outils/creer-modele-excel.js)
const MODELE = [
  { project: "Restitution graphe", title: "Index sur CHECKSUM(DTA_1..4)", description: "Accélérer LINE_VIS_GetNodesSuccessorsPredecessors",
    priority: "haute", label: "SQL", due: "2026-10-15", column: "done" },
  { project: "Restitution graphe", title: "LINE_VIS_NodesList avec critère < 10 s", description: "Limiter aux 1000 premières lignes filtrées",
    priority: "haute", label: "SQL", due: "2026-10-20", column: "doing" },
  { project: "Restitution graphe", title: "Colonne txn_dta dans le graphe JS", description: "",
    priority: "moyenne", label: "front", due: "2026-10-31", column: "todo" },
  { project: "Restitution graphe", title: "Comparer BFS bi / Dijkstra / A*", description: "Refaire le benchmark avec des poids ≠ 1",
    priority: "basse", label: "C#", due: "", column: "backlog" },
  { project: "Suivi projet", title: "Importer le backlog Excel", description: "Remplir ce modèle puis cliquer sur « Importer Excel »",
    priority: "moyenne", label: "organisation", due: "2026-10-10", column: "todo" },
];

// ---------------------------------------------------------------------------
// Reconnaissance des colonnes et conversion des valeurs
// ---------------------------------------------------------------------------

test("normalize enlève accents, majuscules et ponctuation", () => {
  assert.equal(X.normalize("Date d'Échéance"), "datedecheance");
  assert.equal(X.normalize("  À faire! "), "afaire");
  assert.equal(X.normalize(null), "");
});

test("mapHeaders reconnaît les en-têtes de l'export", () => {
  assert.deepEqual(X.mapHeaders(X.EXPORT_HEADERS),
    { project: 0, title: 1, description: 2, priority: 3, label: 4, due: 5, column: 6 });
});

test("mapHeaders reconnaît des variantes, dans n'importe quel ordre", () => {
  assert.deepEqual(X.mapHeaders(["Title", "Status", "Due date", "Labels", "Notes"]),
    { title: 0, column: 1, due: 2, label: 3, description: 4 });
  // « Nom du projet » va dans project, pas dans title (qui accepte pourtant « nom »)
  assert.deepEqual(X.mapHeaders(["Nom du projet", "Nom"]), { project: 0, title: 1 });
  // Correspondance exacte prioritaire : « Date » seule n'écrase pas « Date limite »
  assert.equal(X.mapHeaders(["Date", "Date limite", "Tâche"]).due, 1);
});

test("mapHeaders sans colonne de titre : pas de champ title", () => {
  assert.equal("title" in X.mapHeaders(["Projet", "Statut"]), false);
});

test("toPriority", () => {
  for (const v of ["Haute", "HIGH", "urgent", "Critique", "P1", "1"]) assert.equal(X.toPriority(v), "haute", v);
  for (const v of ["Basse", "low", "Faible", "mineure", "3"]) assert.equal(X.toPriority(v), "basse", v);
  for (const v of ["Moyenne", "", "normale", "2", "10"]) assert.equal(X.toPriority(v), "moyenne", v);
});

test("toColumn", () => {
  for (const v of ["Terminé", "done", "Fait", "Clôturé", "Livré", "OK"]) assert.equal(X.toColumn(v), "done", v);
  for (const v of ["En cours", "In progress", "WIP"]) assert.equal(X.toColumn(v), "doing", v);
  for (const v of ["À faire", "To do", "todo", "Prêt"]) assert.equal(X.toColumn(v), "todo", v);
  for (const v of ["Backlog", "", "Nouveau", "okay"]) assert.equal(X.toColumn(v), "backlog", v);
});

test("toIsoDate : formats texte et numéros de série Excel", () => {
  assert.equal(X.toIsoDate("31/12/2026"), "2026-12-31");
  assert.equal(X.toIsoDate("5/1/26"), "2026-01-05");
  assert.equal(X.toIsoDate("05.01.2026"), "2026-01-05");
  assert.equal(X.toIsoDate("2026-1-5"), "2026-01-05");
  assert.equal(X.toIsoDate("2026-10-15T00:00:00"), "2026-10-15");
  assert.equal(X.toIsoDate("46022"), "2025-12-31");
  assert.equal(X.toIsoDate("46022.75"), "2025-12-31");   // date + heure
  assert.equal(X.toIsoDate(""), "");
  assert.equal(X.toIsoDate("bientôt"), "");
});

test("toExcelSerial est l'inverse de toIsoDate", () => {
  for (const iso of ["1950-06-15", "2000-02-29", "2025-12-31", "2026-10-04", "2099-01-01"]) {
    assert.equal(X.toIsoDate(String(X.toExcelSerial(iso))), iso, iso);
  }
  assert.equal(X.toExcelSerial("2025-12-31"), 46022);
});

test("rowsToTasks : lignes sans titre ignorées, projet par défaut, Backlog sans statut", () => {
  const rows = [["Tâche", "Priorité"], ["A", "haute"], ["", "basse"], ["  ", ""], ["B", ""]];
  const tasks = X.rowsToTasks(rows, X.mapHeaders(rows[0]), "Défaut", counterId());
  assert.deepEqual(tasks.map(fields), [
    { project: "Défaut", title: "A", description: "", priority: "haute", label: "", due: "", column: "backlog" },
    { project: "Défaut", title: "B", description: "", priority: "moyenne", label: "", due: "", column: "backlog" },
  ]);
  assert.deepEqual(tasks.map(t => t.id), ["id1", "id2"]);
});

test("rowsToTasks : la colonne Projet du fichier l'emporte sur le projet par défaut", () => {
  const rows = [["Projet", "Titre"], ["P1", "a"], ["", "b"]];
  const tasks = X.rowsToTasks(rows, X.mapHeaders(rows[0]), "Défaut", counterId());
  assert.deepEqual(tasks.map(t => t.project), ["P1", "Défaut"]);
});

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

test("parseCsv : point-virgule, guillemets, retours à la ligne, BOM, lignes vides", () => {
  const csv = '﻿Titre;Description\r\n"A;1";"ligne 1\r\nligne 2"\r\n\r\nB;"dit ""ok"""\r\n;\r\n';
  assert.deepEqual(X.parseCsv(csv), [["Titre", "Description"], ["A;1", "ligne 1\r\nligne 2"], ["B", 'dit "ok"']]);
});

test("parseCsv : virgule et tabulation détectées", () => {
  assert.deepEqual(X.parseCsv("a,b\n1,2"), [["a", "b"], ["1", "2"]]);
  assert.deepEqual(X.parseCsv("a\tb\n1\t2\n"), [["a", "b"], ["1", "2"]]);
});

test("decodeText : UTF-8, sinon Windows-1252 (ancien CSV Excel)", () => {
  assert.equal(X.decodeText(new TextEncoder().encode("Priorité")), "Priorité");
  // 0xE9 = « é » en Windows-1252, invalide en UTF-8.
  // (Pas de « € » ici : Node traite Windows-1252 comme Latin-1, contrairement aux navigateurs.)
  assert.equal(X.decodeText(Uint8Array.from([0x50, 0x72, 0x69, 0x6F, 0x72, 0x69, 0x74, 0xE9])), "Priorité");
});

test("import d'un CSV Windows-1252 avec point-virgule", async () => {
  const text = "Projet;Titre;Statut;Échéance\r\nP;Tâche é;En cours;15/10/2026\r\n";
  // encodage Windows-1252 « à la main » (les caractères utilisés ici ont le même code qu'en Latin-1)
  const bytes = Buffer.from(text, "latin1");
  assert.deepEqual(await importer(bytes), [
    { project: "P", title: "Tâche é", description: "", priority: "moyenne", label: "", due: "2026-10-15", column: "doing" },
  ]);
});

// ---------------------------------------------------------------------------
// ZIP et XML
// ---------------------------------------------------------------------------

test("crc32 : valeur de référence", () => {
  assert.equal(X.crc32(new TextEncoder().encode("123456789")), 0xCBF43926);
});

test("createZip puis readZip redonnent les mêmes fichiers", async () => {
  const zip = X.createZip([{ name: "a.txt", text: "bonjour" }, { name: "dossier/é.xml", text: "<x>€</x>" }]);
  const files = await X.readZip(zip.buffer);
  const dec = new TextDecoder();
  assert.deepEqual(Object.keys(files), ["a.txt", "dossier/é.xml"]);
  assert.equal(dec.decode(files["a.txt"]), "bonjour");
  assert.equal(dec.decode(files["dossier/é.xml"]), "<x>€</x>");
});

test("readZip refuse un fichier qui n'est pas un ZIP", async () => {
  await assert.rejects(X.readZip(new Uint8Array(100).buffer), /pas un fichier \.xlsx valide/);
});

test("columnLetter / columnIndex", () => {
  const cas = [[0, "A"], [25, "Z"], [26, "AA"], [27, "AB"], [701, "ZZ"], [702, "AAA"]];
  for (const [i, l] of cas) {
    assert.equal(X.columnLetter(i), l);
    assert.equal(X.columnIndex(l), i);
  }
});

test("escapeXml / unescapeXml", () => {
  const s = `<a href="x">Tom & Jerry's</a>`;
  assert.equal(X.unescapeXml(X.escapeXml(s)), s);
  assert.equal(X.escapeXml("a\u0001b"), "ab");                       // caractère de contrôle supprimé
  assert.equal(X.unescapeXml("a_x000D_b&#233;&#x20AC;"), "a\rbé€");
});

// ---------------------------------------------------------------------------
// Excel (.xlsx)
// ---------------------------------------------------------------------------

test("aller-retour : export .xlsx puis import redonne les mêmes tâches", async () => {
  const taches = [
    { project: "Projet & <test>", title: 'Titre "guillemets" é à ç € 🚀', description: "ligne 1\nligne 2\ttab",
      priority: "haute", label: "SQL", due: "2026-02-28", column: "doing" },
    { project: "", title: "Sans projet ni date", description: "", priority: "basse", label: "", due: "", column: "done" },
    { project: "P", title: "  espaces conservés à l'intérieur  ", description: "x", priority: "moyenne",
      label: "étiquette", due: "2030-12-31", column: "todo" },
    { project: "P", title: "Backlog", description: "", priority: "moyenne", label: "", due: "", column: "backlog" },
  ];
  const xlsx = X.writeXlsx(X.tasksToRows(taches));
  const relu = await importer(Buffer.from(xlsx));
  // L'import retire les espaces au début et à la fin des cellules
  const attendu = taches.map(t => Object.assign({}, t, { title: t.title.trim() }));
  assert.deepEqual(relu, attendu);
});

test("export .xlsx : en-têtes, vraie date (nombre) et cellule vide", async () => {
  const xlsx = X.writeXlsx(X.tasksToRows([{ title: "T", priority: "haute", due: "2025-12-31", column: "done" }]));
  const rows = await X.readXlsx(xlsx.buffer);
  assert.deepEqual(rows, [X.EXPORT_HEADERS, ["", "T", "", "Haute", "", "46022", "Terminé"]]);
});

test("export .xlsx d'une liste vide : seulement les en-têtes", async () => {
  const rows = await X.readXlsx(X.writeXlsx(X.tasksToRows([])).buffer);
  assert.deepEqual(rows, [X.EXPORT_HEADERS]);
});

test("le fichier modèle modele-backlog.xlsx est à jour et s'importe", async () => {
  const modele = fs.readFileSync(path.join(__dirname, "..", "modele-backlog.xlsx"));
  assert.deepEqual(await importer(modele), MODELE);
});

test("le modèle réenregistré par Microsoft Excel s'importe à l'identique", async () => {
  // Fichier écrit par Excel lui-même : textes partagés (sharedStrings.xml) et compression deflate
  assert.deepEqual(await importer(fixture("modele-reenregistre-par-excel.xlsx")), MODELE);
});

test("fichier écrit par openpyxl : autres en-têtes, dates, texte enrichi, 1re feuille seulement", async () => {
  // Voir tests/fixtures/creer-fixture-openpyxl.py
  assert.deepEqual(await importer(fixture("backlog-openpyxl.xlsx")), [
    { project: "Graphe", title: "Créer la table LINE_VIS_EDG", description: "ligne 1\nligne 2",
      priority: "haute", label: "", due: "2026-11-03", column: "doing" },
    { project: "Graphe", title: "Écrire les tests", description: 'avec "guillemets" & <chevrons>',
      priority: "basse", label: "", due: "2026-09-30", column: "done" },
    { project: "Kanban", title: "Texte enrichi", description: "",
      priority: "haute", label: "", due: "", column: "todo" },
  ]);
});

test("readSpreadsheet refuse l'ancien format .xls", async () => {
  const xls = Uint8Array.from([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
  await assert.rejects(X.readSpreadsheet(xls.buffer), /ancien format \.xls/);
});
