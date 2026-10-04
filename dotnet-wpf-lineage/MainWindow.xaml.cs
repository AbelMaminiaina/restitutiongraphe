using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using LineageExplorer.Data;
using LineageExplorer.Graph;

namespace LineageExplorer
{
    /// <summary>
    /// Fenêtre principale : relie la recherche (à gauche), le graphe (au centre)
    /// et les détails (à droite).
    ///
    /// Règle d'or pour la fluidité : chaque appel SQL est "await"é. Pendant que
    /// la base travaille, la fenêtre continue d'afficher, de zoomer, d'animer.
    /// </summary>
    public partial class MainWindow : Window
    {
        private static readonly Brush OkBrush = new SolidColorBrush(Color.FromRgb(0x16, 0xA3, 0x4A));
        private static readonly Brush ErrorBrush = new SolidColorBrush(Color.FromRgb(0xDC, 0x26, 0x26));

        private readonly LineageGraph _graph = new LineageGraph();
        private LineageRepository _repo;

        // Jetons d'annulation : Cancel() interrompt la requête SQL en cours
        private CancellationTokenSource _searchCts = new CancellationTokenSource();
        private CancellationTokenSource _graphCts = new CancellationTokenSource();
        private int _busyCount;

        public MainWindow()
        {
            InitializeComponent();

            Graph.Reset(_graph);
            Graph.NodeSelected += n => ShowDetails(DetailsModel.ForNode(n));
            Graph.EdgeSelected += e => ShowDetails(DetailsModel.ForEdge(e));
            Graph.ExpandRequested += (n, type) => { var _ = ExpandAsync(n, type); };
            Graph.NodeActionRequested += OnNodeAction;
            Graph.BackgroundClicked += () => { Graph.ClearSelection(); ShowDetails(null); };
        }

        // ------------------------------------------------------------------
        // Démarrage
        // ------------------------------------------------------------------

        private async void Window_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _repo = LineageRepository.FromConfig();
                ConnectionText.Text = _repo.DataSourceLabel;
                await _repo.TestConnectionAsync(CancellationToken.None);
                ConnectionDot.Fill = OkBrush;
            }
            catch (Exception ex)
            {
                ConnectionDot.Fill = ErrorBrush;
                ConnectionText.Text = "Connexion impossible";
                SetStatus("Connexion impossible : " + ex.Message, true);
                MessageBox.Show(this,
                    "Impossible de se connecter à la base.\n\n" + ex.Message +
                    "\n\nVérifie la chaîne de connexion « RestitutionGrapheProd » dans App.config.",
                    "Lineage Explorer", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            // Première liste : sans filtre, la procédure renvoie des nœuds dont la colonne commence par 'f'
            await RunSearchAsync();
            ColumnBox.Focus();
        }

        // ------------------------------------------------------------------
        // Recherche (colonne de gauche)
        // ------------------------------------------------------------------

        private async void SearchButton_Click(object sender, RoutedEventArgs e)
        {
            await RunSearchAsync();
        }

        private async Task RunSearchAsync()
        {
            if (_repo == null) return;

            // une nouvelle recherche annule la précédente si elle n'est pas finie
            _searchCts.Cancel();
            _searchCts = new CancellationTokenSource();
            var token = _searchCts.Token;

            BeginBusy("Recherche des nœuds…");
            try
            {
                var sw = Stopwatch.StartNew();
                var result = await _repo.SearchNodesAsync(ColumnBox.Text, TableBox.Text, SchemaBox.Text, EnvBox.Text,
                                                          ReadInt(MaxResultsBox, 100), token);
                ResultsList.ItemsSource = result.Rows;

                string total = result.Total == null ? ""
                             : result.Total > 1000 ? " — plus de 1000 correspondances, affine les filtres"
                             : " sur " + result.Total;
                ResultsInfo.Text = result.Rows.Count + " nœud(s)" + total;
                SetStatus("Recherche : " + result.Rows.Count + " nœud(s) en " + sw.ElapsedMilliseconds + " ms", false);
            }
            catch (Exception ex)
            {
                if (token.IsCancellationRequested) SetStatus("Recherche annulée", false);
                else SetStatus("Erreur pendant la recherche : " + ex.Message, true);
            }
            finally
            {
                EndBusy();
            }
        }

        private void ResultsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            var row = ResultsList.SelectedItem as NodeSearchRow;
            if (row != null) OpenRoot(row.Coords, new LoadRef(row.Row, false));
        }

