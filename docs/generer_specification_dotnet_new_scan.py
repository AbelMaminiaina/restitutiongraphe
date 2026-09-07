# -*- coding: utf-8 -*-
"""Génère docs/Specification-fonctionnelle-dotnet-new-scan.docx.

Spécification fonctionnelle + dossier de conception détaillé du projet
`dotnet-new-scan` (assembly PathFinder.ScanMvc) : recherche de plus court
chemin sur dbo.LINE_VIS_EDG, avec pré-calculs (composantes faibles,
condensation SCC) et graphe chargé en mémoire, plus quatre algorithmes de
parcours (BFS bidirectionnel, Dijkstra, Dijkstra bidirectionnel, A*).

Le document reprend des extraits de code RÉELS du dépôt : ils sont relus à
chaque exécution du script (fonctions `between()` et `method()` ci-dessous),
donc ils restent synchronisés avec le code tant que les ancres de recherche
(bouts de signature) ne changent pas.

Lancer :  python docs/generer_specification_dotnet_new_scan.py
Sortie  :  docs/Specification-fonctionnelle-dotnet-new-scan.docx
"""

from datetime import date
from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from docx.shared import Pt, RGBColor

# --------------------------------------------------------------------------
# Emplacements
# --------------------------------------------------------------------------
REPO = Path(r"C:\Users\amami\GitHub\restitutiondonnees")
PROJ = "dotnet-new-scan"                       # racine du projet dans le dépôt
OUT = REPO / "docs" / "Specification-fonctionnelle-dotnet-new-scan.docx"

doc = Document()

# --------------------------------------------------------------------------
# Styles de base (repris de docs/generer_docx.py pour rester cohérent)
# --------------------------------------------------------------------------
normal = doc.styles["Normal"]
normal.font.name = "Calibri"
normal.font.size = Pt(11)

code_style = doc.styles.add_style("CodeBlock", 1)   # 1 = style de paragraphe
code_style.font.name = "Consolas"
code_style.font.size = Pt(8.5)
code_style.paragraph_format.space_before = Pt(4)
code_style.paragraph_format.space_after = Pt(10)
code_style.paragraph_format.left_indent = Pt(6)


def _shade(paragraph, fill="F2F2F2"):
    """Fond gris + fine bordure gauche pour les blocs de code."""
    pPr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    pPr.append(shd)
    pBdr = OxmlElement("w:pBdr")
    left = OxmlElement("w:left")
    left.set(qn("w:val"), "single")
    left.set(qn("w:sz"), "18")
    left.set(qn("w:space"), "6")
    left.set(qn("w:color"), "9CA3AF")
    pBdr.append(left)
    pPr.append(pBdr)


# --------------------------------------------------------------------------
# Aides de mise en page
# --------------------------------------------------------------------------
def h1(t):
    doc.add_heading(t, level=1)


def h2(t):
    doc.add_heading(t, level=2)


def h3(t):
    doc.add_heading(t, level=3)


def para(t, bold=False, italic=False):
    p = doc.add_paragraph()
    r = p.add_run(t)
    r.bold = bold
    r.italic = italic
    return p


def kv(label, value):
    p = doc.add_paragraph()
    p.add_run(f"{label} : ").bold = True
    p.add_run(value)
    return p


def bullets(items):
    for it in items:
        doc.add_paragraph(it, style="List Bullet")


def numbered(items):
    for it in items:
        doc.add_paragraph(it, style="List Number")


def code(text, caption="C#"):
    """Bloc de code monospace grisé, précédé d'un commentaire de légende."""
    text = text.strip("\n")
    p = doc.add_paragraph(style="CodeBlock")
    if caption:
        r = p.add_run(f"// {caption}\n")
        r.font.color.rgb = RGBColor(0x6B, 0x72, 0x80)
    for i, line in enumerate(text.split("\n")):
        p.add_run(("\n" if (i or caption) else "") + line.replace("\t", "    "))
    _shade(p)
    return p


def table(rows, col_widths=None, first_row_bold=True, font_size=9):
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = "Light Grid Accent 1"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, row in enumerate(rows):
        for j, val in enumerate(row):
            cell = t.cell(i, j)
            cell.text = str(val)
            for p in cell.paragraphs:
                for r in p.runs:
                    r.font.size = Pt(font_size)
                    if i == 0 and first_row_bold:
                        r.font.bold = True
    return t


# --------------------------------------------------------------------------
# Extraction de code réel depuis le dépôt
# --------------------------------------------------------------------------
def _dedent(lines):
    base = min((len(l) - len(l.lstrip()) for l in lines if l.strip()), default=0)
    return [l[base:] if len(l) >= base else l for l in lines]


def between(relpath, start_sub, end_sub, keep_end=True):
    """Bloc entre la 1re ligne contenant `start_sub` et la 1re ligne suivante
    contenant `end_sub`. `keep_end` inclut (ou non) la ligne de fin."""
    lines = (REPO / PROJ / relpath).read_text(encoding="utf-8").splitlines()
    i0 = next(i for i, l in enumerate(lines) if start_sub in l)
    i1 = next(i for i, l in enumerate(lines) if i > i0 and end_sub in l)
    chunk = lines[i0: i1 + 1] if keep_end else lines[i0:i1]
    return "\n".join(_dedent(chunk))


def _strip_noncode(line):
    """Retire d'une ligne C# le contenu des chaînes "..." et le commentaire //
    final, pour pouvoir compter les accolades { } de structure sans se faire
    piéger par `$"...{x}..."` ou par une accolade citée dans un commentaire."""
    out, i, in_str = [], 0, False
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            else:
                out.append(c)
        i += 1
    return "".join(out)


def method(relpath, sig, keep_leading_comment=True):
    """Méthode C# complète : de sa signature (ligne contenant `sig`) jusqu'à
    l'accolade fermante correspondante, en remontant éventuellement le bloc de
    commentaires // et les attributs [..] juste au-dessus."""
    lines = (REPO / PROJ / relpath).read_text(encoding="utf-8").splitlines()
    start = next(i for i, l in enumerate(lines) if sig in l)

    j = start
    if keep_leading_comment:
        while j > 0 and lines[j - 1].lstrip().startswith(("//", "[")):
            j -= 1

    depth, seen_open, end = 0, False, start
    for k in range(start, len(lines)):
        codepart = _strip_noncode(lines[k])
        depth += codepart.count("{") - codepart.count("}")
        if "{" in codepart:
            seen_open = True
        if seen_open and depth <= 0:
            end = k
            break

    return "\n".join(_dedent(lines[j:end + 1]))


# ==========================================================================
# PAGE DE TITRE
# ==========================================================================
t = doc.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = t.add_run("Spécification fonctionnelle et conception")
r.bold = True
r.font.size = Pt(23)

st = doc.add_paragraph()
st.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = st.add_run("dotnet-new-scan  —  PathFinder.ScanMvc\n"
               "Recherche de plus court chemin sur dbo.LINE_VIS_EDG :\n"
               "pré-calculs (composantes, condensation SCC), graphe en mémoire, "
               "et quatre algorithmes de parcours")
r.font.size = Pt(12.5)
r.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

