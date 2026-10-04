// ===========================================================================
// kanban-excel.js — Lecture / écriture des fichiers Excel (.xlsx) et CSV
//
// Ce fichier ne touche pas à la page (aucun document.getElementById) : il ne contient
// que des fonctions « pures » (on leur donne des données, elles en renvoient d'autres).
// C'est ce qui permet de le tester avec Node, sans navigateur (voir tests/).
//
// Dans le navigateur, il est chargé AVANT kanban.js, qui utilise ses fonctions.
// Aucune bibliothèque externe : un .xlsx n'est qu'une archive ZIP contenant des fichiers XML,
// on fabrique et on lit cette archive nous-mêmes.
// ===========================================================================

// ---------------------------------------------------------------------------
// 1. Colonnes du fichier Excel <-> champs d'une tâche
// ---------------------------------------------------------------------------

// Les 4 colonnes du tableau (identifiant interne + nom affiché)
const COLUMNS = [
  { id: "backlog", name: "Backlog" },
  { id: "todo",    name: "À faire" },
  { id: "doing",   name: "En cours" },
  { id: "done",    name: "Terminé" },
];
const PRIORITY_LABEL = { basse: "Basse", moyenne: "Moyenne", haute: "Haute" };

// En-têtes écrits par l'export (et dans le fichier modèle). L'import les reconnaît forcément.
const EXPORT_HEADERS = ["Projet", "Titre", "Description", "Priorité", "Étiquette", "Échéance", "Statut"];

// Met un texte en minuscules, sans accents ni espaces/ponctuation : « Date d'échéance » -> « datedecheance »
function normalize(text) {
  return String(text || "").toLowerCase().normalize("NFD")
    .replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]/g, "");
}

// Noms de colonnes acceptés pour chaque champ (déjà normalisés).
// L'ordre compte : « Nom du projet » doit être pris par « project » avant « title » (qui accepte « nom »).
const CSV_FIELDS = [
  ["project",     ["projet", "project", "application", "appli"]],
  ["due",         ["echeance", "datelimite", "deadline", "duedate", "due", "datefin", "date"]],
  ["priority",    ["priorite", "priority", "prio", "urgence"]],
  ["column",      ["statut", "status", "etat", "colonne", "avancement"]],
  ["label",       ["etiquette", "label", "tag", "categorie", "type", "theme"]],
  ["description", ["description", "desc", "detail", "details", "commentaire", "commentaires", "notes"]],
  ["title",       ["titre", "title", "tache", "intitule", "libelle", "sujet", "resume", "summary", "userstory", "nom"]],
];

// Associe chaque champ à l'index de sa colonne : d'abord les titres identiques,
// puis les titres qui contiennent le mot (ex. « Date d'échéance » contient « echeance »).
// Les mots sont essayés dans l'ordre de CSV_FIELDS, du plus précis au plus vague :
// avec « Date » et « Date limite », c'est « Date limite » qui est choisie.
// Renvoie par ex. { title: 1, project: 0, due: 5 }.
function mapHeaders(headers) {
  const norm = headers.map(normalize);
  const used = new Set(), map = {};
  for (const pass of ["exact", "contains"]) {
    for (const [field, words] of CSV_FIELDS) {
      if (field in map) continue;
      for (const w of words) {
        const idx = norm.findIndex((h, i) => !used.has(i) && h && (pass === "exact" ? h === w : h.includes(w)));
        if (idx >= 0) { map[field] = idx; used.add(idx); break; }
      }
    }
  }
  return map;
}

function toPriority(value) {
  const v = normalize(value);
  if (/^(haute|high|urgent|critique|critical|bloquant|elevee|p1$|1$)/.test(v)) return "haute";
  if (/^(basse|low|faible|mineure|p3$|p4$|3$|4$)/.test(v)) return "basse";
  return "moyenne";
}

function toColumn(value) {
  const v = normalize(value);
  if (/^(termine|done|fait|fini|clos|cloture|ferme|livre|resolu|ok$)/.test(v)) return "done";
  if (/^(encours|doing|inprogress|wip|demarre|commence)/.test(v)) return "doing";
  if (/^(afaire|todo|pret|ready|planifie|prochain)/.test(v)) return "todo";
  return "backlog";
}

// Excel compte les dates en jours depuis le 30/12/1899 (« nombre de série » : 46022 = 31/12/2025)
const EXCEL_EPOCH = Date.UTC(1899, 11, 30);
const DAY_MS = 86400000;

