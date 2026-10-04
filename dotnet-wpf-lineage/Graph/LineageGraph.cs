using System;
using System.Collections.Generic;
using System.Linq;
using LineageExplorer.Data;

namespace LineageExplorer.Graph
{
    /// <summary>État de chargement d'un côté d'un nœud (prédécesseurs ou successeurs).</summary>
    public enum LoadState { NotLoaded, Loading, Loaded }

    /// <summary>
    /// Un nœud affiché. Level = colonne du dessin :
    ///   0 = nœud choisi (racine), -1, -2... = prédécesseurs (à gauche),
    ///   +1, +2... = successeurs (à droite).
    /// </summary>
    public sealed class GraphNode
    {
        public GraphNode(NodeCoords coords, LoadRef loadRef, int level, int order)
        {
            Coords = coords;
            LoadRef = loadRef;
            Level = level;
            Order = order;
        }

        public NodeCoords Coords { get; }
        public string Key { get { return Coords.Key; } }

        /// <summary>Comment redemander ce nœud à la procédure (ligne + bout DTA/EDG).</summary>
        public LoadRef LoadRef { get; }

        public int Level { get; }

        /// <summary>Ordre de création : départage les nœuds quand le dessin hésite.</summary>
        public int Order { get; }

        public List<GraphEdge> Incoming { get; } = new List<GraphEdge>();
        public List<GraphEdge> Outgoing { get; } = new List<GraphEdge>();

        // Chargement des voisins, côté gauche (I) et côté droit (O)
        public LoadState PredState { get; set; }
        public LoadState SuccState { get; set; }
        public int? PredTotal { get; set; }   // nombre d'arêtes en base (TotalLignes)
        public int? SuccTotal { get; set; }
        public int PredRows { get; set; }     // nombre d'arêtes reçues (au plus "max voisins")
        public int SuccRows { get; set; }

        // ---- Position : utilisée par GraphView ----
        // (X, Y) = position actuelle du coin haut-gauche de la carte ;
        // (TargetX, TargetY) = où le placement veut l'amener. L'animation fait
        // glisser X/Y vers la cible à chaque image : c'est ce qui rend le dessin fluide.
        public double X { get; set; }
        public double Y { get; set; }
        public double TargetX { get; set; }
        public double TargetY { get; set; }
        public double Opacity { get; set; }
        public object Visual { get; set; }

        public LoadState GetState(string type) { return type == "I" ? PredState : SuccState; }

        public void SetState(string type, LoadState s)
        {
            if (type == "I") PredState = s; else SuccState = s;
        }

        public IEnumerable<GraphNode> Neighbors()
        {
            return Incoming.Select(e => e.From).Concat(Outgoing.Select(e => e.To));
        }
    }

    /// <summary>Arête From -> To (le sens du lineage : la donnée va de From vers To).</summary>
    public sealed class GraphEdge
    {
        public GraphEdge(GraphNode from, GraphNode to)
        {
            From = from;
            To = to;
        }

        public GraphNode From { get; }
        public GraphNode To { get; }

        /// <summary>Lignes de LINE_VIS_EDG qui relient ces deux nœuds (souvent 1, parfois plusieurs traitements).</summary>
        public List<EdgeRow> Rows { get; } = new List<EdgeRow>();

        public object Visual { get; set; }
    }

    /// <summary>
    /// Le graphe en mémoire : nœuds, arêtes, et le calcul des positions
    /// (dessin "en couches" de gauche à droite).
    /// </summary>
    public sealed class LineageGraph
    {
        public const double NodeWidth = 240;
        public const double NodeHeight = 84;
        public const double ColumnGap = 150;   // espace horizontal entre deux colonnes
        public const double RowGap = 22;       // espace vertical entre deux cartes

        private readonly Dictionary<string, GraphNode> _nodes = new Dictionary<string, GraphNode>();
        private readonly Dictionary<string, GraphEdge> _edges = new Dictionary<string, GraphEdge>();
        private int _nextOrder;

        public IEnumerable<GraphNode> Nodes { get { return _nodes.Values; } }
        public IEnumerable<GraphEdge> Edges { get { return _edges.Values; } }
        public int NodeCount { get { return _nodes.Count; } }
        public GraphNode Root { get; private set; }

        public void Clear()
        {
            _nodes.Clear();
            _edges.Clear();
            Root = null;
            _nextOrder = 0;
        }

        /// <summary>Repart de zéro avec un seul nœud, au centre.</summary>
        public GraphNode SetRoot(NodeCoords coords, LoadRef loadRef)
        {
            Clear();
            Root = new GraphNode(coords, loadRef, 0, _nextOrder++) { Opacity = 1 };
            _nodes[Root.Key] = Root;
            return Root;
        }