d = doc.add_paragraph()
d.alignment = WD_ALIGN_PARAGRAPH.CENTER
d.add_run(f"Généré le {date.today().isoformat()} — extraits de code repris tel "
          f"quel du dépôt restitutiongraphe, projet {PROJ}/").italic = True

doc.add_paragraph()
para("Ce document décrit CE QUE fait l'application (spécification fonctionnelle, "
     "chapitres 1 à 4) puis COMMENT elle est conçue (dossier de conception, "
     "chapitres 5 à 6). Il se lit dans l'ordre la première fois ; ensuite les "
     "chapitres se consultent séparément. Un glossaire clôt le document.")

doc.add_page_break()

# ==========================================================================
h1("1. Présentation")

h2("1.1  Objet du document")
para("Décrire de façon détaillée le comportement attendu et la conception "
     "interne du projet " + PROJ + " (assembly PathFinder.ScanMvc), une "
     "application web ASP.NET Core MVC qui répond à une question : "
     "« existe-t-il un chemin orienté entre deux nœuds du graphe, et quel est "
     "le plus court ? », en s'appuyant sur la table SQL Server dbo.LINE_VIS_EDG.")

h2("1.2  Situation dans le dépôt")
para("Le dépôt restitutiongraphe contient plusieurs implémentations du même "
     "domaine métier — la restitution d'un graphe orienté de transformations "
     "de données. Quatre d'entre elles sont des projets .NET nommés "
     "PathFinder.* :")
table([
    ("Dossier", "Assembly", "Rôle"),
    ("dotnet-mvc/", "PathFinder.RazorMvc", "Recherche de chemin, BFS bidirectionnel exécuté en SQL palier par palier"),
    ("dotnet-angular-mvc/", "PathFinder.Mvc", "Idem + front Angular"),
    ("dotnet-angular/backend/", "PathFinder.Api", "API .NET + front Angular séparé"),
    (PROJ + "/", "PathFinder.ScanMvc", "OBJET DE CE DOCUMENT — reprend dotnet-mvc et ajoute le « scan » (chapitre 11 de la spécification C#) : pré-calculs + graphe en mémoire + 3 algorithmes supplémentaires"),
])
para("Les références « § 11.x » dans le code et dans ce document renvoient au "
     "chapitre 11 de la spécification fonctionnelle générale "
     "(docs/Specification-fonctionnelle-PathFinder-CSharp.docx).")

h2("1.3  Périmètre fonctionnel")
bullets([
    "Rechercher le plus court chemin orienté entre deux nœuds, et l'afficher "
    "(chaîne de nœuds + transformation portée par chaque arête).",
    "Choisir l'algorithme de parcours parmi quatre : BFS bidirectionnel "
    "(défaut), Dijkstra, Dijkstra bidirectionnel, A*.",
    "Trancher « aucun chemin » sans parcours, grâce à deux pré-calculs "
    "(composantes connexes faibles ; condensation en composantes fortement "
    "connexes).",
    "Déclencher et suivre l'état de ces pré-calculs, et du chargement du "
    "graphe en mémoire, depuis une page dédiée.",
    "Illustrer les grandes familles de graphes (connexe, complet, pondéré, "
    "cyclique, arbre…) par des images SVG générées côté serveur.",
])

h2("1.4  Fonctionnement sur tous les postes, sans base")
para("L'application démarre sur N'IMPORTE QUEL poste sans SQL Server ni aucun "
     "script à exécuter. Au démarrage, GraphDataProvider choisit la source des "
     "données selon la clé de configuration Data:Source (ou la variable "
     "d'environnement RESTITUTION_DATA_SOURCE) :")
table([
    ("Data:Source", "Comportement"),
    ("auto (défaut)", "sonde SQL Server (.\\SQLEXPRESS01 / RestitutionGraphe + table LINE_VIS_EDG non vide, timeout 3 s). Joignable -> mode SQL. Sinon -> graphe généré."),
    ("sql", "force le mode SQL (échoue si la base est absente)"),
    ("generated", "force le graphe généré en mémoire, même si SQL est disponible"),
])
para("Le graphe généré (GeneratedGraphData) : Data:GeneratedNodes nœuds "
     "(défaut 5 000), 2 à 6 arêtes sortantes chacun, transformation aléatoire "
     "par arête, GRAINE FIXE — donc exactement le même graphe sur toutes les "
     "machines. En mode généré, les pré-calculs § 11.4 / § 11.5 (qui écrivent "
     "des tables SQL) sont désactivés : sur un petit graphe toute recherche "
     "est déjà sous la milliseconde. Tout le reste fonctionne à l'identique.")

h2("1.5  Hors périmètre (ce que l'application ne fait pas)")
bullets([
    "Aucune écriture dans dbo.LINE_VIS_EDG : l'application lit le graphe, elle "
    "ne le modifie jamais. En mode SQL elle crée ses propres tables de "
    "pré-calcul (NODE_COMPONENT, NODE_SCC, SCC_EDGE).",
    "Aucun JavaScript, aucune API JSON, aucun projet front séparé : tout est "
    "rendu en HTML/CSS côté serveur (vues Razor), les graphes sont dessinés "
    "en SVG (balisage, pas de script).",
    "Aucune authentification ni gestion d'utilisateurs : application interne, "
    "un seul rôle implicite.",
    "Pas de pondération réelle des arêtes : toutes les arêtes ont le même "
    "poids (voir § 5.2.1). Dijkstra et A* sont fournis comme alternatives "
    "prêtes si cela changeait un jour.",
])

doc.add_page_break()

# ==========================================================================
h1("2. Contexte et modèle de données")

h2("2.1  La table dbo.LINE_VIS_EDG")
para("Source de vérité unique. Il n'y a pas de table de nœuds séparée : un "
     "nœud est simplement une valeur qui apparaît dans une colonne d'identifiant.")
table([
    ("Colonne", "Type", "Signification"),
    ("Nodes", "VARCHAR(8000)", "Un des deux nœuds de la ligne"),
    ("NodesLie", "VARCHAR(8000)", "L'autre nœud de la ligne"),
    ("Direction", "VARCHAR", "'predecesseur' ou 'successeur' — rôle de Nodes par rapport à NodesLie"),
    ("Transformation", "VARCHAR", "Libellé de la transformation portée par l'arête (SELECT, JOIN, FILTER…)"),
])
para("Dérivation du sens d'une ligne en arête orientée :", bold=True)
bullets([
    "Direction = 'predecesseur'  →  Nodes précède NodesLie  →  arête  Nodes → NodesLie",
    "Direction = 'successeur'    →  Nodes suit NodesLie      →  arête  NodesLie → Nodes",
])
para("Cette dérivation est faite en un seul endroit, la fonction ToEdge :", bold=True)
code(between("Models/LineVisEdgRepository.cs",
             "private static (string Source, string Target) ToEdge",
             "? (nodes, nodesLie) : (nodesLie, nodes);"),
     "C# — Models/LineVisEdgRepository.cs")

h2("2.2  Contraintes SQL Server à connaître")
bullets([
    "Nodes / NodesLie sont des VARCHAR (non NVARCHAR). Microsoft.Data.SqlClient "
    "lie par défaut une string .NET en NVARCHAR ; comparer une colonne VARCHAR "
    "à un paramètre NVARCHAR force SQL Server à convertir la colonne, donc un "
    "balayage complet (scan) au lieu d'une recherche d'index (seek). Chaque "
    "paramètre est donc typé explicitement VARCHAR (méthode AddVarChar).",
    "La clé d'un index classique est plafonnée à 900 octets : les tables de "
    "pré-calcul utilisent VARCHAR(450) pour la colonne d'identifiant, pas "
    "VARCHAR(8000).",
])

