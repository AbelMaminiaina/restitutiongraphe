# PathFinder + Scan — ASP.NET Core MVC (Razor, SQL Server)

Reprend `dotnet-mvc/` (recherche de plus court chemin sur `dbo.LINE_VIS_EDG`,
vues Razor, aucune API, aucun JavaScript) et y ajoute **quatre algorithmes de
parcours** (BFS bidirectionnel par défaut, Dijkstra, Dijkstra bidirectionnel,
A*) et **trois optimisations** du chapitre 11 de la spécification
(`docs/Specification-fonctionnelle-PathFinder-CSharp.docx`) : § 11.4
composantes faibles, § 11.5 condensation SCC, § 11.7 graphe en mémoire.

**Cible imposée** : C# 8.0 / .NET 7.0, sans `async`/`await`. `ImplicitUsings`
désactivé ; pas de `record`, ni namespaces à portée de fichier, ni collection
expressions `[]`. `Microsoft.Data.SqlClient` 5.2.2.

Documents : `../docs/Specification-fonctionnelle-dotnet-new-scan.docx` (conception
détaillée), `../docs/algorithmes-chemin.md` (comparatif des 4 algorithmes),
`../docs/PathFinder-essentiel.pptx` (résumé en diapos).

## Source des données — aucune base requise

L'application marche sur **n'importe quel poste**, sans SQL Server ni aucun
script à exécuter. Au démarrage, `GraphDataProvider` choisit la source :

| `Data:Source` (ou env `RESTITUTION_DATA_SOURCE`) | Comportement |
|---|---|
| `auto` (défaut) | sonde `.\SQLEXPRESS01` / `RestitutionGraphe` + table `LINE_VIS_EDG` (timeout 3 s). Joignable → **SQL**. Sinon → **graphe généré**. |
| `sql` | force SQL Server (échoue si absent) |
| `generated` | force le **graphe généré en mémoire** — `Data:GeneratedNodes` nœuds (défaut 5 000), 2 à 6 arêtes chacun, transformations aléatoires, **graine fixe** ⇒ exactement le même graphe partout. Aucune base. |

En mode graphe généré, les pré-calculs § 11.4 / § 11.5 (qui écrivent des tables
SQL) sont désactivés — inutiles sur un petit graphe où toute recherche est déjà
sous la milliseconde. Tout le reste fonctionne à l'identique.

## Cœur PathFinder — les fichiers essentiels

Si l'on ne s'intéresse qu'à la recherche de chemin (en ignorant le scan
§ 11.4/11.5 et la galerie `/Graphes`), voici le strict nécessaire.

### 1. Mise en mémoire des données

| Fichier | Rôle |
|---|---|
| `Services/GraphDataProvider.cs` | choisit la source (SQL ou généré) et expose `StreamAllDirectedEdges()` / `DescribePath()` sans que les autres classes sachent d'où viennent les arêtes |
| `Models/LineVisEdgRepository.cs` → `StreamAllDirectedEdges()` | mode SQL : l'unique `SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG` (sans `WHERE`), lu en flux ; + `CanConnect()` (sonde) |
| `Services/GeneratedGraphData.cs` | mode généré : construit le graphe de démo en RAM (graine fixe), fournit les arêtes et les transformations |
| `Services/DirectedGraph.cs` → `Build(...)` | consomme le flux d'arêtes et construit la structure **CSR** en RAM (successeurs / prédécesseurs indexés par entier) |
| `Services/InMemoryGraphService.cs` (`Reload()` + `EnsureLoaded()` + `GraphPreloader`) | lance `Build` sur un **Thread d'arrière-plan** au démarrage ; `EnsureLoaded()` le construit sous verrou si une recherche arrive avant ; garde le graphe (`_graph`, volatile) et son statut |

### 2. Le pathfinder (`.cs`)

