# javascript/ — Visualiseur de graphe orienté non pondéré

Petite application **100 % navigateur, 100 % hors ligne** (HTML + JavaScript,
aucun serveur, aucune installation, aucun accès internet) qui affiche le graphe
orienté non pondéré décrit dans un fichier texte au format `NOEUDS` / `ARETES`
(comme `exemple.txt`).

## Lancer

Double-cliquez sur **`index.html`** (ou ouvrez-le dans un navigateur).

> Les librairies (cytoscape, dagre) sont stockées **en local** dans `vendor/` —
> rien n'est téléchargé au chargement.

## Utilisation

| Action | Comment |
| --- | --- |
| Charger un fichier | Bouton **« Importer un .txt »** ou **glisser-déposer** le fichier sur la zone centrale |
| Voir la démo | Bouton **« Charger l'exemple »** (contenu de `exemple.txt` intégré au code) |
| Voisins d'un nœud | **Cliquez un nœud** : ses *successeurs* (vert) et *prédécesseurs* (jaune) sont mis en évidence |
| Changer la disposition | Menu **« Mise en page »** (hiérarchique, cercle, forces…) |
| Exporter | Bouton **« Exporter PNG »** |

## Format de fichier attendu

```
NOEUDS
A
B
C
ARETES
A B      <- arête orientée A -> B
B C
```

- Lignes vides et lignes débutant par `#` : ignorées.
- Un nœud cité seulement dans `ARETES` est ajouté automatiquement.

## Partager à des utilisateurs (sans leur donner le code source)

Le dossier **`dist/`** contient une version prête à distribuer :

| Fichier | Rôle |
| --- | --- |
| `graphe.html` | **Un seul fichier autonome** (~660 Ko) : HTML + CSS + JS de l'appli **minifiés** + les librairies, tout intégré. Aucun `.js` lisible à côté, **aucun accès internet** |
| `Ouvrir le graphe.bat` | Windows : double-clic → ouvre `graphe.html` dans le navigateur |
| `Ouvrir le graphe.command` | macOS/Linux : idem (1er lancement : clic droit → Ouvrir) |
| `exemple.txt`, `LISEZ-MOI.txt` | jeu de démo + notice |

**Pour partager** : copiez le dossier `dist/` sur une clé USB, un lecteur réseau
ou un `.zip` par mail. L'utilisateur double-clique le lanceur — aucun outil à
installer, aucune connexion requise.

> À savoir : du JavaScript exécuté dans un navigateur n'est **jamais totalement
> masqué** (`F12` / « afficher le code source » restent possibles). La
> minification le rend seulement illisible sans effort.

### Régénérer `dist/`

```
node build.mjs
```

Nécessite Node.js + accès npm (npx télécharge `terser` au premier appel).
Le build ne télécharge **pas** les librairies : il réutilise celles de `vendor/`.

## Fichiers source

| Fichier | Rôle |
| --- | --- |
| `index.html` | Structure de la page + chargement des librairies locales |
| `style.css` | Thème sombre, mise en page |
| `app.js` | Parsing du `.txt`, rendu cytoscape, statistiques, interactions |
| `build.mjs` | Génère `dist/` (fichier unique autonome minifié + lanceurs) |
| `vendor/` | Librairies (cytoscape, dagre, cytoscape-dagre) copiées depuis jsDelivr |
| `exemple.txt` | Jeu de données de démonstration (5 nœuds, 6 arêtes, contient un cycle) |

## Librairies utilisées

- [Cytoscape.js](https://js.cytoscape.org/) `3.30.2` — rendu et interaction du graphe
- [dagre](https://github.com/dagrejs/dagre) `0.8.5` + [cytoscape-dagre](https://github.com/cytoscape/cytoscape.js-dagre) `2.5.0` — disposition hiérarchique orientée

Pour mettre à jour une librairie : remplacez le fichier dans `vendor/` (même
nom), ajustez les versions ci-dessus, puis `node build.mjs`.