h2("2.3  Tables produites par l'application")
table([
    ("Table", "Colonnes", "Produite par", "Contenu"),
    ("dbo.NODE_COMPONENT", "NodeId, ComponentId", "GraphScanService (§ 11.4)", "Numéro de composante connexe FAIBLE de chaque nœud"),
    ("dbo.NODE_SCC", "NodeId, SccId", "SccCondensationService (§ 11.5)", "Numéro de composante FORTEMENT connexe de chaque nœud"),
    ("dbo.SCC_EDGE", "FromScc, ToScc", "SccCondensationService (§ 11.5)", "Arêtes du graphe condensé (un DAG de super-nœuds)"),
])
para("Ces trois tables sont recréées intégralement (DROP + CREATE + chargement "
     "en masse par SqlBulkCopy) à chaque exécution du pré-calcul correspondant. "
     "Opérations idempotentes.")

h2("2.4  Connexion à la base (mode SQL)")
kv("Serveur par défaut", r".\SQLEXPRESS01  (authentification Windows, Trusted_Connection=True)")
kv("Base par défaut", "RestitutionGraphe")
kv("Surcharge", "variables d'environnement RESTITUTION_DB_SERVER / RESTITUTION_DB_NAME, "
   "ou clés de configuration Database:Server / Database:Name")
para("La chaîne de connexion est construite identiquement dans les trois "
     "repositories (LineVisEdgRepository, NodeComponentRepository, SccRepository).")

doc.add_page_break()

# ==========================================================================
h1("3. Architecture logicielle")

h2("3.1  Pile technique")
table([
    ("Élément", "Choix"),
    ("Framework", "ASP.NET Core MVC (contrôleurs + vues Razor)"),
    ("Cible", ".NET 7.0  /  langage C# 8.0  (voir § 6.1)"),
    ("Rendu", "100 % côté serveur — HTML/CSS + SVG. Aucun JavaScript."),
    ("Source des données", "SQL Server si joignable, sinon graphe généré en mémoire (aucune base requise) — GraphDataProvider"),
    ("Accès SQL", "Microsoft.Data.SqlClient 5.2.2 (ADO.NET, requêtes paramétrées, SqlBulkCopy) — mode SQL uniquement"),
    ("Asynchronisme", "Aucun : pas d'async / await. Préchargement sur un Thread dédié."),
    ("État applicatif", "Services singletons en mémoire + IMemoryCache borné"),
])

h2("3.2  Découpage MVC")
para("Le projet suit le patron MVC « classique » : le contrôleur reçoit la "
     "requête, appelle un ou plusieurs services / repositories, remplit un "
     "ViewModel, et la vue Razor met en forme. Aucune logique métier dans les "
     "vues ni dans les contrôleurs.")
table([
    ("Couche", "Fichiers", "Responsabilité"),
    ("Controllers", "HomeController, ScanController, GraphesController",
     "Aiguillage HTTP, orchestration, remplissage des ViewModels"),
    ("Source des données", "GraphDataProvider, GeneratedGraphData, LineVisEdgRepository",
     "Choisit SQL ou graphe généré ; fournit les arêtes en flux + les transformations. Seul LineVisEdgRepository contient du SQL."),
    ("Models — repositories SQL", "NodeComponentRepository, SccRepository",
     "Persistance des pré-calculs (tables NODE_COMPONENT / NODE_SCC / SCC_EDGE). Mode SQL uniquement."),
    ("Models — ViewModels / données", "PathViewModel, ScanPageViewModel, GraphSample(s)",
     "Structures passées aux vues ; catalogue des graphes d'exemple"),
    ("Services — algorithmes", "InMemoryGraphService + DirectedGraph + GraphPreloader, "
                               "GraphScanService, SccCondensationService, SvgGraphRenderer",
     "TOUS les algorithmes (parcours, Union-Find, Kosaraju, rendu SVG). Aucune requête SQL."),
    ("Views", "Home/Index, Scan/Index, Graphes/Index+Build, Shared/_Layout",
     "Mise en forme HTML/SVG, formulaires GET/POST"),
])
para("Règle de séparation stricte, répétée dans les en-têtes de fichiers : "
     "un service ne contient jamais de SqlConnection / SqlCommand ; seul "
     "LineVisEdgRepository en contient. Les services consomment les arêtes via "
     "GraphDataProvider, sans savoir d'où elles viennent (SQL ou généré).")

h2("3.3  Schéma des couches")
code(
    "Navigateur (HTML/CSS, zéro JS)\n"
    "        │  GET /?source=&target=&algo=        POST /Scan/*\n"
    "        ▼\n"
    "Controllers (Home, Scan, Graphes)\n"
    "        │\n"
    "        ├────────────────┬───────────────────┬──────────────────┐\n"
    "        ▼                ▼                   ▼                  ▼\n"
    "SccCondensation     GraphScanService   InMemoryGraphService  SvgGraphRenderer\n"
    "  Service (Kosaraju)   (Union-Find)     + DirectedGraph        (galerie)\n"
    "        │                │              (CSR + 4 algos)\n"
    "        │                │                   │\n"
    "        │        ┌───────┴──────── GraphDataProvider ─────────┐\n"
    "        │        ▼                                            ▼\n"
    "        │   LineVisEdgRepository (mode SQL)          GeneratedGraphData\n"
    "        │        │   lecture LINE_VIS_EDG              (graphe en RAM,\n"
    "        ▼        ▼   (StreamAll*, CanConnect)           graine fixe)\n"
    "SccRepository  NodeComponentRepo\n"
    "  (NODE_SCC,     (NODE_COMPONENT)   ─────►  SQL Server  RestitutionGraphe\n"
    "   SCC_EDGE)                                (mode SQL uniquement)\n",
    caption="")

h2("3.4  Injection de dépendances (Program.cs)")
para("Tout est enregistré en singleton : les repositories ne gardent que la "
     "chaîne de connexion ; les services gardent l'état des pré-calculs et le "
     "graphe en mémoire, qui doivent être partagés entre toutes les requêtes.")
code(method("Program.cs", "public static void Main(string[] args)"),
     "C# — Program.cs")

h2("3.5  Cycle de vie au démarrage")
numbered([
    "GraphDataProvider est construit : il choisit la source (sonde SQL en mode "
    "auto), et l'écrit dans le log (« Source de données : … »).",
    "Le serveur démarre et accepte les requêtes immédiatement.",
    "GraphPreloader (IHostedService) lance un Thread d'arrière-plan qui appelle "
    "InMemoryGraphService.EnsureLoaded().",
    "EnsureLoaded() -> Reload() lit toutes les arêtes orientées (un seul SELECT "
    "sans WHERE en mode SQL, ou la liste en RAM en mode généré), construit la "
    "structure CSR, puis prépare les repères ALT de A* (quelques BFS complets).",
    "Si une recherche arrive avant la fin du préchargement, HomeController "
    "appelle EnsureLoaded() qui construit le graphe SOUS VERROU (une seule "
    "fois). Le préchargement n'est donc qu'une optimisation — il n'y a plus de "
    "repli SQL palier par palier.",
])
para("Aucun async : le préchargement est un Thread classique en arrière-plan.", bold=True)
code(between("Services/InMemoryGraphService.cs",
             "public Task StartAsync(CancellationToken",
             "public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;"),
     "C# — Services/InMemoryGraphService.cs (GraphPreloader)")

