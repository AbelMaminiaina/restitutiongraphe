/* ==================================================================
   Génère javascript/exemple.xlsx — un jeu de démonstration d'une
   vingtaine de lignes au format attendu par l'application.
   ------------------------------------------------------------------
   Lancer :  node generer-exemple.mjs

   Utilise la librairie déjà présente dans vendor/ (SheetJS) : aucune
   installation, aucun accès internet.

   Le script affiche aussi le tableau `EXEMPLE_ROWS` à recopier dans
   app.js (le bouton « Charger l'exemple » doit rester synchronisé).
   ================================================================== */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const XLSX = require(join(HERE, "vendor", "xlsx.mini.min.js"));

/* ------------------------------------------------------------------
   1. Description du graphe de démonstration
   ------------------------------------------------------------------
   - nœuds « données »  : DA .. DM   (13)
   - nœuds « edg »       : EA .. EF   (6)
   - chaque enregistrement ci-dessous = [ nœudDonnées, sens, nœudEdg, txn_dta, Typos ]
       sens "I" -> arête  données -> edg   (données prédécesseur de edg)
       sens "O" -> arête  edg -> données   (données successeur  de edg)
   Le jeu contient un cycle (entièrement « Parcours ») :
     DC -> EA -> DA -> EB -> DE -> ED -> DG -> EF -> DC

   txn_dta = la TRANSFORMATION appliquée sur l'arête (simple étiquette).
   Vide ("") -> l'arc est dessiné en POINTILLÉ dans l'application.

   Typos = "Parcours" ou "Complete", appliqué aux DEUX nœuds de la ligne
   (« Parcours » l'emporte si un nœud apparaît sur plusieurs lignes) :
     - Parcours : nœud intermédiaire du parcours (couleur orange) ;
     - Complete : nœud FEUILLE, c'est-à-dire SANS SUCCESSEUR.
   RÈGLE respectée ici : un nœud qui reste « Complete » n'a aucune arête
   sortante. D'où la forme des lignes Complete : toujours sens "O"
   (edg -> données), le nœud données (DI..DM) n'apparaissant QUE dans des
   lignes Complete, et le nœud edg étant déjà « Parcours » par une autre
   ligne. L'application signale toute violation (stat « Complete non
   feuilles »).
------------------------------------------------------------------ */
const RECORDS = [
  // --- Parcours : nœuds intermédiaires (dont le cycle) ---
  ["DA", "O", "EA", "agrégation", "Parcours"],
  ["DB", "I", "EA", "filtre", "Parcours"],
  ["DC", "I", "EA", "jointure", "Parcours"],
  ["DA", "I", "EB", "tri", "Parcours"],
  ["DD", "O", "EB", "calcul", "Parcours"],
  ["DE", "O", "EB", "arrondi", "Parcours"],
  ["DD", "I", "EC", "normalisation", "Parcours"],
  ["DE", "I", "ED", "déduplication", "Parcours"],
  ["DG", "O", "ED", "conversion", "Parcours"],
  ["DG", "I", "EF", "jointure", "Parcours"],
  ["DC", "O", "EF", "calcul", "Parcours"],
  ["DF", "I", "EE", "filtre", "Parcours"],
  ["DH", "O", "EE", "agrégation", "Parcours"],
  ["DH", "I", "EF", "tri", "Parcours"],
  // --- Complete : feuilles DI..DM (aucun successeur) ---
  ["DI", "O", "EC", "concaténation", "Complete"],
  ["DJ", "O", "EE", "", "Complete"],
  ["DK", "O", "EF", "", "Complete"],
  ["DL", "O", "EA", "normalisation", "Complete"],
  ["DM", "O", "ED", "", "Complete"],
  ["DI", "O", "EB", "déduplication", "Complete"],
];

/* ------------------------------------------------------------------
   2. Transforme chaque enregistrement en une ligne de 9 colonnes
   ------------------------------------------------------------------
   Un nœud logique « DA » est décrit par ses 4 morceaux DA1..DA4.
   Comme l'application concatène dans l'ordre 4->1, l'étiquette
   affichée sera « DA4.DA3.DA2.DA1 » (même logique que E11..E14 dans
   l'exemple d'origine).
------------------------------------------------------------------ */
const HEADER = ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta", "Typos"];

const parts = (nom) => [1, 2, 3, 4].map((i) => `${nom}${i}`); // "DA" -> ["DA1","DA2","DA3","DA4"]

const dataRows = RECORDS.map(([dta, dir, edg, txn, typos]) => [...parts(dta), dir, ...parts(edg), txn, typos]);
const rows = [HEADER, ...dataRows];

/* ------------------------------------------------------------------
   3. Écrit le fichier .xlsx
------------------------------------------------------------------ */
const ws = XLSX.utils.aoa_to_sheet(rows);
const wb = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(wb, ws, "Feuil1");
const buf = XLSX.write(wb, { type: "buffer", bookType: "xlsx" });

// Chemin de sortie : argument optionnel, sinon ./exemple.xlsx
const outPath = process.argv[2] ? process.argv[2] : join(HERE, "exemple.xlsx");
writeFileSync(outPath, buf);

console.log(`${outPath} écrit : ${dataRows.length} lignes de données.`);

/* ------------------------------------------------------------------
   4. Affiche le tableau à recopier dans app.js (const EXEMPLE_ROWS)
------------------------------------------------------------------ */
const jsArray =
  "const EXEMPLE_ROWS = [\n" +
  rows.map((r) => "  [" + r.map((c) => JSON.stringify(c)).join(", ") + "],").join("\n") +
  "\n];";
console.log("\n--- à recopier dans app.js ---\n" + jsArray);

/* Petit contrôle : relit le fichier et compte les lignes. */
const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
const readRows = XLSX.utils.sheet_to_json(back.Sheets[back.SheetNames[0]], { header: 1 });
console.log(`\nRelecture OK : ${readRows.length - 1} lignes de données.`);