| Fichier | Rôle |
|---|---|
| `Services/DirectedGraph.cs` | les 4 algorithmes : `ShortestPath` (BFS bi), `ShortestPathDijkstra`, `ShortestPathDijkstraBi`, `ShortestPathAStar` + `PrepareLandmarks` / `Heuristic` (ALT) |
| `Services/InMemoryGraphService.cs` | `EnsureLoaded()` + passe-plats `ShortestPath*` |
| `Controllers/HomeController.cs` | route `/` : normalise `?algo=`, `EnsureLoaded()`, aiguille vers la bonne méthode, cache le résultat 5 min par `(algo, source, cible, maxDepth)` |
| `Models/PathViewModel.cs` | données passées à la vue (`Path`, `Edges`, `AlgoLabel`, `SourceDescription`, drapeaux `SolvedInMemory` / `FromCache` / `Skipped*`) |
| `Services/GraphDataProvider.cs` → `DescribePath()` | relit la `Transformation` de chaque arête du chemin trouvé (via SQL ou via le graphe généré) |

### 3. Front minimal (HTML rendu côté serveur, aucun JavaScript)

| Fichier | Rôle |
|---|---|
| `Views/Home/Index.cshtml` | le formulaire (`source`, `cible`, menu `algo`) + l'affichage du résultat (bannière, chaîne de nœuds, tableau des transformations) |
| `Views/Shared/_Layout.cshtml` | gabarit commun (en-tête, navigation) |
| `wwwroot/css/site.css` | feuille de style unique |

`Program.cs` câble le tout (voir plus bas). Le reste des fichiers concerne les
pré-calculs et la galerie.

## § 11.4 — composantes connexes faibles (le « scan »)

Un balayage complet de `LINE_VIS_EDG`, **une seule fois**, étiquette chaque
nœud d'un identifiant d'« île » (sens des arêtes ignoré, via Union-Find)
dans `dbo.NODE_COMPONENT`. Deux nœuds sur des îles différentes ⇒ **« aucun
chemin » en O(1)**, sans BFS. Ne tranche PAS le cas « même île ».

## § 11.5 — condensation SCC (verdict exact)

Calcule les composantes **fortement** connexes (algorithme de Kosaraju,
2 parcours en profondeur itératifs, O(n+m)), les contracte en super-nœuds →
un petit **graphe condensé** (toujours un DAG) dans `dbo.NODE_SCC` et
`dbo.SCC_EDGE`. Existence d'un chemin orienté u→v ⟺ `SccId(v)` atteignable
depuis `SccId(u)` dans le graphe condensé (BFS sur quelques milliers de
super-nœuds, pas 100 000). Donne un **OUI/NON exact sans BFS** sur le
graphe d'origine.

Mesuré sur la base de démo : 100 000 nœuds → **1 979 SCC** (dont une géante
de 98 028 nœuds), graphe condensé de 1 979 super-nœuds / 2 144 arêtes.

Exemple que le § 11.4 seul ne pouvait pas trancher : `X5 → X1` (même île,
mais aucun chemin en respectant le sens) → la condensation SCC répond
« aucun chemin » **instantanément**.

## § 11.7 — graphe orienté en mémoire

Au démarrage, tout le graphe est chargé en RAM en tableaux **CSR**
(Compressed Sparse Row, indexés par entier : ~12 Mo pour 100 000 nœuds,
~80 Mo pour 2 M). Les **quatre algorithmes** de parcours s'exécutent alors
**entièrement en mémoire** — plus aucun aller-retour SQL par palier.

Mesuré (mode SQL, jeu de démo, hors cache) : chargement CSR ~**1,2–2,0 s** +
6 repères ALT ~**0,4 s** ; recherche de **0,06 ms** (BFS bidirectionnel) à
~**20 ms** (Dijkstra) selon l'algorithme. En mode graphe généré (5 000 nœuds) :
chargement ~**35 ms**, recherche sous la milliseconde. Chargé sur un Thread
d'arrière-plan ; `EnsureLoaded()` le construit à la première recherche s'il
n'est pas prêt. Détail : `../docs/algorithmes-chemin.md`.

## Les quatre algorithmes de parcours

Sélection par le menu **Algorithme** du formulaire `/` (`?algo=…`). Les arêtes
ayant toutes le même poids (1), les quatre rendent le **même chemin** (à un
ex æquo près) ; seule la durée diffère.

