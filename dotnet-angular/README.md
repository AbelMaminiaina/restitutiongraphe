# Recherche de chemin — C# / Angular

Duplication de la fonctionnalité "recherche de chemin" (`web/path.html` +
`src/restitution/db.py::shortest_path` + `/api/path`) dans une autre pile
technique, avec la même structure et la même base de données SQL Server
(`RestitutionGraphe`, table `dbo.LINE_VIS_EDG`).

```
dotnet-angular/
├── backend/                    # API minimale ASP.NET Core (C#)
│   ├── Program.cs              # routes HTTP — équivalent de src/restitution/api.py
│   └── LineVisEdgRepository.cs # accès SQL + BFS — équivalent de src/restitution/db.py
│
└── frontend/                   # Angular (zoneless, signals) — équivalent de web/path.html + path.js
    └── src/app/
        ├── path-api.service.ts # appel HTTP vers l'API C#
        ├── app.ts               # état (Signals) + rendu Cytoscape
        └── app.html
```

## Différences volontaires avec la version Python/vanilla JS

- **Typage des paramètres SQL** : en Python, un `CAST(? AS VARCHAR(8000))` est
  injecté dans le texte SQL (pyodbc lie les `str` en NVARCHAR par défaut). En
  C#, c'est plus direct : chaque `SqlParameter` est typé explicitement en
  `SqlDbType.VarChar` (voir `AddVarChar` dans `LineVisEdgRepository.cs`) — pas
  besoin de `CAST` textuel, le driver envoie déjà le bon type.
- **État réactif Angular** : ce projet Angular est **zoneless** (pas de
  `zone.js`, comportement par défaut des projets Angular récents). Une
  propriété de classe classique mutée après un `await` ne déclenche pas de
  nouveau rendu — l'état affiché (`bannerText`, `path`...) utilise donc des
  **Signals** (`signal()` / `.set()`), qui déclenchent la réactivité
  automatiquement, avec ou sans zone.js.

## Lancer le tout

```bash
# 1. Backend (par défaut sur http://127.0.0.1:5065)
cd dotnet-angular/backend
dotnet run

# 2. Frontend (par défaut sur http://127.0.0.1:4200)
cd dotnet-angular/frontend
npm install   # première fois seulement
npx ng serve --host 127.0.0.1
```

Puis ouvrir http://127.0.0.1:4200. Le backend doit tourner pour que la
recherche fonctionne (CORS ouvert, aucune configuration supplémentaire
nécessaire). Connexion SQL Server par défaut : `localhost\SQLEXPRESS01` /
base `RestitutionGraphe`, authentification Windows — configurable via les
mêmes variables d'environnement que la version Python
(`RESTITUTION_DB_SERVER`, `RESTITUTION_DB_NAME`).

**Note Windows** : `ng serve` sans `--host` s'est lié uniquement à `[::1]`
(IPv6) dans ce projet, injoignable depuis `127.0.0.1` — d'où le
`--host 127.0.0.1` explicite ci-dessus.
