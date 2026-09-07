// Graphe de démonstration GÉNÉRÉ EN MÉMOIRE — aucune base, aucun fichier.
//
// Sert de source de repli quand SQL Server n'est pas disponible sur le poste
// (voir GraphDataProvider). Déterministe : graine fixe => exactement le même
// graphe à chaque démarrage, sur n'importe quelle machine.
//
// Même forme que scripts/seed_sqlserver.py : des nœuds "N1".."Nk", 2 à 6
// arêtes sortantes chacun (cibles tirées au hasard, dédupliquées), une
// Transformation aléatoire par arête.
//
// C# 8.0 : classe classique, aucun async.

using System;
using System.Collections.Generic;

namespace PathFinder.ScanMvc.Services
{
    public sealed class GeneratedGraphData
    {
        private const int MinOutDegree = 2;
        private const int MaxOutDegree = 6;
        private const int Seed = 12345;   // graine fixe = graphe reproductible

        private static readonly string[] TransformationLabels =
        {
            "SELECT", "JOIN", "FILTER", "AGGREGATE", "MERGE", "CAST", "PIVOT", "UNION_ALL",
        };

        public int NodeCount { get; }
        public int EdgeCount => _edges.Count;

        private readonly List<(string From, string To)> _edges;
        private readonly Dictionary<(string From, string To), string> _transformationByEdge;

        // nodeCount : nombre de nœuds à générer (défaut 5 000 — assez pour que
        // les algorithmes soient intéressants, assez petit pour être instantané).
        public GeneratedGraphData(int nodeCount = 5000)
        {
            NodeCount = Math.Max(2, nodeCount);

            var random = new Random(Seed);
            var seenPairs = new HashSet<(int, int)>();
            _edges = new List<(string, string)>();
            _transformationByEdge = new Dictionary<(string, string), string>();

            for (var i = 1; i <= NodeCount; i++)
            {
                var outDegree = random.Next(MinOutDegree, MaxOutDegree + 1);
                for (var k = 0; k < outDegree; k++)
                {
                    var j = random.Next(1, NodeCount + 1);
                    if (j == i || !seenPairs.Add((i, j)))
                        continue;

                    var edge = ("N" + i, "N" + j);
                    _edges.Add(edge);
                    _transformationByEdge[edge] =
                        TransformationLabels[random.Next(TransformationLabels.Length)];
                }
            }
        }

        // Toutes les arêtes orientées (source -> cible).
        public IEnumerable<(string From, string To)> DirectedEdges => _edges;

        // Transformation portée par l'arête from -> to, ou null si l'arête
        // n'existe pas dans ce sens.
        public string? EdgeTransformation(string from, string to)
            => _transformationByEdge.TryGetValue((from, to), out var label) ? label : null;
    }
}