        /// <summary>
        /// Ajoute au graphe les voisins renvoyés par la procédure.
        /// type "O" : center -> voisin (successeurs) ; type "I" : voisin -> center.
        /// Un voisin déjà affiché n'est pas recréé : on ajoute juste l'arête.
        /// Renvoie le nombre de lignes ignorées (voisin sans coordonnées).
        /// </summary>
        public int AddNeighbors(GraphNode center, string type, IEnumerable<EdgeRow> rows)
        {
            int skipped = 0;
            int level = center.Level + (type == "O" ? 1 : -1);

            foreach (var row in rows)
            {
                if (row.Edg == null || row.Edg.IsEmpty) { skipped++; continue; }

                GraphNode other;
                if (!_nodes.TryGetValue(row.Edg.Key, out other))
                {
                    // Le voisin est le bout "EDG" de cette ligne : pour le déplier
                    // plus tard on redonnera cette ligne avec @p_useEdg = 1.
                    other = new GraphNode(row.Edg, new LoadRef(row.Row, true), level, _nextOrder++)
                    {
                        // il "sort" de son parent puis glisse à sa place (animation)
                        X = center.X,
                        Y = center.Y,
                        Opacity = 0
                    };
                    _nodes[other.Key] = other;
                }

                if (other == center) continue;   // boucle sur soi-même : rien à dessiner

                var from = type == "O" ? center : other;
                var to = type == "O" ? other : center;
                string edgeKey = from.Key + "\u001E" + to.Key;

                GraphEdge edge;
                if (!_edges.TryGetValue(edgeKey, out edge))
                {
                    edge = new GraphEdge(from, to);
                    _edges[edgeKey] = edge;
                    from.Outgoing.Add(edge);
                    to.Incoming.Add(edge);
                }

                // la même ligne peut revenir si on déplie deux fois des nœuds voisins
                if (!edge.Rows.Any(r => r.Row.LnaUid == row.Row.LnaUid && r.Row.LinUid == row.Row.LinUid))
                    edge.Rows.Add(row);
            }

            return skipped;
        }

        /// <summary>
        /// Calcule TargetX / TargetY de chaque nœud.
        /// Une colonne par niveau. Dans une colonne, chaque nœud vise la hauteur
        /// moyenne de ses voisins de la colonne plus proche du centre (ça évite
        /// que les arêtes se croisent), puis on écarte les cartes qui se chevauchent.
        /// </summary>
        public void ComputeLayout()
        {
            if (_nodes.Count == 0) return;

            var levels = _nodes.Values.GroupBy(n => n.Level).ToDictionary(g => g.Key, g => g.OrderBy(n => n.Order).ToList());
            int min = levels.Keys.Min();
            int max = levels.Keys.Max();

            // Colonne 0 : les cartes empilées autour de y = 0
            List<GraphNode> level0;
            if (levels.TryGetValue(0, out level0))
                Place(level0, level0.Select((n, i) => (double)i * (NodeHeight + RowGap)).ToList(), 0);

            // Puis on s'éloigne du centre, colonne par colonne
            for (int l = 1; l <= max; l++)
                if (levels.ContainsKey(l)) PlaceLevel(levels[l], l, l - 1);
            for (int l = -1; l >= min; l--)
                if (levels.ContainsKey(l)) PlaceLevel(levels[l], l, l + 1);
        }

        private static void PlaceLevel(List<GraphNode> nodes, int level, int innerLevel)
        {
            // Hauteur souhaitée = moyenne des voisins déjà placés (colonne intérieure)
            var wanted = nodes.Select(n =>
            {
                var inner = n.Neighbors().Where(m => m.Level == innerLevel).ToList();
                if (inner.Count == 0) inner = n.Neighbors().Where(m => m.Level != level).ToList();
                double y = inner.Count == 0 ? 0 : inner.Average(m => m.TargetY + NodeHeight / 2);
                return new { Node = n, Y = y };
            })
            .OrderBy(w => w.Y).ThenBy(w => w.Node.Order)
            .ToList();

            Place(wanted.Select(w => w.Node).ToList(), wanted.Select(w => w.Y).ToList(), level);
        }

        /// <summary>
        /// Place les cartes d'une colonne au plus près des hauteurs voulues
        /// (centres, triés du haut vers le bas) sans qu'elles se chevauchent.
        /// </summary>
        private static void Place(List<GraphNode> nodes, List<double> wantedCenters, int level)
        {
            double step = NodeHeight + RowGap;
            var y = new double[nodes.Count];

            // 1) on descend : chaque carte au moins "step" sous la précédente
            for (int i = 0; i < nodes.Count; i++)
                y[i] = i == 0 ? wantedCenters[0] : Math.Max(wantedCenters[i], y[i - 1] + step);

            // 2) le bloc a pu glisser vers le bas : on le remonte pour qu'en moyenne
            //    chaque carte soit à sa hauteur voulue (les écarts restent inchangés)
            double shift = 0;
            for (int i = 0; i < nodes.Count; i++) shift += wantedCenters[i] - y[i];
            shift /= nodes.Count;

            for (int i = 0; i < nodes.Count; i++)
            {
                nodes[i].TargetX = level * (NodeWidth + ColumnGap);
                nodes[i].TargetY = y[i] + shift - NodeHeight / 2;
            }
        }
    }
}
