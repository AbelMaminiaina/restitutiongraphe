// ASP.NET Core MVC « classique » : tout l'affichage est rendu côté serveur
// avec des vues Razor (.cshtml). AUCUN JavaScript, aucun projet front, aucune
// API JSON.
//
// Ce projet reprend dotnet-mvc/ (recherche de plus court chemin) et y ajoute
// le SCAN décrit au chapitre 11 de la spécification, plus trois algorithmes
// supplémentaires (Dijkstra, Dijkstra bidirectionnel, A*) sur le graphe en
// mémoire — voir docs/algorithmes-chemin.md.
//
// C# 8.0 : pas de top-level statements — un Program avec un Main classique.
// C# 8.0 : pas d'async — le préchargement du graphe se fait sur un Thread
// d'arrière-plan (voir GraphPreloader).
//
// Lancer avec : dotnet run  (port par défaut : http://localhost:5185, voir
// Properties/launchSettings.json)

using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using PathFinder.ScanMvc.Models;
using PathFinder.ScanMvc.Services;

namespace PathFinder.ScanMvc
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);

            // AddControllersWithViews : le moteur MVC + le moteur de vues Razor.
            builder.Services.AddControllersWithViews();

            // Les Models d'accès aux données : une seule instance partagée chacun
            // (ils ne gardent aucun état mutable, juste la chaîne de connexion).
            builder.Services.AddSingleton<LineVisEdgRepository>();       // dbo.LINE_VIS_EDG (mode SQL)
            builder.Services.AddSingleton<NodeComponentRepository>();    // dbo.NODE_COMPONENT (§ 11.4, mode SQL)
            builder.Services.AddSingleton<SccRepository>();              // dbo.NODE_SCC + dbo.SCC_EDGE (§ 11.5, mode SQL)

            // Graphe de démonstration généré en mémoire (repli quand SQL Server
            // est absent — aucune base, aucun script à créer). Taille réglable
            // par la clé de configuration Data:GeneratedNodes (défaut 5 000).
            var generatedNodes = builder.Configuration.GetValue("Data:GeneratedNodes", 5000);
            builder.Services.AddSingleton(new GeneratedGraphData(generatedNodes));

            // Décide, au démarrage, d'où viennent les données : SQL Server si
            // joignable, sinon le graphe généré (config Data:Source =
            // auto | sql | generated).
            builder.Services.AddSingleton<GraphDataProvider>();

            // Constructeur d'images SVG pour la galerie « Types de graphes » (sans état).
            builder.Services.AddSingleton<SvgGraphRenderer>();

            // Services des pré-calculs : singletons, ils gardent en mémoire le
            // statut du dernier calcul (et, pour la condensation, le petit graphe
            // condensé).
            builder.Services.AddSingleton<GraphScanService>();          // § 11.4 — composantes faibles
            builder.Services.AddSingleton<SccCondensationService>();    // § 11.5 — condensation SCC

            // § 11.7 — graphe orienté chargé en mémoire (+ repères ALT pour A*),
            // chargement sur un Thread d'arrière-plan au démarrage.
            builder.Services.AddSingleton<InMemoryGraphService>();
            builder.Services.AddHostedService<GraphPreloader>();

            // Cache applicatif pour la recherche de chemin : mémorise le résultat
            // par couple (algo, source, cible, maxDepth), y compris les « aucun
            // chemin ». SizeLimit borne le nombre d'entrées.
            builder.Services.AddMemoryCache(options => options.SizeLimit = 10_000);

            var app = builder.Build();

            app.UseStaticFiles(); // sert wwwroot/ (la feuille de style site.css)

            // Route MVC par défaut : /{controller=Home}/{action=Index}/{id?}
            // -> sans rien dans l'URL, on tombe sur HomeController.Index.
            app.MapControllerRoute(
                name: "default",
                pattern: "{controller=Home}/{action=Index}/{id?}");

            app.Run();
        }
    }
}
