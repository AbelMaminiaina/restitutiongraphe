# Architecture — restitutiongraphe

Visualiseur de graphe orienté : un fichier texte (nœuds + arêtes) devient
soit une image (via le CLI Python), soit un graphe interactif dans le
navigateur (via `web/`).

## 1. Vue d'ensemble

```
restitutiondonnees/
├── exemple.txt                     # fichier de données (format NOEUDS/ARETES)
├── pyproject.toml                  # dépendances Python (networkx, matplotlib, extra "api")
├── scripts/
│   └── seed_sqlserver.py           # génère 100k nœuds + arêtes dans SQL Server
│
├── web/                            # visualisation navigateur, autonome (aucun serveur requis)
│   ├── index.html / app.js         # graphe interactif (fichier .txt ou base)
│   ├── nodes.html / nodes.js       # liste paginée des nœuds + transformations
│   ├── node.html / node.js         # détail d'un nœud : successeurs/prédécesseurs
│   └── style.css
│
├── src/restitution/
│   ├── cli.py                      # Controller CLI — point d'entrée ligne de commande
│   ├── api.py                      # Controller API — FastAPI, sert des sous-graphes
│   ├── db.py                       # Model DB — accès SQL Server (recherche/voisinage/BFS)
│   ├── models/
│   │   └── graph.py                # Model fichier — GraphModel : parsing + validation
│   └── views/
│       └── image_view.py           # View — GraphModel -> PNG/SVG/PDF
│
└── tests/
    └── test_graph_model.py
```

Le projet suit une architecture **MVC** :

- **Model** (`models/graph.py`) — la seule source de vérité métier. Il sait
  lire le format texte et construire un graphe. Il ne connaît ni matplotlib
  ni la ligne de commande.
- **View** (`views/image_view.py`) — transforme un `GraphModel` en image.
  Une vue ne modifie jamais le modèle, elle le *présente*.
- **Controller** (`cli.py`) — reçoit l'entrée (arguments de la ligne de
  commande), appelle le Model puis la View. Aucune logique métier ici.

Le frontend web (`web/`) est un **client totalement indépendant** : il ne
lance pas Python, ne fait aucun appel réseau. Il réimplémente le parsing en
JavaScript (miroir de `GraphModel`) car ouvrir un simple fichier `.html`
dans le navigateur ne peut pas exécuter de code Python.

## 2. Générer un graphe

### Format du fichier texte

```
NOEUDS
A
B
C
ARETES
A B
B C
A C
```

- Section `NOEUDS` : un identifiant par ligne.
- Section `ARETES` : `source cible` par ligne → une arête orientée
  source → cible.
- Lignes vides et lignes commençant par `#` ignorées.
- En-têtes insensibles à la casse/accents (`NOEUDS`/`NŒUDS`,
  `ARETES`/`ARÊTES`).

### Option A — image (CLI Python)

```bash
python -m restitution.cli exemple.txt -o graphe.png
```

`GraphModel.from_file()` parse le fichier → `render_to_file()` calcule un
**layout hiérarchique par niveaux** (façon Sugiyama/dagre, fait maison sans
dépendance Graphviz) : les nœuds sont rangés par niveau selon le sens des
arêtes ; les cycles sont détectés par DFS (arêtes de "retour") et exclus du
calcul des niveaux, mais restent dessinés. La taille de la figure et des
nœuds s'adapte automatiquement au nombre de nœuds pour rester lisible sur
de gros graphes.

### Option B — interactif (navigateur)

Ouvrir `web/index.html` directement (double-clic, pas de serveur requis),
puis glisser un `.txt` ou cliquer "Choisir un fichier". `app.js` parse le
fichier et l'affiche avec **Cytoscape.js** + le plugin **dagre** (layout
hiérarchique automatique, zoom/pan, sélection de nœuds).

Fonctionnalités additionnelles côté navigateur :
- **Plus court chemin** (BFS, non pondéré) entre deux nœuds du graphe
  chargé — via les menus déroulants ou en cliquant deux nœuds.
- **Restitution du graphe** : densité, composantes connexes, degré
  moyen/max, nœuds isolés, présence de cycle — recalculés à chaque
  chargement, sur le sous-graphe affiché.

## 3bis. Grands volumes — base SQL Server + API

Au-delà de quelques dizaines de milliers de nœuds, tout charger dans le
navigateur ne tient plus (`web/` casse). Le principe : **ne jamais envoyer
le graphe complet au client**, seulement le sous-graphe demandé.

```
SQL Server (RestitutionGraphe : dbo.LINE_VIS_EDG)
        │  pyodbc
        ▼
src/restitution/db.py        — BFS/recherche par paliers, bornés en
                                profondeur et en nombre de nœuds
        │
        ▼
src/restitution/api.py       — FastAPI, endpoints REST (JSON)
        │  fetch()
        ▼
web/app.js (panneau "Base de données")
```

