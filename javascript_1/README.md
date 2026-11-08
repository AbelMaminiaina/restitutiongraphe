# javascript/ — Visualiseur de graphe orienté non pondéré

Petite application **100 % navigateur, 100 % hors ligne** (HTML + JavaScript,
aucun serveur, aucune installation, aucun accès internet) qui construit et
affiche un graphe orienté non pondéré à partir d'un **fichier Excel `.xlsx`**
(comme `exemple_parcours.xlsx` ou `exemple_adjacent.xlsx`).

## Lancer

Double-cliquez sur **`index.html`** (ou ouvrez-le dans un navigateur).

> Les librairies (cytoscape, dagre, xlsx) sont stockées **en local** dans
> `vendor/` — rien n'est téléchargé au chargement.

## Utilisation

| Action | Comment |
| --- | --- |
| Charger un fichier | Bouton **« Importer un .xlsx »** ou **glisser-déposer** le fichier sur la zone centrale |
| Voir la démo | Boutons **« Exemple parcours »** et **« Exemple adjacent »** (données de `exemple_parcours.xlsx` / `exemple_adjacent.xlsx` intégrées au code) |
| Voisins d'un nœud | **Cliquez un nœud** : ses *successeurs* (vert) et *prédécesseurs* (jaune) sont mis en évidence, avec leur **transformation** (`txn_dta`) dans deux tableaux du panneau latéral |
| Changer la disposition | Menu **« Mise en page »** (hiérarchique, cercle, forces…) |
| Exporter | Bouton **« Exporter PNG »** |

### Mode d'affichage : suffixe du nom du fichier

Le nom du fichier importé doit se terminer (juste avant `.xlsx`) par
**`parcours`** ou **`adjacent`** — casse ignorée, séparateur libre
(`lineage_parcours.xlsx`, `Flux-Adjacent.xlsx`…) :

| Suffixe | Nœuds « données » `dta_*` | Nœuds `edg_*` |
| --- | --- | --- |
| `…_parcours.xlsx` | **jaune** (ce sont tous des parcours) | **jaune** |
| `…_adjacent.xlsx` | **jaune** (nœuds source = parcours) | **bleu** (neutres) |
| autre nom | violet | bleu |

Le mode détecté est affiché à côté du nom du fichier. En mode adjacent, un nœud
présent à la fois en `dta_*` et en `edg_*` est jaune.

Au clic sur un nœud : successeurs en **vert**, prédécesseurs en **orange**.

Les arcs **avec** transformation (`txn_dta` renseigné) sont en **trait plein
rouge vif** ; les arcs **sans** transformation en **pointillé gris**.

## Les exemples fournis

Deux fichiers d'exemple, un par mode, servent de démonstration **et de modèle**
pour construire vos propres fichiers. Ils sont aussi intégrés au site : boutons
**« Exemple parcours »** et **« Exemple adjacent »** (aucun fichier à ouvrir).

> Dans les tableaux ci-dessous, « DA » désigne les 4 morceaux `DA1`..`DA4`
> (colonnes `dta_1`..`dta_4` ou `edg_1`..`edg_4`) ; le nœud affiché s'appelle
> `DA4.DA3.DA2.DA1`. « — » = `txn_dta` vide (arc en pointillé).

### `exemple_parcours.xlsx` — un parcours = une ligne

Un parcours se lit d'un bout à l'autre, **sans embranchement ni boucle** : chaque
nœud a au plus un prédécesseur et un successeur. Données (`D…`) et traitements
(`E…`) alternent ; tous les nœuds sont **jaunes**.

```
DA → EA → DB → EB → DC → EC → DD → ED → DE → EE → DF
```

| données (`dta_*`) | `edg_dir` | edg (`edg_*`) | `txn_dta` | arc obtenu |
| --- | --- | --- | --- | --- |
| DA | `I` | EA | filtre | DA → EA |
| DB | `O` | EA | agrégation | EA → DB |
| DB | `I` | EB | — | DB → EB |
| DC | `O` | EB | jointure | EB → DC |
| DC | `I` | EC | tri | DC → EC |
| DD | `O` | EC | — | EC → DD |
| DD | `I` | ED | calcul | DD → ED |
| DE | `O` | ED | normalisation | ED → DE |
| DE | `I` | EE | — | DE → EE |
| DF | `O` | EE | déduplication | EE → DF |

