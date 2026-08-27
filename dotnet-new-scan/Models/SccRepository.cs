// Model (au sens MVC) : accès aux deux tables produites par la condensation
// SCC (§ 11.5 de la spécification), remplies par SccCondensationService.
//
//   dbo.NODE_SCC  (NodeId -> SccId)          : la SCC de chaque nœud
//   dbo.SCC_EDGE  (FromScc, ToScc)           : les arêtes du graphe condensé
//                                              (un DAG, beaucoup plus petit)
//
// Comme NodeComponentRepository, c'est ici — et nulle part ailleurs — que
// vivent les requêtes SQL. Le service ne fait que l'algorithme.

using System.Data;

using Microsoft.Data.SqlClient;

namespace PathFinder.ScanMvc.Models;

public class SccRepository
{
    private const int NodeKeySize = 450; // clé d'index SQL Server <= 900 octets

    private readonly string _connectionString;

    public SccRepository(IConfiguration configuration)
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

    // Remplace INTÉGRALEMENT les deux tables à partir du résultat de la
    // condensation. Idempotent (DROP + CREATE + chargement en masse).
    public void ReplaceAll(
        IEnumerable<(string NodeId, int SccId)> nodeScc,
        IEnumerable<(int FromScc, int ToScc)> sccEdges)
    {
        var nodeTable = new DataTable();
        nodeTable.Columns.Add("NodeId", typeof(string));
        nodeTable.Columns.Add("SccId", typeof(int));
        foreach (var (nodeId, sccId) in nodeScc)
            nodeTable.Rows.Add(Clip(nodeId), sccId);

        var edgeTable = new DataTable();
        edgeTable.Columns.Add("FromScc", typeof(int));
        edgeTable.Columns.Add("ToScc", typeof(int));
        foreach (var (fromScc, toScc) in sccEdges)
            edgeTable.Rows.Add(fromScc, toScc);

        using var conn = OpenConnection();

        ExecuteNonQuery(conn,
            "IF OBJECT_ID('dbo.NODE_SCC') IS NOT NULL DROP TABLE dbo.NODE_SCC;");
        ExecuteNonQuery(conn,
            "IF OBJECT_ID('dbo.SCC_EDGE') IS NOT NULL DROP TABLE dbo.SCC_EDGE;");
        ExecuteNonQuery(conn,
            $"CREATE TABLE dbo.NODE_SCC (NodeId VARCHAR({NodeKeySize}) NOT NULL PRIMARY KEY, SccId INT NOT NULL);");
        ExecuteNonQuery(conn,
            "CREATE TABLE dbo.SCC_EDGE (FromScc INT NOT NULL, ToScc INT NOT NULL, " +
            "CONSTRAINT PK_SCC_EDGE PRIMARY KEY (FromScc, ToScc));");

        BulkCopy(conn, "dbo.NODE_SCC", nodeTable, ("NodeId", "NodeId"), ("SccId", "SccId"));
        BulkCopy(conn, "dbo.SCC_EDGE", edgeTable, ("FromScc", "FromScc"), ("ToScc", "ToScc"));

        ExecuteNonQuery(conn,
            "CREATE INDEX IX_NODE_SCC_Scc ON dbo.NODE_SCC (SccId);");
    }

    // SccId des deux nœuds en une requête. null si le nœud est absent, ou si
    // la table n'existe pas encore (condensation jamais lancée).
    public (int? Source, int? Target) GetSccIds(string source, string target)
    {
        var s = Clip(source);
        var t = Clip(target);

        try
        {
            using var conn = OpenConnection();
            using var cmd = new SqlCommand(
                "SELECT NodeId, SccId FROM dbo.NODE_SCC WHERE NodeId IN (@a, @b)", conn);
            cmd.Parameters.Add("@a", SqlDbType.VarChar, NodeKeySize).Value = s;
            cmd.Parameters.Add("@b", SqlDbType.VarChar, NodeKeySize).Value = t;

            int? sourceId = null, targetId = null;
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                var id = reader.GetString(0);
                var scc = reader.GetInt32(1);
                if (id == s) sourceId = scc;
                if (id == t) targetId = scc;
            }
            return (sourceId, targetId);
        }
        catch (SqlException)
        {
            return (null, null);
        }
    }

    // Le graphe condensé (petit DAG) sous forme de listes d'adjacence.
    public Dictionary<int, List<int>> LoadCondensedAdjacency()
    {
        var adjacency = new Dictionary<int, List<int>>();

        try
        {
            using var conn = OpenConnection();
            using var cmd = new SqlCommand("SELECT FromScc, ToScc FROM dbo.SCC_EDGE", conn);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                var from = reader.GetInt32(0);
                var to = reader.GetInt32(1);
                if (!adjacency.TryGetValue(from, out var list))
                    adjacency[from] = list = new List<int>();
                list.Add(to);
            }
        }
        catch (SqlException)
        {
            // table absente : on renvoie un DAG vide (le service gère le cas).
        }

        return adjacency;
    }

    private static void BulkCopy(SqlConnection conn, string destination, DataTable table,
        params (string Source, string Dest)[] mappings)
    {
        using var bulk = new SqlBulkCopy(conn) { DestinationTableName = destination, BulkCopyTimeout = 0 };
        foreach (var (src, dst) in mappings)
            bulk.ColumnMappings.Add(src, dst);
        bulk.WriteToServer(table);
    }

    private static void ExecuteNonQuery(SqlConnection conn, string sql)
    {
        using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 0 };
        cmd.ExecuteNonQuery();
    }

    private static string Clip(string s) => s.Length <= NodeKeySize ? s : s[..NodeKeySize];
}
