/* ==================================================================
   Génère les deux jeux de démonstration de l'application :

     exemple_parcours.xlsx  -> affiché en mode « parcours »
                               (tous les nœuds en jaune)
     exemple_adjacent.xlsx  -> affiché en mode « adjacent »
                               (nœuds données dta_* en jaune,
                                nœuds edg_* neutres en bleu)

   Le MODE est choisi par l'application d'après le SUFFIXE du nom du
   fichier (…_parcours.xlsx / …_adjacent.xlsx) : c'est pour ça que les
   noms se terminent ainsi.
   ------------------------------------------------------------------
   Lancer :  node generer-exemple.mjs

   Utilise la librairie déjà présente dans vendor/ (SheetJS) : aucune
   installation, aucun accès internet.

   Le script met aussi à jour AUTOMATIQUEMENT les tableaux
   EXEMPLE_PARCOURS_ROWS et EXEMPLE_ADJACENT_ROWS dans app.js (entre les
   repères « <exemples-debut> » et « <exemples-fin> ») : les boutons
   « Exemple parcours » / « Exemple adjacent » du site restent donc
   synchronisés avec les fichiers .xlsx, sans copier-coller.

   Fermez les fichiers .xlsx dans Excel avant de lancer le script
   (sinon erreur « fichier verrouillé »).
   ================================================================== */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const XLSX = require(join(HERE, "vendor", "xlsx.mini.min.js"));

/* ------------------------------------------------------------------
   1. Description des deux graphes de démonstration
   ------------------------------------------------------------------
   Chaque enregistrement = [ nœudDonnées, sens, nœudEdg, txn_dta ]
     sens "I" -> arête  données -> edg   (données prédécesseur de edg)
     sens "O" -> arête  edg -> données   (données successeur  de edg)
   txn_dta = la TRANSFORMATION appliquée sur l'arête (simple étiquette).
     renseignée -> arc en trait PLEIN dans l'application ;
     vide ("")  -> arc en POINTILLÉ.
------------------------------------------------------------------ */

// --- 1.a  Parcours : UNE LIGNE, du début à la fin --------------------
// Un parcours se lit d'un bout à l'autre, sans embranchement ni boucle :
//   DA -> EA -> DB -> EB -> DC -> EC -> DD -> ED -> DE -> EE -> DF
// Chaque nœud a au plus 1 prédécesseur et 1 successeur, donc le graphe
// s'affiche comme une ligne. Pour chaque traitement edg, on a 2 lignes :
//   sens "I" : la donnée qui ENTRE   (donnée -> edg)
//   sens "O" : la donnée qui SORT    (edg -> donnée)
// En mode parcours, TOUS ces nœuds seront jaunes.
const RECORDS_PARCOURS = [
  ["DA", "I", "EA", "filtre"],
  ["DB", "O", "EA", "agrégation"],
  ["DB", "I", "EB", ""],
  ["DC", "O", "EB", "jointure"],
  ["DC", "I", "EC", "tri"],
  ["DD", "O", "EC", ""],
  ["DD", "I", "ED", "calcul"],
  ["DE", "O", "ED", "normalisation"],
  ["DE", "I", "EE", ""],
  ["DF", "O", "EE", "déduplication"],
];

// --- 1.b  Adjacent : les nœuds jaunes SE SUIVENT, les edg sont à côté ----
// Les nœuds du parcours DA..DF (jaunes en mode adjacent) se suivent
// DIRECTEMENT, arc après arc, sans traitement entre eux :
//   DA -> DB -> DC -> DD -> DE -> DF
// Astuce : pour relier deux données directement, la donnée de départ est
// écrite dans les colonnes edg_1..edg_4 (ex. ligne [DB, "O", DA] = arc
// DA -> DB). Un nœud présent à la fois en dta_* et en edg_* est jaune en
// mode adjacent (il fait partie des nœuds source).
// Les traitements adjacents EA..EF sont de vrais nœuds edg (neutres =>
// BLEUS) : chacun est branché sur UNE donnée du parcours.
const RECORDS_ADJACENT = [
  // la ligne des nœuds jaunes : DA -> DB -> DC -> DD -> DE -> DF
  ["DB", "O", "DA", "filtre"],
  ["DC", "O", "DB", ""],
  ["DD", "O", "DC", "jointure"],
  ["DE", "O", "DD", "calcul"],
  ["DF", "O", "DE", ""],
  // les traitements adjacents (bleus), un par donnée du parcours
  ["DA", "O", "EA", "chargement"], // EA produit DA      (en amont du début)
  ["DB", "I", "EB", ""],           // DB part aussi vers EB
  ["DC", "I", "EC", "copie"],      // DC part aussi vers EC
  ["DD", "O", "ED", ""],           // ED produit aussi DD
  ["DE", "I", "EE", "tri"],        // DE part aussi vers EE
  ["DF", "I", "EF", "export"],     // DF part vers EF     (en aval de la fin)
];

