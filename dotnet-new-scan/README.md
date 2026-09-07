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

## Cœur PathFinder — les fichiers essentiels

Si l'on ne s'intéresse qu'à la recherche de chemin (en ignorant le scan
§ 11.4/11.5 et la galerie `/Graphes`), voici le strict nécessaire.

### 1. Mise en mémoire des données

| Fichier | Rôle |
|---|---|
| `Models/LineVisEdgRepository.cs` → `StreamAllDirectedEdges()` | l'unique `SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG` (sans `WHERE`), lu en flux |
| `Services/DirectedGraph.cs` → `Build(...)` | consomme ce flux et construit la structure **CSR** en RAM (successeurs / prédécesseurs indexés par entier) |
| `Services/InMemoryGraphService.cs` (`Reload()` + `GraphPreloader`) | lance `Build` sur un **Thread d'arrière-plan** au démarrage, garde le graphe (`_graph`, volatile) et son statut |

### 2. Le pathfinder (`.cs`)

| Fichier | Rôle |
|---|---|
| `Services/DirectedGraph.cs` | les 4 algorithmes : `ShortestPath` (BFS bi), `ShortestPathDijkstra`, `ShortestPathDijkstraBi`, `ShortestPathAStar` + `PrepareLandmarks` / `Heuristic` (ALT) |
| `Services/InMemoryGraphService.cs` | passe-plats `ShortestPath*` (null si le graphe n'est pas encore chargé) |
| `Controllers/HomeController.cs` | route `/` : normalise `?algo=`, aiguille vers la bonne méthode, cache le résultat 5 min par `(algo, source, cible, maxDepth)` |
| `Models/PathViewModel.cs` | données passées à la vue (`Path`, `Edges`, `AlgoLabel`, drapeaux `SolvedInMemory` / `FromCache` / `Skipped*`) |
| `Models/LineVisEdgRepository.cs` | `ShortestPath` (BFS SQL palier par palier, **repli** si le graphe RAM n'est pas prêt) + `DescribePath` (relit la `Transformation` de chaque arête du chemin trouvé) |

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

Mesuré (jeu de démo, hors cache) : chargement CSR ~**1,2–2,0 s** + 6 repères
ALT ~**0,4 s** ; recherche de **0,06 ms** (BFS bidirectionnel) à ~**20 ms**
(Dijkstra) selon l'algorithme. Chargé sur un Thread d'arrière-plan ; repli
automatique sur le BFS SQL tant qu'il n'est pas prêt. Détail :
`docs/algorithmes-chemin.md`.

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

1. **condensation SCC** (§ 11.5) — exacte. `NotReachable` → « aucun chemin »,
   sans BFS. `Reachable` → le chemin existe ; on lance quand même le BFS pour
   en afficher le tracé.
2. sinon (SCC pas calculée) → **composantes faibles** (§ 11.4). Îles
   différentes → « aucun chemin », sans parcours.
3. sinon → cache applicatif (5 min), puis **l'algorithme choisi** (`?algo=`) —
   sur le **graphe en mémoire** (§ 11.7) s'il est chargé, sinon par requêtes
   SQL palier par palier (comme `dotnet-mvc/`).

```
dotnet-new-scan/
├── Program.cs                        # câblage : AddSingleton des 3 services + 3 repositories,
│                                     #   AddHostedService<GraphPreloader>, AddMemoryCache
├── Controllers/
│   ├── HomeController.cs             # /  — SCC puis composantes faibles, PUIS l'algo choisi
│   ├── ScanController.cs             # /Scan, POST /Scan/{Run,RunScc,ReloadGraph}
│   └── GraphesController.cs          # /Graphes — galerie des types de graphes
├── Models/
│   ├── LineVisEdgRepository.cs       # SQL : BFS de repli, DescribePath, StreamAllEdges, StreamAllDirectedEdges
│   ├── NodeComponentRepository.cs    # SQL : dbo.NODE_COMPONENT   (§ 11.4)
│   ├── SccRepository.cs              # SQL : dbo.NODE_SCC + dbo.SCC_EDGE   (§ 11.5)
│   ├── PathViewModel.cs              # Path, Edges, Algo/AlgoLabel, SolvedInMemory, FromCache, Skipped*
│   ├── ScanPageViewModel.cs
│   └── GraphSample(s).cs             # catalogue des graphes d'exemple (/Graphes)
├── Services/
│   ├── DirectedGraph.cs              # § 11.7 — CSR + 4 algos (BFS bi, Dijkstra, Dijkstra bi, A*/ALT)
│   ├── InMemoryGraphService.cs       # § 11.7 — chargement (Thread), statut, GraphPreloader (IHostedService)
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
| `POST /Scan/Run` | (re)calcule les composantes faibles → `dbo.NODE_COMPONENT` |
| `POST /Scan/RunScc` | (re)calcule la condensation SCC → `dbo.NODE_SCC`, `dbo.SCC_EDGE` |
| `POST /Scan/ReloadGraph` | (re)charge le graphe orienté en mémoire (§ 11.7) |
| `GET /Graphes` | galerie illustrée des types de graphes (SVG serveur) |

Aucune route ne renvoie du JSON.

## Séparation service / repository

Les services `GraphScanService` et `SccCondensationService` ne contiennent
**que l'algorithme** (Union-Find, Kosaraju, BFS sur le graphe condensé). Ils
ne référencent ni `SqlConnection` ni `SqlCommand`. Toutes les requêtes SQL
sont dans les repositories :

| Service (0 SQL) | Repository (tout le SQL) |
|---|---|
| `GraphScanService` — Union-Find, verdict | `LineVisEdgRepository.StreamAllEdges()` · `NodeComponentRepository` |
| `SccCondensationService` — Kosaraju, graphe condensé | `LineVisEdgRepository.StreamAllDirectedEdges()` · `SccRepository` |
| `InMemoryGraphService` / `DirectedGraph` — CSR + 4 algos en mémoire | `LineVisEdgRepository.StreamAllDirectedEdges()` |

## Tables créées

```sql
dbo.NODE_COMPONENT (NodeId VARCHAR(450) PK, ComponentId INT)   -- § 11.4
dbo.NODE_SCC       (NodeId VARCHAR(450) PK, SccId INT)         -- § 11.5
dbo.SCC_EDGE       (FromScc INT, ToScc INT, PK (FromScc, ToScc)) -- § 11.5, le DAG condensé
```

Chaque `Run*` fait `DROP` + `CREATE` + `SqlBulkCopy` (idempotent). Nécessite
les droits `CREATE TABLE` / `DROP TABLE` (l'utilisateur Windows par défaut de
SQLEXPRESS les a).

## Lancer

```bash
cd dotnet-new-scan
dotnet run
```

→ http://localhost:5185

1. Ouvrir **/Scan** et lancer les deux pré-calculs (une fois).
2. Aller sur **/** et chercher un chemin. Exemples (après
   `scripts/seed_disconnected_test.sql` + re-calculs) :

| Recherche | Verdict |
|---|---|
| `N1 → X1` | condensation SCC : aucun chemin (exact, sans parcours) |
| `X5 → X1` | condensation SCC : aucun chemin (que le § 11.4 ne pouvait pas trancher) |
| `X1 → X5` | SCC : atteignable → parcours → `X1→X2→X3→X4→X5` |
| `N1 → N500` | même SCC géante → parcours → chemin |
| `/?source=N1&target=N500&algo=dijkstra-bi` | force l'algorithme via l'URL |

Connexion SQL par défaut : `localhost\SQLEXPRESS01` / `RestitutionGraphe`,
authentification Windows — surchargeable par `RESTITUTION_DB_SERVER` /
`RESTITUTION_DB_NAME`.
