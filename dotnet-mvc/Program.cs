// ASP.NET Core MVC « classique » : tout l'affichage est rendu côté serveur
// avec des vues Razor (.cshtml). Contrairement à dotnet-angular-mvc/, il n'y
// a AUCUN JavaScript et aucun projet front séparé — le navigateur ne reçoit
// que du HTML/CSS déjà calculé. Le graphe du chemin trouvé est dessiné en
// SVG (balisage, pas de script) et détaillé dans un tableau HTML.
//
// Une seule page : le formulaire (source / cible) et son résultat vivent sur
// la même URL « / », le formulaire est soumis en GET (l'URL du résultat est
// donc partageable, ex. /?source=N1&target=N50000).
//
// Lancer avec : dotnet run  (port par défaut : http://localhost:5175, voir
// Properties/launchSettings.json)

using PathFinder.RazorMvc.Models;
using PathFinder.RazorMvc.Services;

var builder = WebApplication.CreateBuilder(args);

// AddControllersWithViews : le moteur MVC + le moteur de vues Razor.
builder.Services.AddControllersWithViews();

// Le Model d'accès aux données : une seule instance partagée (il ne garde
// aucun état mutable, juste la chaîne de connexion).
builder.Services.AddSingleton<LineVisEdgRepository>();

// Constructeur d'images SVG pour la galerie « Types de graphes » (sans état).
builder.Services.AddSingleton<SvgGraphRenderer>();

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