/* ------------------------------------------------------------------
   2. Transforme chaque enregistrement en une ligne de 10 colonnes
   ------------------------------------------------------------------
   Un nœud logique « DA » est décrit par ses 4 morceaux DA1..DA4.
   Comme l'application concatène dans l'ordre 4->1, l'étiquette
   affichée sera « DA4.DA3.DA2.DA1 ».
------------------------------------------------------------------ */
const HEADER = ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta"];

const parts = (nom) => [1, 2, 3, 4].map((i) => `${nom}${i}`); // "DA" -> ["DA1","DA2","DA3","DA4"]

// toRows : enregistrements -> tableau complet (en-tête + lignes)
const toRows = (records) => [
  HEADER,
  ...records.map(([dta, dir, edg, txn]) => [...parts(dta), dir, ...parts(edg), txn]),
];

/* ------------------------------------------------------------------
   3. Écrit un fichier .xlsx et le relit pour contrôle
------------------------------------------------------------------ */
function writeXlsx(fileName, rows) {
  const outPath = join(HERE, fileName);
  const ws = XLSX.utils.aoa_to_sheet(rows);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "Feuil1");
  writeFileSync(outPath, XLSX.write(wb, { type: "buffer", bookType: "xlsx" }));

  // Petit contrôle : relit le fichier et compte les lignes.
  const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
  const readRows = XLSX.utils.sheet_to_json(back.Sheets[back.SheetNames[0]], { header: 1 });
  console.log(`${fileName} écrit : ${readRows.length - 1} lignes de données (relecture OK).`);
}

const rowsParcours = toRows(RECORDS_PARCOURS);
const rowsAdjacent = toRows(RECORDS_ADJACENT);
writeXlsx("exemple_parcours.xlsx", rowsParcours);
writeXlsx("exemple_adjacent.xlsx", rowsAdjacent);

/* ------------------------------------------------------------------
   4. Met à jour les exemples intégrés dans app.js
   ------------------------------------------------------------------
   On remplace tout ce qui se trouve entre les deux lignes repères
   « // <exemples-debut> » et « // <exemples-fin> ».
------------------------------------------------------------------ */
const jsArray = (name, rows) =>
  `const ${name} = [\n` +
  rows.map((r) => "  [" + r.map((c) => JSON.stringify(c)).join(", ") + "],").join("\n") +
  "\n];";

const appPath = join(HERE, "app.js");
const app = readFileSync(appPath, "utf8");
// [\s\S]*? = « n'importe quoi, même rien, même sur plusieurs lignes ».
const repere = /(\/\/ <exemples-debut>)[\s\S]*?(\/\/ <exemples-fin>)/;
if (!repere.test(app)) {
  throw new Error("Repères <exemples-debut> / <exemples-fin> introuvables dans app.js");
}
const bloc =
  jsArray("EXEMPLE_PARCOURS_ROWS", rowsParcours) + "\n\n" + jsArray("EXEMPLE_ADJACENT_ROWS", rowsAdjacent);
// Fonction de remplacement (et non chaîne) : évite que des "$" éventuels
// dans les données soient interprétés par replace().
writeFileSync(appPath, app.replace(repere, (_, debut, fin) => debut + "\n" + bloc + "\n" + fin));
console.log("app.js mis à jour : EXEMPLE_PARCOURS_ROWS et EXEMPLE_ADJACENT_ROWS.");
