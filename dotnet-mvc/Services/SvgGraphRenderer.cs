// Rendu d'un GraphSample en image SVG, entièrement côté serveur.
//
// SVG = du balisage XML, pas du JavaScript : le fichier produit est une image
// statique, affichable dans une balise <img> ou téléchargeable telle quelle.
// Aucune dépendance externe : la disposition des nœuds (layout) et le tracé
// sont calculés ici « à la main ».

using System.Globalization;
using System.Text;

using PathFinder.RazorMvc.Models;

namespace PathFinder.RazorMvc.Services;

public class SvgGraphRenderer
{
    private const int NodeRadius = 16;

    private readonly record struct Pt(double X, double Y);

    public string Render(GraphSample g)
    {
        var pos = g.Layout == GraphLayout.Layered ? LayeredLayout(g) : CircularLayout(g);

        var margin = 32.0;
        var minX = pos.Values.Min(p => p.X) - margin;
        var minY = pos.Values.Min(p => p.Y) - margin;
        var maxX = pos.Values.Max(p => p.X) + margin;
        var maxY = pos.Values.Max(p => p.Y) + margin;
        var w = maxX - minX;
        var h = maxY - minY;

        var sb = new StringBuilder();
        sb.Append($"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"{F(minX)} {F(minY)} {F(w)} {F(h)}\" ");
        sb.Append($"width=\"{F(w)}\" height=\"{F(h)}\" font-family=\"system-ui, -apple-system, sans-serif\">");
        sb.Append("<defs><marker id=\"arrow\" viewBox=\"0 0 10 10\" refX=\"9\" refY=\"5\" ");
        sb.Append("markerWidth=\"7\" markerHeight=\"7\" orient=\"auto\">");
        sb.Append("<path d=\"M0,0 L10,5 L0,10 z\" fill=\"#94a3b8\"/></marker></defs>");
        sb.Append($"<rect x=\"{F(minX)}\" y=\"{F(minY)}\" width=\"{F(w)}\" height=\"{F(h)}\" fill=\"#ffffff\"/>");

        // --- arêtes ---
        foreach (var e in g.Edges)
        {
            var a = pos[e.From];
            var b = pos[e.To];
            var (x1, y1, x2, y2) = Trim(a, b, g.Directed);

            sb.Append($"<line x1=\"{F(x1)}\" y1=\"{F(y1)}\" x2=\"{F(x2)}\" y2=\"{F(y2)}\" ");
            sb.Append("stroke=\"#94a3b8\" stroke-width=\"1.6\"");
            if (g.Directed) sb.Append(" marker-end=\"url(#arrow)\"");
            sb.Append("/>");

            if (g.Weighted && e.Weight is { } weight)
            {
                var mx = (a.X + b.X) / 2;
                var my = (a.Y + b.Y) / 2;
                sb.Append($"<rect x=\"{F(mx - 9)}\" y=\"{F(my - 9)}\" width=\"18\" height=\"16\" rx=\"3\" ");
                sb.Append("fill=\"#ffffff\" stroke=\"#e5e7eb\"/>");
                sb.Append($"<text x=\"{F(mx)}\" y=\"{F(my + 3)}\" text-anchor=\"middle\" ");
                sb.Append($"font-size=\"10\" fill=\"#6b7280\">{weight}</text>");
            }
        }

        // --- nœuds ---
        foreach (var n in g.Nodes)
        {
            var p = pos[n];
            sb.Append($"<circle cx=\"{F(p.X)}\" cy=\"{F(p.Y)}\" r=\"{NodeRadius}\" fill=\"#4C72B0\"/>");
            sb.Append($"<text x=\"{F(p.X)}\" y=\"{F(p.Y + 4)}\" text-anchor=\"middle\" ");
            sb.Append($"font-size=\"11\" fill=\"#ffffff\">{Escape(n)}</text>");
        }

        sb.Append("</svg>");
        return sb.ToString();
    }

    // Raccourcit le segment pour qu'il s'arrête au bord des disques (et laisse
    // la place à la pointe de flèche si le graphe est orienté).
    private static (double, double, double, double) Trim(Pt a, Pt b, bool directed)
    {
        var dx = b.X - a.X;
        var dy = b.Y - a.Y;
        var len = Math.Sqrt(dx * dx + dy * dy);
        if (len < 1e-6) return (a.X, a.Y, b.X, b.Y);

        var ux = dx / len;
        var uy = dy / len;
        var startGap = NodeRadius + 1.0;
        var endGap = NodeRadius + (directed ? 5.0 : 1.0);
        return (a.X + ux * startGap, a.Y + uy * startGap, b.X - ux * endGap, b.Y - uy * endGap);
    }