        // ------------------------------------------------------------------
        // Graphe
        // ------------------------------------------------------------------

        /// <summary>Repart d'un nouveau nœud : il est placé au centre puis ses deux côtés se chargent.</summary>
        private async void OpenRoot(NodeCoords coords, LoadRef loadRef)
        {
            // les chargements de l'ancien graphe ne servent plus à rien
            _graphCts.Cancel();
            _graphCts = new CancellationTokenSource();

            var root = _graph.SetRoot(coords, loadRef);
            Graph.Reset(_graph);
            Graph.Sync();
            Graph.Select(root);
            Graph.CenterOnNode(root);
            EmptyHint.Visibility = Visibility.Collapsed;
            ShowDetails(DetailsModel.ForNode(root));

            // prédécesseurs et successeurs en parallèle (chacun sa connexion)
            await Task.WhenAll(ExpandAsync(root, "I"), ExpandAsync(root, "O"));
            if (_graph.Root == root) Graph.FitAll();
        }

        /// <summary>Charge les voisins d'un côté ("I" = prédécesseurs, "O" = successeurs).</summary>
        private async Task ExpandAsync(GraphNode node, string type)
        {
            if (_repo == null || node.GetState(type) != LoadState.NotLoaded) return;

            var token = _graphCts.Token;
            var rootAtStart = _graph.Root;
            string what = type == "I" ? "prédécesseurs" : "successeurs";
            string name = string.IsNullOrWhiteSpace(node.Coords.Column) ? "(nœud)" : node.Coords.Column;

            node.SetState(type, LoadState.Loading);
            Graph.RefreshNode(node);
            RefreshDetailsIfShown(node);

            // Nœud trouvé par son bout EDG avec une coordonnée NULL : la procédure
            // ne peut pas utiliser son index et lit les 7 M lignes. On prévient.
            bool slow = node.LoadRef.UseEdg && node.Coords.IsIncomplete;
            BeginBusy("Chargement des " + what + " de " + name +
                      (slow ? " — coordonnées incomplètes : la base lit toute la table, cela peut prendre plusieurs minutes…" : "…"));
            try
            {
                var sw = Stopwatch.StartNew();
                var page = await _repo.GetNeighborsAsync(node.LoadRef, type, ReadInt(MaxNeighborsBox, 100), token);

                // pendant l'attente, l'utilisateur a pu ouvrir un autre nœud
                if (_graph.Root != rootAtStart) return;

                int skipped = _graph.AddNeighbors(node, type, page.Rows);
                int total = page.Total ?? page.Rows.Count;
                if (type == "I") { node.PredRows = page.Rows.Count; node.PredTotal = total; }
                else { node.SuccRows = page.Rows.Count; node.SuccTotal = total; }
                node.SetState(type, LoadState.Loaded);

                Graph.Sync();
                // on ne bouge la vue que si les nouveaux nœuds sortent de l'écran
                var side = type == "I" ? node.Incoming.Select(x => x.From) : node.Outgoing.Select(x => x.To);
                Graph.FitNodes(new[] { node }.Concat(side), onlyIfNeeded: true);

                string msg = name + " : " + page.Rows.Count + " " + what.TrimEnd('s') + "(s)";
                if (total > page.Rows.Count) msg += " affichés sur " + total + " (augmente « Max voisins »)";
                if (skipped > 0) msg += ", " + skipped + " ligne(s) sans coordonnées ignorée(s)";
                SetStatus(msg + " — " + sw.ElapsedMilliseconds + " ms", false);
            }
            catch (Exception ex)
            {
                node.SetState(type, LoadState.NotLoaded);   // on pourra réessayer
                if (token.IsCancellationRequested) SetStatus("Chargement des " + what + " annulé", false);
                else SetStatus("Erreur pendant le chargement des " + what + " : " + ex.Message, true);
            }
            finally
            {
                EndBusy();
                Graph.RefreshNode(node);
                RefreshDetailsIfShown(node);
            }
        }

