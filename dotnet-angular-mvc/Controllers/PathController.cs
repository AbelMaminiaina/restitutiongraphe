// Controller (MVC) : expose la recherche de plus court chemin au frontend
// Angular servi par ce même projet (ClientApp/, compilé dans wwwroot/).
// Délègue toute la logique au Model (LineVisEdgRepository).

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using PathFinder.Mvc.Models;

namespace PathFinder.Mvc.Controllers;

[ApiController]
[Route("api/path")]
public class PathController : ControllerBase
{
    private readonly LineVisEdgRepository _repository;
    private readonly IMemoryCache _cache;

    public PathController(LineVisEdgRepository repository, IMemoryCache cache)
    {
        _repository = repository;
        _cache = cache;
    }

    // Cache applicatif : mémorise le résultat par (source, cible, maxDepth),
    // y compris les "aucun chemin" (les recherches les plus coûteuses,
    // celles qui vont jusqu'au plafond des 30 000 nœuds par sens).
    [HttpGet]
    public IActionResult Get(string source, string target, int maxDepth = 12)
    {
        var effectiveMaxDepth = Math.Min(maxDepth, 20);
        var cacheKey = $"path:{source}:{target}:{effectiveMaxDepth}";

        var cacheHit = _cache.TryGetValue(cacheKey, out ShortestPathResult? cached);
        var result = cached ?? _cache.Set(cacheKey, _repository.ShortestPath(source, target, effectiveMaxDepth), new MemoryCacheEntryOptions
        {
            Size = 1,
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5),
        });

        Response.Headers["X-Cache"] = cacheHit ? "HIT" : "MISS";

        if (!result.Found)
            return NotFound(new { detail = $"Aucun chemin de '{source}' vers '{target}'." });

        return Ok(new { path = result.Path, found = result.Found });
    }
}
