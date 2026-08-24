# Restitution de graphe orienté — Python MVC (networkx, sans serveur)

Même fonctionnalité que `web/index.html` (upload d'un fichier `.txt`,
restitution d'un graphe orienté), organisée en MVC, avec `networkx` qui
calcule le graphe initial — parsing, détection de cycle, layout hiérarchique.
Pas de serveur web ici : `export_static.py` génère une page `.html`
autonome, ouvrable directement en double-clic.

```
python-mvc/
├── index.html              # page générée (double-clic, sans serveur) — voir plus bas
├── export_static.py        # Controller (CLI) : génère index.html/graphe.html
├── models/
│   └── graph_model.py      # Model — GraphModel (networkx.DiGraph) : parsing,
│                            #   détection de cycle (DFS), layout hiérarchique
│                            #   (générations topologiques networkx)
├── views/
│   └── graph_view.py       # View — GraphModel -> structure JSON pour Cytoscape
└── static/
    └── style.css
```

(Une première version utilisait Flask + des templates Jinja2 pour servir la
page sur `http://127.0.0.1:5000` — supprimée : elle créait de la confusion
avec `index.html`, généré lui aussi à la racine, mais ouvrable directement.
Il n'y a plus qu'une seule façon d'utiliser ce dossier.)

## Comment ça marche

`export_static.py` lit un `.txt`, construit le graphe avec `GraphModel`
(networkx), calcule les positions hiérarchiques
(`layered_positions()` — DFS pour repérer les arêtes de retour, puis
`nx.topological_sort` sur le graphe acyclique restant pour ranger les nœuds
par niveaux) et écrit un fichier `.html` complet (CSS et données du graphe
intégrés, pas de template externe).

La page générée a un bouton "Choisir un fichier .txt". Comme il n'y a plus
de serveur une fois le fichier ouvert (`file://`), ce bouton parse et met en
page un nouveau fichier **en JavaScript** (mirroir du parsing Python,
layout via le plugin `dagre` plutôt que l'algorithme networkx) — même
compromis que `web/index.html`. Le pied de page indique laquelle des deux
méthodes (networkx au chargement, JS après un upload) a produit le graphe
affiché.

## Utilisation

```bash
python -m pip install -r requirements.txt
python export_static.py exemple.txt -o index.html
```

Puis ouvrir `index.html` directement (double-clic). Pour regénérer avec un
autre fichier ou sous un autre nom :

```bash
python export_static.py ton_fichier.txt -o graphe.html
```
