using System;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;   // pilote SQL Server inclus dans .NET Framework (aucun NuGet)
using System.Threading;
using System.Threading.Tasks;

namespace LineageExplorer.Data
{
    /// <summary>
    /// Accès à la base RestitutionGrapheProd.
    /// On n'écrit aucune requête SQL ici : on appelle uniquement les procédures
    /// stockées de Sql-procedure-table (LINE_VIS_NodesList et
    /// LINE_VIS_GetNodesSuccessorsPredecessors).
    ///
    /// Toutes les méthodes sont "async" : pendant que SQL Server travaille,
    /// la fenêtre reste fluide (on peut zoomer, déplacer, annuler...).
    /// </summary>
    public sealed class LineageRepository
    {
        private readonly string _connectionString;
        private readonly int _commandTimeout;

        public LineageRepository(string connectionString, int commandTimeoutSeconds)
        {
            _connectionString = connectionString;
            _commandTimeout = commandTimeoutSeconds;
        }

        /// <summary>Lit la chaîne de connexion et le délai dans App.config.</summary>
        public static LineageRepository FromConfig()
        {
            var cs = ConfigurationManager.ConnectionStrings["RestitutionGrapheProd"];
            if (cs == null)
                throw new ConfigurationErrorsException("Chaîne de connexion 'RestitutionGrapheProd' absente de App.config.");

            int timeout;
            if (!int.TryParse(ConfigurationManager.AppSettings["CommandTimeoutSeconds"], out timeout))
                timeout = 300;

            return new LineageRepository(cs.ConnectionString, timeout);
        }

        /// <summary>Texte affiché dans l'interface, p. ex. ".\SQLEXPRESS01 / RestitutionGrapheProd".</summary>
        public string DataSourceLabel
        {
            get
            {
                var b = new SqlConnectionStringBuilder(_connectionString);
                return b.DataSource + " / " + b.InitialCatalog;
            }
        }

        /// <summary>Ouvre puis ferme une connexion : lève une exception si la base est injoignable.</summary>
        public async Task TestConnectionAsync(CancellationToken ct)
        {
            using (var cn = new SqlConnection(_connectionString))
            {
                await cn.OpenAsync(ct);
            }
        }

        /// <summary>
        /// Recherche de nœuds : appelle dbo.LINE_VIS_NodesList.
        /// Chaque filtre est un "contient" (LIKE '%...%'), sans casse ni accents.
        /// Tous les filtres vides = les premiers nœuds dont la colonne commence par 'f'.
        /// </summary>
        public async Task<SearchResult> SearchNodesAsync(string column, string table, string schema, string env,
                                                         int maxRes, CancellationToken ct)
        {
            var result = new SearchResult();

            using (var cn = new SqlConnection(_connectionString))
            using (var cmd = NewProcedure(cn, "dbo.LINE_VIS_NodesList"))
            {
                AddVarChar(cmd, "@p_column", column, 1000);
                AddVarChar(cmd, "@p_table", table, 1000);
                AddVarChar(cmd, "@p_schema", schema, 8000);
                AddVarChar(cmd, "@p_env", env, 1000);
                cmd.Parameters.Add("@p_maxres", SqlDbType.Int).Value = maxRes;

                await cn.OpenAsync(ct);
                using (var r = await cmd.ExecuteReaderAsync(ct))
                {
                    // ReadAsync passe à la ligne suivante ; renvoie false à la fin
                    while (await r.ReadAsync(ct))
                    {
                        result.Rows.Add(new NodeSearchRow
                        {
                            Coords = ReadCoords(r, "DTA_"),
                            Row = new RowRef(Str(r, "LNA_UID"), Str(r, "LIN_UID"), Str(r, "EDG_DIR"))
                        });
                        // TotalLignes est répété sur chaque ligne : on le lit une fois
                        if (result.Total == null)
                            result.Total = IntOrNull(r, "TotalLignes");
                    }
                }
            }

            return result;
        }