// Convertit une date lue dans Excel/CSV en AAAA-MM-JJ. Formats acceptés :
// 31/12/2026, 31-12-26, 2026-12-31, ou un nombre de série Excel (46022, 46022.5 avec une heure).
function toIsoDate(value) {
  const v = String(value || "").trim();
  let m;
  if ((m = v.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/))) return isoDate(m[1], m[2], m[3]);
  if ((m = v.match(/^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})/))) {
    const year = m[3].length === 2 ? "20" + m[3] : m[3];
    return isoDate(year, m[2], m[1]);
  }
  if (/^\d{5}(\.\d+)?$/.test(v)) {
    return new Date(EXCEL_EPOCH + Math.floor(Number(v)) * DAY_MS).toISOString().slice(0, 10);
  }
  return "";
}
function isoDate(y, m, d) {
  return y + "-" + String(m).padStart(2, "0") + "-" + String(d).padStart(2, "0");
}

// AAAA-MM-JJ -> nombre de série Excel (inverse de la conversion ci-dessus)
function toExcelSerial(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  return (Date.UTC(y, m - 1, d) - EXCEL_EPOCH) / DAY_MS;
}

// Transforme les lignes lues (1re ligne = titres) en tâches.
// - map : résultat de mapHeaders(rows[0])
// - defaultProject : projet donné aux lignes qui n'en ont pas
// - makeId : fonction qui fabrique un identifiant unique
// Les lignes sans titre sont ignorées.
function rowsToTasks(rows, map, defaultProject, makeId) {
  const cell = (row, field) => field in map ? String(row[map[field]] || "").trim() : "";
  return rows.slice(1)
    .filter(r => cell(r, "title"))
    .map(r => ({
      id: makeId(),
      title: cell(r, "title"),
      description: cell(r, "description"),
      project: cell(r, "project") || defaultProject || "",
      priority: toPriority(cell(r, "priority")),
      label: cell(r, "label"),
      due: toIsoDate(cell(r, "due")),
      column: "column" in map ? toColumn(cell(r, "column")) : "backlog",
      createdAt: new Date().toISOString(),
    }));
}

// Inverse : tâches -> lignes pour l'export (1re ligne = EXPORT_HEADERS).
// Les échéances deviennent des nombres de série, pour qu'Excel les traite comme de vraies dates.
function tasksToRows(tasks) {
  const columnName = id => (COLUMNS.find(c => c.id === id) || COLUMNS[0]).name;
  return [EXPORT_HEADERS].concat(tasks.map(t => [
    t.project || "",
    t.title,
    t.description || "",
    PRIORITY_LABEL[t.priority] || "Moyenne",
    t.label || "",
    t.due ? { date: toExcelSerial(t.due) } : "",
    columnName(t.column),
  ]));
}

// ---------------------------------------------------------------------------
// 2. CSV
// ---------------------------------------------------------------------------

// Excel « CSV UTF-8 » est en UTF-8 ; l'ancien format « CSV (séparateur : point-virgule) » est en
// Windows-1252. On essaie UTF-8 en mode strict, et en cas d'erreur on décode en Windows-1252.
function decodeText(buffer) {
  try { return new TextDecoder("utf-8", { fatal: true }).decode(buffer); }
  catch (e) { return new TextDecoder("windows-1252").decode(buffer); }
}

// Lit un texte CSV et renvoie un tableau de lignes (chaque ligne = tableau de cellules).
// Gère les guillemets (cellules contenant ; , ou retours à la ligne) et devine le séparateur :
// Excel en français utilise « ; », en anglais « , ».
function parseCsv(text) {
  text = text.replace(/^﻿/, "");               // retire le BOM UTF-8 éventuel
  const firstLine = text.split(/\r?\n/, 1)[0];
  const sep = [";", ",", "\t"].reduce((best, c) =>
    firstLine.split(c).length > firstLine.split(best).length ? c : best, ";");

  const rows = [];
  let row = [], cell = "", inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }   // "" = guillemet échappé
      else if (ch === '"') inQuotes = false;
      else cell += ch;
    } else if (ch === '"') inQuotes = true;
    else if (ch === sep) { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(cell); rows.push(row); row = []; cell = "";
    } else cell += ch;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows.filter(r => r.some(c => c.trim()));   // ignore les lignes vides
}

// ---------------------------------------------------------------------------
// 3. Archive ZIP (un .xlsx est un ZIP)
// ---------------------------------------------------------------------------

