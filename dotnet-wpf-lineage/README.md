# Lineage Explorer — WPF (.NET Framework 4.8)

Application Windows (pas une console) pour explorer le **graphe de lineage**
de la base `RestitutionGrapheProd` (scripts de `Sql-procedure-table/`).

- **Aucun NuGet** : l'accès SQL passe par `System.Data.SqlClient`, inclus
  dans .NET Framework.
- **Aucune requête SQL écrite à la main** : l'appli appelle seulement les
  procédures `LINE_VIS_NodesList` (recherche) et
  `LINE_VIS_GetNodesSuccessorsPredecessors` (voisins).
- **Interface fluide** : les appels SQL sont asynchrones (la fenêtre ne gèle
  jamais), et le graphe est animé (zoom, déplacement, cartes qui glissent à
  leur place).

## Lancer

1. Double-clic sur `LineageExplorer.sln` (Visual Studio 2022).
2. **F5** (ou le bouton vert ▶ Démarrer).

Si la connexion échoue, corrige la chaîne `RestitutionGrapheProd` dans
`App.config` (par défaut `Server=.\SQLEXPRESS01`, compte Windows).

## Utilisation

| Action | Effet |
|---|---|
| Filtres à gauche + **Entrée** | recherche de nœuds (« contient », sans casse ni accents) |
| Clic sur un résultat | le nœud s'affiche au centre, ses prédécesseurs et successeurs se chargent |
| Bouton **‹** / **›** d'une carte | déplie les prédécesseurs / successeurs de ce nœud |
| Double-clic sur une carte | déplie les deux côtés |
| Clic droit sur une carte | déplier, repartir de ce nœud, copier le nom complet |
| Clic sur une carte ou une flèche | détails à droite (traitement, programme, TXN_DTA…) |
| Molette / glisser le fond | zoom / déplacement |
| **F**, **C**, **+**, **−** | tout voir, recentrer, zoomer, dézoomer |
| **Échap** | annule la requête en cours |

Les chiffres dans les boutons ronds donnent le nombre d'arêtes chargées ;
`50+` signifie qu'il y en a plus en base (augmenter « Max voisins »).

## Comment le graphe est lu

Une ligne de `LINE_VIS_EDG` est une arête :

- `DTA_1..DTA_4` = le nœud (colonne, table, schéma, environnement) ;
- `EDG_1..EDG_4` = le voisin ;
- `EDG_DIR = 'O'` : le voisin est un **successeur**, `'I'` : un **prédécesseur**.

Pour déplier un voisin, l'appli redonne la ligne d'arête à la procédure avec
`@p_useEdg = 1` (la procédure cherche alors les lignes dont les DTA valent
ces EDG). Si une des 4 coordonnées EDG est NULL, la procédure ne peut pas
utiliser son index et lit toute la table : la barre d'état prévient, et
**Échap** annule.

> Avec les données de test générées par `LINE_VIS_EDG_data.sql`, les valeurs
> EDG (`xDI_…`, `EDG2_…`) n'existent jamais comme DTA : on voit donc un
> niveau de voisins autour du nœud choisi, pas plus. Sur de vraies données de
> lineage, le dépliage continue de proche en proche.

## Fichiers

```
dotnet-wpf-lineage/
├── LineageExplorer.sln / .csproj   # projet WPF .NET Framework 4.8 classique
├── App.config                      # chaîne de connexion + délai des requêtes
├── App.xaml                        # couleurs et styles communs
├── MainWindow.xaml(.cs)            # fenêtre : recherche, graphe, détails, barre d'état
├── Details.cs                      # contenu du panneau de droite
├── Data/
│   ├── Models.cs                   # NodeCoords, RowRef, EdgeRow...
│   └── LineageRepository.cs        # appels des procédures (async, annulables)
└── Graph/
    ├── LineageGraph.cs             # nœuds, arêtes, placement en colonnes
    └── GraphView.cs                # dessin, zoom/déplacement, animations
```
