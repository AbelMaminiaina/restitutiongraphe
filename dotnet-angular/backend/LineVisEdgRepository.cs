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
//
// Volontairement synchrone (pas d'async/await) : chaque appel HTTP est traité
// sur son propre thread du pool, sans recouvrement d'E/S recherché ici.

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

    public bool RowExists(string nodeId)
    {
        using var conn = OpenConnection();
        return RowExists(conn, nodeId);
    }

    private static bool RowExists(SqlConnection conn, string nodeId)
    {
        using (var cmd = new SqlCommand("SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG WHERE Nodes = @id", conn))
        {
            AddVarChar(cmd, "@id", nodeId);
            if (cmd.ExecuteScalar() is not null) return true;
        }
        using (var cmd = new SqlCommand("SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG WHERE NodesLie = @id", conn))
        {
            AddVarChar(cmd, "@id", nodeId);
            return cmd.ExecuteScalar() is not null;
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
    private static List<(string Nodes, string Direction, string NodesLie)> FetchEdgesFrom(
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
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    rows.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }

            using (var cmd = new SqlCommand(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG " +
                $"WHERE NodesLie IN ({inClause}) AND Direction = 'successeur'", conn))
            {
                for (var i = 0; i < chunk.Count; i++) AddVarChar(cmd, names[i], chunk[i]);
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    rows.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }
        }

        return rows;
    }

    // Arêtes entrantes des nœuds de `frontier` (miroir de FetchEdgesFrom, sens
    // inversé) : une arête entre dans un nœud X de deux façons possibles :
    // soit (NodesLie = X, Direction = predecesseur) -> Nodes -> X,
    // soit (Nodes = X, Direction = successeur) -> NodesLie -> X.
    private static List<(string Nodes, string Direction, string NodesLie)> FetchEdgesInto(
        SqlConnection conn, List<string> frontier)
    {
        var rows = new List<(string, string, string)>();

        foreach (var chunk in Chunks(frontier, ParamBatch))
        {
            var names = chunk.Select((_, i) => $"@n{i}").ToList();
            var inClause = string.Join(",", names);

            using (var cmd = new SqlCommand(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG " +
                $"WHERE NodesLie IN ({inClause}) AND Direction = 'predecesseur'", conn))
            {
                for (var i = 0; i < chunk.Count; i++) AddVarChar(cmd, names[i], chunk[i]);
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    rows.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }

            using (var cmd = new SqlCommand(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG " +
                $"WHERE Nodes IN ({inClause}) AND Direction = 'successeur'", conn))
            {
                for (var i = 0; i < chunk.Count; i++) AddVarChar(cmd, names[i], chunk[i]);
                using var reader = cmd.ExecuteReader();
                while (reader.Read())
                    rows.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }
        }

        return rows;
    }

    // BFS bidirectionnel non pondéré, sens des arêtes respecté, exécuté par
    // paliers en SQL. Un front avance depuis la source (arêtes sortantes),
    // l'autre depuis la cible (arêtes entrantes), en alternance à chaque
    // palier. Dès qu'un nœud est découvert des deux côtés, on a trouvé le
    // plus court chemin. Pour un chemin de longueur R, ça ne coûte
    // qu'environ 2 * degré^(R/2) nœuds visités au lieu de degré^R pour un
    // BFS à sens unique (comme shortest_path() dans src/restitution/db.py,
    // resté à sens unique côté Python).
    public ShortestPathResult ShortestPath(string sourceId, string targetId, int maxDepth = 12)
    {
        using var conn = OpenConnection();

        if (!RowExists(conn, sourceId) || !RowExists(conn, targetId))
            return new ShortestPathResult([], false);

        if (sourceId == targetId)
            return new ShortestPathResult([sourceId], true);

        const int maxVisitedPerSide = 30_000; // garde-fou, par sens

        // forwardPrev[X] = nœud précédent de X sur le chemin depuis la source.
        // backwardNext[X] = nœud suivant de X sur le chemin vers la cible.
        var forwardPrev = new Dictionary<string, string?> { [sourceId] = null };
        var backwardNext = new Dictionary<string, string?> { [targetId] = null };
        var forwardFrontier = new List<string> { sourceId };
        var backwardFrontier = new List<string> { targetId };

        for (var step = 0; step < maxDepth; step++)
        {
            if (forwardFrontier.Count == 0 && backwardFrontier.Count == 0) break;

            var expandForward = step % 2 == 0;

            if (expandForward && forwardFrontier.Count > 0 && forwardPrev.Count < maxVisitedPerSide)
            {
                var rows = FetchEdgesFrom(conn, forwardFrontier);
                var next = new List<string>();

                foreach (var (nodes, direction, nodesLie) in rows)
                {
                    var (source, target) = ToEdge(nodes, direction, nodesLie);
                    if (!forwardPrev.ContainsKey(source)) continue; // ligne rapatriée dans le lot mais qui ne part pas de la frontière
                    if (forwardPrev.ContainsKey(target)) continue;

                    forwardPrev[target] = source;
                    next.Add(target);

                    if (backwardNext.ContainsKey(target))
                        return BuildBidirectionalPath(target, forwardPrev, backwardNext);
                }

                forwardFrontier = next;
            }
            else if (!expandForward && backwardFrontier.Count > 0 && backwardNext.Count < maxVisitedPerSide)
            {
                var rows = FetchEdgesInto(conn, backwardFrontier);
                var next = new List<string>();

                foreach (var (nodes, direction, nodesLie) in rows)
                {
                    var (source, target) = ToEdge(nodes, direction, nodesLie);
                    if (!backwardNext.ContainsKey(target)) continue; // ligne rapatriée dans le lot mais qui n'arrive pas dans la frontière
                    if (backwardNext.ContainsKey(source)) continue;

                    backwardNext[source] = target;
                    next.Add(source);

                    if (forwardPrev.ContainsKey(source))
                        return BuildBidirectionalPath(source, forwardPrev, backwardNext);
                }

                backwardFrontier = next;
            }
            // sinon : ce front est déjà vide ou plafonné pour ce palier, on
            // retente l'autre sens au palier suivant.
        }

        return new ShortestPathResult([], false);
    }

    private static ShortestPathResult BuildBidirectionalPath(
        string meetingNode, Dictionary<string, string?> forwardPrev, Dictionary<string, string?> backwardNext)
    {
        var path = new List<string> { meetingNode };

        var cur = forwardPrev[meetingNode];
        while (cur is not null)
        {
            path.Insert(0, cur);
            cur = forwardPrev[cur];
        }

        cur = backwardNext[meetingNode];
        while (cur is not null)
        {
            path.Add(cur);
            cur = backwardNext[cur];
        }

        return new ShortestPathResult(path, true);
    }
}