        private void OnNodeAction(GraphNode node, NodeAction action)
        {
            switch (action)
            {
                case NodeAction.ExpandPredecessors:
                    { var _ = ExpandAsync(node, "I"); }
                    break;
                case NodeAction.ExpandSuccessors:
                    { var _ = ExpandAsync(node, "O"); }
                    break;
                case NodeAction.MakeRoot:
                    ResultsList.SelectedItem = null;
                    OpenRoot(node.Coords, node.LoadRef);
                    break;
                case NodeAction.CopyName:
                    Clipboard.SetText(node.Coords.FullName);
                    SetStatus("Copié : " + node.Coords.FullName, false);
                    break;
            }
        }

        // ------------------------------------------------------------------
        // Panneau de détails
        // ------------------------------------------------------------------

        private void ShowDetails(DetailsModel model)
        {
            DetailsScroll.DataContext = model;
            DetailsScroll.Visibility = model == null ? Visibility.Collapsed : Visibility.Visible;
            DetailsEmpty.Visibility = model == null ? Visibility.Visible : Visibility.Collapsed;
            DetailsScroll.ScrollToTop();
        }

        /// <summary>Si le nœud affiché à droite vient de changer (chargement), on rafraîchit.</summary>
        private void RefreshDetailsIfShown(GraphNode node)
        {
            if (Graph.SelectedNode != node) return;
            var offset = DetailsScroll.VerticalOffset;
            ShowDetails(DetailsModel.ForNode(node));
            DetailsScroll.ScrollToVerticalOffset(offset);
        }

        // ------------------------------------------------------------------
        // Barre d'outils, clavier, annulation
        // ------------------------------------------------------------------

        private void ZoomIn_Click(object sender, RoutedEventArgs e) { Graph.ZoomCenter(1.25); }
        private void ZoomOut_Click(object sender, RoutedEventArgs e) { Graph.ZoomCenter(1 / 1.25); }
        private void Fit_Click(object sender, RoutedEventArgs e) { Graph.FitAll(); }

        private void Center_Click(object sender, RoutedEventArgs e)
        {
            var n = Graph.SelectedNode ?? _graph.Root;
            if (n != null) Graph.CenterOnNode(n);
        }

        private void Cancel_Click(object sender, RoutedEventArgs e) { CancelAll(); }

        private void CancelAll()
        {
            _searchCts.Cancel();
            _searchCts = new CancellationTokenSource();
            _graphCts.Cancel();
            _graphCts = new CancellationTokenSource();
        }

        private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape) { CancelAll(); e.Handled = true; return; }
            if (e.Key == Key.F && Keyboard.Modifiers == ModifierKeys.Control)
            {
                ColumnBox.Focus();
                ColumnBox.SelectAll();
                e.Handled = true;
                return;
            }

            // Raccourcis du graphe : pas quand on tape dans une zone de texte
            if (Keyboard.FocusedElement is TextBox) return;
            switch (e.Key)
            {
                case Key.F: Graph.FitAll(); e.Handled = true; break;
                case Key.C: Center_Click(null, null); e.Handled = true; break;
                case Key.Add:
                case Key.OemPlus: Graph.ZoomCenter(1.25); e.Handled = true; break;
                case Key.Subtract:
                case Key.OemMinus: Graph.ZoomCenter(1 / 1.25); e.Handled = true; break;
            }
        }

        // ------------------------------------------------------------------
        // Barre d'état
        // ------------------------------------------------------------------

        private void BeginBusy(string message)
        {
            _busyCount++;
            BusyBar.Visibility = Visibility.Visible;
            CancelButton.Visibility = Visibility.Visible;
            SetStatus(message, false);
        }

        private void EndBusy()
        {
            _busyCount = Math.Max(0, _busyCount - 1);
            if (_busyCount > 0) return;
            BusyBar.Visibility = Visibility.Collapsed;
            CancelButton.Visibility = Visibility.Collapsed;
        }

        private void SetStatus(string message, bool isError)
        {
            StatusText.Text = message;
            StatusText.Foreground = isError ? ErrorBrush : (Brush)FindResource("MutedBrush");
        }

        /// <summary>Lit un entier dans une zone de texte (valeur par défaut si invalide), borné à 1..1000.</summary>
        private static int ReadInt(TextBox box, int fallback)
        {
            int v;
            if (!int.TryParse(box.Text, out v)) v = fallback;
            return Math.Max(1, Math.Min(1000, v));
        }
    }
}
