/* ==================================================================
   Script de construction (build) — génère dist/ pour partage local.
   ------------------------------------------------------------------
   Ce que ça fait :
     1. lit index.html + style.css + app.js
     2. minifie le CSS (regex) et le JS (terser via npx)
     3. produit UN SEUL fichier dist/graphe.html avec CSS et JS intégrés
        et minifiés (le code n'est plus lisible tel quel dans un éditeur)
     4. garde les 3 <script> des librairies sur le CDN jsDelivr
     5. copie exemple.txt et crée les lanceurs double-clic (.bat / .command)

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
const js = readFileSync(join(HERE, "app.js"), "utf8");

/* --- 2a. Minification CSS (suffisante pour ce fichier simple) ----- */
const cssMin = css
  .replace(/\/\*[\s\S]*?\*\//g, "") // commentaires
  .replace(/\s+/g, " ") // espaces multiples -> un seul
  .replace(/\s*([{}:;,>])\s*/g, "$1") // espaces autour des séparateurs
  .replace(/;}/g, "}")
  .trim();

/* --- 2b. Minification JS via terser (npx) ------------------------- */
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
let out = html
  // on retire le lien vers la feuille de style externe…
  .replace(/\s*<link rel="stylesheet" href="style\.css"\s*\/>\n?/, "\n")
  // …et on l'injecte, minifiée, dans un <style>
  .replace("</head>", `  <style>${cssMin}</style>\n</head>`)
  // on remplace le <script src="app.js"> par le JS minifié en ligne
  .replace(/<script src="app\.js"><\/script>/, `<script>${jsMin}</script>`);

writeFileSync(join(DIST, "graphe.html"), out);

/* --- 4. Fichiers d'accompagnement ------------------------------- */
copyFileSync(join(HERE, "exemple.txt"), join(DIST, "exemple.txt"));

// Lanceur Windows : ouvre graphe.html dans le navigateur par défaut.
writeFileSync(
  join(DIST, "Ouvrir le graphe.bat"),
  '@echo off\r\nstart "" "%~dp0graphe.html"\r\n'
);

// Lanceur macOS/Linux (rendre exécutable : chmod +x).
writeFileSync(
  join(DIST, "Ouvrir le graphe.command"),
  '#!/bin/bash\ncd "$(dirname "$0")"\nif command -v open >/dev/null; then open graphe.html; else xdg-open graphe.html; fi\n'
);

writeFileSync(
  join(DIST, "LISEZ-MOI.txt"),
  [
    "Visualiseur de graphe orienté",
    "=============================",
    "",
    "Windows : double-cliquez « Ouvrir le graphe.bat »",
    "macOS   : double-cliquez « Ouvrir le graphe.command »",
    "          (au 1er lancement : clic droit > Ouvrir)",
    "Sinon   : ouvrez « graphe.html » avec un navigateur.",
    "",
    "Une connexion internet est requise au chargement",
    "(les librairies d'affichage viennent d'un CDN).",
    "",
    "Chargez votre fichier .txt (bouton ou glisser-déposer),",
    "ou cliquez « Charger l'exemple ».",
  ].join("\n") + "\n"
);

console.log("OK -> " + DIST);
