/* ==================================================================
   Génère exemple_vert_adjacent.xlsx : un exemple où TOUS les nœuds ont
   le caractère V (vert).
   ------------------------------------------------------------------
   Lancer :  node generer-exemple-vert.mjs

   Même graphe que exemple_adjacent.xlsx (onglet « Arc » identique),
   mais dans l'onglet « Noeud » chaque nœud a Cara_vis = "V".
   Dans l'application :
     - tous les nœuds sont verts, la légende ne montre que V ;
     - la liste « Caractère » propose seulement Tous / V ;
     - filtre V : tous les nœuds restent, chaque arc devient un arc
       sans flèche (deux nœuds V voisins sont reliés directement).

   Ce script n'écrit QUE ce fichier : il ne touche ni aux autres
   exemples, ni à app.js. Fermez le fichier dans Excel avant de lancer.
   ================================================================== */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const XLSX = require(join(HERE, "vendor", "xlsx.mini.min.js"));

// Les arcs : [ nœudDonnées, sens, nœudEdg, txn_dta ] (comme generer-exemple.mjs)
//   sens "I" -> arc données -> edg ; sens "O" -> arc edg -> données
const RECORDS = [
  ["DB", "O", "DA", "filtre"],
  ["DC", "O", "DB", ""],
  ["DD", "O", "DC", "jointure"],
  ["DE", "O", "DD", "calcul"],
  ["DF", "O", "DE", ""],
  ["DA", "O", "EA", "chargement"],
  ["DB", "I", "EB", ""],
  ["DC", "I", "EC", "copie"],
  ["DD", "O", "ED", ""],
  ["DE", "I", "EE", "tri"],
  ["DF", "I", "EF", "export"],
];

// Les nœuds de l'onglet « Noeud » : tous avec le caractère V.
const NOEUDS = ["DA", "DB", "DC", "DD", "DE", "DF", "EA", "EB", "EC", "ED", "EE", "EF"];

const parts = (nom) => [1, 2, 3, 4].map((i) => `${nom}${i}`); // "DA" -> ["DA1","DA2","DA3","DA4"]

const arcs = [
  ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta"],
  ...RECORDS.map(([dta, dir, edg, txn]) => [...parts(dta), dir, ...parts(edg), txn]),
];
const noeuds = [
  ["Nœud_1", "Nœud_2", "Nœud_3", "Nœud_4", "Cara_vis"],
  ...NOEUDS.map((nom) => [...parts(nom), "V"]),
];

// Écriture : « Arc » en 1er onglet, « Noeud » en 2e.
const fileName = "exemple_vert_adjacent.xlsx";
const outPath = join(HERE, fileName);
const wb = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(arcs), "Arc");
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(noeuds), "Noeud");
writeFileSync(outPath, XLSX.write(wb, { type: "buffer", bookType: "xlsx" }));

// Petit contrôle : relecture.
const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
const nb = (nom) => XLSX.utils.sheet_to_json(back.Sheets[nom], { header: 1 }).length - 1;
console.log(`${fileName} écrit : ${nb("Arc")} arcs, ${nb("Noeud")} nœuds, tous V (relecture OK).`);