// Table pour le calcul du CRC-32 (somme de contrôle exigée par le format ZIP)
const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) crc = CRC_TABLE[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

// Crée un ZIP « stocké » (sans compression : plus simple, et Excel l'accepte très bien).
// files : [{ name: "xl/workbook.xml", text: "<?xml…" }, …]  ->  Uint8Array
function createZip(files) {
  const enc = new TextEncoder();
  const parts = [], central = [];
  let offset = 0;

  for (const f of files) {
    const name = enc.encode(f.name);
    const data = enc.encode(f.text);
    const crc = crc32(data);

    // En-tête local (30 octets + nom) suivi des données
    const local = new DataView(new ArrayBuffer(30));
    local.setUint32(0, 0x04034b50, true);   // signature
    local.setUint16(4, 20, true);           // version nécessaire (2.0)
    local.setUint16(6, 0x0800, true);       // noms en UTF-8
    local.setUint16(8, 0, true);            // méthode 0 = stocké
    local.setUint16(10, 0, true);           // heure
    local.setUint16(12, 0x21, true);        // date (01/01/1980)
    local.setUint32(14, crc, true);
    local.setUint32(18, data.length, true); // taille compressée
    local.setUint32(22, data.length, true); // taille réelle
    local.setUint16(26, name.length, true);
    local.setUint16(28, 0, true);           // pas de champ « extra »
    parts.push(new Uint8Array(local.buffer), name, data);

    // Entrée du répertoire central (46 octets + nom), à la fin du fichier
    const dir = new DataView(new ArrayBuffer(46));
    dir.setUint32(0, 0x02014b50, true);
    dir.setUint16(4, 20, true);             // créé par (2.0)
    dir.setUint16(6, 20, true);
    dir.setUint16(8, 0x0800, true);
    dir.setUint16(10, 0, true);
    dir.setUint16(12, 0, true);
    dir.setUint16(14, 0x21, true);
    dir.setUint32(16, crc, true);
    dir.setUint32(20, data.length, true);
    dir.setUint32(24, data.length, true);
    dir.setUint16(28, name.length, true);
    dir.setUint32(42, offset, true);        // position de l'en-tête local
    central.push(new Uint8Array(dir.buffer), name);

    offset += 30 + name.length + data.length;
  }

  const centralSize = central.reduce((s, p) => s + p.length, 0);
  const end = new DataView(new ArrayBuffer(22));   // « fin du répertoire central »
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(8, files.length, true);
  end.setUint16(10, files.length, true);
  end.setUint32(12, centralSize, true);
  end.setUint32(16, offset, true);

  const all = parts.concat(central, [new Uint8Array(end.buffer)]);
  const out = new Uint8Array(all.reduce((s, p) => s + p.length, 0));
  let pos = 0;
  for (const p of all) { out.set(p, pos); pos += p.length; }
  return out;
}

// Lit un ZIP et renvoie { "xl/workbook.xml": Uint8Array, … }.
// Excel compresse ses fichiers (méthode « deflate ») : on les décompresse avec
// DecompressionStream, intégré aux navigateurs récents et à Node 18+. D'où le « async ».
async function readZip(buffer) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

  // On cherche la « fin du répertoire central » en partant de la fin du fichier
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("ce n'est pas un fichier .xlsx valide (archive ZIP introuvable)");

  const count = view.getUint16(eocd + 10, true);
  let p = view.getUint32(eocd + 16, true);          // début du répertoire central
  const files = {};
  const dec = new TextDecoder();

  for (let n = 0; n < count; n++) {
    if (view.getUint32(p, true) !== 0x02014b50) throw new Error("archive ZIP abîmée");
    const method = view.getUint16(p + 10, true);
    const compSize = view.getUint32(p + 20, true);
    const nameLen = view.getUint16(p + 28, true);
    const extraLen = view.getUint16(p + 30, true);
    const commentLen = view.getUint16(p + 32, true);
    const localOffset = view.getUint32(p + 42, true);
    const name = dec.decode(bytes.subarray(p + 46, p + 46 + nameLen));

    // Les données commencent après l'en-tête local, dont le nom/extra peuvent différer du central
    const start = localOffset + 30 + view.getUint16(localOffset + 26, true) + view.getUint16(localOffset + 28, true);
    const raw = bytes.subarray(start, start + compSize);
    if (method === 0) files[name] = raw;
    else if (method === 8) files[name] = await inflate(raw);
    else throw new Error("méthode de compression ZIP non gérée : " + method);

    p += 46 + nameLen + extraLen + commentLen;
  }
  return files;
}

