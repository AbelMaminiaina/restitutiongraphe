// ASP.NET Core MVC + Angular en un seul projet : les Controllers exposent
// l'API (/api/...), et les fichiers compilés d'Angular (ClientApp/, build ->
// wwwroot/) sont servis en statique par ce même process, sur le même port.
// Contrairement à dotnet-angular/ (backend et frontend séparés), pas besoin
// de CORS ici : tout est servi depuis la même origine.
//
// Lancer avec : dotnet run (voir Properties/launchSettings.json pour le port)
// — après avoir construit Angular au moins une fois : cd ClientApp && npm
// install && npx ng build.

using PathFinder.Mvc.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSingleton<LineVisEdgRepository>();
builder.Services.AddMemoryCache(options => options.SizeLimit = 10_000);

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapControllers();
app.MapFallbackToFile("index.html");

app.Run();
