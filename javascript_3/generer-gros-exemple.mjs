/* ==================================================================
   Génère exemple_gros.xlsx : un GROS graphe pour tester la pagination.
   ------------------------------------------------------------------
   Lancer :  node generer-gros-exemple.mjs            (20 000 nœuds)
             node generer-gros-exemple.mjs 270000     (270 000 nœuds)

   Le graphe est tiré au hasard, mais avec une GRAINE FIXE : relancer
   le script donne toujours exactement le même fichier.

   Ce qu'il contient :
     - un TRÈS GROS morceau (30 % des nœuds), bien plus grand qu'une page
       de 2000 nœuds => il est coupé en plusieurs pages, et on voit
       apparaître des NŒUDS FANTÔMES (arcs vers une autre page) ;
     - beaucoup de petits morceaux (2 à 300 nœuds) => ils sont regroupés
       dans les pages sans jamais être coupés.
   Chaque morceau est un ARBRE : un nœud de départ, puis chaque nouveau
   nœud est rattaché à un nœud déjà créé du même morceau (choisi parmi
   les 50 derniers, pour avoir des chaînes assez longues comme un lineage).

   Règle des nœuds (comme dans les autres exemples) : un arc relie
   toujours un nœud « données » (D…) et un nœud « edg » (E…) ; on
   alterne D / E d'une génération à la suivante :
     - parent D -> enfant E : ligne sens I (données -> edg)
     - parent E -> enfant D : ligne sens O (edg -> données)
   Pour garder un fichier léger, seul dta_1 / edg_1 est rempli
   (le nom du nœud est donc simplement "D123" ou "E456").

   Ce script n'écrit QUE exemple_gros.xlsx : il ne touche ni aux autres
   exemples, ni à app.js. Fermez le fichier dans Excel avant de lancer.
   ================================================================== */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const XLSX = require(join(HERE, "vendor", "xlsx.mini.min.js"));

// Nombre de nœuds voulu : 1er argument de la ligne de commande, 20 000 sinon.
const N = parseInt(process.argv[2], 10) || 20000;

// Générateur pseudo-aléatoire à graine fixe (mulberry32) : même graine
// => même suite de nombres => même fichier à chaque lancement.
let graine = 12345;
function hasard() {
  graine = (graine + 0x6d2b79f5) | 0;
  let t = graine;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296; // nombre entre 0 et 1
}
const entre = (a, b) => a + Math.floor(hasard() * (b - a + 1)); // entier entre a et b inclus
const auHasard = (liste) => liste[Math.floor(hasard() * liste.length)];

const CARAS = ["V", "R", "C", "U", "G"];
const TXNS = ["filtre", "jointure", "calcul", "tri", "agrégation", "", "", ""]; // "" = sans transformation

const arcs = [["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta"]];
const noeuds = [["Nœud_1", "Nœud_2", "Nœud_3", "Nœud_4", "Cara_vis"]];

let compteur = 0; // numéro du prochain nœud créé

// fabriquerMorceau(taille) : crée un arbre de `taille` nœuds.
function fabriquerMorceau(taille) {
  const crees = []; // [{ nom, estD }] des nœuds de ce morceau
  for (let i = 0; i < taille; i++) {
    // Le 1er nœud du morceau est une donnée (D) ; les suivants alternent
    // selon leur parent.
    const parent = i === 0 ? null : crees[Math.max(0, crees.length - entre(1, 50))];
    const estD = parent ? !parent.estD : true;
    const nom = (estD ? "D" : "E") + ++compteur;
    crees.push({ nom, estD });
    noeuds.push([nom, "", "", "", auHasard(CARAS)]);

    if (parent) {
      const txn = auHasard(TXNS);
      if (parent.estD) {
        // parent D -> enfant E : la donnée ENTRE dans le traitement (I)
        arcs.push([parent.nom, "", "", "", "I", nom, "", "", "", txn]);
      } else {
        // parent E -> enfant D : le traitement PRODUIT la donnée (O)
        arcs.push([nom, "", "", "", "O", parent.nom, "", "", "", txn]);
      }
    }
  }
}

// 1) Le très gros morceau : 30 % des nœuds.
fabriquerMorceau(Math.floor(N * 0.3));
// 2) Puis des petits morceaux jusqu'à atteindre N nœuds.
while (compteur < N) fabriquerMorceau(Math.min(entre(2, 300), N - compteur));

// Écriture : « Arc » en 1er onglet, « Noeud » en 2e.
const fileName = "exemple_gros.xlsx";
const outPath = join(HERE, fileName);
const wb = XLSX.utils.book_new();
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(arcs), "Arc");
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(noeuds), "Noeud");
writeFileSync(outPath, XLSX.write(wb, { type: "buffer", bookType: "xlsx", compression: true }));

// Petit contrôle : relecture.
const back = XLSX.read(new Uint8Array(readFileSync(outPath)), { type: "array" });
const nb = (nom) => XLSX.utils.sheet_to_json(back.Sheets[nom], { header: 1 }).length - 1;
console.log(`${fileName} écrit : ${nb("Arc")} arcs, ${nb("Noeud")} nœuds (relecture OK).`);
