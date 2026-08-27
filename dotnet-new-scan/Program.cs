// ASP.NET Core MVC « classique » : tout l'affichage est rendu côté serveur
// avec des vues Razor (.cshtml). AUCUN JavaScript, aucun projet front, aucune
// API JSON.
//
// Ce projet reprend dotnet-mvc/ (recherche de plus court chemin par BFS
// bidirectionnel sur dbo.LINE_VIS_EDG) et y ajoute le SCAN décrit au
// chapitre 11 de la spécification : un balayage complet de la table, une
// seule fois, qui étiquette chaque nœud d'un identifiant de composante
// connexe (dbo.NODE_COMPONENT). La recherche d'existence commence alors par
// une comparaison O(1) : composantes différentes -> « aucun chemin »
// immédiat, sans lancer de BFS.
//
// Lancer avec : dotnet run  (port par défaut : http://localhost:5185, voir
// Properties/launchSettings.json)

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

var builder = WebApplication.CreateBuilder(args);

// AddControllersWithViews : le moteur MVC + le moteur de vues Razor.
builder.Services.AddControllersWithViews();

// Les Models d'accès aux données : une seule instance partagée chacun (ils
// ne gardent aucun état mutable, juste la chaîne de connexion).
builder.Services.AddSingleton<LineVisEdgRepository>();       // dbo.LINE_VIS_EDG
builder.Services.AddSingleton<NodeComponentRepository>();    // dbo.NODE_COMPONENT (§ 11.4)
builder.Services.AddSingleton<SccRepository>();              // dbo.NODE_SCC + dbo.SCC_EDGE (§ 11.5)

// Constructeur d'images SVG pour la galerie « Types de graphes » (sans état).
builder.Services.AddSingleton<SvgGraphRenderer>();

// Services des pré-calculs : singletons, ils gardent en mémoire le statut du
// dernier calcul (et, pour la condensation, le petit graphe condensé).
builder.Services.AddSingleton<GraphScanService>();          // § 11.4 — composantes faibles
builder.Services.AddSingleton<SccCondensationService>();    // § 11.5 — condensation SCC

// § 11.7 — graphe orienté chargé en mémoire, + chargement en tâche de fond
// au démarrage.
builder.Services.AddSingleton<InMemoryGraphService>();
builder.Services.AddHostedService<GraphPreloader>();

// Cache applicatif pour la recherche de chemin : mémorise le résultat par
// couple (source, cible, maxDepth), y compris les « aucun chemin » (ce sont
// les recherches les plus coûteuses). SizeLimit borne le nombre d'entrées.
builder.Services.AddMemoryCache(options => options.SizeLimit = 10_000);

var app = builder.Build();

app.UseStaticFiles(); // sert wwwroot/ (la feuille de style site.css)

// Route MVC par défaut : /{controller=Home}/{action=Index}/{id?}
// -> sans rien dans l'URL, on tombe sur HomeController.Index.
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
