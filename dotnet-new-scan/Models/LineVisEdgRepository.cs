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
// Ce repository NE FAIT PLUS de parcours : le plus court chemin se calcule
// entièrement en mémoire (Services/DirectedGraph.cs). Il ne reste ici que la
// LECTURE des arêtes (en flux) et la relecture des Transformation, plus une
// sonde de connexion (CanConnect) utilisée par GraphDataProvider.
//
// C# 8.0 : pas de `record` — ShortestPathResult et PathEdge sont des classes.

using System;
using System.Collections.Generic;
using System.Data;

using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace PathFinder.ScanMvc.Models
{
    // Résultat d'un parcours : la liste ordonnée des nœuds (source -> ... ->
    // cible) et un drapeau « trouvé ». Produit par Services/DirectedGraph.
    public sealed class ShortestPathResult
    {
        public List<string> Path { get; }
        public bool Found { get; }

        public ShortestPathResult(List<string> path, bool found)
        {
            Path = path;
            Found = found;
        }
    }

    // Une arête du chemin trouvé, enrichie de sa transformation (peut être null
    // si l'arête n'en porte pas). Utilisé pour le tableau détaillé de la vue.
    public sealed class PathEdge
    {
        public int Index { get; }
        public string From { get; }
        public string To { get; }
        public string? Transformation { get; }

        public PathEdge(int index, string from, string to, string? transformation)
        {
            Index = index;
            From = from;
            To = to;
            Transformation = transformation;
        }
    }

    public class LineVisEdgRepository
    {
        private const int NodeColumnSize = 8000; // doit correspondre au type de Nodes/NodesLie

        private readonly string _server;
        private readonly string _database;
        private readonly string _connectionString;

        public LineVisEdgRepository(IConfiguration configuration)
        {
            _server = Environment.GetEnvironmentVariable("RESTITUTION_DB_SERVER")
                ?? configuration["Database:Server"]
                ?? @"localhost\SQLEXPRESS01";
            _database = Environment.GetEnvironmentVariable("RESTITUTION_DB_NAME")
                ?? configuration["Database:Name"]
                ?? "RestitutionGraphe";

            _connectionString =
                $"Server={_server};Database={_database};Trusted_Connection=True;TrustServerCertificate=True;";
        }

        public string ConnectionSummary => $"{_server} / {_database}";

        private SqlConnection OpenConnection()
        {
            var conn = new SqlConnection(_connectionString);
            conn.Open();
            return conn;
        }

        // Sonde rapide : la base est-elle joignable ET la table LINE_VIS_EDG
        // présente et non vide ? Timeout court (3 s) pour ne pas retarder le
        // démarrage quand SQL Server est absent. Toute exception => false.
        public bool CanConnect()
        {
            try
            {
                var probe = new SqlConnectionStringBuilder(_connectionString) { ConnectTimeout = 3 };
                using var conn = new SqlConnection(probe.ConnectionString);
                conn.Open();
                using var cmd = new SqlCommand("SELECT TOP 1 1 FROM dbo.LINE_VIS_EDG", conn)
                {
                    CommandTimeout = 3,
                };
                return cmd.ExecuteScalar() != null;
            }
            catch (Exception)
            {
                return false;
            }
        }

        // Ajoute un paramètre typé VARCHAR (et non NVARCHAR) : indispensable pour
        // que SQL Server garde une recherche d'index sur Nodes/NodesLie.
        private static SqlParameter AddVarChar(SqlCommand cmd, string name, string value)
        {
            var p = cmd.Parameters.Add(name, SqlDbType.VarChar, NodeColumnSize);
            p.Value = value;
            return p;
        }

        // Dérive (source, cible) d'une ligne LINE_VIS_EDG selon sa Direction.
        private static (string Source, string Target) ToEdge(string nodes, string direction, string nodesLie)
            => direction == "predecesseur" ? (nodes, nodesLie) : (nodesLie, nodes);

        // ----- détail du chemin trouvé (pour le tableau de la vue) -----------

        // Pour chaque arête consécutive du chemin (path[i] -> path[i+1]), relit la
        // Transformation portée par la ligne LINE_VIS_EDG correspondante.
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

        // Transformation d'une seule arête from -> to. Une arête u -> v est
        // stockée soit en (Nodes = u, predecesseur, NodesLie = v), soit en
        // (Nodes = v, successeur, NodesLie = u) ; on essaie les deux formes.
        public string? EdgeTransformation(string from, string to)
        {
            using var conn = OpenConnection();
            return EdgeTransformation(conn, from, to);
        }

        private static string? EdgeTransformation(SqlConnection conn, string from, string to)
        {
            using (var cmd = new SqlCommand(
                "SELECT TOP 1 Transformation FROM dbo.LINE_VIS_EDG " +
                "WHERE Nodes = @from AND NodesLie = @to AND Direction = 'predecesseur'", conn))
            {
                AddVarChar(cmd, "@from", from);
                AddVarChar(cmd, "@to", to);
                var r = cmd.ExecuteScalar();
                if (r != null && !(r is DBNull)) return (string?)r;
            }

            using (var cmd = new SqlCommand(
                "SELECT TOP 1 Transformation FROM dbo.LINE_VIS_EDG " +
                "WHERE Nodes = @to AND NodesLie = @from AND Direction = 'successeur'", conn))
            {
                AddVarChar(cmd, "@from", from);
                AddVarChar(cmd, "@to", to);
                var r = cmd.ExecuteScalar();
                if (r != null && !(r is DBNull)) return (string?)r;
            }

            return null;
        }

        // ----- lecture en flux de toutes les arêtes -------------------------

        // Toutes les arêtes (Nodes, NodesLie), sens NON dérivé. Utilisé par
        // GraphScanService (connexité faible : le sens ne compte pas).
        public IEnumerable<(string From, string To)> StreamAllEdges()
        {
            using var conn = OpenConnection();
            using var cmd = new SqlCommand("SELECT Nodes, NodesLie FROM dbo.LINE_VIS_EDG", conn)
            {
                CommandTimeout = 0, // la table peut être grande
            };
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
                yield return (reader.GetString(0), reader.GetString(1));
        }

        // Toutes les arêtes ORIENTÉES (source -> cible), le sens dérivé de la
        // colonne Direction (via ToEdge). Utilisé par SccCondensationService
        // (composantes fortement connexes : le sens compte) et par
        // InMemoryGraphService (graphe en mémoire, § 11.7).
        public IEnumerable<(string From, string To)> StreamAllDirectedEdges()
        {
            using var conn = OpenConnection();
            using var cmd = new SqlCommand(
                "SELECT Nodes, Direction, NodesLie FROM dbo.LINE_VIS_EDG", conn)
            {
                CommandTimeout = 0,
            };
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
                yield return ToEdge(reader.GetString(0), reader.GetString(1), reader.GetString(2));
        }
    }
}