Résultat : **11 nœuds** (tous jaunes), **10 arcs** (7 pleins, 3 pointillés).
Astuce : menu « Mise en page » → **« Hiérarchique (de gauche à droite) »** pour
voir la ligne à l'horizontale.

### `exemple_adjacent.xlsx` — les nœuds parcours se suivent, les edg à côté

Les nœuds du parcours (**jaunes**) **se suivent directement**, arc après arc ;
les traitements adjacents (nœuds `edg`, **bleus**, neutres) sont branchés à
côté, un par donnée :

```
EA → DA → DB → DC → DD → DE → DF → EF
          ↓    ↓    ↑    ↓
          EB   EC   ED   EE
```

Pour relier **deux données directement** (DA → DB), la donnée de départ est
écrite dans les colonnes **`edg_1`..`edg_4`** : la ligne `DB | O | DA` donne
l'arc DA → DB. Un nœud présent à la fois en `dta_*` et en `edg_*` est jaune en
mode adjacent.

| données (`dta_*`) | `edg_dir` | edg (`edg_*`) | `txn_dta` | arc obtenu |
| --- | --- | --- | --- | --- |
| DB | `O` | DA | filtre | DA → DB |
| DC | `O` | DB | — | DB → DC |
| DD | `O` | DC | jointure | DC → DD |
| DE | `O` | DD | calcul | DD → DE |
| DF | `O` | DE | — | DE → DF |
| DA | `O` | EA | chargement | EA → DA |
| DB | `I` | EB | — | DB → EB |
| DC | `I` | EC | copie | DC → EC |
| DD | `O` | ED | — | ED → DD |
| DE | `I` | EE | tri | DE → EE |
| DF | `I` | EF | export | DF → EF |

Résultat : **12 nœuds** (6 jaunes DA..DF, 6 bleus EA..EF), **11 arcs**
(7 pleins, 4 pointillés).

### Faire son propre fichier

1. Partir de l'exemple du bon mode (copier `exemple_parcours.xlsx` ou
   `exemple_adjacent.xlsx`).
2. **Garder la fin du nom** : `…_parcours.xlsx` ou `…_adjacent.xlsx` (c'est elle
   qui choisit les couleurs).
3. Remplacer les valeurs ligne par ligne, en gardant la ligne d'en-tête.

## Format du fichier Excel attendu

Une feuille, une ligne d'en-tête, puis une ligne par enregistrement. Colonnes :

| `dta_1` | `dta_2` | `dta_3` | `dta_4` | `edg_dir` | `edg_1` | `edg_2` | `edg_3` | `edg_4` | `txn_dta` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DA1 | DA2 | DA3 | DA4 | `O` | EA1 | EA2 | EA3 | EA4 | agrégation |
| DB1 | DB2 | DB3 | DB4 | `I` | EA1 | EA2 | EA3 | EA4 | filtre |

Chaque ligne définit **deux nœuds** et **une arête** entre eux :

- nœud « données » = concaténation `dta_4.dta_3.dta_2.dta_1` (ex. `DA4.DA3.DA2.DA1`) ;
- nœud « edg » = concaténation `edg_4.edg_3.edg_2.edg_1` (ex. `EA4.EA3.EA2.EA1`) ;
- la colonne **`edg_dir`** donne le **sens** de l'arête :
  - **`I`** (Input) → le nœud « données » est **prédécesseur** du nœud « edg »
    ⇒ arête `données → edg` ;
  - **`O`** (Output) → le nœud « données » est **successeur** du nœud « edg »
    ⇒ arête `edg → données`.
- la colonne **`txn_dta`** donne la **transformation** appliquée sur cette arête
  (une simple étiquette texte) ; elle est affichée dans les tableaux
  successeurs/prédécesseurs du panneau latéral quand un nœud est sélectionné.

Donc : les **nœuds** du graphe sont toutes les concaténations `dta_*` et `edg_*`,
les **arêtes** sont les couples (données, edg) orientés selon `edg_dir`, chacune
portant sa transformation `txn_dta`.

Tolérances de lecture :

- en-têtes insensibles à la casse ; `edg4` accepté comme `edg_4` ; la colonne de
  sens est repérée par n'importe quel en-tête contenant `dir` (`edr_dir`,
  `direction`…) ; la colonne de transformation par n'importe quel en-tête
  contenant `txn` ;
- morceaux `dta_*` / `edg_*` vides ignorés dans la concaténation ;
- ligne dont le nœud « données » ou « edg » est entièrement vide : ignorée ;
- colonne `txn_dta` optionnelle : absente ou vide → transformation affichée
  comme « — » et arc dessiné en pointillé.

