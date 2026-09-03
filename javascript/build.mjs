/* ==================================================================
   Script de construction (build) — génère dist/ pour partage local.
   ------------------------------------------------------------------
   Ce que ça fait :
     1. lit index.html + style.css + app.js + vendor/*.js (librairies)
     2. minifie le CSS (regex) et le JS de l'appli (terser via npx)
     3. produit UN SEUL fichier dist/graphe.html : CSS, librairies et JS
        tous intégrés -> AUCUN accès internet, aucun fichier .js à côté
     4. copie exemple.txt et crée les lanceurs double-clic (.bat / .command)

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

// Librairies locales, dans l'ordre de chargement (cytoscape avant son extension).
const VENDOR = ["cytoscape.min.js", "dagre.min.js", "cytoscape-dagre.min.js"];
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
  // les 3 <script src="vendor/..."> -> un seul <script> avec les libs intégrées
  .replace(
    /\s*<script src="vendor\/cytoscape\.min\.js"><\/script>\s*<script src="vendor\/dagre\.min\.js"><\/script>\s*<script src="vendor\/cytoscape-dagre\.min\.js"><\/script>/,
    () => `\n  <script>${vendorJs}</script>`
  )
  // <script src="app.js"> -> JS de l'appli minifié en ligne
  .replace(/<script src="app\.js"><\/script>/, () => `<script>${jsMin}</script>`);

if (/\ssrc="(vendor\/|app\.js)|href="style\.css"/.test(out)) {
  throw new Error("Assemblage incomplet : une référence externe subsiste dans graphe.html");
}

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
    "Fonctionne 100 % hors ligne (aucune connexion internet requise).",
    "",
    "Chargez votre fichier .txt (bouton ou glisser-déposer),",
    "ou cliquez « Charger l'exemple ».",
  ].join("\n") + "\n"
);

const kb = Math.round(Buffer.byteLength(out) / 1024);
console.log(`OK -> ${DIST}  (graphe.html : ${kb} Ko, autonome)`);
