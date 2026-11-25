/* ==================================================================
   Génère deux fichiers .xlsx de démonstration des CAS LIMITES gérés
   par l'application (nœuds isolés, colonne edg_dir optionnelle…).
   ------------------------------------------------------------------
   Lancer :  node generer-cas-limites.mjs

   Utilise la librairie déjà présente dans vendor/ (SheetJS) : aucune
   installation, aucun accès internet.

   Fichiers produits (dans le même dossier) :
     - exemple-cas-limites.xlsx   : la colonne edg_dir EXISTE mais est
                                    vide sur certaines lignes
     - exemple-sans-edg_dir.xlsx  : la colonne edg_dir est TOTALEMENT
                                    absente du fichier
   ================================================================== */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const XLSX = require(join(HERE, "vendor", "xlsx.mini.min.js"));

/* ------------------------------------------------------------------
   Petit utilitaire : transformer un nom court en ses 4 morceaux.
   ------------------------------------------------------------------
   L'application attend 4 colonnes (dta_1..dta_4 ou edg_1..edg_4) et
   recolle "morceau4.morceau3.morceau2.morceau1". Ici, pour garder des
   étiquettes lisibles, on met TOUT le nom dans le 1er morceau et on
   laisse les 3 autres vides -> l'étiquette affichée sera juste "SA".

     nom  "SA"  ->  ["SA", "", "", ""]     (affiché : "SA")
     ""   (vide) ->  ["", "", "", ""]      (nœud absent de cette ligne)
------------------------------------------------------------------ */
const parts = (nom) => [nom || "", "", "", ""];

/* ==================================================================
   FICHIER 1 : exemple-cas-limites.xlsx
   ------------------------------------------------------------------
   En-tête COMPLET (avec edg_dir). Chaque ligne = [ nœud dta, sens, nœud edg ].
   Un champ vide "" = ce côté est absent de la ligne.

   Les 6 cas illustrés :

   #1  arête normale, sens I   -> SA -> PA
   #2  arête normale, sens O   -> PA -> OA
       (PA a donc 1 prédécesseur et 1 successeur)

   #3  nœud « données » ISOLÉ  -> seule la colonne dta est remplie,
                                  ni edg ni sens          => ISOL_D isolé

   #4  nœud « edg » ISOLÉ      -> seule la colonne edg est remplie
                                                          => ISOL_E isolé

   #5  les DEUX nœuds remplis MAIS sens VIDE
       -> on garde NS_D et NS_E dans le graphe, SANS arête entre eux
       -> comme aucune autre ligne ne les relie, ils restent isolés

   #6  les DEUX nœuds remplis MAIS sens non reconnu ("X")
       -> même comportement que #5 (aucune arête, avertissement console)

   #7 + #8  un nœud qui SEMBLE isolé sur une ligne, mais qui est relié
            sur une autre ligne
       -> ligne #7 : LINKED_D seul (aurait l'air isolé)
       -> ligne #8 : LINKED_D -> LNK_E (sens I)
       -> BILAN : LINKED_D a un successeur, il n'est PAS compté isolé
------------------------------------------------------------------ */
const HEADER_COMPLET = ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4"];

// [ nom dta, sens, nom edg ]  ("" = côté absent)
const RECORDS_CAS_LIMITES = [
  ["SA", "I", "PA"], // #1  SA -> PA
  ["OA", "O", "PA"], // #2  PA -> OA
  ["ISOL_D", "", ""], // #3  nœud données isolé
  ["", "", "ISOL_E"], // #4  nœud edg isolé
  ["NS_D", "", "NS_E"], // #5  deux nœuds, sens vide -> pas d'arête
  ["BAD_D", "X", "BAD_E"], // #6  sens non reconnu -> pas d'arête
  ["LINKED_D", "", ""], // #7  a l'air isolé ici...
  ["LINKED_D", "I", "LNK_E"], // #8  ...mais relié ici -> pas isolé au final
];

