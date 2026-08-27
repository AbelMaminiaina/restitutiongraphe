// Model (au sens MVC) : accès à la table dbo.NODE_COMPONENT, remplie par le
// scan (voir Services/GraphScanService.cs).
//
// C'est ici, et NULLE PART ailleurs, que vivent les requêtes SQL du scan :
//   - ReplaceAll    : (re)crée la table et la charge en masse ;
//   - GetComponentIds : lit le numéro de composante de deux nœuds.
//
// Le service, lui, ne contient que l'algorithme (Union-Find) et ne connaît
// ni SqlConnection, ni SqlCommand.

using System.Data;

using Microsoft.Data.SqlClient;

namespace PathFinder.ScanMvc.Models;

public class NodeComponentRepository
{
    // Une clé d'index SQL Server ne peut pas dépasser 900 octets : la colonne
    // NodeId de NODE_COMPONENT est donc VARCHAR(450), pas VARCHAR(8000) comme
    // dans LINE_VIS_EDG. Les identifiants réels tiennent largement dedans.
    private const int NodeKeySize = 450;

    private readonly string _connectionString;

    public NodeComponentRepository(IConfiguration configuration)
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

    // Remplace INTÉGRALEMENT la table à partir des couples (NodeId, ComponentId)
    // calculés par le service : DROP + CREATE + chargement en masse + index.
    // Idempotent.
    public void ReplaceAll(IEnumerable<(string NodeId, int ComponentId)> rows)
    {
        var table = new DataTable();
        table.Columns.Add("NodeId", typeof(string));
        table.Columns.Add("ComponentId", typeof(int));
        foreach (var (nodeId, componentId) in rows)
            table.Rows.Add(Clip(nodeId), componentId);

        using var conn = OpenConnection();

        ExecuteNonQuery(conn,
            "IF OBJECT_ID('dbo.NODE_COMPONENT') IS NOT NULL DROP TABLE dbo.NODE_COMPONENT;");
        ExecuteNonQuery(conn,
            $"CREATE TABLE dbo.NODE_COMPONENT (" +
            $"NodeId VARCHAR({NodeKeySize}) NOT NULL PRIMARY KEY, " +
            $"ComponentId INT NOT NULL);");

        using (var bulk = new SqlBulkCopy(conn) { DestinationTableName = "dbo.NODE_COMPONENT", BulkCopyTimeout = 0 })
        {
            bulk.ColumnMappings.Add("NodeId", "NodeId");
            bulk.ColumnMappings.Add("ComponentId", "ComponentId");
            bulk.WriteToServer(table);
        }

        ExecuteNonQuery(conn,
            "CREATE INDEX IX_NODE_COMPONENT_Comp ON dbo.NODE_COMPONENT (ComponentId);");
    }

    // Numéro de composante de deux nœuds, en une seule requête. Chaque valeur
    // est null si le nœud est absent de la table — ou si la table n'existe pas
    // encore (scan jamais lancé) : dans ce cas le service laissera le BFS agir.
    public (int? Source, int? Target) GetComponentIds(string source, string target)
    {
        var s = Clip(source);
        var t = Clip(target);

        try
        {
            using var conn = OpenConnection();
            using var cmd = new SqlCommand(
                "SELECT NodeId, ComponentId FROM dbo.NODE_COMPONENT WHERE NodeId IN (@a, @b)", conn);
            cmd.Parameters.Add("@a", SqlDbType.VarChar, NodeKeySize).Value = s;
            cmd.Parameters.Add("@b", SqlDbType.VarChar, NodeKeySize).Value = t;

            int? source_id = null, target_id = null;
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                var id = reader.GetString(0);
                var comp = reader.GetInt32(1);
                if (id == s) source_id = comp;
                if (id == t) target_id = comp;
            }
            return (source_id, target_id);
        }
        catch (SqlException)
        {
            return (null, null);
        }
    }

    private static void ExecuteNonQuery(SqlConnection conn, string sql)
    {
        using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 0 };
        cmd.ExecuteNonQuery();
    }

    private static string Clip(string s) => s.Length <= NodeKeySize ? s : s[..NodeKeySize];
}