doc.add_page_break()

# ==========================================================================
h1("4. Spécifications fonctionnelles — les écrans")

# ---- 4.1 --------------------------------------------------------------
h2("4.1  Écran « Recherche de plus court chemin »  (route /)")

h3("4.1.1  Formulaire")
para("Une seule page sert le formulaire vide et le résultat. Le formulaire "
     "est soumis en GET : l'URL du résultat est partageable "
     "(ex. /?source=N1&target=N50000&algo=dijkstra-bi).")
table([
    ("Champ", "Paramètre", "Valeurs", "Défaut"),
    ("Source", "source", "identifiant de nœud (texte libre)", "—"),
    ("Cible", "target", "identifiant de nœud (texte libre)", "—"),
    ("Algorithme", "algo", "bfs | dijkstra | dijkstra-bi | astar", "bfs"),
    ("(profondeur max)", "maxDepth", "entier, plafonné à 20 par le contrôleur — via l'URL seulement, pas de champ", "12"),
])

h3("4.1.2  Déroulé d'une recherche (règles fonctionnelles)")
numbered([
    "Aucun champ rempli → on affiche le formulaire vide, sans message "
    "(première visite).",
    "Un seul champ rempli → message « Renseigne un nœud source ET un nœud "
    "cible. », pas de recherche.",
    "Source ET cible remplies → recherche. On normalise d'abord l'algorithme "
    "sur l'une des quatre valeurs connues (défaut bfs).",
    "Vérification 1 (mode SQL seulement) — condensation SCC (§ 11.5, si "
    "calculée) : verdict EXACT d'atteignabilité orientée. « NotReachable » → "
    "« aucun chemin », sans aucun parcours.",
    "Vérification 2 (mode SQL seulement) — sinon, scan des composantes faibles "
    "(§ 11.4, si calculé) : si source et cible sont dans des composantes "
    "différentes → « aucun chemin », sans parcours.",
    "Sinon — EnsureLoaded() (construit le graphe en mémoire si le préchargement "
    "n'a pas fini), puis parcours avec l'algorithme demandé. TOUJOURS en "
    "mémoire : il n'y a pas de repli SQL.",
    "Le résultat (trouvé / non trouvé + chemin) est mémorisé 5 minutes dans le "
    "cache applicatif, sous une clé qui inclut l'algorithme.",
])
para("L'ordre des vérifications, dans HomeController.Index :", bold=True)
code(between("Controllers/HomeController.cs",
             "var result = _cache.GetOrCreate(cacheKey, entry =>",
             "})!;"),
     "C# — Controllers/HomeController.cs")

h3("4.1.3  Affichage du résultat")
bullets([
    "Bannière verte « ✓ Un chemin existe (N arêtes) », avec mention de "
    "l'algorithme et « sur le graphe en mémoire » si résolu en RAM.",
    "Chaîne de nœuds : source → … → cible, la source et la cible mises en "
    "évidence.",
    "Tableau détaillé : une ligne par arête du chemin (numéro, De, Vers, "
    "Transformation). La transformation vient de GraphDataProvider.DescribePath "
    "(relue en base en mode SQL, ou dans le graphe généré).",
    "En tête de page : « Source : … » (SQL Server ou graphe généré).",
    "Si source = cible : « Chemin de longueur 0 ».",
    "Note « Résultat servi depuis le cache applicatif (5 min) » le cas échéant.",
])

h3("4.1.4  Cas « aucun chemin » — trois sous-messages")
table([
    ("Sous-cas", "Message", "Déclencheur"),
    ("Tranché par SCC", "« la condensation SCC prouve qu'aucun chemin orienté n'existe (verdict exact, sans BFS) »", "sccReach == NotReachable"),
    ("Tranché par le scan", "« les deux nœuds sont dans des composantes connexes différentes (sans BFS) »", "weakVerdict == DifferentComponents"),
    ("Non trouvé", "« nœud inexistant, ou pas de chemin en 20 paliers maximum »", "le parcours n'a rien trouvé"),
])

h3("4.1.5  URL partageable et cache")
kv("Clé de cache", "path:{algo}:{source}:{target}:{maxDepth}")
kv("Durée de vie", "5 minutes (expiration absolue), y compris pour les « aucun chemin » "
   "(ce sont les recherches les plus coûteuses)")
kv("Plafond", "SizeLimit = 10 000 entrées (chaque entrée compte pour 1)")

# ---- 4.2 --------------------------------------------------------------
h2("4.2  Écran « Pré-calculs / Scan »  (route /Scan)")

para("Tableau de bord des trois optimisations. La page affiche d'abord la "
     "source des données. Les actions sont en POST-redirect-GET (bouton → POST "
     "→ recalcul → redirection vers /Scan) et protégées par un jeton "
     "anti-forgery.")
table([
    ("Bloc", "Route POST", "Effet", "Disponible"),
    ("1. Composantes faibles (§ 11.4)", "/Scan/Run", "Union-Find sur toutes les arêtes → NODE_COMPONENT", "mode SQL seulement"),
    ("2. Condensation SCC (§ 11.5)", "/Scan/RunScc", "Kosaraju + graphe condensé → NODE_SCC, SCC_EDGE", "mode SQL seulement"),
    ("3. Graphe en mémoire (§ 11.7)", "/Scan/ReloadGraph", "Reconstruit la structure CSR + les repères ALT (RAM)", "tous modes"),
])
para("En mode graphe généré, les blocs 1 et 2 affichent « réservé au mode "
     "SQL » et les POST correspondants répondent par un message (aucune "
     "action). Le petit graphe généré n'en a de toute façon aucun besoin.")
para("Chaque bloc affiche l'état du dernier calcul : date UTC, durée, nombre de "
     "nœuds / arêtes, nombre de composantes, taille de la plus grande, et pour "
     "le graphe en mémoire l'empreinte (~Mo) et le nombre de repères ALT.")
para("Quand relancer : après toute modification de dbo.LINE_VIS_EDG. Les trois "
     "pré-calculs sont indépendants ; l'ordre d'utilisation à la recherche est "
     "SCC (exact) → composantes faibles → parcours.")

# ---- 4.3 --------------------------------------------------------------
h2("4.3  Écran « Types de graphes »  (route /Graphes)")
bullets([
    "Galerie : une vignette par famille de graphe (connexe, non connexe, "
    "complet K5, dense, creux, non pondéré, pondéré, DAG, cyclique, arbre). "
    "Le catalogue est codé en dur (GraphSamples).",
    "Chaque image est un SVG construit à la volée par SvgGraphRenderer et "
    "servie à l'URL /Graphes/Image/{slug} (utilisable seule dans une balise "
    "<img>).",
    "/Graphes/Build écrit les SVG en fichiers dans wwwroot/img/graphes/ et "
    "affiche la liste produite.",
    "Purement pédagogique : cet écran est indépendant de la recherche de "
    "chemin et de la base.",
])