## Partager à des utilisateurs (sans leur donner le code source)

Le dossier **`dist/`** contient une version prête à distribuer :

| Fichier | Rôle |
| --- | --- |
| `graphe.html` | **Un seul fichier autonome** (~900 Ko) : HTML + CSS + JS de l'appli **minifiés** + les librairies, tout intégré. Aucun `.js` lisible à côté, **aucun accès internet** |
| `Ouvrir le graphe.bat` | Windows : double-clic → ouvre `graphe.html` dans le navigateur |
| `Ouvrir le graphe.command` | macOS/Linux : idem (1er lancement : clic droit → Ouvrir) |
| `exemple_parcours.xlsx`, `exemple_adjacent.xlsx`, `LISEZ-MOI.txt` | jeux de démo + notice |

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
   **« Exemple parcours »** puis **« Exemple adjacent »**, contrôler que le graphe s'affiche.
5. Distribuer : copier **tout le dossier `dist/`** (clé USB, lecteur réseau,
   `.zip`). Ne pas séparer `graphe.html` des lanceurs si on veut le double-clic.

> `dist/` est ignoré par le `.gitignore` du dépôt (c'est un résultat de build,
> pas du code source). Il est donc normal qu'il n'apparaisse pas sur GitHub :
> chacun le régénère avec `node build.mjs`.

### Régénérer les jeux d'exemple (`exemple_parcours.xlsx`, `exemple_adjacent.xlsx`)

Les données de démonstration (10 et 11 lignes, voir « Les exemples fournis »)
sont décrites dans
**`generer-exemple.mjs`** (tableaux `RECORDS_PARCOURS` et `RECORDS_ADJACENT`). Après modification :

```
node generer-exemple.mjs
```

Le script réécrit les deux `.xlsx` **et** met à jour tout seul les tableaux
`EXEMPLE_PARCOURS_ROWS` / `EXEMPLE_ADJACENT_ROWS` dans `app.js` (entre les
repères `// <exemples-debut>` et `// <exemples-fin>`) : les boutons « Exemple
parcours » / « Exemple adjacent » lisent ces lignes intégrées, pas les
fichiers. Fermez les `.xlsx` dans Excel avant de lancer le script (sinon
« fichier verrouillé »).

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
| `index.html` | Structure de la page + chargement, dans le `<head>`, des librairies locales puis de `app.js` |
| `style.css` | Thème sombre, mise en page |
| `app.js` | Lecture du `.xlsx`, construction du graphe, rendu cytoscape, statistiques, interactions |
| `build.mjs` | Génère `dist/` (fichier unique autonome minifié + lanceurs) |
| `generer-exemple.mjs` | (Re)génère les deux `.xlsx` d'exemple + les tableaux `EXEMPLE_PARCOURS_ROWS` / `EXEMPLE_ADJACENT_ROWS` de `app.js` |
| `vendor/` | Librairies (cytoscape, dagre, cytoscape-dagre, xlsx) copiées depuis jsDelivr |
| `exemple_parcours.xlsx` | Démo mode parcours : 10 lignes → une seule ligne de 11 nœuds (tous jaunes) DA → EA → DB → … → DF, 10 arêtes (7 pleines, 3 pointillées) |
| `exemple_adjacent.xlsx` | Démo mode adjacent : 6 nœuds jaunes qui se suivent DA → DB → DC → DD → DE → DF + 6 traitements voisins EA..EF (bleus), un par donnée → 12 nœuds, 11 arêtes (7 pleines, 4 pointillées) |

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
| **Console** (saisie directe) | tester une fonction : `rowsToGraph(EXEMPLE_PARCOURS_ROWS)`, `computeStats(currentData)`, `cy.nodes().length` |
| Onglet **Sources** | poser ses propres points d'arrêt en cliquant un numéro de ligne |
| Onglet **Network** | vérifier que `vendor/*.js` se chargent en `200` (un `404` = chemin cassé) |
| Onglet **Elements** | inspecter le HTML réel ; vérifier qu'un `id` existe |
| `console.table(rows)` | afficher un tableau lisible |

Erreurs fréquentes : `XLSX is not defined` → un `<script vendor/>` non chargé,
ou placé **après** `app.js` ;
`Cannot read properties of null` → un `id` HTML absent / mal écrit, ou un
`document.getElementById(…)` ajouté **hors** de `getDomRefs()` (il s'exécute
alors avant que la page existe, voir « Chargement de `app.js` dans le `<head>` ») ;
« Colonnes attendues introuvables » → mauvaises colonnes dans le `.xlsx`.

