using System;
using System.Collections.Generic;
using System.Linq;

namespace LineageExplorer.Data
{
    /// <summary>
    /// Coordonnées d'un nœud du lineage : les 4 colonnes DTA_1..DTA_4 (ou
    /// EDG_1..EDG_4 pour l'autre bout d'une arête).
    /// D'après les paramètres de LINE_VIS_NodesList :
    ///   1 = colonne, 2 = table, 3 = schéma, 4 = environnement.
    /// </summary>
    public sealed class NodeCoords
    {
        public NodeCoords(string column, string table, string schema, string env)
        {
            Column = column;
            Table = table;
            Schema = schema;
            Env = env;
        }

        public string Column { get; }
        public string Table { get; }
        public string Schema { get; }
        public string Env { get; }

        /// <summary>Vrai si les 4 coordonnées sont vides : pas de nœud à afficher.</summary>
        public bool IsEmpty
        {
            get { return Parts().All(string.IsNullOrWhiteSpace); }
        }

        /// <summary>Vrai si au moins une coordonnée est NULL / vide.</summary>
        public bool IsIncomplete
        {
            get { return Parts().Any(string.IsNullOrWhiteSpace); }
        }

        /// <summary>
        /// Identifiant du nœud dans le graphe. La base compare sans tenir compte
        /// des majuscules ni des espaces de fin (collation CI) : on fait pareil,
        /// sinon un même nœud apparaîtrait deux fois.
        /// </summary>
        public string Key
        {
            get
            {
                return string.Join("\u001F", Parts().Select(p => (p ?? "").TrimEnd().ToUpperInvariant()));
            }
        }

        /// <summary>Nom complet lisible : env / schéma / table / colonne.</summary>
        public string FullName
        {
            get
            {
                var parts = new[] { Env, Schema, Table, Column }.Where(p => !string.IsNullOrWhiteSpace(p));
                return string.Join(" / ", parts);
            }
        }

        private IEnumerable<string> Parts()
        {
            yield return Column;
            yield return Table;
            yield return Schema;
            yield return Env;
        }
    }

    /// <summary>Clé primaire d'une ligne de LINE_VIS_EDG.</summary>
    public sealed class RowRef
    {
        public RowRef(string lnaUid, string linUid, string edgDir)
        {
            LnaUid = lnaUid;
            LinUid = linUid;
            EdgDir = edgDir;
        }

        public string LnaUid { get; }
        public string LinUid { get; }

        /// <summary>'O' = arête sortante (vers un successeur), 'I' = entrante (depuis un prédécesseur).</summary>
        public string EdgDir { get; }
    }

    /// <summary>
    /// Ce qu'il faut donner à LINE_VIS_GetNodesSuccessorsPredecessors pour
    /// retrouver un nœud : une ligne de LINE_VIS_EDG + quel bout de cette ligne
    /// (UseEdg = false : DTA_1..4, UseEdg = true : EDG_1..4).
    /// </summary>
    public sealed class LoadRef
    {
        public LoadRef(RowRef row, bool useEdg)
        {
            Row = row;
            UseEdg = useEdg;
        }

        public RowRef Row { get; }
        public bool UseEdg { get; }
    }

    /// <summary>Une ligne renvoyée par LINE_VIS_NodesList.</summary>
    public sealed class NodeSearchRow
    {
        public NodeCoords Coords { get; set; }
        public RowRef Row { get; set; }

        // Propriétés utilisées par la liste de résultats (binding XAML)
        public string ColumnText { get { return Display(Coords.Column); } }
        public string TableText { get { return Display(Coords.Table); } }
        public string SchemaText { get { return Display(Coords.Schema); } }
        public string EnvText { get { return Display(Coords.Env); } }

        private static string Display(string s)
        {
            return string.IsNullOrWhiteSpace(s) ? "—" : s;
        }
    }

    /// <summary>Résultat complet de LINE_VIS_NodesList.</summary>
    public sealed class SearchResult
    {
        public List<NodeSearchRow> Rows { get; } = new List<NodeSearchRow>();

        /// <summary>
        /// Nombre de nœuds trouvés : NULL quand aucun filtre n'est donné,
        /// 1001 = « plus de 1000 » (voir les commentaires de la procédure).
        /// </summary>
        public int? Total { get; set; }
    }

    /// <summary>
    /// Une arête renvoyée par LINE_VIS_GetNodesSuccessorsPredecessors :
    /// la ligne de LINE_VIS_EDG + l'en-tête LINE_VIS_HEA du traitement (LNA_UID).
    /// </summary>
    public sealed class EdgeRow
    {
        public RowRef Row { get; set; }
        public NodeCoords Dta { get; set; }   // le nœud demandé
        public NodeCoords Edg { get; set; }   // le voisin (autre bout de l'arête)
        public string TxnDta { get; set; }
        public string PrxTxnDta { get; set; }
        public string RonApp { get; set; }
        public string PckPgmNme { get; set; }
        public string ExePgmNme { get; set; }
        public string VrsExePgm { get; set; }
        public string AppEnv { get; set; }
        public DateTime? DlyPgmTsp { get; set; }
        public DateTime? LnaTsp { get; set; }
        public string PgmTec { get; set; }
        public string VrsLnaToo { get; set; }
        public int TusInd { get; set; }
        public string CurrentNode { get; set; }
    }

    /// <summary>Une page de voisins + le nombre total de voisins en base.</summary>
    public sealed class NeighborPage
    {
        public List<EdgeRow> Rows { get; } = new List<EdgeRow>();
        public int? Total { get; set; }
    }
}
