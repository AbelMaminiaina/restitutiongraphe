# javascript/ — Visualiseur de graphe orienté non pondéré

Petite application **100 % navigateur, 100 % hors ligne** (HTML + JavaScript,
aucun serveur, aucune installation, aucun accès internet) qui construit et
affiche un graphe orienté non pondéré à partir d'un **fichier Excel `.xlsx`**
(comme `exemple.xlsx`).

## Lancer

Double-cliquez sur **`index.html`** (ou ouvrez-le dans un navigateur).

> Les librairies (cytoscape, dagre, xlsx) sont stockées **en local** dans
> `vendor/` — rien n'est téléchargé au chargement.

## Utilisation

| Action | Comment |
| --- | --- |
| Charger un fichier | Bouton **« Importer un .xlsx »** ou **glisser-déposer** le fichier sur la zone centrale |
| Voir la démo | Bouton **« Charger l'exemple »** (données de `exemple.xlsx` intégrées au code) |
| Voisins d'un nœud | **Cliquez un nœud** : ses *successeurs* (vert) et *prédécesseurs* (jaune) sont mis en évidence |
| Changer la disposition | Menu **« Mise en page »** (hiérarchique, cercle, forces…) |
| Exporter | Bouton **« Exporter PNG »** |

Les nœuds `edg_*` sont en **bleu**, les nœuds « données » `dta_*` en **violet**.

## Format du fichier Excel attendu

Une feuille, une ligne d'en-tête, puis une ligne par enregistrement. Colonnes :

| `dta_1` | `dta_2` | `dta_3` | `dta_4` | `edg_dir` | `edg_1` | `edg_2` | `edg_3` | `edg_4` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DA1 | DA2 | DA3 | DA4 | `O` | EA1 | EA2 | EA3 | EA4 |
| DB1 | DB2 | DB3 | DB4 | `I` | EA1 | EA2 | EA3 | EA4 |

Chaque ligne définit **deux nœuds** et **une arête** entre eux :

- nœud « données » = concaténation `dta_4.dta_3.dta_2.dta_1` (ex. `DA4.DA3.DA2.DA1`) ;
- nœud « edg » = concaténation `edg_4.edg_3.edg_2.edg_1` (ex. `EA4.EA3.EA2.EA1`) ;
- la colonne **`edg_dir`** donne le **sens** de l'arête :
  - **`I`** (Input) → le nœud « données » est **prédécesseur** du nœud « edg »
    ⇒ arête `données → edg` ;
  - **`O`** (Output) → le nœud « données » est **successeur** du nœud « edg »
    ⇒ arête `edg → données`.

Donc : les **nœuds** du graphe sont toutes les concaténations `dta_*` et `edg_*`,
les **arêtes** sont les couples (données, edg) orientés selon `edg_dir`.

Tolérances de lecture :

- en-têtes insensibles à la casse ; `edg4` accepté comme `edg_4` ; la colonne de
  sens est repérée par n'importe quel en-tête contenant `dir` (`edr_dir`,
  `direction`…) ;
- morceaux `dta_*` / `edg_*` vides ignorés dans la concaténation ;
- ligne dont le nœud « données » ou « edg » est entièrement vide : ignorée.

## Partager à des utilisateurs (sans leur donner le code source)

Le dossier **`dist/`** contient une version prête à distribuer :

| Fichier | Rôle |
| --- | --- |
| `graphe.html` | **Un seul fichier autonome** (~900 Ko) : HTML + CSS + JS de l'appli **minifiés** + les librairies, tout intégré. Aucun `.js` lisible à côté, **aucun accès internet** |
| `Ouvrir le graphe.bat` | Windows : double-clic → ouvre `graphe.html` dans le navigateur |
| `Ouvrir le graphe.command` | macOS/Linux : idem (1er lancement : clic droit → Ouvrir) |
| `exemple.xlsx`, `LISEZ-MOI.txt` | jeu de démo + notice |

**Pour partager** : copiez le dossier `dist/` sur une clé USB, un lecteur réseau
ou un `.zip` par mail. L'utilisateur double-clique le lanceur — aucun outil à
installer, aucune connexion requise.

> À savoir : du JavaScript exécuté dans un navigateur n'est **jamais totalement
> masqué** (`F12` / « afficher le code source » restent possibles). La
> minification le rend seulement illisible sans effort.