doc.add_page_break()

# ==========================================================================
h1("5. Conception détaillée")

# ---- 5.1 --------------------------------------------------------------
h2("5.1  Le graphe en mémoire (§ 11.7)")

h3("5.1.1  Représentation CSR (Compressed Sparse Row)")
para("Le graphe complet est chargé une fois en RAM sous forme de tableaux "
     "d'entiers, format CSR : compact et très rapide à parcourir. Les nœuds "
     "sont indexés par un entier 0..n-1 (dictionnaire nom → indice) ; les noms "
     "ne réapparaissent qu'à la reconstruction finale du chemin.")
table([
    ("Tableau", "Taille", "Contenu"),
    ("_names", "n", "indice → nom du nœud"),
    ("_index", "n", "nom → indice"),
    ("_fwdOffset", "n + 1", "bornes des tranches de _fwdTarget"),
    ("_fwdTarget", "m", "successeurs, concaténés ; ceux de u = _fwdTarget[_fwdOffset[u] .. _fwdOffset[u+1]]"),
    ("_revOffset", "n + 1", "bornes des tranches de _revSource"),
    ("_revSource", "m", "prédécesseurs, concaténés (miroir de _fwdTarget)"),
])
para("Empreinte : 2·(n+1) + 2·m entiers, plus les noms. Ordre de grandeur : "
     "~12 Mo pour le jeu de démonstration (100 008 nœuds, 400 787 arêtes) ; "
     "~80 Mo pour 2 M nœuds / 8 M arêtes. Les repères ALT ajoutent "
     "2·(nombre de repères)·n entiers (~5 Mo pour 6 repères et 100 000 nœuds).")

h3("5.1.2  Accès aux voisins")
para("Une tranche de tableau (ReadOnlySpan) : aucune allocation, aucune copie.")
code(between("Services/DirectedGraph.cs",
             "private ReadOnlySpan<int> Successors",
             "=> _revSource.AsSpan(_revOffset[u], _revOffset[u + 1] - _revOffset[u]);"),
     "C# — Services/DirectedGraph.cs")

h3("5.1.3  Construction")
para("DirectedGraph.Build consomme le flux d'arêtes orientées "
     "(GraphDataProvider.StreamAllDirectedEdges — SQL ou graphe généré) : "
     "indexation des nœuds, comptage des degrés, sommes préfixes → offsets, "
     "remplissage. O(n + m), une seule passe sur les arêtes plus une passe de "
     "remplissage.")
para("En mode SQL, la lecture est un seul SELECT sans WHERE, en flux :", bold=True)
code(between("Models/LineVisEdgRepository.cs",
             "public IEnumerable<(string From, string To)> StreamAllDirectedEdges()",
             "yield return ToEdge(reader.GetString(0), reader.GetString(1), reader.GetString(2));"),
     "C# — Models/LineVisEdgRepository.cs")
para("En mode graphe généré, le graphe est produit une fois au démarrage "
     "(graine fixe), et Build itère simplement la liste en mémoire :", bold=True)
code(method("Services/GeneratedGraphData.cs", "public GeneratedGraphData(int nodeCount = 5000)"),
     "C# — Services/GeneratedGraphData.cs")

# ---- 5.2 --------------------------------------------------------------
h2("5.2  Les quatre algorithmes de plus court chemin")

h3("5.2.1  Hypothèse : poids d'arêtes uniformes")
para("Toutes les arêtes ont le même poids, la constante EdgeWeight = 1. Le "
     "« coût » d'un chemin est donc son nombre d'arêtes. Conséquences :")
bullets([
    "Un simple BFS suffit à trouver l'optimum : c'est le choix par défaut.",
    "Dijkstra et A*, faits pour les graphes pondérés, renvoient exactement le "
    "même chemin (à un ex æquo près) — plus lentement. Ils sont fournis comme "
    "alternatives prêtes si la colonne Transformation devenait un coût réel.",
    "Le seul endroit à modifier pour introduire une pondération est la "
    "constante EdgeWeight (et la lecture du poids par arête).",
])

h3("5.2.2  BFS bidirectionnel  (algo=bfs, défaut)")
kv("Méthode", "DirectedGraph.ShortestPath")
para("Deux fronts en largeur : l'un avance depuis la source par les "
     "successeurs, l'autre depuis la cible par les prédécesseurs ; on alterne "
     "un front par palier (step % 2). Dès qu'un nœud est atteint des deux "
     "côtés, on recolle les deux demi-chemins (BuildPath). File FIFO, aucun tas.")
kv("Complexité", "≈ 2·b^(R/2) nœuds visités (b = facteur de branchement ≈ degré, "
   "R = longueur du chemin), contre b^R pour un BFS à sens unique.")
kv("Garde-fou", "MaxVisitedPerSide = 300 000 nœuds par sens.")

h3("5.2.3  Dijkstra  (algo=dijkstra)")
kv("Méthode", "DirectedGraph.ShortestPathDijkstra")
para("File de priorité (PriorityQueue de .NET) : on développe toujours le nœud "
     "de plus petit coût cumulé depuis la source. Un seul front. « settled » "
     "(HashSet) garantit qu'un nœud n'est traité qu'une fois, à sa première "
     "extraction (coût alors optimal).")
kv("Complexité", "O((n + m)·log n). Unidirectionnel : fige toute la boule de "
   "rayon R, souvent presque tout le graphe.")

h3("5.2.4  Dijkstra bidirectionnel  (algo=dijkstra-bi)")
kv("Méthode", "DirectedGraph.ShortestPathDijkstraBi")
para("Deux Dijkstra en miroir. Sur un graphe pondéré on ne peut pas s'arrêter "
     "au premier nœud vu des deux côtés : on garde le meilleur chemin complet "
     "rencontré (best) et on s'arrête quand la somme des deux plus petits "
     "coûts encore en file ne peut plus le battre (topF + topB ≥ best). On "
     "développe à chaque tour le front qui a le moins de nœuds figés.")
code(between("Services/DirectedGraph.cs",
             "while (pqF.Count > 0 && pqB.Count > 0)",
             "if (settledF.Count + settledB.Count > MaxVisited) break;"),
     "C# — Services/DirectedGraph.cs (condition d'arrêt)")

h3("5.2.5  A*  (algo=astar) — heuristique ALT")
kv("Méthode", "DirectedGraph.ShortestPathAStar  +  Heuristic  +  PrepareLandmarks")
para("A* = Dijkstra classant les nœuds par g(n) + h(n), où h(n) estime le coût "
     "restant jusqu'à la cible. Pour que le résultat reste optimal, h doit être "
     "ADMISSIBLE (ne jamais surestimer). Les nœuds n'ayant ni coordonnées ni "
     "poids géographiques, on ne peut pas faire de distance à vol d'oiseau : on "
     "utilise l'heuristique ALT (A*, Landmarks, Triangle inequality).")