| `algo=` | Nom | Correct si poids ≠ 1 | Chemin existant (méd.) | Aucun chemin |
|---|---|---|---|---|
| `bfs` | BFS bidirectionnel (défaut) | non | **0,06 ms** | 22,8 ms |
| `dijkstra` | Dijkstra | oui | 22,4 ms | 61,8 ms |
| `dijkstra-bi` | Dijkstra bidirectionnel | oui | **0,37 ms** | **0,001 ms** |
| `astar` | A* (heuristique ALT, 6 repères) | oui | 8,3 ms | 103,7 ms |

Verdict : garder le **BFS bidirectionnel** tant que les poids valent 1 ; passer
au **Dijkstra bidirectionnel** si `Transformation` devient un coût réel. A* ne
se rentabilise que sur un graphe à structure exploitable.

## Ordre des vérifications (HomeController)

1. *(mode SQL seulement)* **condensation SCC** (§ 11.5, si calculée) — exacte.
   `NotReachable` → « aucun chemin », sans parcours.
2. *(mode SQL seulement)* sinon → **composantes faibles** (§ 11.4, si calculées).
   Îles différentes → « aucun chemin », sans parcours.
3. cache applicatif (5 min).
4. sinon → `EnsureLoaded()` puis **l'algorithme choisi** (`?algo=`), toujours
   sur le **graphe en mémoire** (§ 11.7).

```
dotnet-new-scan/
├── Program.cs                        # câblage : DI, AddHostedService<GraphPreloader>, AddMemoryCache
├── appsettings.json                  # Data:Source (auto|sql|generated), Data:GeneratedNodes, Database:*
├── Controllers/
│   ├── HomeController.cs             # /  — (mode SQL) SCC + composantes, puis l'algo choisi en mémoire
│   ├── ScanController.cs             # /Scan, POST /Scan/{Run,RunScc,ReloadGraph}
│   └── GraphesController.cs          # /Graphes — galerie des types de graphes
├── Models/
│   ├── LineVisEdgRepository.cs       # mode SQL : CanConnect, DescribePath, StreamAllEdges, StreamAllDirectedEdges
│   ├── NodeComponentRepository.cs    # SQL : dbo.NODE_COMPONENT   (§ 11.4)
│   ├── SccRepository.cs              # SQL : dbo.NODE_SCC + dbo.SCC_EDGE   (§ 11.5)
│   ├── PathViewModel.cs              # Path, Edges, Algo/AlgoLabel, SourceDescription, SolvedInMemory, ...
│   ├── ScanPageViewModel.cs
│   └── GraphSample(s).cs             # catalogue des graphes d'exemple (/Graphes)
├── Services/
│   ├── GraphDataProvider.cs          # choisit la source (SQL / généré) ; StreamAll*, DescribePath
│   ├── GeneratedGraphData.cs         # graphe de démo généré en mémoire (graine fixe)
│   ├── DirectedGraph.cs              # § 11.7 — CSR + 4 algos (BFS bi, Dijkstra, Dijkstra bi, A*/ALT)
│   ├── InMemoryGraphService.cs       # § 11.7 — Reload / EnsureLoaded / GraphPreloader (Thread)
│   ├── GraphScanService.cs           # § 11.4 — Union-Find, AUCUNE requête SQL
│   ├── SccCondensationService.cs     # § 11.5 — Kosaraju + graphe condensé, AUCUNE requête SQL
│   └── SvgGraphRenderer.cs           # GraphSample -> SVG (/Graphes)
└── Views/Home, Views/Scan, Views/Graphes, wwwroot/css/site.css
```

## Routes