- **Schéma** : une seule table, `dbo.LINE_VIS_EDG(Id, Nodes, Direction,
  NodesLie, Transformation)`. Pas de table de nœuds séparée — un nœud est
  simplement une valeur qui apparaît en colonne `Nodes` ou `NodesLie`.
  Chaque ligne relie `Nodes` à `NodesLie` ; `Direction` (`'predecesseur'`
  ou `'successeur'`) indique le rôle de `Nodes` par rapport à `NodesLie` :
  - `Direction = 'predecesseur'` → `Nodes` précède `NodesLie` → arête
    **Nodes → NodesLie**
  - `Direction = 'successeur'` → `Nodes` suit `NodesLie` → arête
    **NodesLie → Nodes**

  `Nodes` et `NodesLie` sont en `VARCHAR(8000)` (le maximum autorisé par
  SQL Server pour un `VARCHAR` non-`MAX` — `9000` dépasse cette limite et
  est rejeté par le moteur). Deux index composites permettent les
  recherches de voisinage/chemin sans balayage complet : `(Nodes,
  Direction) INCLUDE (NodesLie)` et `(NodesLie, Direction) INCLUDE
  (Nodes)`. `db.py` interroge toujours ces deux colonnes séparément
  (jamais un seul `OR` entre les deux) pour que chaque requête utilise son
  index par une recherche (seek). Limite à connaître : la clé d'un index
  classique est plafonnée à 900 octets par SQL Server — l'insertion d'un
  identifiant réel dépassant cette taille échouerait avec ces index en
  place (avertissement émis à la création de la table).
- **`scripts/seed_sqlserver.py`** génère un jeu de démonstration : 100 000
  nœuds, 2 à 6 arêtes sortantes chacune (~400 000 lignes), avec une
  `Transformation` aléatoire (SELECT/JOIN/FILTER/...), insertion par lots
  avec `fast_executemany`.
- **`src/restitution/db.py`** expose `search_nodes`, `list_nodes` (page de
  nœuds distincts + leurs transformations liées), `node_detail`
  (successeurs/prédécesseurs directs d'un nœud), `neighborhood` (voisinage
  à N sauts, non orienté, plafonné en taille), `shortest_path` (BFS
  dirigé), `global_stats`. Les requêtes de parcours par paliers sont
  découpées par lots de 1000 paramètres (limite SQL Server ~2100/requête)
  car un front de BFS explose vite avec un degré moyen élevé.
- **`src/restitution/api.py`** — `uvicorn restitution.api:app --port 8000
  --app-dir src` — expose ces fonctions en REST (`/api/search`,
  `/api/nodes`, `/api/node`, `/api/neighborhood`, `/api/path`,
  `/api/stats/global`), CORS ouvert pour être appelé depuis `web/` en
  `fetch()`.
- **`web/nodes.html`** liste les nœuds distincts (paginée, recherche par
  sous-chaîne) avec leurs transformations liées ; cliquer une ligne ouvre
  **`web/node.html?id=...`**, qui affiche deux tableaux — prédécesseurs et
  successeurs directs, chacun avec sa transformation — et permet de
  naviguer de nœud en nœud en cliquant les lignes.
- Côté navigateur, un voisinage ou un chemin récupéré depuis l'API est
  injecté dans le **même pipeline de rendu** que le chargement de fichier
  (`renderGraph`, `computeStats`, `runPathSearch`) : aucune duplication de
  logique entre les deux modes de chargement. `app.js` appelle l'API en
  `127.0.0.1` plutôt que `localhost` — sur Windows, la résolution de
  `localhost` essaie d'abord IPv6 (`::1`) avant de retomber sur IPv4, ce
  qui ajoute plusieurs secondes de latence perceptible par requête.

Connexion par défaut : `localhost\SQLEXPRESS01` (authentification
Windows), configurable via les variables d'environnement
`RESTITUTION_DB_SERVER` / `RESTITUTION_DB_NAME`.

## 3. Python — les bases utilisées ici

Ce projet est un bon terrain pour voir ces notions en situation réelle.

**Type hints** (`models/graph.py`)
```python
def from_text(cls, text: str) -> GraphModel:
```
Indique les types attendus/retournés. Ignoré à l'exécution, mais lu par
l'éditeur et les outils d'analyse statique pour détecter des erreurs avant
de lancer le code.

**Classmethods comme constructeurs alternatifs**
```python
class GraphModel:
    def __init__(self, graph=None): ...

    @classmethod
    def from_text(cls, text: str) -> GraphModel: ...

    @classmethod
    def from_file(cls, path) -> GraphModel: ...
```
`@classmethod` donne accès à la classe (`cls`) plutôt qu'à une instance
(`self`). Pratique pour offrir plusieurs façons de construire un objet
(`GraphModel.from_text(...)` vs `GraphModel.from_file(...)`) sans multiplier
les paramètres optionnels dans `__init__`.

