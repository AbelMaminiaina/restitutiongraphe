/* ==================================================================
   Script de construction (build) — génère dist/ pour partage local.
   ------------------------------------------------------------------
   Ce que ça fait :
     1. lit index.html + style.css + exemple-data.js + app.js + vendor/*.js
     2. minifie le CSS (regex) et le JS de l'appli (terser via npx)
     3. produit UN SEUL fichier dist/lineage.html : CSS, librairies et JS
        tous intégrés -> AUCUN accès internet, aucun fichier .js à côté
     4. copie exemple.xlsx et crée les lanceurs double-clic (.bat / .command)

   Lancer :  node build.mjs
   Pré-requis : Node.js + accès npm (npx télécharge terser au 1er appel).
   ================================================================== */

import { readFileSync, writeFileSync, mkdirSync, rmSync, copyFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIST = join(HERE, "dist");

/* --- 1. Lecture des sources --------------------------------------- */
const html = readFileSync(join(HERE, "index.html"), "utf8");
const css = readFileSync(join(HERE, "style.css"), "utf8");
// exemple-data.js (données du bouton « Charger l'exemple ») est placé AVANT
// app.js, comme dans index.html : les deux sont minifiés ensemble.
const js =
  readFileSync(join(HERE, "exemple-data.js"), "utf8") + "\n;\n" + readFileSync(join(HERE, "app.js"), "utf8");

// Librairies locales : on lit exactement les <script src="vendor/…"> d'index.html,
// dans leur ordre d'apparition (cytoscape doit précéder son extension dagre).
const VENDOR = [...html.matchAll(/<script src="vendor\/([^"]+)"><\/script>/g)].map((m) => m[1]);
if (VENDOR.length === 0) throw new Error("Aucun <script src=\"vendor/…\"> trouvé dans index.html");
const vendorJs = VENDOR.map((name) =>
  readFileSync(join(HERE, "vendor", name), "utf8")
    // on enlève les commentaires "sourceMappingURL" -> pas de .map à chercher
    .replace(/\/\/#\s*sourceMappingURL=.*$/gm, "")
    .trim()
).join("\n;\n");

/* --- 2a. Minification CSS (suffisante pour ce fichier simple) ----- */
const cssMin = css
  .replace(/\/\*[\s\S]*?\*\//g, "") // commentaires
  .replace(/\s+/g, " ") // espaces multiples -> un seul
  .replace(/\s*([{}:;,>])\s*/g, "$1") // espaces autour des séparateurs
  .replace(/;}/g, "}")
  .trim();

/* --- 2b. Minification du JS de l'appli via terser (npx) --------- */
console.log("Minification du JS avec terser…");
const tmpIn = join(DIST, "_in.js");
const tmpOut = join(DIST, "_out.js");
mkdirSync(DIST, { recursive: true });
writeFileSync(tmpIn, js);
// shell: true -> laisse le shell résoudre "npx" / "npx.cmd" selon l'OS.
execSync(
  `npx --yes terser@5.36.0 "${tmpIn}" --compress --mangle --output "${tmpOut}"`,
  { stdio: "inherit", shell: true }
);
const jsMin = readFileSync(tmpOut, "utf8");
rmSync(tmpIn);
rmSync(tmpOut);

/* --- 3. Assemblage du fichier unique ----------------------------- */
/* Note : on passe des FONCTIONS à replace() et non des chaînes, sinon les
   séquences « $& », « $' », « $1 »… présentes dans le code minifié des
   librairies seraient interprétées par replace() et casseraient le fichier. */
let out = html
  // on retire le commentaire qui décrit les <script> des librairies
  .replace(/\s*<!--\s*Librairies modernes[\s\S]*?-->\n?/, "\n")
  // feuille de style externe -> <style> intégré et minifié
  .replace(/\s*<link rel="stylesheet" href="style\.css"\s*\/>\n?/, "\n")
  .replace("</head>", () => `  <style>${cssMin}</style>\n</head>`)
  // 1er <script src="vendor/..."> -> un seul <script> avec toutes les libs intégrées
  .replace(/[ \t]*<script src="vendor\/[^"]+"><\/script>\n?/, () => `  <script>${vendorJs}</script>\n`)
  // les autres <script src="vendor/..."> -> supprimés (déjà intégrés ci-dessus)
  .replace(/[ \t]*<script src="vendor\/[^"]+"><\/script>\n?/g, "")
  // <script src="exemple-data.js"> -> supprimé (intégré avec app.js ci-dessous)
  .replace(/[ \t]*<script src="exemple-data\.js"><\/script>\n?/, "")
  // <script src="app.js"> -> JS de l'appli minifié en ligne
  .replace(/<script src="app\.js"><\/script>/, () => `<script>${jsMin}</script>`);

if (/\ssrc="(vendor\/|app\.js|exemple-data\.js)|href="style\.css"/.test(out)) {
  throw new Error("Assemblage incomplet : une référence externe subsiste dans lineage.html");
}

writeFileSync(join(DIST, "lineage.html"), out);

/* --- 4. Fichiers d'accompagnement ------------------------------- */
copyFileSync(join(HERE, "exemple.xlsx"), join(DIST, "exemple.xlsx"));

// Lanceur Windows : ouvre lineage.html dans le navigateur par défaut.
writeFileSync(
  join(DIST, "Ouvrir le lineage.bat"),
  '@echo off\r\nstart "" "%~dp0lineage.html"\r\n'
);

// Lanceur macOS/Linux (rendre exécutable : chmod +x).
writeFileSync(
  join(DIST, "Ouvrir le lineage.command"),
  '#!/bin/bash\ncd "$(dirname "$0")"\nif command -v open >/dev/null; then open lineage.html; else xdg-open lineage.html; fi\n'
);

writeFileSync(
  join(DIST, "LISEZ-MOI.txt"),
  [
    "Saisie et cartographie du lignage de données",
    "============================================",
    "",
    "Windows : double-cliquez « Ouvrir le lineage.bat »",
    "macOS   : double-cliquez « Ouvrir le lineage.command »",
    "          (au 1er lancement : clic droit > Ouvrir)",
    "Sinon   : ouvrez « lineage.html » avec un navigateur.",
    "",
    "Fonctionne 100 % hors ligne (aucune connexion internet requise).",
    "",
    "Chargez votre fichier Excel .xlsx (bouton ou glisser-déposer),",
    "ou cliquez « Charger l'exemple ».",
  ].join("\n") + "\n"
);

const kb = Math.round(Buffer.byteLength(out) / 1024);
console.log(`OK -> ${DIST}  (lineage.html : ${kb} Ko, autonome)`);