numbered([
    "PrepareLandmarks choisit 6 « repères » bien étalés (farthest-first : "
    "chaque nouveau repère est le nœud le plus loin des précédents).",
    "Pour chaque repère, on précalcule par BFS sa distance VERS tous les "
    "nœuds et DEPUIS tous les nœuds (2 BFS complets par repère).",
    "L'inégalité triangulaire donne alors une borne inférieure valable de "
    "dist(n, cible) : le maximum sur les repères de "
    "(dist(repère, cible) − dist(repère, n)) et de "
    "(dist(n, repère) − dist(cible, repère)).",
])
para("Tant que PrepareLandmarks n'a pas tourné, h = 0 et A* se comporte "
     "exactement comme Dijkstra.")
code(between("Services/DirectedGraph.cs",
             "private int Heuristic(int n, int t)",
             "return h;"),
     "C# — Services/DirectedGraph.cs (heuristique ALT)")

h3("5.2.6  Comparatif")
para("Mesures : moyenne sur 200–300 appels, sur le graphe en mémoire, hors "
     "serveur web et hors cache (mode SQL, jeu de démonstration : 100 008 "
     "nœuds, 400 787 arêtes, graphe aléatoire, poids = 1). Machine de "
     "développement — c'est le rapport entre algorithmes qui compte. En mode "
     "graphe généré (5 000 nœuds) tous les algorithmes sont sous la "
     "milliseconde, les écarts restent dans le même sens.")
table([
    ("Algorithme", "Temps (pire cas)", "Chemin existant (médiane)", "Aucun chemin", "Correct si poids ≠ 1"),
    ("BFS bidirectionnel", "O(b^(R/2))", "0,06 ms", "22,8 ms", "non"),
    ("Dijkstra", "O((n+m)·log n)", "22,4 ms", "61,8 ms", "oui"),
    ("Dijkstra bidirectionnel", "~O(b^(R/2)·log b)", "0,37 ms", "0,001 ms", "oui"),
    ("A* (ALT)", "O((n+m)·log n)", "8,3 ms", "103,7 ms", "oui"),
])
bullets([
    "Le bidirectionnel (BFS ou Dijkstra) écrase le reste : deux fronts de "
    "rayon R/2 au lieu d'un de rayon R.",
    "Dijkstra bidirectionnel sur « aucun chemin » : 0,001 ms — un front se "
    "vide instantanément quand un nœud mène à un petit cul-de-sac.",
    "A* est le PIRE sur « aucun chemin » (~104 ms) : il calcule l'heuristique "
    "pour chaque nœud touché sans jamais pouvoir élaguer.",
    "A* reste lent sur ce graphe aléatoire : l'heuristique ALT n'a aucune "
    "structure spatiale à exploiter.",
])
para("Verdict de conception : tant que les poids valent 1, garder le BFS "
     "bidirectionnel (rien ne le bat, aucun précalcul). Si Transformation "
     "devient un coût réel, passer au Dijkstra bidirectionnel. A* ne se "
     "rentabiliserait que sur un graphe à structure exploitable (couches, "
     "coordonnées). Détail complet : docs/algorithmes-chemin.md.")

h3("5.2.7  Aiguillage et cache (HomeController)")
para("Normalisation de l'algorithme demandé :", bold=True)
code(between("Controllers/HomeController.cs",
             "var algoKey = (algo ?? ",
             "};"),
     "C# — Controllers/HomeController.cs")
para("Puis, dans la fabrique du cache : court-circuits SCC / scan (mode SQL), "
     "sinon EnsureLoaded() puis switch sur algoKey vers la bonne méthode du "
     "graphe en mémoire — toujours en mémoire (voir l'extrait du § 4.1.2).")

# ---- 5.3 --------------------------------------------------------------
h2("5.3  Pré-calcul § 11.4 — Composantes connexes faibles (Union-Find)")
kv("Service", "GraphScanService   —   Repository : NodeComponentRepository")
para("But : regrouper les nœuds par « île » en ignorant le sens des arêtes. "
     "Si deux nœuds sont dans des îles différentes, il n'existe AUCUN chemin "
     "entre eux, même non orienté — verdict certain, jamais un faux « non ». "
     "La connexité faible est une condition nécessaire d'existence d'un chemin.")
numbered([
    "Balayer toutes les arêtes (GraphDataProvider.StreamAllEdges, sens non "
    "dérivé) et les fusionner dans une structure Union-Find en mémoire "
    "(compression de chemin + union par rang, quasi O(1) amorti).",
    "Attribuer un numéro de composante (0, 1, 2…) par racine.",
    "Écrire (NodeId, ComponentId) en masse dans dbo.NODE_COMPONENT.",
])
para("Réservé au mode SQL : ScanController ne l'appelle qu'alors.", italic=True)
para("À la recherche, comparaison en O(1) :", bold=True)
code(method("Services/GraphScanService.cs",
            "public ComponentVerdict Compare(string source, string target)"),
     "C# — Services/GraphScanService.cs")

# ---- 5.4 --------------------------------------------------------------
h2("5.4  Pré-calcul § 11.5 — Condensation SCC (Kosaraju)")
kv("Service", "SccCondensationService   —   Repository : SccRepository")
para("Le scan des composantes faibles ne tranche pas le cas « même île ». La "
     "condensation SCC va plus loin : elle donne un OUI / NON EXACT pour "
     "l'existence d'un chemin ORIENTÉ, sans parcours du graphe d'origine.")
numbered([
    "Calculer les composantes fortement connexes (SCC) — algorithme de "
    "Kosaraju : deux parcours en profondeur ITÉRATIFS (pile explicite, pour "
    "ne pas déborder la pile d'appel sur 100 000 nœuds), O(n + m). Dans une "
    "SCC, tout nœud atteint tout autre.",
    "Contracter chaque SCC en un super-nœud → le « graphe condensé », qui est "
    "TOUJOURS un DAG (sans cycle) et beaucoup plus petit (quelques centaines "
    "de super-nœuds).",
    "Écrire (NodeId → SccId) dans NODE_SCC et les arêtes du condensé dans "
    "SCC_EDGE.",
    "À la recherche : un chemin u → v existe si et seulement si SccId(u) == "
    "SccId(v), ou si SccId(v) est atteignable depuis SccId(u) par un petit "
    "BFS sur le graphe condensé (mis en cache mémoire).",
])
code(method("Services/SccCondensationService.cs",
            "public SccReach Reachable(string source, string target)"),
     "C# — Services/SccCondensationService.cs")

# ---- 5.5 --------------------------------------------------------------
h2("5.5  Pipeline complet avant parcours")
para("Résumé de l'ordre, du plus précis / le moins coûteux au plus général :")
table([
    ("Étape", "Coût", "Peut conclure ?"),
    ("1. Condensation SCC (mode SQL, si calculée)", "O(1) + petit BFS condensé", "OUI (chemin existe) ou NON (exact), sans parcours"),
    ("2. Composantes faibles (mode SQL, si SCC absente)", "O(1)", "NON seulement (îles différentes), sans parcours"),
    ("3. Cache applicatif", "O(1)", "OUI, résultat déjà calculé < 5 min"),
    ("4. EnsureLoaded() + parcours (algo choisi, en mémoire)", "voir § 5.2.6", "OUI / NON définitif"),
])
para("Il n'y a plus d'étape « repli SQL » : le parcours est TOUJOURS en "
     "mémoire, EnsureLoaded() garantit que le graphe est construit.", italic=True)