/* ==================================================================
   FICHIER 2 : exemple-sans-edg_dir.xlsx
   ------------------------------------------------------------------
   En-tête SANS la colonne edg_dir. Le fichier doit quand même se
   charger (colonne devenue optionnelle).

   - Lignes avec les deux côtés remplis : AUCUNE arête (pas de sens
     disponible) -> les nœuds sont tous isolés.
   - Lignes avec un seul côté : nœud isolé, comme d'habitude.
------------------------------------------------------------------ */
const HEADER_SANS_DIR = ["dta_1", "dta_2", "dta_3", "dta_4", "edg_1", "edg_2", "edg_3", "edg_4"];

// [ nom dta, nom edg ]  ("" = côté absent) — pas de sens du tout
const RECORDS_SANS_DIR = [
  ["A1", "B1"], // deux nœuds, pas de sens -> aucune arête
  ["A2", ""], // nœud données seul -> isolé
  ["", "B2"], // nœud edg seul     -> isolé
];

/* ------------------------------------------------------------------
   Fabrique le tableau de lignes (en-tête + données) puis écrit le .xlsx.
------------------------------------------------------------------ */
function ecrireClasseur(nomFichier, header, dataRows) {
  const rows = [header, ...dataRows];

  const ws = XLSX.utils.aoa_to_sheet(rows); // tableau de tableaux -> feuille
  const wb = XLSX.utils.book_new(); // classeur vide
  XLSX.utils.book_append_sheet(wb, ws, "Feuil1");
  const buf = XLSX.write(wb, { type: "buffer", bookType: "xlsx" });

  const outPath = join(HERE, nomFichier);
  writeFileSync(outPath, buf);
  console.log(`${outPath} écrit : ${dataRows.length} lignes de données.`);

  // Petit contrôle : on relit le fichier et on recompte les lignes.
  const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
  const readRows = XLSX.utils.sheet_to_json(back.Sheets[back.SheetNames[0]], { header: 1 });
  console.log(`  relecture OK : ${readRows.length - 1} lignes de données relues.\n`);
}

/* ------------------------------------------------------------------
   Génération des deux fichiers.
------------------------------------------------------------------ */

// Fichier 1 : chaque enregistrement [dta, dir, edg] -> 9 colonnes.
const rows1 = RECORDS_CAS_LIMITES.map(([dta, dir, edg]) => [
  ...parts(dta),
  dir || "",
  ...parts(edg),
]);
ecrireClasseur("exemple-cas-limites.xlsx", HEADER_COMPLET, rows1);

// Fichier 2 : chaque enregistrement [dta, edg] -> 8 colonnes (pas de edg_dir).
const rows2 = RECORDS_SANS_DIR.map(([dta, edg]) => [...parts(dta), ...parts(edg)]);
ecrireClasseur("exemple-sans-edg_dir.xlsx", HEADER_SANS_DIR, rows2);

/* ------------------------------------------------------------------
   Résumé de ce qu'on doit observer dans l'application.
------------------------------------------------------------------ */
console.log(
  [
    "Résultats attendus dans l'appli :",
    "",
    "  exemple-cas-limites.xlsx",
    "    Nœuds        : 11  (SA, PA, OA, ISOL_D, ISOL_E, NS_D, NS_E,",
    "                        BAD_D, BAD_E, LINKED_D, LNK_E)",
    "    Arêtes       : 3   (SA->PA, PA->OA, LINKED_D->LNK_E)",
    "    Nœuds isolés : 6   (ISOL_D, ISOL_E, NS_D, NS_E, BAD_D, BAD_E)",
    "    -> LINKED_D n'est PAS isolé (relié sur une autre ligne)",
    "    -> 2 avertissements console (lignes NS_* et BAD_*)",
    "",
    "  exemple-sans-edg_dir.xlsx",
    "    Nœuds        : 4   (A1, B1, A2, B2)",
    "    Arêtes       : 0",
    "    Nœuds isolés : 4",
    "    -> le fichier se charge malgré l'absence de colonne edg_dir",
  ].join("\n")
);
