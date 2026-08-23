// API minimale ASP.NET Core : sert la recherche de plus court chemin sur
// RestitutionGraphe (table dbo.LINE_VIS_EDG) au frontend Angular.
//
// Équivalent C# de src/restitution/api.py (Python/FastAPI) : mêmes routes,
// même forme de réponse JSON, même logique déléguée à un repository dédié
// (LineVisEdgRepository, équivalent de db.py).
//
// Lancer avec : dotnet run (par défaut sur http://localhost:5065, voir
// Properties/launchSettings.json)

using Microsoft.Extensions.Caching.Memory;
using PathFinder.Api;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<LineVisEdgRepository>();

// Cache applicatif pour /api/path : mémorise le résultat par couple
// (source, cible, maxDepth), y compris les "aucun chemin" (ce sont
// justement les recherches les plus coûteuses, celles qui vont au bout du
// plafond des 30 000 nœuds par sens). SizeLimit borne le nombre d'entrées
// pour éviter une croissance illimitée ; le cache SQL Server (buffer pool)
// continue de faire son travail indépendamment de celui-ci.
builder.Services.AddMemoryCache(options => options.SizeLimit = 10_000);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader());
});

var app = builder.Build();

app.UseCors();

app.MapGet("/api/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/api/path", (
    string source, string target, LineVisEdgRepository repo, IMemoryCache cache, HttpContext http, int maxDepth = 12) =>
{
    var effectiveMaxDepth = Math.Min(maxDepth, 20);
    var cacheKey = $"path:{source}:{target}:{effectiveMaxDepth}";

    var cacheHit = cache.TryGetValue(cacheKey, out ShortestPathResult? cached);
    var result = cached ?? cache.Set(cacheKey, repo.ShortestPath(source, target, effectiveMaxDepth), new MemoryCacheEntryOptions
    {
        Size = 1,
        AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5),
    });

    http.Response.Headers["X-Cache"] = cacheHit ? "HIT" : "MISS";

    if (!result.Found)
        return Results.NotFound(new { detail = $"Aucun chemin de '{source}' vers '{target}'." });

    return Results.Ok(new { path = result.Path, found = result.Found });
});

app.Run();