# ---- 5.6 --------------------------------------------------------------
h2("5.6  Cache applicatif")
para("IMemoryCache (Microsoft.Extensions.Caching.Memory). Mémorise le résultat "
     "de chaque recherche, y compris les « aucun chemin » (les plus coûteuses).")
bullets([
    "Clé : path:{algo}:{source}:{target}:{maxDepth} — chaque algorithme est "
    "mémorisé séparément.",
    "Expiration absolue 5 minutes.",
    "SizeLimit = 10 000 entrées (Size = 1 par entrée) : borne la mémoire.",
    "PathViewModel.FromCache indique à la vue que le résultat vient du cache.",
])

# ---- 5.7 --------------------------------------------------------------
h2("5.7  Rendu SVG des graphes d'exemple")
para("SvgGraphRenderer transforme un GraphSample (nœuds + arêtes + type de "
     "layout) en chaîne SVG. Deux layouts calculés « à la main », sans "
     "dépendance : circulaire (une composante connexe = un cercle, cercles en "
     "grille) et par niveaux (tri topologique pour les DAG, BFS depuis le "
     "premier nœud pour les arbres). Aucune interaction, image statique.")

doc.add_page_break()

# ==========================================================================
h1("6. Contraintes techniques et non-fonctionnelles")

h2("6.1  Cible imposée : C# 8.0 / .NET 7.0, sans async")
table([
    ("Réglage (PathFinder.ScanMvc.csproj)", "Valeur"),
    ("TargetFramework", "net7.0"),
    ("LangVersion", "8.0"),
    ("Nullable", "enable"),
    ("ImplicitUsings", "disable"),
    ("Microsoft.Data.SqlClient", "5.2.2  (les versions 7.x ne ciblent que net8.0+)"),
])
para("Aucun SDK .NET 7 n'est requis sur le poste : le SDK 10 compile pour "
     "net7.0 (packs de référence restaurés via NuGet) et le runtime 7.0 "
     "installé exécute l'application.")

h2("6.2  Conséquences sur le style de code")
para("Le C# 8.0 interdit plusieurs constructions récentes utilisées ailleurs "
     "dans le dépôt. Règles à respecter dans ce projet :")
table([
    ("Interdit (C# 9+)", "À la place (C# 8)"),
    ("record / record struct", "classes scellées / struct : constructeur + propriétés en lecture seule"),
    ("namespace X;  (portée fichier)", "namespace X { … }  (bloc, tout indenté)"),
    ("using implicites (ImplicitUsings)", "using explicites dans chaque fichier"),
    ("[]  (collection expressions)", "new List<T>()  /  new T[] { … }  /  Array.Empty<T>()"),
    ("new()  (ciblé par le type)", "new TypeExplicite()"),
    ("is not null  /  is not X", "!= null  /  !(x is X)"),
    ("top-level statements", "class Program { static void Main(string[] args) }"),
    ("async / await", "Thread pour le préchargement ; Task.CompletedTask toléré (imposé par IHostedService)"),
])

h2("6.3  Performance")
bullets([
    "Chargement CSR au démarrage : ~1,2–2,0 s pour 100 000 nœuds (mode SQL), "
    "~35 ms pour 5 000 nœuds (mode généré) ; repères ALT : ~0,2–0,5 s de plus "
    "en mode SQL. En tâche de fond, le serveur répond pendant ce temps.",
    "Recherche en mémoire : voir tableau § 5.2.6 (de 0,04 ms à ~20 ms selon "
    "l'algorithme et le cas, mode SQL ; toujours < 1 ms en mode généré).",
    "Premier appel avant fin du préchargement : EnsureLoaded() bloque la "
    "requête le temps de construire le graphe (rare, ~2 s en mode SQL).",
    "Cache 5 min : une 2e requête identique répond en O(1).",
])

h2("6.4  Robustesse — garde-fous")
table([
    ("Garde-fou", "Où", "Rôle"),
    ("maxDepth (défaut 12, ≤ 20)", "HomeController", "Plafonne la longueur de chemin cherchée"),
    ("MaxVisitedPerSide = 300 000", "DirectedGraph (BFS bi)", "Plafonne les nœuds visités par sens"),
    ("MaxVisited = 600 000", "DirectedGraph (Dijkstra, Dijkstra bi, A*)", "Plafonne les nœuds figés"),
    ("verrou _loadLock", "InMemoryGraphService", "EnsureLoaded() ne construit le graphe qu'une seule fois même sous requêtes concurrentes"),
    ("Connect Timeout = 3 s", "LineVisEdgRepository.CanConnect", "La sonde SQL du mode auto ne retarde pas le démarrage si la base est absente"),
    ("CommandTimeout = 0", "lectures en flux (StreamAll*)", "Pas de timeout sur les gros SELECT"),
    ("try/catch SqlException", "repositories de scan", "Table absente (scan jamais lancé) → on laisse le parcours agir"),
])

h2("6.5  Sécurité")
bullets([
    "Toutes les requêtes SQL sont paramétrées (SqlParameter), jamais de "
    "concaténation d'entrée utilisateur. Les identifiants de colonnes de "
    "clause IN sont générés (@n0, @n1…), les valeurs restent des paramètres.",
    "Paramètres typés VARCHAR explicitement (performance ET pas de surprise "
    "de collation).",
    "Les actions d'écriture (/Scan/Run, /Scan/RunScc, /Scan/ReloadGraph) sont "
    "en POST et protégées par [ValidateAntiForgeryToken].",
    "Aucune donnée sensible : identifiants de nœuds et libellés de "
    "transformation uniquement.",
])

h2("6.6  Limites connues")
bullets([
    "Poids d'arêtes non gérés (uniformes = 1) — voir § 5.2.1.",
    "Mode graphe généré : c'est une DÉMONSTRATION, pas les vraies données. "
    "Les pré-calculs § 11.4 / § 11.5 y sont désactivés.",
    "Les tables de pré-calcul sont recréées en entier à chaque exécution : "
    "pas de mise à jour incrémentale, et une exécution concurrente de deux "
    "scans du même type n'est pas protégée (usage attendu : un opérateur, "
    "ponctuellement).",
    "Le graphe en mémoire est un instantané : après modification de la source "
    "il faut relancer /Scan/ReloadGraph (et, en mode SQL, les deux autres "
    "pré-calculs).",
    "Montée en charge mémoire : ~40 octets/arête + ~30 octets/nœud pour le "
    "CSR, plus les repères ALT ; au-delà de quelques millions de nœuds, "
    "prévoir la RAM correspondante.",
])

doc.add_page_break()

