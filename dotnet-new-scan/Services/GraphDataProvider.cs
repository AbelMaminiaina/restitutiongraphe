// D'où viennent les données du graphe : SQL Server, ou un graphe généré en
// mémoire.
//
// Le but : l'application marche sur N'IMPORTE QUEL poste, SANS aucun script
// SQL ni base à créer. Trois modes (config Data:Source ou variable
// d'environnement RESTITUTION_DATA_SOURCE) :
//
//   "auto" (défaut) : on sonde SQL Server (.\SQLEXPRESS01 / RestitutionGraphe
//                     + table LINE_VIS_EDG non vide). Joignable -> SQL.
//                     Sinon -> graphe généré.
//   "sql"           : force SQL Server (échec si absent).
//   "generated"     : force le graphe généré (ignore SQL même s'il est là).
//
// Toutes les autres classes (InMemoryGraphService, GraphScanService,
// SccCondensationService, HomeController) passent par ce provider et ne
// savent pas d'où viennent les arêtes.
//
// C# 8.0 : pas d'async.

using System;
using System.Collections.Generic;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

using PathFinder.ScanMvc.Models;

namespace PathFinder.ScanMvc.Services
{
    public enum DataSourceMode
    {
        Sql,        // vraies données, table dbo.LINE_VIS_EDG
        Generated,  // graphe de démonstration généré en mémoire
    }

    public sealed class GraphDataProvider
    {
        private readonly LineVisEdgRepository _sql;
        private readonly GeneratedGraphData _generated;

        public DataSourceMode Mode { get; }

        // Phrase lisible pour l'interface (« Source : … »).
        public string Description { get; }

        // true seulement en mode SQL : les pré-calculs § 11.4 / § 11.5 écrivent
        // des tables et n'ont de sens que sur le grand graphe SQL.
        public bool ScanAvailable => Mode == DataSourceMode.Sql;

        public GraphDataProvider(
            IConfiguration configuration,
            LineVisEdgRepository sql,
            GeneratedGraphData generated,
            ILogger<GraphDataProvider> logger)
        {
            _sql = sql;
            _generated = generated;

            var requested = (Environment.GetEnvironmentVariable("RESTITUTION_DATA_SOURCE")
                ?? configuration["Data:Source"]
                ?? "auto").Trim().ToLowerInvariant();

            switch (requested)
            {
                case "sql":
                    Mode = DataSourceMode.Sql;
                    break;
                case "generated":
                case "genere":
                case "memoire":
                    Mode = DataSourceMode.Generated;
                    break;
                default: // "auto"
                    Mode = _sql.CanConnect() ? DataSourceMode.Sql : DataSourceMode.Generated;
                    break;
            }

            Description = Mode == DataSourceMode.Sql
                ? $"SQL Server — {_sql.ConnectionSummary}"
                : $"graphe généré en mémoire — {_generated.NodeCount:N0} nœuds, "
                  + $"{_generated.EdgeCount:N0} arêtes, graine fixe (aucune base requise)";

            logger.LogInformation("Source de données ({Requested}) : {Description}", requested, Description);
        }

        // ----- lecture des arêtes (pour InMemoryGraphService et les scans) --

        public IEnumerable<(string From, string To)> StreamAllDirectedEdges()
            => Mode == DataSourceMode.Sql ? _sql.StreamAllDirectedEdges() : _generated.DirectedEdges;

        // Connexité faible : le sens ne compte pas, donc les mêmes couples
        // suffisent (le graphe généré n'a pas de colonne Direction).
        public IEnumerable<(string From, string To)> StreamAllEdges()
            => Mode == DataSourceMode.Sql ? _sql.StreamAllEdges() : _generated.DirectedEdges;

        // ----- transformation portée par chaque arête du chemin trouvé -----

        public List<PathEdge> DescribePath(IReadOnlyList<string> path)
        {
            if (Mode == DataSourceMode.Sql)
                return _sql.DescribePath(path);

            var edges = new List<PathEdge>();
            for (var i = 0; i < path.Count - 1; i++)
                edges.Add(new PathEdge(i + 1, path[i], path[i + 1],
                    _generated.EdgeTransformation(path[i], path[i + 1])));
            return edges;
        }
    }
}
