# Recherche de chemin — C# MVC + Angular (projet unique)

Même fonctionnalité que `dotnet-angular/` (recherche de chemin sur
`LINE_VIS_EDG`, même BFS bidirectionnel), mais organisée différemment :
**un seul projet** ASP.NET Core, structuré en MVC, qui sert lui-même les
fichiers compilés d'Angular. Pas de séparation backend/frontend au
runtime — un seul process, un seul port.

```
dotnet-angular-mvc/
├── PathFinder.Mvc.csproj
├── Program.cs                      # Controllers + fichiers statiques (wwwroot/)
├── Controllers/
│   ├── PathController.cs           # Controller — /api/path (+ cache applicatif)
│   └── HealthController.cs         # Controller — /api/health
├── Models/
│   └── LineVisEdgRepository.cs     # Model — accès SQL + BFS bidirectionnel
├── ClientApp/                      # View — projet Angular (source)
│   └── angular.json                # outputPath configuré vers ../wwwroot
└── wwwroot/                        # généré par `ng build` (ClientApp -> ../wwwroot), pas committé
```

Le découpage `Controllers/` (Controller) / `Models/` (Model) / `ClientApp/`
(View, au sens large — c'est Angular qui gère l'affichage) reprend le
vocabulaire MVC déjà utilisé pour décrire le projet Python dans
`ARCHITECTURE.md`.

## Différence avec `dotnet-angular/`

- Là-bas : deux projets séparés (`backend/` + `frontend/`), deux process,
  deux ports, CORS nécessaire pour qu'Angular (port 4200) appelle l'API
  (port 5065).
- Ici : un seul projet, un seul process (`dotnet run`), un seul port —
  Angular est compilé une fois (`ng build`) dans `wwwroot/`, servi en
  statique par le même serveur ASP.NET Core qui expose aussi l'API. Pas de
  CORS, pas d'URL absolue côté client (`path-api.service.ts` utilise une
  URL relative `/api/path`).

## Lancer

```bash
# 1. Construire Angular (uniquement après un changement dans ClientApp/)
cd dotnet-angular-mvc/ClientApp
npm install   # première fois seulement
npx ng build

# 2. Lancer l'appli (sert l'API ET la page Angular sur le même port)
cd ..
dotnet run
```

Puis ouvrir `http://127.0.0.1:5141` (port fixé dans
`Properties/launchSettings.json`). Connexion SQL Server par défaut :
`localhost\SQLEXPRESS01` / base `RestitutionGraphe`, authentification
Windows — configurable via `RESTITUTION_DB_SERVER` / `RESTITUTION_DB_NAME`
(mêmes variables que les autres versions).

Contrairement à `dotnet-angular/frontend`, pas besoin de lancer `ng serve`
en parallèle pour utiliser l'application — seul `dotnet run` suffit une
fois Angular construit. `ng serve` reste utile pour itérer avec rechargement
à chaud pendant le développement du frontend (nécessite alors un
`proxy.conf.json` pointant vers l'API, non fourni ici).