### Générer une version distribuable (`dist/`)

**Pré-requis** : [Node.js](https://nodejs.org) ≥ 18 installé. Au tout premier
build, `npx` télécharge `terser` (le minifieur) — une connexion est nécessaire
**cette fois-là uniquement**. Les librairies d'affichage, elles, ne sont jamais
téléchargées : le build réutilise les copies de `vendor/`.

1. Ouvrir un terminal dans le dossier `javascript/` :
   ```
   cd chemin/vers/restitutiondonnees/javascript
   ```
2. (Optionnel) mettre à jour l'exemple ou le code source (`app.js`, `style.css`,
   `index.html`).
3. Lancer le build :
   ```
   node build.mjs
   ```
   Sortie attendue :
   ```
   Minification du JS avec terser…
   OK -> …/javascript/dist  (graphe.html : 909 Ko, autonome)
   ```
   Si un fichier de `vendor/` a été renommé/déplacé, ou si une référence externe
   reste dans le HTML, le script s'arrête avec un message d'erreur explicite.
4. Vérifier : ouvrir `dist/graphe.html` dans un navigateur, cliquer
   **« Charger l'exemple »**, contrôler que le graphe s'affiche.
5. Distribuer : copier **tout le dossier `dist/`** (clé USB, lecteur réseau,
   `.zip`). Ne pas séparer `graphe.html` des lanceurs si on veut le double-clic.

> `dist/` est ignoré par le `.gitignore` du dépôt (c'est un résultat de build,
> pas du code source). Il est donc normal qu'il n'apparaisse pas sur GitHub :
> chacun le régénère avec `node build.mjs`.

### Régénérer le jeu d'exemple (`exemple.xlsx`)

Les données de démonstration (≈ 20 lignes) sont décrites dans
**`generer-exemple.mjs`** (tableau `RECORDS`). Après modification :

```
node generer-exemple.mjs
```

Le script réécrit `exemple.xlsx` **et** affiche le tableau `EXEMPLE_ROWS` à
recopier dans `app.js` (le bouton « Charger l'exemple » lit ces lignes
intégrées, pas le fichier). Fermez `exemple.xlsx` dans Excel avant de lancer
le script (sinon « fichier verrouillé »).

### Mettre à jour une librairie

1. Télécharger la nouvelle version depuis jsDelivr, **sous le même nom de
   fichier**, dans `vendor/` :
   ```
   curl -L -o vendor/cytoscape.min.js https://cdn.jsdelivr.net/npm/cytoscape@<version>/dist/cytoscape.min.js
   ```
2. Ajuster le numéro de version dans la section « Librairies utilisées »
   ci-dessous.
3. `node build.mjs`, puis re-vérifier `dist/graphe.html` dans un navigateur.

## Fichiers source

| Fichier | Rôle |
| --- | --- |
| `index.html` | Structure de la page + chargement des librairies locales |
| `style.css` | Thème sombre, mise en page |
| `app.js` | Lecture du `.xlsx`, construction du graphe, rendu cytoscape, statistiques, interactions |
| `build.mjs` | Génère `dist/` (fichier unique autonome minifié + lanceurs) |
| `generer-exemple.mjs` | (Re)génère `exemple.xlsx` + le tableau `EXEMPLE_ROWS` de `app.js` |
| `vendor/` | Librairies (cytoscape, dagre, cytoscape-dagre, xlsx) copiées depuis jsDelivr |
| `exemple.xlsx` | Jeu de démonstration : 20 lignes → 14 nœuds, 20 arêtes, avec un cycle |

## Déboguer

Tout se passe dans les **outils de développement du navigateur** (`F12`).
Débogue **`index.html`** (lisible), jamais `dist/graphe.html` (minifié).

### Points d'arrêt intégrés (`DEBUG`)

`app.js` (section 0) contient une fonction `brk("…")` placée aux étapes clés :
entrée/sortie de `rowsToGraph`, repérage des colonnes, chaque ligne traitée,
`renderGraph`, `selectNode`, `loadFile`. Elle ne fait rien tant que `DEBUG`
est faux. Pour l'activer :

- **soit** ouvrir la page avec `?debug=1` à la fin de l'URL
  (`.../index.html?debug=1`) ;
- **soit** éditer `app.js` : `const DEBUG = true || ( … )`.