### VS Code

Extension **Live Server** → bouton **« Go Live »** : sert la page sur
`http://localhost:5500` avec rechargement automatique (mieux que le double-clic).

## Comprendre le code

`app.js` commence par un **guide de lecture** : les 10 sections classées de la
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

### Chargement de `app.js` dans le `<head>`

Dans `index.html`, `app.js` est chargé dans le **`<head>`**, juste **après** les
4 librairies `vendor/` qu'il utilise, **sans `defer`** :

```html
<head>
  …
  <script src="vendor/xlsx.mini.min.js"></script>
  <script src="app.js"></script>
</head>
```

À ce moment-là, le `<body>` n'est **pas encore construit** : les boutons, le
`<div id="cy">`… n'existent pas. `app.js` attend donc lui-même que la page soit
prête avant d'y toucher :

| Section de `app.js` | Rôle |
| --- | --- |
| 3. `getDomRefs()` | remplit les variables `stage`, `fileInput`, `statsEl`… (déclarées vides en haut) |
| 9. `wireEvents()` | branche les clics, le glisser-déposer, les menus |
| 10. Démarrage | appelle `getDomRefs()` puis `wireEvents()` sur l'événement **`DOMContentLoaded`** (HTML entièrement lu), ou tout de suite si la page est déjà prête |

Tout le reste (`rowsToGraph`, `computeStats`, `renderGraph`…) ne touche pas à la
page au chargement : ce sont des fonctions, appelées plus tard.

**Règles quand on modifie le code :**

- un nouvel élément HTML à manipuler → déclarer la variable avec les autres
  (section 3) et ajouter son `document.getElementById(…)` **dans `getDomRefs()`** ;
- un nouveau clic / événement → l'ajouter **dans `wireEvents()`** ;
- garder `<script src="app.js">` **après** les `<script src="vendor/…">` ;
- ne pas ajouter `defer` : `build.mjs` cherche exactement
  `<script src="app.js"></script>`, et `defer` est sans effet sur le script en
  ligne de `dist/graphe.html`. Le démarrage sur `DOMContentLoaded` marche, lui,
  dans les deux cas.

## Développer `app.js` hors ligne

Tout ce qu'il faut est du code **vanilla** exécuté par le navigateur : **aucune
compilation, aucune vérification, aucun outil obligatoire**. La boucle complète :

```
1. Ouvrir  javascript/app.js  dans un éditeur (VS Code, ou même le Bloc-notes)
2. Modifier, puis  Ctrl+S
3. Aller dans le navigateur,  Ctrl+R  (recharger index.html)
4. Regarder le résultat + la console F12 pour les erreurs  →  retour à l'étape 2
```

Il n'y a **rien d'autre** : pas de `npm run`, pas de `tsc`, pas de `build`.
`build.mjs` ne sert **qu'à** fabriquer `dist/` pour la distribution, jamais pour
développer.

### Pourquoi ça marche sans compilation

