# javascript/ — Visualiseur de graphe orienté non pondéré

Petite application **100 % navigateur** (HTML + JavaScript, aucun serveur, aucune
installation) qui affiche le graphe orienté non pondéré décrit dans un fichier
texte au format `NOEUDS` / `ARETES` (comme `exemple.txt`).

## Lancer

Double-cliquez sur **`index.html`** (ou ouvrez-le dans un navigateur).

> Les librairies (cytoscape, dagre) sont chargées depuis un CDN : une connexion
> internet est nécessaire au premier chargement.

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

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `index.html` | Structure de la page + chargement des librairies CDN |
| `style.css` | Thème sombre, mise en page |
| `app.js` | Parsing du `.txt`, rendu cytoscape, statistiques, interactions |
| `exemple.txt` | Jeu de données de démonstration (5 nœuds, 6 arêtes, contient un cycle) |

## Librairies utilisées

- [Cytoscape.js](https://js.cytoscape.org/) — rendu et interaction du graphe
- [dagre](https://github.com/dagrejs/dagre) + [cytoscape-dagre](https://github.com/cytoscape/cytoscape.js-dagre) — disposition hiérarchique orientée