Ensuite, `F12` ouvert, recharge : l'exécution **s'arrête à chaque `brk()`**.
Touches : `F10` (ligne suivante), `F11` (entrer dans la fonction), `F8`
(continuer). Les variables à regarder sont indiquées dans le message console.

> Ces points d'arrêt sont **retirés automatiquement** du build : `dist/graphe.html`
> ne contient aucun `debugger`.

### Sans les points d'arrêt

| Outil | Usage |
| --- | --- |
| Onglet **Console** | erreurs en rouge (clique la ligne `app.js:123`) ; messages `console.warn` du code |
| **Console** (saisie directe) | tester une fonction : `rowsToGraph(EXEMPLE_ROWS)`, `computeStats(currentData)`, `cy.nodes().length` |
| Onglet **Sources** | poser ses propres points d'arrêt en cliquant un numéro de ligne |
| Onglet **Network** | vérifier que `vendor/*.js` se chargent en `200` (un `404` = chemin cassé) |
| Onglet **Elements** | inspecter le HTML réel ; vérifier qu'un `id` existe |
| `console.table(rows)` | afficher un tableau lisible |

Erreurs fréquentes : `XLSX is not defined` → un `<script vendor/>` non chargé ;
`Cannot read properties of null` → un `id` HTML absent / mal écrit ;
« Colonnes attendues introuvables » → mauvaises colonnes dans le `.xlsx`.

### VS Code

Extension **Live Server** → bouton **« Go Live »** : sert la page sur
`http://localhost:5500` avec rechargement automatique (mieux que le double-clic).

## Comprendre le code

`app.js` commence par un **guide de lecture** : les 9 sections classées de la
plus simple à la plus technique, l'ordre conseillé, et un rappel de vocabulaire
(graphe orienté, successeur/prédécesseur, degré, cycle…).

Difficulté globale : **moyenne**. Les parties faciles (récupération des éléments
HTML, réglages, câblage des clics) sont peu commentées exprès pour rester
lisibles ; les parties denses sont commentées **ligne par ligne** :

- `rowsToGraph` — Excel → `{ nodes, edges }` ;
- `detectCycle` — parcours en profondeur (DFS) avec coloriage blanc/gris/noir ;
- `countWeakComponents` — parcours en largeur (BFS) avec une file ;
- `selectNode` — l'API « collections + classes » de cytoscape.

## Librairies utilisées

