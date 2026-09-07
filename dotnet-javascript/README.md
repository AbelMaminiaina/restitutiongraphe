# dotnet-javascript

Hôte **ASP.NET Core MVC (.NET 6.0)** pour l'application JavaScript de `../javascript`.

Ce projet ne contient **aucune logique métier** : il sert une page (`Views/Home/Index.cshtml`,
copie de `javascript/index.html`) et expose le dossier voisin `../javascript` en fichiers
statiques sous l'URL `/javascript`. Tout le travail (lecture du `.xlsx`, construction du
graphe, rendu Cytoscape, statistiques) est fait **côté navigateur** par
`javascript/app.js`, exactement comme quand on ouvre `javascript/index.html` directement.

## Lancer

```bash
cd dotnet-javascript
dotnet run
```

Puis ouvrir <http://localhost:5186>.

Le dossier `../javascript` (avec `app.js`, `style.css`, `vendor/*.js`) doit exister à côté
de ce dossier — c'est le cas dans le dépôt.

## Utiliser

- **« Charger l'exemple »** : affiche un graphe de démonstration intégré.
- **« Importer un .xlsx »** ou glisser-déposer : charge un fichier Excel
  (colonnes `dta_1..dta_4`, `edg_dir` *(optionnelle)*, `edg_1..edg_4`).
- Fichiers de démonstration des cas limites : `../javascript/exemple-cas-limites.xlsx`,
  `../javascript/exemple-sans-edg_dir.xlsx`.
- Clic sur un nœud → successeurs / prédécesseurs ; menu de disposition ; « Recentrer » ;
  « Exporter PNG ».

## Notes

- **Cible .NET 6.0** : l'appli tourne nativement sur le runtime ASP.NET Core 6.0.x quand
  il est présent. Le *build* utilise un SDK plus récent (9 ou 10) faute de SDK 6 installé.
  `RollForward=LatestMajor` (dans le `.csproj`) autorise, si besoin, l'exécution sur un
  runtime plus récent. En dernier recours : `<TargetFramework>net8.0</TargetFramework>`,
  ou installer le SDK .NET 6.
- **`dotnet publish`** : le chemin `../javascript` est résolu depuis le dossier de travail.
  Pour un déploiement autonome, copier le dossier `javascript/` à côté de l'exécutable
  publié, ou copier `app.js` / `style.css` / `vendor/` dans un `wwwroot/` local.
- Si `javascript/index.html` évolue, répercuter les changements dans
  `Views/Home/Index.cshtml` (le balisage y est dupliqué).
