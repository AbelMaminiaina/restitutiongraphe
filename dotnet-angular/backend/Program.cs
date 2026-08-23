// API minimale ASP.NET Core : sert la recherche de plus court chemin sur
// RestitutionGraphe (table dbo.LINE_VIS_EDG) au frontend Angular.
//
// Équivalent C# de src/restitution/api.py (Python/FastAPI) : mêmes routes,
// même forme de réponse JSON, même logique déléguée à un repository dédié
// (LineVisEdgRepository, équivalent de db.py).
//
// Lancer avec : dotnet run (par défaut sur http://localhost:5080)

using PathFinder.Api;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<LineVisEdgRepository>();

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader());
});

var app = builder.Build();

app.UseCors();

app.MapGet("/api/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/api/path", async (string source, string target, LineVisEdgRepository repo, int maxDepth = 12) =>
{
    var result = await repo.ShortestPathAsync(source, target, Math.Min(maxDepth, 20));

    if (!result.Found)
        return Results.NotFound(new { detail = $"Aucun chemin de '{source}' vers '{target}'." });

    return Results.Ok(new { path = result.Path, found = result.Found });
});

app.Run();
