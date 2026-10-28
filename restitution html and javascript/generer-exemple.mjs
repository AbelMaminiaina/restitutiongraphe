/* ==================================================================
   Génère exemple.xlsx à partir de exemple-data.js
   ------------------------------------------------------------------
   Lancer :  node generer-exemple.mjs  [chemin de sortie optionnel]

   Le classeur produit contient 3 feuilles :
     - lineage    : les relations (format dta_* / edg_dir / edg_* / txn_dta + statut)
     - assets     : la fiche descriptive de chaque asset (criticité, PII…)
     - historique : le journal des modifications

   Utilise la librairie déjà présente dans vendor/ (SheetJS) : aucune
   installation, aucun accès internet. Fermez exemple.xlsx dans Excel
   avant de lancer le script (sinon « fichier verrouillé »).
   ================================================================== */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const XLSX = require(join(HERE, "vendor", "xlsx.mini.min.js"));
// Les données de démonstration : le même fichier que celui chargé par la page.
const EXEMPLE = require(join(HERE, "exemple-data.js"));

const wb = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(EXEMPLE.lineage), "lineage");
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(EXEMPLE.assets), "assets");
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(EXEMPLE.historique), "historique");
const buf = XLSX.write(wb, { type: "buffer", bookType: "xlsx" });

const outPath = process.argv[2] ? process.argv[2] : join(HERE, "exemple.xlsx");
writeFileSync(outPath, buf);

// Petit contrôle : on relit le fichier et on compte les lignes de chaque feuille.
const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
for (const name of back.SheetNames) {
  const rows = XLSX.utils.sheet_to_json(back.Sheets[name], { header: 1 });
  console.log(`${name} : ${rows.length - 1} lignes`);
}
console.log(`${outPath} écrit.`);