async function inflate(raw) {
  const stream = new Blob([raw]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

// ---------------------------------------------------------------------------
// 4. Excel (.xlsx)
// ---------------------------------------------------------------------------

function escapeXml(text) {
  return String(text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    // caractères de contrôle interdits en XML (sauf tabulation et retours à la ligne)
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");
}

function unescapeXml(text) {
  return text
    .replace(/_x([0-9A-Fa-f]{4})_/g, (_, h) => String.fromCharCode(parseInt(h, 16)))   // ex. _x000D_
    .replace(/&#x([0-9A-Fa-f]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

// Numéro de colonne (0, 1, … 26) -> lettres Excel (A, B, … AA)
function columnLetter(index) {
  let s = "";
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s;
  return s;
}

// Lettres Excel -> numéro de colonne (A -> 0)
function columnIndex(letters) {
  let n = 0;
  for (const ch of letters) n = n * 26 + ch.charCodeAt(0) - 64;
  return n - 1;
}

// Fabrique un fichier .xlsx à une feuille.
// rows : tableau de lignes ; une cellule est un texte, un nombre, ou { date: numéroDeSérie }.
// La 1re ligne est mise en gras, figée en haut, et reçoit un filtre automatique.
// options : { sheetName, widths: [largeur de chaque colonne] }  ->  Uint8Array
function writeXlsx(rows, options) {
  const opts = Object.assign({ sheetName: "Backlog", widths: [] }, options);
  const nbCols = Math.max(1, ...rows.map(r => r.length));
  const lastCell = columnLetter(nbCols - 1) + Math.max(1, rows.length);

  const sheetRows = rows.map((row, r) => {
    const cells = row.map((value, c) => {
      const ref = columnLetter(c) + (r + 1);
      const style = r === 0 ? ' s="1"' : "";           // style 1 = en-tête en gras
      if (value === "" || value === null || value === undefined) return "";
      if (typeof value === "object" && "date" in value) return `<c r="${ref}" s="2"><v>${value.date}</v></c>`;
      if (typeof value === "number") return `<c r="${ref}"${style}><v>${value}</v></c>`;
      return `<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${escapeXml(value)}</t></is></c>`;
    }).join("");
    return `<row r="${r + 1}">${cells}</row>`;
  }).join("");

  const cols = opts.widths.length
    ? "<cols>" + opts.widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("") + "</cols>"
    : "";

  const xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  const ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  const nsR = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
  const rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

  return createZip([
    { name: "[Content_Types].xml", text: xml +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
      "</Types>" },
    { name: "_rels/.rels", text: xml +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      `<Relationship Id="rId1" Type="${rel}/officeDocument" Target="xl/workbook.xml"/>` +
      "</Relationships>" },
    { name: "xl/workbook.xml", text: xml +
      `<workbook ${ns} ${nsR}><sheets><sheet name="${escapeXml(opts.sheetName)}" sheetId="1" r:id="rId1"/></sheets>` +
      // plage nommée utilisée par Excel pour le filtre automatique
      `<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'${escapeXml(opts.sheetName)}'!$A$1:$${lastCell.replace(/\d+/, "")}$${lastCell.replace(/\D+/, "")}</definedName></definedNames>` +
      "</workbook>" },
    { name: "xl/_rels/workbook.xml.rels", text: xml +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      `<Relationship Id="rId1" Type="${rel}/worksheet" Target="worksheets/sheet1.xml"/>` +
      `<Relationship Id="rId2" Type="${rel}/styles" Target="styles.xml"/>` +
      "</Relationships>" },
    { name: "xl/styles.xml", text: xml +
      `<styleSheet ${ns}>` +
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="3">' +
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +                         // 0 : normal
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +           // 1 : gras
      '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +  // 2 : date
      "</cellXfs>" +
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
      "</styleSheet>" },
    { name: "xl/worksheets/sheet1.xml", text: xml +
      `<worksheet ${ns} ${nsR}>` +
      `<dimension ref="A1:${lastCell}"/>` +
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
      cols +
      `<sheetData>${sheetRows}</sheetData>` +
      `<autoFilter ref="A1:${lastCell}"/>` +
      "</worksheet>" },
  ]);
}

// Lit la 1re feuille d'un fichier .xlsx et renvoie ses lignes (tableaux de textes).
// Les dates arrivent sous forme de nombre de série (« 46022 ») : toIsoDate sait les convertir.
async function readXlsx(buffer) {
  const files = await readZip(buffer);
  const dec = new TextDecoder();
  const text = name => files[name] ? dec.decode(files[name]) : "";

  // Textes partagés : Excel stocke chaque texte une seule fois dans sharedStrings.xml,
  // et les cellules y font référence par leur numéro.
  const shared = [];
  const sst = text("xl/sharedStrings.xml");
  for (const m of sst.matchAll(/<si>([\s\S]*?)<\/si>/g)) shared.push(joinTexts(m[1]));

  // Trouver le fichier de la 1re feuille : workbook.xml -> identifiant -> workbook.xml.rels -> chemin
  let sheetPath = "xl/worksheets/sheet1.xml";
  const firstSheet = text("xl/workbook.xml").match(/<sheet\b[^>]*\br:id="([^"]+)"/);
  if (firstSheet) {
    for (const rel of text("xl/_rels/workbook.xml.rels").matchAll(/<Relationship\b[^>]*>/g)) {
      const id = (rel[0].match(/\bId="([^"]+)"/) || [])[1];
      const target = (rel[0].match(/\bTarget="([^"]+)"/) || [])[1];
      if (id === firstSheet[1] && target) {
        sheetPath = target.startsWith("/") ? target.slice(1) : "xl/" + target;
      }
    }
  }
  const sheet = text(sheetPath);
  if (!sheet) throw new Error("feuille introuvable dans le fichier .xlsx");

  const rows = [];
  for (const rowMatch of sheet.matchAll(/<row\b[^>]*?(?:\/>|>([\s\S]*?)<\/row>)/g)) {
    const row = [];
    let next = 0;                                   // colonne suivante si la cellule n'a pas de « r »
    for (const c of (rowMatch[1] || "").matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = c[1], inner = c[2] || "";
      const ref = attrs.match(/\br="([A-Z]+)\d+"/);
      const col = ref ? columnIndex(ref[1]) : next;
      next = col + 1;
      const type = (attrs.match(/\bt="([^"]+)"/) || [])[1];
      const v = (inner.match(/<v>([\s\S]*?)<\/v>/) || [])[1];
      let value = "";
      if (type === "s") value = shared[Number(v)] || "";
      else if (type === "inlineStr") value = joinTexts(inner);
      else if (v !== undefined) value = unescapeXml(v);
      while (row.length < col) row.push("");
      row[col] = value;
    }
    rows.push(row);
  }
  return rows.filter(r => r.some(c => String(c).trim()));   // ignore les lignes vides
}

// Concatène les morceaux <t>…</t> d'un texte (un texte « riche » est découpé en plusieurs morceaux).
// Les <rPh> sont des indications de prononciation (japonais) : on les ignore.
function joinTexts(xml) {
  const clean = xml.replace(/<rPh\b[\s\S]*?<\/rPh>/g, "");
  let s = "";
  for (const m of clean.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)) s += unescapeXml(m[1]);
  return s;
}

// Le fichier est-il un ZIP (donc un .xlsx) ? Les ZIP commencent par « PK »
function isZip(buffer) {
  const b = new Uint8Array(buffer, 0, Math.min(2, buffer.byteLength));
  return b[0] === 0x50 && b[1] === 0x4B;
}

// Lit un fichier .xlsx ou .csv (contenu brut) et renvoie ses lignes
async function readSpreadsheet(buffer) {
  if (isZip(buffer)) return readXlsx(buffer);
  const b = new Uint8Array(buffer, 0, Math.min(8, buffer.byteLength));
  if (b[0] === 0xD0 && b[1] === 0xCF) {             // signature des anciens .xls (Excel 97-2003)
    throw new Error("ancien format .xls non géré : dans Excel, « Enregistrer sous » > Classeur Excel (.xlsx)");
  }
  return parseCsv(decodeText(buffer));
}

// Pour les tests sous Node : rend les fonctions disponibles via require().
// Dans le navigateur, « module » n'existe pas et les fonctions restent simplement globales.
if (typeof module !== "undefined") {
  module.exports = {
    COLUMNS, PRIORITY_LABEL, EXPORT_HEADERS, CSV_FIELDS,
    normalize, mapHeaders, toPriority, toColumn, toIsoDate, toExcelSerial, rowsToTasks, tasksToRows,
    decodeText, parseCsv, crc32, createZip, readZip, columnLetter, columnIndex,
    escapeXml, unescapeXml, writeXlsx, readXlsx, readSpreadsheet,
  };
}