# ==========================================================================
h1("7. Inventaire des fichiers")
table([
    ("Fichier", "Type", "Rôle"),
    ("Program.cs", "Démarrage", "Injection de dépendances, route MVC par défaut, hosted service"),
    ("appsettings.json", "Configuration", "Data:Source (auto|sql|generated), Data:GeneratedNodes, Database:*"),
    ("Controllers/HomeController.cs", "Controller", "Recherche de chemin : (mode SQL) SCC → scan, puis EnsureLoaded + algo + cache"),
    ("Controllers/ScanController.cs", "Controller", "Page /Scan : statuts + déclenchement des pré-calculs (refusés hors mode SQL)"),
    ("Controllers/GraphesController.cs", "Controller", "Galerie « types de graphes » + génération de fichiers SVG"),
    ("Services/GraphDataProvider.cs", "Service", "Choisit la source (SQL / généré) ; StreamAll*, DescribePath, ScanAvailable"),
    ("Services/GeneratedGraphData.cs", "Service", "Graphe de démonstration généré en RAM (graine fixe) — aucune base requise"),
    ("Models/LineVisEdgRepository.cs", "Repository", "Mode SQL : CanConnect, DescribePath, StreamAllEdges / StreamAllDirectedEdges"),
    ("Models/NodeComponentRepository.cs", "Repository", "NODE_COMPONENT : ReplaceAll, GetComponentIds"),
    ("Models/SccRepository.cs", "Repository", "NODE_SCC + SCC_EDGE : ReplaceAll, GetSccIds, LoadCondensedAdjacency"),
    ("Models/PathViewModel.cs", "ViewModel", "Données de l'écran de recherche (dont AlgoLabel, SourceDescription)"),
    ("Models/ScanPageViewModel.cs", "ViewModel", "Statuts des trois pré-calculs + source + ScanAvailable"),
    ("Models/GraphSample.cs / GraphSamples.cs", "Données", "Catalogue codé en dur des graphes d'exemple"),
    ("Services/DirectedGraph.cs", "Service", "Structure CSR + BFS bi, Dijkstra, Dijkstra bi, A* (ALT), PrepareLandmarks"),
    ("Services/InMemoryGraphService.cs", "Service", "Reload / EnsureLoaded / GraphPreloader (Thread), passe-plats, GraphStatus"),
    ("Services/GraphScanService.cs", "Service", "§ 11.4 — Union-Find, Compare"),
    ("Services/SccCondensationService.cs", "Service", "§ 11.5 — Kosaraju, condensation, Reachable"),
    ("Services/SvgGraphRenderer.cs", "Service", "GraphSample → SVG (layouts circulaire / par niveaux)"),
    ("Views/Home/Index.cshtml", "Vue", "Formulaire + résultat de la recherche"),
    ("Views/Scan/Index.cshtml", "Vue", "Tableau de bord des pré-calculs"),
    ("Views/Graphes/Index.cshtml + Build.cshtml", "Vues", "Galerie + liste des fichiers produits"),
    ("Views/Shared/_Layout.cshtml", "Vue", "Gabarit commun (en-tête, navigation)"),
    ("wwwroot/css/site.css", "Style", "Feuille de style unique"),
], font_size=8)

doc.add_page_break()

# ==========================================================================
h1("8. Glossaire")
gloss = [
    ("BFS (parcours en largeur)", "Explore le graphe niveau par niveau depuis un nœud. Sur un graphe non pondéré, le premier chemin trouvé vers un nœud est le plus court (en nombre d'arêtes)."),
    ("BFS bidirectionnel", "Deux BFS simultanés, un depuis la source, un depuis la cible ; ils se rejoignent au milieu. ~2·b^(R/2) nœuds au lieu de b^R."),
    ("Dijkstra", "Généralisation du BFS aux graphes pondérés : développe toujours le nœud de plus petit coût cumulé, via une file de priorité."),
    ("A*", "Dijkstra guidé par une estimation h(n) du coût restant. Optimal si h est admissible (ne surestime jamais)."),
    ("Heuristique admissible", "Fonction h(n) qui ne surestime jamais le vrai coût de n à la cible. Condition pour que A* trouve l'optimum."),
    ("ALT (A*, Landmarks, Triangle inequality)", "Heuristique pour A* sans coordonnées : quelques repères, distances précalculées, borne inférieure par inégalité triangulaire."),
    ("Repère (landmark)", "Nœud choisi dont on précalcule la distance vers/depuis tous les autres, pour alimenter l'heuristique ALT."),
    ("Front / frontière", "Ensemble des nœuds découverts au palier courant d'un parcours, à partir desquels on avance."),
    ("Palier", "Une itération d'un parcours par largeur : on traite toute la frontière courante d'un coup."),
    ("Relâchement (relax)", "Mettre à jour le meilleur coût connu d'un nœud v quand on trouve un chemin plus court en passant par un voisin u."),
    ("Composante connexe faible", "Ensemble maximal de nœuds reliés entre eux si l'on ignore le sens des arêtes. Nœuds dans des composantes faibles différentes = aucun chemin possible."),
    ("SCC (composante fortement connexe)", "Ensemble maximal de nœuds où chacun atteint tous les autres en respectant le sens des arêtes."),
    ("Graphe condensé", "Graphe obtenu en contractant chaque SCC en un seul super-nœud. C'est toujours un DAG."),
    ("DAG", "Graphe orienté sans cycle (Directed Acyclic Graph). Ses nœuds peuvent être rangés par niveaux (tri topologique)."),
    ("Union-Find (disjoint set)", "Structure qui regroupe des éléments en ensembles disjoints avec fusion et test d'appartenance quasi O(1)."),
    ("Kosaraju", "Algorithme de calcul des SCC en deux parcours en profondeur (un sur le graphe, un sur le graphe inversé)."),
    ("CSR (Compressed Sparse Row)", "Représentation compacte d'un graphe : les voisins de tous les nœuds concaténés dans un tableau, plus un tableau d'offsets."),
    ("ToEdge / Direction", "Règle qui transforme une ligne (Nodes, Direction, NodesLie) en arête orientée."),
    ("Mode auto / SQL / généré", "auto : SQL si joignable, sinon graphe généré. sql : force SQL. generated : force le graphe de démo en mémoire (aucune base)."),
    ("EnsureLoaded()", "Construit le graphe en mémoire à la demande, sous verrou, s'il n'est pas déjà prêt. Remplace l'ancien repli SQL palier par palier."),
]
for term, definition in gloss:
    p = doc.add_paragraph()
    p.add_run(term + " — ").bold = True
    p.add_run(definition)

doc.add_page_break()

# ==========================================================================
h1("Annexe — Détail des durées mesurées")
para("ms par appel, moyenne sur 200 appels, MODE SQL, jeu de démonstration "
     "100 008 nœuds, hors serveur et hors cache. Longueur du chemin entre "
     "parenthèses. En mode graphe généré (5 000 nœuds), tout est < 1 ms.")
table([
    ("Couple", "BFS bidir.", "Dijkstra", "Dijkstra bidir.", "A* (ALT)"),
    ("N1 → N500 (9)", "0,14", "52,6", "0,64", "17,7"),
    ("N1 → N50 (8)", "0,16", "22,4", "0,44", "8,3"),
    ("N1 → N99000 (7)", "0,04", "11,9", "0,08", "2,4"),
    ("N2 → N3 (8)", "0,05", "24,4", "0,37", "11,1"),
    ("N77 → N88888 (7)", "0,06", "9,2", "0,16", "7,6"),
    ("N12345 → N67890 (aucun chemin)", "22,8", "61,8", "0,001", "103,7"),
])
para("Reproductible avec le banc d'essai scratchpad/bench/ "
     "(dotnet run -c Release -- <source> <cible> <nbIterations>).", italic=True)

# ==========================================================================
OUT.parent.mkdir(parents=True, exist_ok=True)
doc.save(OUT)
print(f"OK -> {OUT}")
