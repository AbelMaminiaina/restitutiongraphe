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
   - nœuds « données »  : DA .. DH   (8)
   - nœuds « edg »       : EA .. EF   (6)
   - chaque enregistrement ci-dessous = [ nœudDonnées, sens, nœudEdg ]
       sens "I" -> arête  données -> edg   (données prédécesseur de edg)
       sens "O" -> arête  edg -> données   (données successeur  de edg)
   Le jeu contient un cycle :
     DC -> EA -> DA -> EB -> DE -> ED -> DG -> EF -> DC
------------------------------------------------------------------ */
const RECORDS = [
  ["DA", "O", "EA"],
  ["DB", "I", "EA"],
  ["DC", "I", "EA"],
  ["DA", "I", "EB"],
  ["DD", "O", "EB"],
  ["DE", "O", "EB"],
  ["DD", "I", "EC"],
  ["DF", "O", "EC"],
  ["DE", "I", "ED"],
  ["DG", "O", "ED"],
  ["DF", "I", "EE"],
  ["DH", "O", "EE"],
  ["DG", "I", "EF"],
  ["DH", "I", "EF"],
  ["DC", "O", "EF"],
  ["DB", "O", "EC"],
  ["DA", "I", "EE"],
  ["DH", "O", "EA"],
  ["DF", "I", "EB"],
  ["DG", "I", "EA"],
];

/* ------------------------------------------------------------------
   2. Transforme chaque enregistrement en une ligne de 9 colonnes
   ------------------------------------------------------------------
   Un nœud logique « DA » est décrit par ses 4 morceaux DA1..DA4.
   Comme l'application concatène dans l'ordre 4->1, l'étiquette
   affichée sera « DA4.DA3.DA2.DA1 » (même logique que E11..E14 dans
   l'exemple d'origine).
------------------------------------------------------------------ */
const HEADER = ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4"];

const parts = (nom) => [1, 2, 3, 4].map((i) => `${nom}${i}`); // "DA" -> ["DA1","DA2","DA3","DA4"]

const dataRows = RECORDS.map(([dta, dir, edg]) => [...parts(dta), dir, ...parts(edg)]);
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