| | `app.js` (navigateur) | Comparaison : `dotnet-new-scan` (.NET) |
| --- | --- | --- |
| Étape avant exécution | **aucune** | `dotnet build` |
| « Lancer » le code | recharger l'onglet (`Ctrl+R`) | `dotnet run` |
| Vérification des types | aucune (JS n'a pas de types) | le compilateur refuse le code invalide |

Pour qui vient de Python : c'est comme éditer un `.py` puis relancer
`python script.py`… sauf qu'ici on ne tape même pas de commande, on **recharge
la page**.

### Servir la page en local (Python, déjà installé)

Le double-clic sur `index.html` (`file://`) **fonctionne** pour ce projet (les
`vendor/*.js` sont en chemins relatifs, le `.xlsx` est lu par `FileReader`, pas
par `fetch`). Un petit serveur local est toutefois plus propre :

```powershell
cd chemin\vers\restitutiondonnees\javascript
python -m http.server 8000
```

Puis ouvrir <http://localhost:8000>. `Ctrl+C` pour arrêter. Avantage : pas de
cache `file://` capricieux, et l'onglet **Network** du F12 montre bien les `200`
/ `404` des `vendor/*.js`.

> Si le navigateur ressert un vieux `app.js` : **`Ctrl+Shift+R`** (rechargement
> forcé), ou F12 → **Network** → cocher **« Disable cache »**.

### Sans vérification : où sont signalées les erreurs

Rien ne contrôle le code **avant** son exécution, donc :

- faute de frappe (parenthèse non fermée…) → **erreur rouge dans la console F12**
  avec le numéro de ligne (`app.js:123`, cliquable) ;
- erreur de logique (mauvais nom de variable) → `undefined` silencieux ou
  `Cannot read properties of null`, là aussi dans la console.

Filets de sécurité **optionnels** (aucun n'est requis) :

- coloration syntaxique de VS Code (accolades/parenthèses non équilibrées) ;
- **F12 → Console** : le vrai vérificateur, en direct ;
- **Prettier** et **ESLint** installés en local (voir ci-dessous) si on veut un
  contrôle automatique — mais le code tourne très bien sans.

### Qualité du code hors ligne (Prettier + ESLint)

À télécharger **une seule fois** avec une connexion, puis utilisables hors ligne :

```powershell
cd chemin\vers\restitutiondonnees\javascript
npm install --save-dev prettier eslint      # connexion nécessaire cette fois uniquement
```

Ensuite, hors ligne :

```powershell
npx prettier --write app.js                  # reformate proprement
npx eslint app.js                            # == au lieu de ===, variables inutilisées…
```

Ou les extensions VS Code **Prettier** et **ESLint** (installées une fois en
ligne) : formatage à la sauvegarde, erreurs soulignées en direct.

### Ce qui exige (une fois) une connexion

| Étape | Hors ligne ? |
| --- | --- |
| Éditer `app.js`, servir avec `python -m http.server`, déboguer au F12 | ✅ toujours |
| Librairies `vendor/*.js` | ✅ déjà téléchargées |
| **1re** install de Prettier / ESLint / extensions VS Code | ❌ une fois |
| **1er** `node build.mjs` (télécharge `terser`) | ❌ une fois |
| Tout le reste ensuite | ✅ hors ligne |

## Aide de l'IA pour écrire `app.js`

### En ligne

| Outil | Note |
| --- | --- |
| **Claude Code** (CLI) | Écrit et modifie `app.js` directement, lance le serveur, teste, corrige. |
| **GitHub Copilot** (extension VS Code) | Autocomplétion + chat ; abonnement (gratuit étudiants / OSS). |
| **Continue** (extension VS Code) | Gratuit, open source ; se branche sur Claude / GPT **ou sur un modèle local** (voir ci-dessous). |
| **Codeium / Windsurf**, **Cursor** | Paliers gratuits ; assistants intégrés à l'éditeur. |
| **Chat web** (<https://claude.ai>, <https://chatgpt.com>) | Coller `app.js` **et** ce README, poser la question, recopier. |

### 100 % hors ligne — Ollama

`ollama` est installé sur le poste mais **aucun modèle n'est encore
téléchargé**. Une fois, avec une connexion :

```powershell
ollama pull qwen2.5-coder:7b       # ~4,7 Go, spécialisé code
```

Ensuite, totalement hors ligne :

- **ligne de commande** : `ollama run qwen2.5-coder:7b` ;
- **dans VS Code** : extension **Continue** configurée sur `qwen2.5-coder` via
  Ollama → autocomplétion + chat sans internet.

> Un modèle local est moins fort que Claude, mais suffit pour du vanilla ES2015
> simple.

### ⚠️ Toujours donner les règles à l'IA

Sans contexte, n'importe quelle IA propose du React, du TypeScript, des
`import`, du `?.`… ce qui **casse** ce projet. Lui coller :

```
Contraintes pour app.js :
- JavaScript vanilla, <script> classique : PAS de module, PAS d'import/export.
- app.js est chargé dans le <head> (sans defer) : tout getElementById va dans
  getDomRefs(), tout addEventListener d'interface dans wireEvents()
  (lancés sur DOMContentLoaded, section 10).
- ES2015 (ES6) maximum : interdit ?. , ?? , async/await, class,
  Array.includes / .at() / .flat() , Object.entries / fromEntries.
- Aucun framework, aucun build, aucune nouvelle dépendance
  (seules cytoscape, dagre, cytoscape-dagre, xlsx sont disponibles, en local).
- Commentaires en FRANÇAIS, généreux (niveau débutant).
- Respecter le modèle de données : nœuds dta_* / edg_*, colonne edg_dir (I/O),
  et l'API cytoscape « collections + classes ».
```

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
3. L'aperçu de droite affiche la page. Cliquer **« Exemple parcours »** pour
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