    // --- Layout circulaire : une composante connexe = un cercle ; les cercles
    //     sont disposés en grille. ---
    private static Dictionary<string, Pt> CircularLayout(GraphSample g)
    {
        var components = Components(g);
        var result = new Dictionary<string, Pt>();

        var cols = (int)Math.Ceiling(Math.Sqrt(components.Count));
        const double cell = 240;

        for (var ci = 0; ci < components.Count; ci++)
        {
            var comp = components[ci];
            var cx = (ci % cols) * cell + cell / 2;
            var cy = (ci / cols) * cell + cell / 2;

            if (comp.Count == 1)
            {
                result[comp[0]] = new Pt(cx, cy);
                continue;
            }

            var r = Math.Min(92.0, 24.0 + 12.0 * comp.Count);
            for (var i = 0; i < comp.Count; i++)
            {
                var angle = -Math.PI / 2 + i * 2 * Math.PI / comp.Count;
                result[comp[i]] = new Pt(cx + r * Math.Cos(angle), cy + r * Math.Sin(angle));
            }
        }

        return result;
    }

    // --- Layout par niveaux : pour les DAG (niveau = distance depuis un nœud
    //     sans prédécesseur) et les arbres (niveau = distance depuis Nodes[0]). ---
    private static Dictionary<string, Pt> LayeredLayout(GraphSample g)
    {
        var layer = new Dictionary<string, int>();

        if (g.Directed)
        {
            var indegree = g.Nodes.ToDictionary(n => n, _ => 0);
            foreach (var e in g.Edges) indegree[e.To]++;

            var successors = g.Nodes.ToDictionary(n => n, _ => new List<string>());
            foreach (var e in g.Edges) successors[e.From].Add(e.To);

            var work = new Queue<string>();
            foreach (var n in g.Nodes.Where(n => indegree[n] == 0))
            {
                layer[n] = 0;
                work.Enqueue(n);
            }

            while (work.Count > 0)
            {
                var u = work.Dequeue();
                foreach (var v in successors[u])
                {
                    var candidate = layer[u] + 1;
                    if (!layer.TryGetValue(v, out var current) || candidate > current)
                    {
                        layer[v] = candidate;
                        work.Enqueue(v);
                    }
                }
            }
        }
        else
        {
            var adjacency = g.Nodes.ToDictionary(n => n, _ => new List<string>());
            foreach (var e in g.Edges)
            {
                adjacency[e.From].Add(e.To);
                adjacency[e.To].Add(e.From);
            }

            var queue = new Queue<string>();
            layer[g.Nodes[0]] = 0;
            queue.Enqueue(g.Nodes[0]);
            while (queue.Count > 0)
            {
                var u = queue.Dequeue();
                foreach (var v in adjacency[u])
                {
                    if (layer.ContainsKey(v)) continue;
                    layer[v] = layer[u] + 1;
                    queue.Enqueue(v);
                }
            }
        }

        foreach (var n in g.Nodes) layer.TryAdd(n, 0);

        var byLayer = g.Nodes
            .GroupBy(n => layer[n])
            .OrderBy(grp => grp.Key)
            .ToDictionary(grp => grp.Key, grp => grp.ToList());

        const double xGap = 92, yGap = 92;
        var widest = byLayer.Values.Max(v => v.Count);
        var result = new Dictionary<string, Pt>();

        foreach (var (level, nodes) in byLayer)
        {
            for (var i = 0; i < nodes.Count; i++)
            {
                var x = (i - (nodes.Count - 1) / 2.0) * xGap + widest * xGap / 2 + 20;
                var y = level * yGap + 20;
                result[nodes[i]] = new Pt(x, y);
            }
        }

        return result;
    }

    // Composantes connexes au sens non orienté (parcours en profondeur).
    private static List<List<string>> Components(GraphSample g)
    {
        var adjacency = g.Nodes.ToDictionary(n => n, _ => new List<string>());
        foreach (var e in g.Edges)
        {
            adjacency[e.From].Add(e.To);
            adjacency[e.To].Add(e.From);
        }

        var seen = new HashSet<string>();
        var components = new List<List<string>>();

        foreach (var start in g.Nodes)
        {
            if (!seen.Add(start)) continue;

            var component = new List<string>();
            var stack = new Stack<string>();
            stack.Push(start);
            while (stack.Count > 0)
            {
                var cur = stack.Pop();
                component.Add(cur);
                foreach (var next in adjacency[cur])
                    if (seen.Add(next))
                        stack.Push(next);
            }

            components.Add(component);
        }

        return components;
    }

    private static string F(double d) => d.ToString("0.##", CultureInfo.InvariantCulture);

    private static string Escape(string s) => s
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
}