- [Cytoscape.js](https://js.cytoscape.org/) `3.30.2` — rendu et interaction du graphe
- [dagre](https://github.com/dagrejs/dagre) `0.8.5` + [cytoscape-dagre](https://github.com/cytoscape/cytoscape.js-dagre) `2.5.0` — disposition hiérarchique orientée
- [SheetJS / xlsx](https://sheetjs.com/) `0.18.5` (build `xlsx.mini.min.js`) — lecture des fichiers `.xlsx`

## Inspiration et version du code

`app.js` n'est **ni un fork ni l'adaptation d'un projet existant** : c'est du code
écrit pour ce dépôt, construit petit à petit (voir `git log -- javascript/app.js`).
Il n'a donc **pas de numéro de version** — le seul historique est celui de git.

Ses tournures sont reprises de trois sources classiques :

| Partie de `app.js` | Source de la façon de faire |
| --- | --- |
| `renderGraph` : objet `{ elements, style: [...sélecteurs], layout }`, `cy.$id()`, `node.outgoers()` / `.incomers()`, `addClass` / `removeClass`, `cy.on("tap", …)` | Documentation officielle **Cytoscape.js** (js.cytoscape.org) — style des tutoriels « collections + classes » |
| `workbookBufferToGraph` : `XLSX.read(…, { type: "array" })` puis `sheet_to_json(ws, { header: 1 })` | Documentation **SheetJS** (pattern canonique de lecture d'une feuille) |
| `LAYOUT_CONFIGS` (`rankDir`, `nodeSep`, `rankSep`…) | Options documentées de **cytoscape-dagre** |
| `detectCycle` : DFS à 3 couleurs blanc / gris / noir | Algorithme de manuel (CLRS *Introduction to Algorithms*, articles « tri topologique » / « détection de cycle ») |
| `countWeakComponents` : BFS avec file pour compter les composantes | Idem, algorithme de manuel |

### Version de JavaScript

`app.js` est un **script classique** (`<script src="app.js">`, pas `type="module"`)
**exécuté tel quel par le navigateur** : `build.mjs` ne fait que le *minifier*, il
ne le transpile pas. Aucun `import` / `export`, pas de `"use strict"`.

Le plafond des fonctionnalités employées est **ES2015 (ES6)**, rien au-dessus :
`const` / `let`, fonctions fléchées, littéraux gabarits, `Map` / `Set`, `for…of`,
spread dans les tableaux, déstructuration de paramètres, paramètres par défaut,
`String.prototype.includes`.

Volontairement **non utilisés** (pour rester lisible et compatible partout) :
`async` / `await`, chaînage optionnel `?.`, coalescence `??`, `class`,
`Array.prototype.includes` / `.at()` / `.flat()`, `Object.entries` / `fromEntries`.
Le chargement de fichier reste géré avec `FileReader` + callback `onload`.

> À ne pas confondre avec les fichiers `*.mjs` (`build.mjs`, `generer-exemple.mjs`…) :
> ce sont des **modules ES pour Node.js ≥ 18** (`import { … } from "node:fs"`), qui
> ne s'exécutent jamais dans le navigateur.

## Développer `app.js` en ligne (sans rien installer)

`app.js` est du **vanilla** : pas de build, juste `index.html` + `app.js` +
`vendor/`. L'outil en ligne adapté est donc un **bac à sable qui sert des
fichiers statiques** (il reproduit ce que fait un double-clic sur `index.html`).

### Recommandé : StackBlitz — <https://stackblitz.com>

Pourquoi c'est le meilleur choix ici :

- il lance un vrai serveur statique dans le navigateur, comme en local ;
- on peut **glisser-déposer tout le dossier `javascript/`** (avec `vendor/`) ;
- aperçu en direct : dès qu'on sauve `app.js`, la page se recharge ;
- le **glisser-déposer d'un `.xlsx`** dans la page marche (indispensable pour
  tester `loadFile`) ;
- console et onglet réseau intégrés, comme le `F12` local.

Étapes :

1. Aller sur <https://stackblitz.com>, cliquer **« Create »** → template
   **« Static »** (HTML/CSS/JS).
2. Dans l'arborescence de gauche, supprimer les fichiers d'exemple, puis
   **glisser-déposer** le dossier `javascript/` (au minimum `index.html`,
   `app.js`, `style.css`, `vendor/`).
3. L'aperçu de droite affiche la page. Cliquer **« Charger l'exemple »** pour
   vérifier.
4. Modifier `app.js` : la page se recharge toute seule.

### Alternative projet complet : CodeSandbox — <https://codesandbox.io>

Même principe (template **« Static »** / **« Vanilla »**), interface façon
VS Code, partage par lien. Un peu plus lourd que StackBlitz, mais pratique pour
garder un projet dans le temps.

### Pour tester juste un bout de code (un layout, un style cytoscape)

Si on veut seulement essayer **une idée sur cytoscape** sans tout le projet :

| Outil | Lien | Note |
| --- | --- | --- |
| **CodePen** | <https://codepen.io> | Le plus rapide. Menu ⚙️ du panneau JS → **« Add External Scripts »** → coller les 4 URL jsDelivr (cytoscape, dagre, cytoscape-dagre, xlsx) |
| **JSFiddle** | <https://jsfiddle.net> | Idem, section **« Resources »** à gauche pour les librairies |

> Sur CodePen / JSFiddle, le **glisser-déposer d'un fichier `.xlsx`** est peu
> pratique : les garder pour la partie graphe, pas pour tester la lecture Excel.

### Outils qualité (en complément)

| Outil | Lien | Usage |
| --- | --- | --- |
| **Prettier Playground** | <https://prettier.io/playground> | Coller `app.js` → code reformaté proprement |
| **ESLint Demo** | <https://eslint.org/play> | Repère les erreurs vanilla (`==` au lieu de `===`, variable non utilisée…) |
| **Can I use** | <https://caniuse.com> | Vérifier qu'une fonctionnalité JS (ex. `Array.prototype.at`) est bien supportée avant de l'ajouter, puisque le code n'est pas transpilé |

> En local, l'équivalent de tous ces bacs à sable est l'extension **Live Server**
> de VS Code (voir la section « Déboguer » → « VS Code »). Les outils en ligne
> servent surtout à **partager un test par lien** ou à **bricoler sans rien
> installer**.