| Route | Rôle |
|---|---|
| `GET /` | recherche de chemin (form GET, `?source=&target=&algo=`). Pré-calculs consultés avant le parcours. |
| `GET /Scan` | statut des trois pré-calculs (§ 11.4 / 11.5 / 11.7) |
| `POST /Scan/Run` | *(mode SQL)* (re)calcule les composantes faibles → `dbo.NODE_COMPONENT` |
| `POST /Scan/RunScc` | *(mode SQL)* (re)calcule la condensation SCC → `dbo.NODE_SCC`, `dbo.SCC_EDGE` |
| `POST /Scan/ReloadGraph` | (re)charge le graphe orienté en mémoire (§ 11.7), tous modes |
| `GET /Graphes` | galerie illustrée des types de graphes (SVG serveur) |

Aucune route ne renvoie du JSON. Les `POST /Scan/{Run,RunScc}` en mode graphe
généré répondent par un message « réservé au mode SQL ».

## Séparation service / repository

Les services `GraphScanService` et `SccCondensationService` ne contiennent
**que l'algorithme** (Union-Find, Kosaraju, BFS sur le graphe condensé). Ils
ne référencent ni `SqlConnection` ni `SqlCommand`. Toutes les requêtes SQL
sont dans les repositories :

| Service (0 SQL) | Source des arêtes / persistance |
|---|---|
| `GraphScanService` — Union-Find, verdict | `GraphDataProvider.StreamAllEdges()` · `NodeComponentRepository` |
| `SccCondensationService` — Kosaraju, graphe condensé | `GraphDataProvider.StreamAllDirectedEdges()` · `SccRepository` |
| `InMemoryGraphService` / `DirectedGraph` — CSR + 4 algos en mémoire | `GraphDataProvider.StreamAllDirectedEdges()` |

`GraphDataProvider` masque la source : en mode SQL il délègue à
`LineVisEdgRepository` (seul à contenir `SqlConnection` / `SqlCommand`), en mode
généré à `GeneratedGraphData`.

## Tables créées

```sql
dbo.NODE_COMPONENT (NodeId VARCHAR(450) PK, ComponentId INT)   -- § 11.4
dbo.NODE_SCC       (NodeId VARCHAR(450) PK, SccId INT)         -- § 11.5
dbo.SCC_EDGE       (FromScc INT, ToScc INT, PK (FromScc, ToScc)) -- § 11.5, le DAG condensé
```

Ces tables ne concernent que le mode SQL. Chaque `Run*` fait `DROP` + `CREATE` +
`SqlBulkCopy` (idempotent). Nécessite les droits `CREATE TABLE` / `DROP TABLE`
(l'utilisateur Windows par défaut de SQLEXPRESS les a).

## Lancer

```bash
cd dotnet-new-scan
dotnet run
```

→ http://localhost:5185 — **aucun prérequis** : si SQL Server n'est pas là,
l'application démarre sur le graphe généré (5 000 nœuds, même graphe partout).
Les nœuds s'appellent `N1`..`N5000` ; exemple : `/?source=N1&target=N2500`.

### Avec la vraie base SQL

Rien à faire si `.\SQLEXPRESS01` / `RestitutionGraphe` (table `LINE_VIS_EDG`
peuplée) est joignable : le mode `auto` la détecte. Puis, pour activer les
pré-calculs :

1. Ouvrir **/Scan** et lancer les deux pré-calculs (une fois).
2. Chercher un chemin sur **/**. Exemples :

| Recherche | Verdict |
|---|---|
| `X5 → X1` | condensation SCC : aucun chemin (que le § 11.4 ne pouvait pas trancher) |
| `X1 → X5` | SCC : atteignable → parcours → `X1→X2→X3→X4→X5` |
| `/?source=N1&target=N500&algo=dijkstra-bi` | force l'algorithme via l'URL |

### Configuration

| Clé (`appsettings.json`) / variable d'environnement | Défaut |
|---|---|
| `Data:Source` / `RESTITUTION_DATA_SOURCE` — `auto` \| `sql` \| `generated` | `auto` |
| `Data:GeneratedNodes` — taille du graphe généré | `5000` |
| `Database:Server` / `RESTITUTION_DB_SERVER` | `.\SQLEXPRESS01` |
| `Database:Name` / `RESTITUTION_DB_NAME` | `RestitutionGraphe` |

Authentification Windows (`Trusted_Connection`).
