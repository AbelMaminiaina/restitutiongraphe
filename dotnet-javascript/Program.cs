// ASP.NET Core MVC minimal : ce projet ne contient AUCUNE logique metier.
//
// Son seul role : servir la page du visualiseur de graphe (une vue .cshtml)
// et rendre disponibles, sous l'URL /javascript, les fichiers deja presents
// dans le dossier voisin ../javascript (app.js, style.css, vendor/*.js).
// C'est exactement la meme application que javascript/index.html, mais hebergee
// par un serveur .NET 6.0.
//
// C# 8.0 : pas de top-level statements -> un Program avec un Main classique.
// Aucun async.
//
// Lancer avec : dotnet run
//   -> http://localhost:5186 (voir Properties/launchSettings.json)

using System.IO;

using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;

namespace PathFinder.JavaScriptMvc
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);

            // Le moteur MVC + le moteur de vues Razor (.cshtml).
            builder.Services.AddControllersWithViews();

            var app = builder.Build();

            // --- Fichiers statiques : le dossier ../javascript expose sous /javascript ---
            // ContentRootPath = dossier du projet quand on lance `dotnet run`.
            // On remonte d'un cran pour retomber sur le dossier "javascript" du depot.
            var jsFolder = Path.GetFullPath(
                Path.Combine(app.Environment.ContentRootPath, "..", "javascript"));

            if (Directory.Exists(jsFolder))
            {
                app.UseStaticFiles(new StaticFileOptions
                {
                    FileProvider = new PhysicalFileProvider(jsFolder),
                    RequestPath = "/javascript",
                    // .xlsx n'est pas un type MIME connu par defaut : on l'ajoute
                    // pour que exemple.xlsx puisse aussi etre telecharge si besoin.
                    ContentTypeProvider = BuildContentTypeProvider(),
                });
            }

            // Route MVC par defaut : /{controller=Home}/{action=Index}/{id?}
            // -> sans rien dans l'URL, on tombe sur HomeController.Index.
            app.MapControllerRoute(
                name: "default",
                pattern: "{controller=Home}/{action=Index}/{id?}");

            app.Run();
        }

        // Table des types MIME : celle par defaut + .xlsx.
        private static FileExtensionContentTypeProvider BuildContentTypeProvider()
        {
            var provider = new FileExtensionContentTypeProvider();
            provider.Mappings[".xlsx"] =
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            return provider;
        }
    }
}
