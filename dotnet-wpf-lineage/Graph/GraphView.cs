using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace LineageExplorer.Graph
{
    /// <summary>Actions du menu clic droit d'un nœud.</summary>
    public enum NodeAction { ExpandPredecessors, ExpandSuccessors, MakeRoot, CopyName }

    /// <summary>
    /// Zone de dessin du graphe, écrite à la main (pas de bibliothèque) :
    ///   - molette = zoom autour de la souris, glisser le fond = déplacer ;
    ///   - les cartes et la "caméra" glissent vers leur position cible à chaque
    ///     image (CompositionTarget.Rendering) : aucun saut, tout est animé ;
    ///   - les boutons ‹ et › de chaque carte déplient prédécesseurs / successeurs.
    ///
    /// Repères : "monde" = coordonnées du graphe (calculées par LineageGraph),
    /// "écran" = pixels du contrôle. écran = monde × échelle + décalage.
    /// </summary>
    public sealed class GraphView : Border
    {
        // Couleurs (mêmes valeurs que App.xaml)
        private static readonly Brush PredBrush = Frozen(Color.FromRgb(0x7C, 0x3A, 0xED));
        private static readonly Brush RootBrush = Frozen(Color.FromRgb(0x25, 0x63, 0xEB));
        private static readonly Brush SuccBrush = Frozen(Color.FromRgb(0xEA, 0x58, 0x0C));
        private static readonly Brush EdgeBrush = Frozen(Color.FromRgb(0xA8, 0xB3, 0xC4));
        private static readonly Brush EdgeHotBrush = Frozen(Color.FromRgb(0x25, 0x63, 0xEB));
        private static readonly Brush CardBrush = Frozen(Colors.White);
        private static readonly Brush CardBorderBrush = Frozen(Color.FromRgb(0xE2, 0xE8, 0xF0));
        private static readonly Brush TextBrush = Frozen(Color.FromRgb(0x0F, 0x17, 0x2A));
        private static readonly Brush MutedBrush = Frozen(Color.FromRgb(0x64, 0x74, 0x8B));

        private const double ButtonSize = 22;
        private const double Overhang = ButtonSize / 2;   // les boutons dépassent de la carte

        private readonly Canvas _world = new Canvas();
        private readonly Canvas _edgeLayer = new Canvas();
        private readonly Canvas _nodeLayer = new Canvas();
        private readonly MatrixTransform _camera = new MatrixTransform();
        private readonly Stopwatch _clock = Stopwatch.StartNew();

        // Caméra : valeurs actuelles et valeurs visées (l'animation va des unes aux autres)
        private double _scale = 1, _offX, _offY;
        private double _tScale = 1, _tOffX, _tOffY;

        private bool _animating;
        private double _lastFrame;
        private bool _panning;
        private Point _panStart;    // dernière position de la souris pendant le glisser
        private Point _pressPoint;  // position au moment du clic

        private LineageGraph _graph;
        private GraphNode _hovered;

        public GraphView()
        {
            ClipToBounds = true;
            Focusable = true;
            Background = MakeDotGrid(_camera);

            _world.Children.Add(_edgeLayer);
            _world.Children.Add(_nodeLayer);
            _world.RenderTransform = _camera;
            Child = _world;

            SizeChanged += (s, e) =>
            {
                // Au premier affichage, on centre le point (0,0) du monde
                if (e.PreviousSize.Width == 0 && _graph == null)
                    CenterOn(new Point(0, 0), 1, animate: false);
            };
        }

        // ------------------------------------------------------------------
        // Événements vers la fenêtre
        // ------------------------------------------------------------------
        public event Action<GraphNode> NodeSelected;
        public event Action<GraphEdge> EdgeSelected;
        public event Action<GraphNode, string> ExpandRequested;   // type "I" ou "O"
        public event Action<GraphNode, NodeAction> NodeActionRequested;
        public event Action BackgroundClicked;

        public GraphNode SelectedNode { get; private set; }
        public GraphEdge SelectedEdge { get; private set; }

        // ------------------------------------------------------------------
        // Synchronisation avec le graphe
        // ------------------------------------------------------------------

        /// <summary>Retire tous les dessins (nouveau graphe).</summary>
        public void Reset(LineageGraph graph)
        {
            _graph = graph;
            _edgeLayer.Children.Clear();
            _nodeLayer.Children.Clear();
            SelectedNode = null;
            SelectedEdge = null;
            _hovered = null;
        }

        /// <summary>
        /// Crée les dessins des nouveaux nœuds / arêtes, recalcule le placement
        /// et lance l'animation vers les nouvelles positions.
        /// </summary>
        public void Sync()
        {
            if (_graph == null) return;

            foreach (var n in _graph.Nodes.Where(n => n.Visual == null))
            {
                var v = new NodeVisual(this, n);
                n.Visual = v;
                _nodeLayer.Children.Add(v);
            }
            foreach (var e in _graph.Edges.Where(e => e.Visual == null))
            {
                var v = new EdgeVisual(this, e);
                e.Visual = v;
                _edgeLayer.Children.Add(v.HitPath);
                _edgeLayer.Children.Add(v.Path);
            }

            foreach (var n in _graph.Nodes) ((NodeVisual)n.Visual).Refresh();
            foreach (var e in _graph.Edges) ((EdgeVisual)e.Visual).Refresh();

            _graph.ComputeLayout();
            UpdateHighlight();
            StartAnimation();
        }

        /// <summary>Met à jour l'affichage d'un nœud (boutons, compteurs) sans rien déplacer.</summary>
        public void RefreshNode(GraphNode n)
        {
            var v = n.Visual as NodeVisual;
            if (v != null) v.Refresh();
        }

        public void Select(GraphNode n)
        {
            SelectedNode = n;
            SelectedEdge = null;
            UpdateHighlight();
        }

        public void ClearSelection()
        {
            SelectedNode = null;
            SelectedEdge = null;
            UpdateHighlight();
        }

        // ------------------------------------------------------------------
        // Caméra : zoom, ajustement, centrage
        // ------------------------------------------------------------------

        /// <summary>Zoom (facteur > 1 = rapprocher) autour d'un point de l'écran.</summary>
        public void ZoomAt(Point screen, double factor)
        {
            double newScale = Clamp(_tScale * factor, 0.12, 2.5);
            // le point du monde sous la souris doit rester sous la souris
            double wx = (screen.X - _tOffX) / _tScale;
            double wy = (screen.Y - _tOffY) / _tScale;
            _tScale = newScale;
            _tOffX = screen.X - wx * newScale;
            _tOffY = screen.Y - wy * newScale;
            StartAnimation();
        }

        public void ZoomCenter(double factor)
        {
            ZoomAt(new Point(ActualWidth / 2, ActualHeight / 2), factor);
        }

        /// <summary>Cadre tout le graphe dans la fenêtre.</summary>
        public void FitAll()
        {
            if (_graph == null || _graph.NodeCount == 0) return;
            FitTo(TargetBounds(_graph.Nodes), onlyIfNeeded: false);
        }

        /// <summary>
        /// Cadre un ensemble de nœuds. onlyIfNeeded = true : ne bouge que si une
        /// partie est hors de l'écran, et ne zoome jamais plus près qu'avant.
        /// </summary>
        public void FitNodes(IEnumerable<GraphNode> nodes, bool onlyIfNeeded)
        {
            var list = nodes.ToList();
            if (list.Count == 0) return;
            FitTo(TargetBounds(list), onlyIfNeeded);
        }

        public void CenterOnNode(GraphNode n)
        {
            CenterOn(new Point(n.TargetX + LineageGraph.NodeWidth / 2, n.TargetY + LineageGraph.NodeHeight / 2),
                     Math.Max(_tScale, 0.8), animate: true);
        }

        private void FitTo(Rect world, bool onlyIfNeeded)
        {
            if (ActualWidth < 10 || ActualHeight < 10) return;
            const double margin = 50;

            if (onlyIfNeeded)
            {
                // déjà entièrement visible avec la caméra visée ? rien à faire
                var screenRect = new Rect(world.X * _tScale + _tOffX, world.Y * _tScale + _tOffY,
                                          world.Width * _tScale, world.Height * _tScale);
                var view = new Rect(margin / 2, margin / 2, ActualWidth - margin, ActualHeight - margin);
                if (view.Contains(screenRect)) return;
            }

            double sx = (ActualWidth - 2 * margin) / Math.Max(world.Width, 1);
            double sy = (ActualHeight - 2 * margin) / Math.Max(world.Height, 1);
            double scale = Clamp(Math.Min(sx, sy), 0.12, 1.1);
            if (onlyIfNeeded) scale = Math.Min(scale, _tScale);

            CenterOn(new Point(world.X + world.Width / 2, world.Y + world.Height / 2), scale, animate: true);
        }

        private void CenterOn(Point world, double scale, bool animate)
        {
            _tScale = scale;
            _tOffX = ActualWidth / 2 - world.X * scale;
            _tOffY = ActualHeight / 2 - world.Y * scale;
            if (!animate)
            {
                _scale = _tScale; _offX = _tOffX; _offY = _tOffY;
                ApplyCamera();
            }
            StartAnimation();
        }

        private static Rect TargetBounds(IEnumerable<GraphNode> nodes)
        {
            var list = nodes.ToList();
            double x1 = list.Min(n => n.TargetX) - Overhang, y1 = list.Min(n => n.TargetY);
            double x2 = list.Max(n => n.TargetX) + LineageGraph.NodeWidth + Overhang;
            double y2 = list.Max(n => n.TargetY) + LineageGraph.NodeHeight;
            return new Rect(new Point(x1, y1), new Point(x2, y2));
        }

        private void ApplyCamera()
        {
            _camera.Matrix = new Matrix(_scale, 0, 0, _scale, _offX, _offY);
        }

        // ------------------------------------------------------------------
        // Animation : à chaque image, tout se rapproche de sa cible
        // ------------------------------------------------------------------

        private void StartAnimation()
        {
            if (_animating) return;
            _animating = true;
            _lastFrame = _clock.Elapsed.TotalSeconds;
            CompositionTarget.Rendering += OnFrame;
        }

        private void OnFrame(object sender, EventArgs e)
        {
            double now = _clock.Elapsed.TotalSeconds;
            double dt = Math.Min(0.05, now - _lastFrame);
            _lastFrame = now;

            // k = part du chemin restant parcourue pendant cette image.
            // Avec une exponentielle, la vitesse ne dépend pas du nombre d'images/s.
            double k = 1 - Math.Exp(-dt * 12);
            bool moving = false;

            // Caméra
            moving |= Approach(ref _scale, _tScale, k, 0.0005);
            moving |= Approach(ref _offX, _tOffX, k, 0.3);
            moving |= Approach(ref _offY, _tOffY, k, 0.3);
            ApplyCamera();

            // Nœuds
            bool nodesMoved = false;
            if (_graph != null)
            {
                foreach (var n in _graph.Nodes)
                {
                    double x = n.X, y = n.Y, o = n.Opacity;
                    bool m = Approach(ref x, n.TargetX, k, 0.3);
                    m |= Approach(ref y, n.TargetY, k, 0.3);
                    m |= Approach(ref o, 1, k, 0.01);
                    if (!m) continue;
                    n.X = x; n.Y = y; n.Opacity = o;
                    ((NodeVisual)n.Visual).ApplyPosition();
                    nodesMoved = true;
                }
                if (nodesMoved)
                    foreach (var ed in _graph.Edges) ((EdgeVisual)ed.Visual).UpdateGeometry();
            }

            if (!moving && !nodesMoved)
            {
                // tout est arrivé : on arrête de redessiner (0 % de processeur au repos)
                CompositionTarget.Rendering -= OnFrame;
                _animating = false;
            }
        }

        /// <summary>Rapproche value de target ; renvoie true s'il reste du chemin.</summary>
        private static bool Approach(ref double value, double target, double k, double epsilon)
        {
            if (Math.Abs(target - value) <= epsilon)
            {
                value = target;
                return false;
            }
            value += (target - value) * k;
            return true;
        }

        // ------------------------------------------------------------------
        // Souris sur le fond : déplacer et zoomer
        // ------------------------------------------------------------------

        protected override void OnMouseWheel(MouseWheelEventArgs e)
        {
            base.OnMouseWheel(e);
            ZoomAt(e.GetPosition(this), e.Delta > 0 ? 1.18 : 1 / 1.18);
            e.Handled = true;
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonDown(e);
            if (e.Handled) return;   // clic déjà traité par une carte ou une arête
            Focus();
            _panning = true;
            _panStart = e.GetPosition(this);
            _pressPoint = _panStart;
            CaptureMouse();
            Cursor = Cursors.SizeAll;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!_panning) return;
            var p = e.GetPosition(this);
            // pendant le glisser, la caméra suit la souris sans délai
            _tOffX += p.X - _panStart.X;
            _tOffY += p.Y - _panStart.Y;
            _offX = _tOffX;
            _offY = _tOffY;
            _panStart = p;
            ApplyCamera();
        }

        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonUp(e);
            if (!_panning) return;
            // la souris n'a presque pas bougé : c'était un clic, pas un glisser
            bool wasClick = (e.GetPosition(this) - _pressPoint).Length < 3;
            _panning = false;
            ReleaseMouseCapture();
            Cursor = null;
            if (wasClick && BackgroundClicked != null) BackgroundClicked();
        }

        // ------------------------------------------------------------------
        // Surlignage : arêtes du nœud survolé / sélectionné
        // ------------------------------------------------------------------

        private void SetHovered(GraphNode n)
        {
            _hovered = n;
            UpdateHighlight();
        }

        private void UpdateHighlight()
        {
            if (_graph == null) return;
            var focus = new HashSet<GraphNode>();
            if (SelectedNode != null) focus.Add(SelectedNode);
            if (_hovered != null) focus.Add(_hovered);

            foreach (var e in _graph.Edges)
            {
                bool hot = e == SelectedEdge || focus.Contains(e.From) || focus.Contains(e.To);
                ((EdgeVisual)e.Visual).SetHot(hot);
            }

            var neighbors = new HashSet<GraphNode>(focus.SelectMany(n => n.Neighbors()));
            if (SelectedEdge != null) { neighbors.Add(SelectedEdge.From); neighbors.Add(SelectedEdge.To); }
            foreach (var n in _graph.Nodes)
                ((NodeVisual)n.Visual).SetHighlight(n == SelectedNode, neighbors.Contains(n));
        }

        // ------------------------------------------------------------------
        // Aides
        // ------------------------------------------------------------------

        private static Brush SideBrush(GraphNode n)
        {
            return n.Level < 0 ? PredBrush : n.Level > 0 ? SuccBrush : RootBrush;
        }

        private static Brush Frozen(Color c)
        {
            var b = new SolidColorBrush(c);
            b.Freeze();   // pinceau figé = plus rapide à dessiner
            return b;
        }

        private static double Clamp(double v, double min, double max)
        {
            return v < min ? min : v > max ? max : v;
        }

        /// <summary>Fond à points qui suit le zoom et le déplacement (même transformation que le graphe).</summary>
        private static Brush MakeDotGrid(Transform camera)
        {
            var dot = new GeometryDrawing(Frozen(Color.FromRgb(0xD5, 0xDB, 0xE5)), null,
                                          new EllipseGeometry(new Point(12, 12), 1.1, 1.1));
            var back = new GeometryDrawing(Frozen(Color.FromRgb(0xF8, 0xFA, 0xFC)), null,
                                           new RectangleGeometry(new Rect(0, 0, 24, 24)));
            var group = new DrawingGroup();
            group.Children.Add(back);
            group.Children.Add(dot);
            return new DrawingBrush(group)
            {
                TileMode = TileMode.Tile,
                Viewport = new Rect(0, 0, 24, 24),
                ViewportUnits = BrushMappingMode.Absolute,
                Viewbox = new Rect(0, 0, 24, 24),
                ViewboxUnits = BrushMappingMode.Absolute,
                Transform = camera
            };
        }

        // ==================================================================
        // Dessin d'un nœud : une carte + deux boutons ronds (‹ à gauche, › à droite)
        // ==================================================================
        private sealed class NodeVisual : Grid
        {
            private readonly GraphView _view;
            private readonly GraphNode _node;
            private readonly Border _card;
            private readonly Border _predButton;
            private readonly Border _succButton;
            private readonly TextBlock _predText;
            private readonly TextBlock _succText;

            public NodeVisual(GraphView view, GraphNode node)
            {
                _view = view;
                _node = node;
                Width = LineageGraph.NodeWidth + 2 * Overhang;
                Height = LineageGraph.NodeHeight;

                var side = SideBrush(node);

                // --- la carte ---
                var stripe = new Border { Width = 5, Background = side, CornerRadius = new CornerRadius(8, 0, 0, 8) };
                var texts = new StackPanel { Margin = new Thickness(12, 8, 14, 8) };
                texts.Children.Add(Line(node.Coords.Column, 13.5, FontWeights.SemiBold, TextBrush));
                texts.Children.Add(Line(node.Coords.Table, 12, FontWeights.Normal, TextBrush));
                texts.Children.Add(Line(node.Coords.Schema, 11, FontWeights.Normal, MutedBrush));
                texts.Children.Add(Line(node.Coords.Env, 11, FontWeights.Normal, MutedBrush));
                var inner = new DockPanel();
                DockPanel.SetDock(stripe, Dock.Left);
                inner.Children.Add(stripe);
                inner.Children.Add(texts);

                _card = new Border
                {
                    Margin = new Thickness(Overhang, 0, Overhang, 0),
                    Background = CardBrush,
                    BorderBrush = CardBorderBrush,
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(8),
                    Child = inner,
                    Cursor = Cursors.Hand,
                    ToolTip = node.Coords.FullName,
                    SnapsToDevicePixels = true
                };
                Children.Add(_card);

                // --- les boutons ---
                _predButton = MakeButton(side, HorizontalAlignment.Left, out _predText);
                _succButton = MakeButton(side, HorizontalAlignment.Right, out _succText);
                _predButton.MouseLeftButtonDown += (s, e) => { e.Handled = true; Request("I"); };
                _succButton.MouseLeftButtonDown += (s, e) => { e.Handled = true; Request("O"); };
                Children.Add(_predButton);
                Children.Add(_succButton);

                // --- souris sur la carte ---
                _card.MouseLeftButtonDown += OnCardDown;
                _card.MouseEnter += (s, e) => _view.SetHovered(_node);
                _card.MouseLeave += (s, e) => { if (_view._hovered == _node) _view.SetHovered(null); };
                _card.ContextMenu = MakeMenu();

                Opacity = node.Opacity;
                ApplyPosition();
            }

            private void OnCardDown(object sender, MouseButtonEventArgs e)
            {
                e.Handled = true;   // ne pas lancer le déplacement du fond
                _view.Focus();
                if (e.ClickCount == 2)
                {
                    // double-clic = déplier les deux côtés
                    Request("I");
                    Request("O");
                    return;
                }
                _view.Select(_node);
                if (_view.NodeSelected != null) _view.NodeSelected(_node);
            }

            private void Request(string type)
            {
                if (_node.GetState(type) != LoadState.NotLoaded) return;
                if (_view.ExpandRequested != null) _view.ExpandRequested(_node, type);
            }

            private ContextMenu MakeMenu()
            {
                var menu = new ContextMenu();
                menu.Items.Add(MenuItem("Déplier les prédécesseurs  ‹", NodeAction.ExpandPredecessors));
                menu.Items.Add(MenuItem("Déplier les successeurs  ›", NodeAction.ExpandSuccessors));
                menu.Items.Add(new Separator());
                menu.Items.Add(MenuItem("Repartir de ce nœud", NodeAction.MakeRoot));
                menu.Items.Add(MenuItem("Copier le nom complet", NodeAction.CopyName));
                return menu;
            }

            private MenuItem MenuItem(string header, NodeAction action)
            {
                var item = new MenuItem { Header = header };
                item.Click += (s, e) =>
                {
                    if (_view.NodeActionRequested != null) _view.NodeActionRequested(_node, action);
                };
                return item;
            }

            /// <summary>Place la carte sur le canevas (les boutons dépassent de Overhang à gauche).</summary>
            public void ApplyPosition()
            {
                Canvas.SetLeft(this, _node.X - Overhang);
                Canvas.SetTop(this, _node.Y);
                Opacity = _node.Opacity;
            }

            /// <summary>Met à jour le texte des boutons selon l'état de chargement.</summary>
            public void Refresh()
            {
                UpdateButton(_predButton, _predText, _node.PredState, _node.PredRows, _node.PredTotal, "‹", "prédécesseur");
                UpdateButton(_succButton, _succText, _node.SuccState, _node.SuccRows, _node.SuccTotal, "›", "successeur");
            }

            private static void UpdateButton(Border button, TextBlock text, LoadState state, int rows, int? total,
                                             string arrow, string word)
            {
                switch (state)
                {
                    case LoadState.NotLoaded:
                        text.Text = arrow;
                        text.FontSize = 15;
                        button.Opacity = 1;
                        button.Cursor = Cursors.Hand;
                        button.ToolTip = "Déplier les " + word + "s";
                        break;
                    case LoadState.Loading:
                        text.Text = "…";
                        text.FontSize = 13;
                        button.Opacity = 1;
                        button.Cursor = Cursors.Wait;
                        button.ToolTip = "Chargement en cours (Échap pour annuler)";
                        break;
                    default:
                        int t = total ?? rows;
                        text.Text = rows < t ? rows + "+" : rows.ToString();
                        text.FontSize = rows > 99 ? 9 : 11;
                        button.Opacity = rows == 0 ? 0.45 : 1;
                        button.Cursor = null;
                        button.ToolTip = rows < t
                            ? rows + " " + word + "(s) affiché(s) sur " + t + " en base (augmenter « Max voisins »)"
                            : rows + " " + word + "(s)";
                        break;
                }
            }

            public void SetHighlight(bool selected, bool neighbor)
            {
                _card.BorderBrush = selected ? SideBrush(_node) : neighbor ? EdgeHotBrush : CardBorderBrush;
                _card.BorderThickness = new Thickness(selected ? 2 : 1);
                Panel.SetZIndex(this, selected ? 2 : neighbor ? 1 : 0);
            }

            private static Border MakeButton(Brush side, HorizontalAlignment align, out TextBlock text)
            {
                text = new TextBlock
                {
                    Foreground = side,
                    FontWeight = FontWeights.Bold,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, -2, 0, 0)
                };
                return new Border
                {
                    Width = ButtonSize,
                    Height = ButtonSize,
                    CornerRadius = new CornerRadius(ButtonSize / 2),
                    Background = CardBrush,
                    BorderBrush = side,
                    BorderThickness = new Thickness(1.5),
                    HorizontalAlignment = align,
                    VerticalAlignment = VerticalAlignment.Center,
                    Child = text
                };
            }

            private static TextBlock Line(string s, double size, FontWeight weight, Brush color)
            {
                return new TextBlock
                {
                    Text = string.IsNullOrWhiteSpace(s) ? "—" : s,
                    FontSize = size,
                    FontWeight = weight,
                    Foreground = color,
                    TextTrimming = TextTrimming.CharacterEllipsis   // texte trop long -> "..."
                };
            }
        }

        // ==================================================================
        // Dessin d'une arête : courbe de Bézier + pointe de flèche
        // ==================================================================
        private sealed class EdgeVisual
        {
            private readonly GraphEdge _edge;
            private readonly PathFigure _curve;
            private readonly BezierSegment _bezier;
            private readonly PathFigure _arrow;
            private readonly LineSegment _arrowA;
            private readonly LineSegment _arrowB;
            private bool _hot;

            public EdgeVisual(GraphView view, GraphEdge edge)
            {
                _edge = edge;

                _bezier = new BezierSegment { IsStroked = true };
                _curve = new PathFigure { IsFilled = false, IsClosed = false };
                _curve.Segments.Add(_bezier);

                _arrowA = new LineSegment();
                _arrowB = new LineSegment();
                _arrow = new PathFigure { IsFilled = true, IsClosed = true };
                _arrow.Segments.Add(_arrowA);
                _arrow.Segments.Add(_arrowB);

                var geometry = new PathGeometry();
                geometry.Figures.Add(_curve);
                geometry.Figures.Add(_arrow);

                Path = new Path
                {
                    Data = geometry,
                    Stroke = EdgeBrush,
                    Fill = EdgeBrush,
                    StrokeThickness = 1.6,
                    IsHitTestVisible = false
                };
                // Chemin invisible et épais, posé sous la courbe : il rend l'arête facile à cliquer
                HitPath = new Path
                {
                    Data = geometry,
                    Stroke = Brushes.Transparent,
                    StrokeThickness = 12,
                    Cursor = Cursors.Hand
                };
                HitPath.MouseLeftButtonDown += (s, e) =>
                {
                    e.Handled = true;
                    view.SelectedNode = null;
                    view.SelectedEdge = _edge;
                    view.UpdateHighlight();
                    if (view.EdgeSelected != null) view.EdgeSelected(_edge);
                };

                UpdateGeometry();
            }

            public Path Path { get; }
            public Path HitPath { get; }

            public void Refresh()
            {
                HitPath.ToolTip = _edge.Rows.Count == 1
                    ? "1 traitement : " + _edge.Rows[0].Row.LnaUid
                    : _edge.Rows.Count + " traitements relient ces deux nœuds";
                ApplyStyle();
            }

            public void SetHot(bool hot)
            {
                if (_hot == hot) return;
                _hot = hot;
                ApplyStyle();
            }

            private void ApplyStyle()
            {
                var brush = _hot ? EdgeHotBrush : EdgeBrush;
                Path.Stroke = brush;
                Path.Fill = brush;
                // plusieurs traitements entre les deux nœuds = trait plus épais
                double baseThickness = _edge.Rows.Count > 1 ? 2.6 : 1.6;
                Path.StrokeThickness = _hot ? baseThickness + 0.8 : baseThickness;
                Panel.SetZIndex(Path, _hot ? 1 : 0);
            }

            /// <summary>Recalcule la courbe : du bord droit de From au bord gauche de To.</summary>
            public void UpdateGeometry()
            {
                var a = new Point(_edge.From.X + LineageGraph.NodeWidth + Overhang, _edge.From.Y + LineageGraph.NodeHeight / 2);
                var b = new Point(_edge.To.X - Overhang - 1, _edge.To.Y + LineageGraph.NodeHeight / 2);

                // points de contrôle horizontaux : départ et arrivée bien "à plat"
                double dx = Math.Max(60, Math.Abs(b.X - a.X) / 2);
                _curve.StartPoint = a;
                _bezier.Point1 = new Point(a.X + dx, a.Y);
                _bezier.Point2 = new Point(b.X - dx, b.Y);
                _bezier.Point3 = b;

                // pointe de flèche (la courbe arrive horizontalement)
                _arrow.StartPoint = b;
                _arrowA.Point = new Point(b.X - 9, b.Y - 4.5);
                _arrowB.Point = new Point(b.X - 9, b.Y + 4.5);

                Path.Opacity = Math.Min(_edge.From.Opacity, _edge.To.Opacity);
            }
        }
    }
}
