# Recherche de chemin — ASP.NET Core MVC (Razor, sans JavaScript)

Même fonctionnalité que `dotnet-angular-mvc/` (recherche du plus court
chemin sur `LINE_VIS_EDG`, même BFS bidirectionnel), mais **tout l'affichage
est rendu côté serveur** avec des vues Razor (`.cshtml`).

- **Aucun JavaScript**, aucun projet frontend, aucun `npm`.
- Le navigateur ne reçoit que du HTML + une feuille de style CSS.
- Le formulaire est un `<form method="get">` classique : la page se recharge
  avec `?source=...&target=...` dans l'URL (résultat partageable).
- Le résultat est affiché sous deux formes : la **chaîne des nœuds**
  (`N1 → N2 → N3`) et un **tableau détaillé** (une ligne par arête, avec la
  `Transformation` lue dans `LINE_VIS_EDG`).

```
dotnet-mvc/
├── PathFinder.RazorMvc.csproj
├── Program.cs                        # AddControllersWithViews + route MVC par défaut
├── Controllers/
│   ├── HomeController.cs             # /  — formulaire + résultat de recherche
│   └── GraphesController.cs          # /Graphes — galerie des types de graphes (images SVG)
├── Models/
│   ├── LineVisEdgRepository.cs       # accès SQL + BFS bidirectionnel + DescribePath()
│   ├── PathViewModel.cs              # données passées à la vue de recherche
│   ├── GraphSample.cs                # un graphe d'exemple (nœuds, arêtes, options)
│   └── GraphSamples.cs               # le catalogue des types de graphes
├── Services/
│   └── SvgGraphRenderer.cs           # construit l'image SVG d'un graphe (sans dépendance)
├── Views/
│   ├── _ViewImports.cshtml
│   ├── _ViewStart.cshtml
│   ├── Shared/_Layout.cshtml
│   ├── Home/Index.cshtml             # rendu recherche (chaîne de nœuds + tableau)
│   └── Graphes/{Index,Build}.cshtml  # galerie + page de génération des fichiers
└── wwwroot/
    ├── css/site.css                  # toute la présentation
    └── img/graphes/                  # SVG écrits par /Graphes/Build (non committé)
```

## Deux pages

| Route | Contenu |
|---|---|
| `GET /` | Recherche de chemin : formulaire (`method="get"`), puis chaîne de nœuds + tableau détaillé (une ligne par arête, avec la `Transformation`). |
| `GET /Graphes` | Galerie des types de graphes : connexe, non connexe, complet, compact, creux, non pondéré, pondéré, orienté (DAG), cyclique, arbre — une image SVG par type. |
| `GET /Graphes/Image/{id}` | L'image SVG d'un type (`image/svg+xml`), construite à la volée par `SvgGraphRenderer`. |
| `GET /Graphes/Build` | Écrit tous les SVG dans `wwwroot/img/graphes/`. |

Aucune de ces routes ne renvoie du JSON : ce ne sont que des pages HTML et,
pour `/Graphes/Image`, une image. `SvgGraphRenderer` produit du **SVG**
(balisage), pas du JavaScript.

## Différences avec `dotnet-angular-mvc/`

| | `dotnet-angular-mvc/` | `dotnet-mvc/` (ici) |
|---|---|---|
| Affichage | Angular + Cytoscape (JavaScript) | Vues Razor, HTML/CSS uniquement |
| API | `/api/path`, `/api/health` (JSON) | aucune — que des pages HTML |
| Build front | `npm install` + `ng build` | rien (pas de front) |
| Requête | `fetch` AJAX | rechargement de page (`GET`) |
| Cœur métier | `LineVisEdgRepository` (BFS bidi) | identique, + `DescribePath()` |

## Lancer

```bash
cd dotnet-mvc
dotnet run
```

Puis ouvrir `http://localhost:5175` (port fixé dans
`Properties/launchSettings.json`).

Connexion SQL Server par défaut : `localhost\SQLEXPRESS01` / base
`RestitutionGraphe`, authentification Windows — configurable via
`RESTITUTION_DB_SERVER` / `RESTITUTION_DB_NAME` (mêmes variables que les
autres versions).

## Exemple d'URL

```
http://localhost:5175/?source=N1&target=N50000
```