        /// <summary>
        /// Voisins d'un nœud : appelle dbo.LINE_VIS_GetNodesSuccessorsPredecessors.
        /// type = "O" pour les successeurs (arêtes sortantes), "I" pour les prédécesseurs.
        /// </summary>
        public async Task<NeighborPage> GetNeighborsAsync(LoadRef node, string type, int maxRes, CancellationToken ct)
        {
            var page = new NeighborPage();

            using (var cn = new SqlConnection(_connectionString))
            using (var cmd = NewProcedure(cn, "dbo.LINE_VIS_GetNodesSuccessorsPredecessors"))
            {
                AddVarChar(cmd, "@p_lnauid", node.Row.LnaUid, 200);
                AddVarChar(cmd, "@p_linuid", node.Row.LinUid, 500);
                cmd.Parameters.Add("@p_edgdir", SqlDbType.Char, 1).Value = node.Row.EdgDir;
                cmd.Parameters.Add("@p_type", SqlDbType.Char, 1).Value = type;
                cmd.Parameters.Add("@p_useEdg", SqlDbType.Bit).Value = node.UseEdg;
                cmd.Parameters.Add("@p_maxres", SqlDbType.Int).Value = maxRes;

                await cn.OpenAsync(ct);
                using (var r = await cmd.ExecuteReaderAsync(ct))
                {
                    while (await r.ReadAsync(ct))
                    {
                        page.Rows.Add(new EdgeRow
                        {
                            Row = new RowRef(Str(r, "LNA_UID"), Str(r, "LIN_UID"), Str(r, "EDG_DIR")),
                            Dta = ReadCoords(r, "DTA_"),
                            Edg = ReadCoords(r, "EDG_"),
                            TxnDta = Str(r, "TXN_DTA"),
                            PrxTxnDta = Str(r, "PRX_TXN_DTA"),
                            RonApp = Str(r, "RON_APP"),
                            PckPgmNme = Str(r, "PCK_PGM_NME"),
                            ExePgmNme = Str(r, "EXE_PGM_NME"),
                            VrsExePgm = Str(r, "VRS_EXE_PGM"),
                            AppEnv = Str(r, "APP_ENV"),
                            DlyPgmTsp = DateOrNull(r, "DLY_PGM_TSP"),
                            LnaTsp = DateOrNull(r, "LNA_TSP"),
                            PgmTec = Str(r, "PGM_TEC"),
                            VrsLnaToo = Str(r, "VRS_LNA_TOO"),
                            TusInd = IntOrNull(r, "TUS_IND") ?? 0,
                            CurrentNode = Str(r, "CURRENT_NODE")
                        });
                        if (page.Total == null)
                            page.Total = IntOrNull(r, "TotalLignes");
                    }
                }
            }

            return page;
        }

        // ------------------------------------------------------------------
        // Petites aides
        // ------------------------------------------------------------------

        private SqlCommand NewProcedure(SqlConnection cn, string name)
        {
            // CommandType.StoredProcedure : le texte est le NOM d'une procédure
            return new SqlCommand(name, cn)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = _commandTimeout
            };
        }

        /// <summary>Paramètre VARCHAR (comme dans la procédure) ; texte vide -> NULL.</summary>
        private static void AddVarChar(SqlCommand cmd, string name, string value, int size)
        {
            var p = cmd.Parameters.Add(name, SqlDbType.VarChar, size);
            p.Value = string.IsNullOrWhiteSpace(value) ? (object)DBNull.Value : value.Trim();
        }

        private static NodeCoords ReadCoords(SqlDataReader r, string prefix)
        {
            return new NodeCoords(Str(r, prefix + "1"), Str(r, prefix + "2"), Str(r, prefix + "3"), Str(r, prefix + "4"));
        }

        /// <summary>Lit une colonne texte ; NULL en base -> null en C#.</summary>
        private static string Str(SqlDataReader r, string column)
        {
            int i = r.GetOrdinal(column);
            return r.IsDBNull(i) ? null : Convert.ToString(r.GetValue(i));
        }

        private static int? IntOrNull(SqlDataReader r, string column)
        {
            int i = r.GetOrdinal(column);
            return r.IsDBNull(i) ? (int?)null : Convert.ToInt32(r.GetValue(i));
        }

        /// <summary>La procédure remplace une date NULL par 1900-01-01 : on la remet à null.</summary>
        private static DateTime? DateOrNull(SqlDataReader r, string column)
        {
            int i = r.GetOrdinal(column);
            if (r.IsDBNull(i)) return null;
            var d = Convert.ToDateTime(r.GetValue(i));
            return d.Year <= 1900 ? (DateTime?)null : d;
        }
    }
}
