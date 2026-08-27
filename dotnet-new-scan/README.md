# PathFinder + Scan — ASP.NET Core MVC (Razor, SQL Server)

Reprend `dotnet-mvc/` (recherche de plus court chemin par **BFS
bidirectionnel** sur `dbo.LINE_VIS_EDG`, vues Razor, aucune API, aucun
JavaScript) et y ajoute **deux pré-calculs** du chapitre 11 de la
spécification (`docs/Specification-fonctionnelle-PathFinder-CSharp.docx`).

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

## Ordre des vérifications (HomeController)

1. **condensation SCC** (§ 11.5) — exacte. `NotReachable` → « aucun chemin »,
   sans BFS. `Reachable` → le chemin existe ; on lance quand même le BFS pour
   en afficher le tracé.
2. sinon (SCC pas calculée) → **composantes faibles** (§ 11.4). Îles
   différentes → « aucun chemin », sans BFS.
3. sinon → **BFS bidirectionnel** sur `LINE_VIS_EDG` (comme `dotnet-mvc/`).

```
dotnet-new-scan/
├── Program.cs                        # + AddSingleton des 2 services et 3 repositories
├── Controllers/
│   ├── HomeController.cs             # /  — SCC puis composantes faibles, AVANT le BFS
│   ├── ScanController.cs             # /Scan, POST /Scan/Run, POST /Scan/RunScc
│   └── GraphesController.cs          # /Graphes — galerie des types de graphes
├── Models/
│   ├── LineVisEdgRepository.cs       # SQL : BFS, DescribePath, StreamAllEdges, StreamAllDirectedEdges
│   ├── NodeComponentRepository.cs    # SQL : dbo.NODE_COMPONENT   (§ 11.4)
│   ├── SccRepository.cs              # SQL : dbo.NODE_SCC + dbo.SCC_EDGE   (§ 11.5)
│   ├── PathViewModel.cs              # + SkippedByScc, SkippedByScan, FromCache
│   └── ScanPageViewModel.cs
├── Services/
│   ├── GraphScanService.cs           # § 11.4 — Union-Find, AUCUNE requête SQL
│   ├── SccCondensationService.cs     # § 11.5 — Kosaraju + graphe condensé, AUCUNE requête SQL
│   └── SvgGraphRenderer.cs
└── Views/Home, Views/Scan, Views/Graphes, wwwroot/css/site.css
```

## Routes

| Route | Rôle |
|---|---|
| `GET /` | recherche de chemin (form GET). Pré-calculs consultés avant le BFS. |
| `GET /Scan` | statut des deux pré-calculs |
| `POST /Scan/Run` | (re)calcule les composantes faibles → `dbo.NODE_COMPONENT` |
| `POST /Scan/RunScc` | (re)calcule la condensation SCC → `dbo.NODE_SCC`, `dbo.SCC_EDGE` |
| `GET /Graphes` | galerie illustrée des types de graphes (SVG serveur) |

Aucune route ne renvoie du JSON.

## Séparation service / repository

Les services `GraphScanService` et `SccCondensationService` ne contiennent
**que l'algorithme** (Union-Find, Kosaraju, BFS sur le graphe condensé). Ils
ne référencent ni `SqlConnection` ni `SqlCommand`. Toutes les requêtes SQL
sont dans les repositories :

| Service (0 SQL) | Repository (tout le SQL) |
|---|---|
| `GraphScanService` — Union-Find, verdict | `LineVisEdgRepository.StreamAllEdges()` · `NodeComponentRepository` (ReplaceAll, GetComponentIds) |
| `SccCondensationService` — Kosaraju, graphe condensé, BFS condensé | `LineVisEdgRepository.StreamAllDirectedEdges()` · `SccRepository` (ReplaceAll, GetSccIds, LoadCondensedAdjacency) |

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
| `N1 → X1` | condensation SCC : aucun chemin (exact, sans BFS) |
| `X5 → X1` | condensation SCC : aucun chemin (que le § 11.4 ne pouvait pas trancher) |
| `X1 → X5` | SCC : atteignable → BFS → `X1→X2→X3→X4→X5` |
| `N1 → N500` | même SCC géante → BFS → chemin |

Connexion SQL par défaut : `localhost\SQLEXPRESS01` / `RestitutionGraphe`,
authentification Windows — surchargeable par `RESTITUTION_DB_SERVER` /
`RESTITUTION_DB_NAME`.
