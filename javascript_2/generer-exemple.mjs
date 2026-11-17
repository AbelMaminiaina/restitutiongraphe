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

   Chaque fichier a DEUX onglets :
     « Arc »   : dta_1..dta_4, edg_dir, edg_1..edg_4, txn_dta
     « Noeud » : Nœud_1..Nœud_4, Cara_vis  (le caractère de chaque nœud)

   Le script met aussi à jour AUTOMATIQUEMENT les objets
   EXEMPLE_PARCOURS et EXEMPLE_ADJACENT dans app.js (entre les
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

// --- 1.c  Caractère de chaque nœud logique (onglet « Noeud ») -------
// Un nœud a UN caractère, quel que soit le nombre de lignes de l'onglet
// « Arc » où il apparaît : d'où une table par nœud, écrite telle quelle
// dans l'onglet « Noeud » (une ligne par nœud, dans l'ordre de la table).
// Le caractère n'est pas limité à V/R/C/U : G, par exemple, est accepté.
const CARA_PARCOURS = {
  DA: "V", EA: "C", DB: "R", EB: "U", DC: "C", EC: "V",
  DD: "U", ED: "R", DE: "V", EE: "C", DF: "R",
};
// (= le contenu de l'onglet « Noeud » du fichier exemple_adjacent.xlsx fourni)
const CARA_ADJACENT = {
  DB: "V", DA: "U", DC: "R", DD: "V", DE: "G", DF: "V",
  EA: "U", EB: "U", EC: "V", ED: "V", EE: "G", EF: "V",
};

/* ------------------------------------------------------------------
   2. Transforme les données en lignes des deux onglets
   ------------------------------------------------------------------
   Un nœud logique « DA » est décrit par ses 4 morceaux DA1..DA4.
   Comme l'application concatène dans l'ordre 4->1, l'étiquette
   affichée sera « [V] DA4.DA3.DA2.DA1 » (V = son caractère).
------------------------------------------------------------------ */
const HEADER_ARC = [
  "dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta",
];
const HEADER_NOEUD = ["Nœud_1", "Nœud_2", "Nœud_3", "Nœud_4", "Cara_vis"];

const parts = (nom) => [1, 2, 3, 4].map((i) => `${nom}${i}`); // "DA" -> ["DA1","DA2","DA3","DA4"]

// arcRows : enregistrements -> onglet « Arc » (en-tête + une ligne par arc)
const arcRows = (records) => [
  HEADER_ARC,
  ...records.map(([dta, dir, edg, txn]) => [...parts(dta), dir, ...parts(edg), txn]),
];

// noeudRows : table des caractères -> onglet « Noeud » (en-tête + une ligne par nœud)
const noeudRows = (cara) => [
  HEADER_NOEUD,
  ...Object.entries(cara).map(([nom, c]) => [...parts(nom), c]),
];

/* ------------------------------------------------------------------
   3. Écrit un fichier .xlsx (2 onglets) et le relit pour contrôle
------------------------------------------------------------------ */
function writeXlsx(fileName, exemple) {
  const outPath = join(HERE, fileName);
  const wb = XLSX.utils.book_new();
  // L'ordre compte : « Arc » en 1er onglet, « Noeud » en 2e.
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(exemple.arcs), "Arc");
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(exemple.noeuds), "Noeud");
  writeFileSync(outPath, XLSX.write(wb, { type: "buffer", bookType: "xlsx" }));

  // Petit contrôle : relit le fichier et compte les lignes de chaque onglet.
  const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
  const nb = (nom) => XLSX.utils.sheet_to_json(back.Sheets[nom], { header: 1 }).length - 1;
  console.log(`${fileName} écrit : ${nb("Arc")} arcs, ${nb("Noeud")} nœuds (relecture OK).`);
}

const exempleParcours = { arcs: arcRows(RECORDS_PARCOURS), noeuds: noeudRows(CARA_PARCOURS) };
const exempleAdjacent = { arcs: arcRows(RECORDS_ADJACENT), noeuds: noeudRows(CARA_ADJACENT) };
writeXlsx("exemple_parcours.xlsx", exempleParcours);
writeXlsx("exemple_adjacent.xlsx", exempleAdjacent);

/* ------------------------------------------------------------------
   4. Met à jour les exemples intégrés dans app.js
   ------------------------------------------------------------------
   On remplace tout ce qui se trouve entre les deux lignes repères
   « // <exemples-debut> » et « // <exemples-fin> ».
------------------------------------------------------------------ */
// jsRows : un tableau de lignes écrit en JS, une sous-liste par ligne.
const jsRows = (rows) =>
  "[\n" + rows.map((r) => "    [" + r.map((c) => JSON.stringify(c)).join(", ") + "],").join("\n") + "\n  ]";
// jsExemple : « const NOM = { arcs: [...], noeuds: [...] }; »
const jsExemple = (name, ex) =>
  `const ${name} = {\n  arcs: ${jsRows(ex.arcs)},\n  noeuds: ${jsRows(ex.noeuds)},\n};`;

const appPath = join(HERE, "app.js");
const app = readFileSync(appPath, "utf8");
// [\s\S]*? = « n'importe quoi, même rien, même sur plusieurs lignes ».
const repere = /(\/\/ <exemples-debut>)[\s\S]*?(\/\/ <exemples-fin>)/;
if (!repere.test(app)) {
  throw new Error("Repères <exemples-debut> / <exemples-fin> introuvables dans app.js");
}
const bloc =
  jsExemple("EXEMPLE_PARCOURS", exempleParcours) + "\n\n" + jsExemple("EXEMPLE_ADJACENT", exempleAdjacent);
// Fonction de remplacement (et non chaîne) : évite que des "$" éventuels
// dans les données soient interprétés par replace().
writeFileSync(appPath, app.replace(repere, (_, debut, fin) => debut + "\n" + bloc + "\n" + fin));
console.log("app.js mis à jour : EXEMPLE_PARCOURS et EXEMPLE_ADJACENT.");
