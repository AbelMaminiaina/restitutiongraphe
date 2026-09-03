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
| A11 | A12 | A13 | A14 | `I` | E11 | E12 | E13 | E14 |
| A21 | A22 | A23 | A24 | `O` | E21 | E22 | E23 | E24 |

Chaque ligne définit **deux nœuds** et **une arête** entre eux :

- nœud « données » = concaténation `dta_4.dta_3.dta_2.dta_1` (ex. `A14.A13.A12.A11`) ;
- nœud « edg » = concaténation `edg_4.edg_3.edg_2.edg_1` (ex. `E14.E13.E12.E11`) ;
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
| `vendor/` | Librairies (cytoscape, dagre, cytoscape-dagre, xlsx) copiées depuis jsDelivr |
| `exemple.xlsx` | Jeu de données de démonstration (2 lignes → 4 nœuds, 2 arêtes) |

## Librairies utilisées

- [Cytoscape.js](https://js.cytoscape.org/) `3.30.2` — rendu et interaction du graphe
- [dagre](https://github.com/dagrejs/dagre) `0.8.5` + [cytoscape-dagre](https://github.com/cytoscape/cytoscape.js-dagre) `2.5.0` — disposition hiérarchique orientée
- [SheetJS / xlsx](https://sheetjs.com/) `0.18.5` (build `xlsx.mini.min.js`) — lecture des fichiers `.xlsx`
