using System;
using System.Collections.Generic;
using System.Linq;
using LineageExplorer.Data;
using LineageExplorer.Graph;

namespace LineageExplorer
{
    /// <summary>Une ligne "libellé : valeur" du panneau de détails.</summary>
    public sealed class DetailField
    {
        public DetailField(string label, string value)
        {
            Label = label;
            Value = value;
        }

        public string Label { get; }
        public string Value { get; }
    }

    /// <summary>Un encadré du panneau : une arête (ligne de LINE_VIS_EDG) et son traitement.</summary>
    public sealed class DetailCard
    {
        public string Header { get; set; }
        public List<DetailField> Fields { get; } = new List<DetailField>();
    }

    /// <summary>
    /// Contenu du panneau de droite. La fenêtre le donne en DataContext :
    /// le XAML affiche Title, Fields et Cards avec des {Binding}.
    /// </summary>
    public sealed class DetailsModel
    {
        private const int MaxCards = 200;   // au-delà, l'affichage devient lourd pour rien

        public string Title { get; set; }
        public string Subtitle { get; set; }
        public List<DetailField> Fields { get; } = new List<DetailField>();
        public string CardsHeader { get; set; }
        public List<DetailCard> Cards { get; } = new List<DetailCard>();

        public static DetailsModel ForNode(GraphNode n)
        {
            var m = new DetailsModel
            {
                Title = Or(n.Coords.Column, "(colonne vide)"),
                Subtitle = n.Level == 0 ? "Nœud de départ"
                         : n.Level < 0 ? "Prédécesseur — niveau " + n.Level
                         : "Successeur — niveau +" + n.Level
            };
            m.Fields.Add(new DetailField("Colonne", Or(n.Coords.Column)));
            m.Fields.Add(new DetailField("Table", Or(n.Coords.Table)));
            m.Fields.Add(new DetailField("Schéma", Or(n.Coords.Schema)));
            m.Fields.Add(new DetailField("Environnement", Or(n.Coords.Env)));
            m.Fields.Add(new DetailField("Prédécesseurs", Count(n.PredState, n.PredRows, n.PredTotal, "‹")));
            m.Fields.Add(new DetailField("Successeurs", Count(n.SuccState, n.SuccRows, n.SuccTotal, "›")));
            m.Fields.Add(new DetailField("Ligne de référence",
                n.LoadRef.Row.LnaUid + " / " + n.LoadRef.Row.LinUid + " / " + n.LoadRef.Row.EdgDir +
                (n.LoadRef.UseEdg ? "  (bout EDG)" : "  (bout DTA)")));

            var edges = n.Incoming.Select(e => new { Edge = e, Header = "← depuis " + Or(e.From.Coords.Column) })
                .Concat(n.Outgoing.Select(e => new { Edge = e, Header = "→ vers " + Or(e.To.Coords.Column) }));
            foreach (var x in edges)
                foreach (var row in x.Edge.Rows)
                    m.AddCard(x.Header, row);

            m.CardsHeader = m.Cards.Count == 0 ? "Aucune arête affichée pour l'instant"
                                               : "Arêtes affichées (" + m.Cards.Count + ")";
            return m;
        }

        public static DetailsModel ForEdge(GraphEdge e)
        {
            var m = new DetailsModel
            {
                Title = Or(e.From.Coords.Column) + "  →  " + Or(e.To.Coords.Column),
                Subtitle = e.Rows.Count == 1 ? "1 traitement" : e.Rows.Count + " traitements"
            };
            m.Fields.Add(new DetailField("Depuis", e.From.Coords.FullName));
            m.Fields.Add(new DetailField("Vers", e.To.Coords.FullName));
            foreach (var row in e.Rows) m.AddCard(row.Row.LnaUid, row);
            m.CardsHeader = "Lignes de LINE_VIS_EDG";
            return m;
        }

        private void AddCard(string header, EdgeRow r)
        {
            if (Cards.Count >= MaxCards) return;
            var c = new DetailCard { Header = header };
            Add(c, "LNA_UID", r.Row.LnaUid);
            Add(c, "LIN_UID", r.Row.LinUid);
            Add(c, "Sens (EDG_DIR)", r.Row.EdgDir == "O" ? "O — sortante" : r.Row.EdgDir == "I" ? "I — entrante" : r.Row.EdgDir);
            Add(c, "Application", r.RonApp);
            Add(c, "Package", r.PckPgmNme);
            Add(c, "Programme", Join(r.ExePgmNme, r.VrsExePgm));
            Add(c, "Env. applicatif", r.AppEnv);
            Add(c, "Technologie", r.PgmTec);
            Add(c, "Date programme", Date(r.DlyPgmTsp));
            Add(c, "Date lineage", Date(r.LnaTsp));
            Add(c, "Outil lineage", r.VrsLnaToo);
            Add(c, "TXN_DTA", r.TxnDta);
            Add(c, "PRX_TXN_DTA", r.PrxTxnDta);
            Cards.Add(c);
        }

        private static void Add(DetailCard c, string label, string value)
        {
            if (!string.IsNullOrWhiteSpace(value)) c.Fields.Add(new DetailField(label, value));
        }

        private static string Count(LoadState state, int rows, int? total, string button)
        {
            if (state == LoadState.NotLoaded) return "non chargés (bouton " + button + " de la carte)";
            if (state == LoadState.Loading) return "chargement…";
            int t = total ?? rows;
            return rows < t ? rows + " affichés sur " + t : rows.ToString();
        }

        private static string Join(string a, string b)
        {
            if (string.IsNullOrWhiteSpace(b)) return a;
            if (string.IsNullOrWhiteSpace(a)) return b;
            return a + "  (" + b + ")";
        }

        private static string Date(DateTime? d)
        {
            return d.HasValue ? d.Value.ToString("dd/MM/yyyy HH:mm:ss") : null;
        }

        private static string Or(string s, string empty = "—")
        {
            return string.IsNullOrWhiteSpace(s) ? empty : s;
        }
    }
}
