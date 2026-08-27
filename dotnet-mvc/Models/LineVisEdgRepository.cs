// Model (au sens MVC) : accès à la base SQL Server RestitutionGraphe.
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
// balayage complet au lieu d'une recherche d'index). Chaque SqlParameter est
// donc typé explicitement en SqlDbType.VarChar (voir AddVarChar).
//
// Le cœur (BFS bidirectionnel) est identique à
// dotnet-angular-mvc/Models/LineVisEdgRepository.cs. Ce projet ajoute
// seulement DescribePath() : une fois le chemin trouvé, on relit pour chaque
// arête consécutive la Transformation portée par la ligne correspondante, afin
// de l'afficher dans le tableau détaillé de la vue Razor.

using Microsoft.Data.SqlClient;

namespace PathFinder.RazorMvc.Models;

// Résultat brut du BFS : la liste ordonnée des nœuds (source -> ... -> cible)
// et un drapeau « trouvé ».
public record ShortestPathResult(List<string> Path, bool Found);

// Une arête du chemin trouvé, enrichie de sa transformation (peut être null si
// la ligne n'en porte pas). Utilisé pour le tableau détaillé de la vue.
public record PathEdge(int Index, string From, string To, string? Transformation);

public class LineVisEdgRepository
{
    private const int ParamBatch = 1000;   // SQL Server plafonne à ~2100 paramètres par requête
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

    // Ajoute un paramètre typé VARCHAR (et non NVARCHAR) : indispensable pour
    // que SQL Server garde une recherche d'index sur Nodes/NodesLie.
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

    // ----- existence d'un nœud ---------------------------------------------

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

    // ----- récupération des arêtes, par lots de paramètres -----------------

    // Arêtes sortantes des nœuds de `frontier` (sens respecté). Une arête sort
    // d'un nœud X soit via (Nodes = X, predecesseur) -> X -> NodesLie, soit via
    // (NodesLie = X, successeur) -> X -> Nodes. Deux requêtes séparées (une par
    // index composite) plutôt qu'un OR, pour garder des recherches d'index.
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
    // inversé) : une arête entre dans X soit via (NodesLie = X, predecesseur)
    // -> Nodes -> X, soit via (Nodes = X, successeur) -> NodesLie -> X.
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

    // ----- BFS bidirectionnel --------------------------------------------

    // BFS bidirectionnel non pondéré, sens des arêtes respecté, exécuté par
    // paliers en SQL. Un front avance depuis la source (arêtes sortantes),
    // l'autre depuis la cible (arêtes entrantes), en alternance à chaque
    // palier. Dès qu'un nœud est découvert des deux côtés, on a trouvé le
    // plus court chemin. Pour un chemin de longueur R, ça ne coûte
    // qu'environ 2 * degré^(R/2) nœuds visités au lieu de degré^R pour un
    // BFS à sens unique.
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
                    if (!forwardPrev.ContainsKey(source)) continue; // ligne du lot qui ne part pas de la frontière
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
                    if (!backwardNext.ContainsKey(target)) continue; // ligne du lot qui n'arrive pas dans la frontière
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

    // ----- détail du chemin trouvé (pour le tableau de la vue) -----------

    // Pour chaque arête consécutive du chemin (path[i] -> path[i+1]), relit la
    // Transformation portée par la ligne LINE_VIS_EDG correspondante. Une arête
    // u -> v est stockée soit en (Nodes = u, predecesseur, NodesLie = v), soit
    // en (Nodes = v, successeur, NodesLie = u) ; on essaie les deux formes.
    public List<PathEdge> DescribePath(IReadOnlyList<string> path)
    {
        var edges = new List<PathEdge>();
        if (path.Count < 2) return edges;

        using var conn = OpenConnection();
        for (var i = 0; i < path.Count - 1; i++)
            edges.Add(new PathEdge(i + 1, path[i], path[i + 1],
                EdgeTransformation(conn, path[i], path[i + 1])));

        return edges;
    }

    private static string? EdgeTransformation(SqlConnection conn, string from, string to)
    {
        using (var cmd = new SqlCommand(
            "SELECT TOP 1 Transformation FROM dbo.LINE_VIS_EDG " +
            "WHERE Nodes = @from AND NodesLie = @to AND Direction = 'predecesseur'", conn))
        {
            AddVarChar(cmd, "@from", from);
            AddVarChar(cmd, "@to", to);
            if (cmd.ExecuteScalar() is { } r && r is not DBNull) return (string?)r;
        }

        using (var cmd = new SqlCommand(
            "SELECT TOP 1 Transformation FROM dbo.LINE_VIS_EDG " +
            "WHERE Nodes = @to AND NodesLie = @from AND Direction = 'successeur'", conn))
        {
            AddVarChar(cmd, "@from", from);
            AddVarChar(cmd, "@to", to);
            if (cmd.ExecuteScalar() is { } r && r is not DBNull) return (string?)r;
        }

        return null;
    }
}
