// Accès à la base SQL Server RestitutionGraphe.
//
// La table dbo.LINE_VIS_EDG est la source de vérité : il n'y a pas de table
// de nœuds séparée, un nœud est simplement une valeur qui apparaît en colonne
// Nodes ou NodesLie. Chaque ligne relie Nodes à NodesLie ; Direction indique
// le rôle de Nodes par rapport à NodesLie :
//
//   Direction = "predecesseur" -> Nodes précède NodesLie -> arête Nodes -> NodesLie
//   Direction = "successeur"   -> Nodes suit NodesLie     -> arête NodesLie -> Nodes
//
// Nodes/NodesLie sont des colonnes VARCHAR(8000). Microsoft.Data.SqlClient
// lie par défaut une chaîne .NET en NVarChar ; comparer une colonne VARCHAR à
// un paramètre NVarChar force SQL Server à convertir la colonne (donc un
// balayage complet au lieu d'une recherche d'index). Le correctif ici est
// plus direct qu'en Python : on type explicitement chaque SqlParameter en
// SqlDbType.VarChar (voir AddVarChar) au lieu de laisser le driver deviner.
//
// Même principe que src/restitution/db.py (Python) : on ne récupère jamais
// tout le graphe, seulement des sous-graphes bornés — ici uniquement la
// recherche de plus court chemin (BFS non pondéré, exécuté par paliers).

using Microsoft.Data.SqlClient;

namespace PathFinder.Api;

public record ShortestPathResult(List<string> Path, bool Found);

public class LineVisEdgRepository
{
    private const int ParamBatch = 1000; // SQL Server plafonne à ~2100 paramètres par requête
    private const int NodeColumnSize = 8000; // doit correspondre au type de Nodes/NodesLie

    private readonly string _connectionString;

    public LineVisEdgRepository(IConfiguration configuration)
    {
        var server = Environment.GetEnvironmentVariable("RESTITUTION_DB_SERVER")
            ?? configuration["Database:Server"]
            ?? @"localhost\SQLEXPRESS01";
        var database = Environment.GetEnvironmentVariable("RESTITUTION_DB_NAME")
            ?? configuration["Database:Name"]
            ?? "RestitutionGraphe";

        _connectionString =
            $"Server={server};Database={database};Trusted_Connection=True;TrustServerCertificate=True;";
    }

    private SqlConnection OpenConnection()
    {
        var conn = new SqlConnection(_connectionString);
        conn.Open();
        return conn;
    }

    private static SqlParameter AddVarChar(SqlCommand cmd, string name, string value)
    {
        var p = cmd.Parameters.Add(name, System.Data.SqlDbType.VarChar, NodeColumnSize);
        p.Value = value;
        return p;
    }

    private static IEnumerable<List<string>> Chunks(List<string> items, int size)
    {
        for (var i = 0; i < items.Count; i += size)
            yield return items.GetRange(i, Math.Min(size, items.Count - i));
    }

    // Dérive (source, cible) d'une ligne LINE_VIS_EDG selon sa Direction.
    private static (string Source, string Target) ToEdge(string nodes, string direction, string nodesLie)
        => direction == "predecesseur" ? (nodes, nodesLie) : (nodesLie, nodes);

    public async Task<bool> RowExistsAsync(string nodeId)
    {
        using var conn = OpenConnection();
        return await RowExistsAsync(conn, nodeId);
    }

    private static async Task<bool> RowExistsAsync(SqlConnection conn, string nodeId)
    {
        using (var cmd = new SqlCommand("SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG WHERE Nodes = @id", conn))
        {
            AddVarChar(cmd, "@id", nodeId);
            if (await cmd.ExecuteScalarAsync() is not null) return true;
        }
        using (var cmd = new SqlCommand("SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG WHERE NodesLie = @id", conn))
        {
            AddVarChar(cmd, "@id", nodeId);
            return await cmd.ExecuteScalarAsync() is not null;
        }
    }

    // Arêtes sortantes des nœuds de `frontier` (sens respecté), par lots de paramètres.
    //
    // Une arête sort d'un nœud X de deux façons possibles dans la table brute :
    // soit (Nodes = X, Direction = predecesseur) -> X -> NodesLie,
    // soit (NodesLie = X, Direction = successeur) -> X -> Nodes.
    // Deux requêtes séparées (une par index composite) plutôt qu'un OR entre
    // deux colonnes différentes, pour que chacune utilise une recherche
    // d'index (seek) au lieu d'un balayage (scan).
    private static async Task<List<(string Nodes, string Direction, string NodesLie)>> FetchEdgesFromAsync(
        SqlConnection conn, List<string> frontier)
    {
        var rows = new List<(string, string, string)>();

        foreach (var chunk in Chunks(frontier, ParamBatch))
        {
            var names = chunk.Select((_, i) => $"@n{i}").ToList();
            var inClause = string.Join(",", names);

            using (var cmd = new SqlCommand(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG " +
                $"WHERE Nodes IN ({inClause}) AND Direction = 'predecesseur'", conn))
            {
                for (var i = 0; i < chunk.Count; i++) AddVarChar(cmd, names[i], chunk[i]);
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                    rows.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }

            using (var cmd = new SqlCommand(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG " +
                $"WHERE NodesLie IN ({inClause}) AND Direction = 'successeur'", conn))
            {
                for (var i = 0; i < chunk.Count; i++) AddVarChar(cmd, names[i], chunk[i]);
                using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                    rows.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }
        }

        return rows;
    }

    // BFS non pondéré, sens des arêtes respecté, exécuté par paliers en SQL.
    // Fidèle à shortest_path() dans src/restitution/db.py (Python).
    public async Task<ShortestPathResult> ShortestPathAsync(string sourceId, string targetId, int maxDepth = 12)
    {
        using var conn = OpenConnection();

        if (!await RowExistsAsync(conn, sourceId) || !await RowExistsAsync(conn, targetId))
            return new ShortestPathResult(new List<string>(), false);

        if (sourceId == targetId)
            return new ShortestPathResult(new List<string> { sourceId }, true);

        var visited = new HashSet<string> { sourceId };
        var prev = new Dictionary<string, string>();
        var frontier = new List<string> { sourceId };
        const int maxVisited = 30_000; // garde-fou : au-delà, on considère que ce n'est pas trouvable en temps utile

        for (var depth = 0; depth < maxDepth; depth++)
        {
            if (frontier.Count == 0 || visited.Count >= maxVisited) break;

            var rows = await FetchEdgesFromAsync(conn, frontier);
            var nextFrontier = new List<string>();

            foreach (var (nodes, direction, nodesLie) in rows)
            {
                var (source, target) = ToEdge(nodes, direction, nodesLie);
                if (!visited.Contains(source)) continue; // ligne rapatriée dans le lot mais qui ne part pas de la frontière
                if (visited.Contains(target)) continue;

                visited.Add(target);
                prev[target] = source;

                if (target == targetId)
                {
                    var path = new List<string> { targetId };
                    var cur = targetId;
                    while (cur != sourceId)
                    {
                        cur = prev[cur];
                        path.Add(cur);
                    }
                    path.Reverse();
                    return new ShortestPathResult(path, true);
                }

                nextFrontier.Add(target);
            }

            frontier = nextFrontier;
        }

        return new ShortestPathResult(new List<string>(), false);
    }
}