**`pathlib.Path` plutôt que des chaînes de caractères**
```python
Path(path).read_text(encoding="utf-8")
```
`Path` représente un chemin de fichier comme objet (portable Windows/Linux,
avec des méthodes comme `.read_text()`, `.exists()`) plutôt que de
manipuler des chaînes brutes.

**`argparse` pour la ligne de commande** (`cli.py`)
```python
parser = argparse.ArgumentParser(...)
parser.add_argument("input", type=Path)
parser.add_argument("-o", "--output", type=Path, default=Path("graphe.png"))
args = parser.parse_args()
```
Déclare les arguments attendus (`input` obligatoire, `-o/--output`
optionnel) ; `argparse` génère automatiquement l'aide (`--help`) et valide
les types.

**Bibliothèque `networkx`** (`models/graph.py`, `views/image_view.py`)
```python
graph = nx.DiGraph()
graph.add_edge(source, target)
nx.topological_sort(dag)
```
`DiGraph` = graphe orienté. `networkx` fournit la structure de données et
des algorithmes de graphe tout faits (tri topologique, parcours...) —
évite de réimplémenter ces structures à la main.

**Docstrings et exceptions explicites**
```python
if graph.number_of_nodes() == 0:
    raise ValueError("Aucun noeud trouvé dans le fichier.")
```
Erreur explicite avec message clair plutôt que laisser une erreur obscure
se produire plus loin dans le code.

## 4. JavaScript — les bases utilisées ici

**`const`/`let`, jamais `var`** (`web/app.js`)
Variables à portée de bloc, pas de comportement surprenant lié au
"hoisting" de `var`.

**Sets pour des recherches rapides**
```javascript
const NODE_HEADERS = new Set(["noeuds", "nœuds", "nodes"]);
NODE_HEADERS.has(header);
```
Un `Set` teste l'appartenance en O(1), plus adapté qu'un tableau (`Array`)
pour ce genre de vérification.

**Destructuring**
```javascript
const [source, target] = parts;
```
Extrait plusieurs valeurs d'un tableau en une ligne.

**Template literals**
```javascript
`${e.source}->${e.target}`
```
Interpolation de chaînes avec `${...}`, plus lisible que la concaténation
`+`.

**API DOM et événements**
```javascript
fileInput.addEventListener("change", (e) => {
  const file = e.target.files?.[0];
  if (file) loadFile(file);
});
```
`addEventListener` réagit aux interactions utilisateur (choix de fichier,
glisser-déposer). `?.` (optional chaining) évite une erreur si
`e.target.files` est vide.

**`FileReader` pour lire un fichier côté client**
```javascript
const reader = new FileReader();
reader.onload = () => { /* reader.result contient le texte */ };
reader.readAsText(file, "utf-8");
```
API navigateur pour lire le contenu d'un fichier choisi par
l'utilisateur — sans jamais envoyer ce fichier à un serveur, tout se passe
localement dans le navigateur.

**Gestion d'erreurs avec `try/catch`**
```javascript
try {
  const data = parseGraphText(String(reader.result));
} catch (err) {
  setHint(err.message, true);
}
```
`parseGraphText` lève une erreur (`throw new Error(...)`) si le format est
invalide ; `catch` l'attrape pour afficher un message à l'utilisateur au
lieu de planter silencieusement.

**Bibliothèque `Cytoscape.js`** (chargée via CDN dans `index.html`)
```javascript
cy = cytoscape({
  container: cyContainer,
  elements,
  style: [...],
  layout: { name: "dagre", rankDir: "TB" },
});
```
Bibliothèque de visualisation de graphes : à partir d'une liste de nœuds/
arêtes (`elements`), elle calcule automatiquement les positions
(`layout: "dagre"` = hiérarchique) et gère zoom/pan/sélection sans code
supplémentaire.

## 5. Lancer le projet

```bash
# Installer les dépendances Python
python -m pip install -e .

# Générer une image
python -m restitution.cli exemple.txt -o graphe.png

# Lancer les tests
python -m pytest tests/ -q

# Visualiser dans le navigateur : ouvrir web/index.html directement

# --- Grands volumes (base SQL Server) ---

# Installer les dépendances de l'API
python -m pip install -e ".[api]"

# Créer/peupler la base (100 000 nœuds, ~400 000 arêtes de démo)
python scripts/seed_sqlserver.py

# Démarrer l'API (nécessaire pour le panneau "Base de données" dans web/)
python -m uvicorn restitution.api:app --port 8000 --app-dir src
```
