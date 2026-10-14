# Lineage en SQL — procédures `LINE_VIS_*`

Procédures SQL Server d'exploration du lineage stocké dans `dbo.LINE_VIS_EDG`
(base `RestitutionGrapheProd`, SQL Server Express). Les résultats se lisent
directement en SQL (SSMS, sqlcmd) : aucune application n'est nécessaire.

Ce document décrit les fonctionnalités de **lineage multi-niveaux** :
`LINE_VIS_Lineage`, `LINE_VIS_Impact`, `LINE_VIS_Chemin`,
`LINE_VIS_LineageTables`, et le **contrôle qualité** `LINE_VIS_ControleQualite`. Les procédures plus anciennes (`LINE_VIS_NodesList`,
`LINE_VIS_NodeById`, `LINE_VIS_GetNodesSuccessorsPredecessors`) sont décrites
dans l'en-tête de leur fichier.

```
Sql-procedure-table/
├── LINE_VIS_EDG.sql, LINE_VIS_HEA.sql        # tables
├── LINE_VIS_EDG_IndexHash.sql                # index (EDG_DIR, DTA_HASH) — utilisé par tout le parcours
├── LINE_VIS_NodesList.sql                    # recherche d'un nœud (point d'entrée)
├── LINE_VIS_Lineage_Parcours.sql             # parcours du graphe (procédure interne, partagée)
├── LINE_VIS_Lineage.sql                      # lineage multi-niveaux
├── LINE_VIS_Impact.sql                       # analyse d'impact
├── LINE_VIS_Chemin.sql                       # plus courts chemins entre deux nœuds
├── LINE_VIS_LineageTables.sql                # lineage table -> table
├── LINE_VIS_ControleQualite.sql              # contrôle qualité des données de lineage
├── LINE_VIS_HEA_manquants.sql                # ajoute les en-têtes LINE_VIS_HEA manquants (après un rechargement)
└── tests/
    ├── run_tests.sh                          # déploie tout dans une base jetable et lance les tests
    ├── experiences_LINE_VIS.sql              # toutes les mesures, avec leurs résultats en commentaire
    └── test_LINE_VIS_*.sql                   # un fichier de test par procédure
```

## Le modèle

| Notion | Dans `LINE_VIS_EDG` |
|---|---|
| **Nœud** (une colonne) | une combinaison `DTA_1..DTA_4` = colonne, table, schéma, environnement |
| **Lien** | une ligne : du nœud `DTA_1..DTA_4` vers le voisin `EDG_1..EDG_4` |
| **Sens** | `EDG_DIR = 'O'` : le voisin est un **successeur** (nœud → voisin) ; `'I'` : un **prédécesseur** (voisin → nœud) |
| **Programme** | `LINE_VIS_HEA` (1 ligne par `LNA_UID`) : `RON_APP`, `PCK_PGM_NME`, `EXE_PGM_NME`, `APP_ENV` |

Règles communes à toutes les procédures :

- seuls les liens dont le `LNA_UID` existe dans `LINE_VIS_HEA` sont suivis ;
- les coordonnées se comparent comme avec `=` : casse et espaces de fin ignorés ;
  une coordonnée `NULL` fait partie de l'identité du nœud ;
- un voisin dont `EDG_1..EDG_4` sont tous vides n'est pas un nœud ;
- un nœud déjà vu n'est jamais exploré deux fois : les **cycles** s'arrêtent seuls ;
- les liens renvoyés vont toujours dans le **sens du flux de données**
  (source → destination), quelle que soit la valeur de `EDG_DIR`.

## Point de départ : trouver un nœud

Les procédures désignent un nœud par la clé primaire d'une de ses lignes
(`LNA_UID`, `LIN_UID`, `EDG_DIR`), telle que la renvoie `LINE_VIS_NodesList` :

```sql
USE RestitutionGrapheProd;
EXEC dbo.LINE_VIS_NodesList @p_column = 'MA_COLONNE', @p_table = 'MA_TABLE';
-- -> colonnes LNA_UID, LIN_UID, EDG_DIR à reprendre ci-dessous
```

## `LINE_VIS_Lineage` — lineage sur plusieurs niveaux

```sql
EXEC dbo.LINE_VIS_Lineage
    @p_lnauid = '...', @p_linuid = '...', @p_edgdir = 'O',
    @p_sens       = 'O',   -- 'O' aval | 'I' amont | 'B' les deux
    @p_profondeur = 5,     -- niveaux maximum
    @p_maxnoeuds  = 500;   -- nœuds maximum (au-delà : TRONQUE = 1)
```

| Jeu de résultats | Colonnes |
|---|---|
| 1. Nœuds | `NOD_ID`, `NIVEAU` (0 = départ), `SENS` (`-` / `O` / `I`), `DTA_1..4`, `NOM_NOEUD`, `EXPLORE` (0 = voisins non lus, dernier niveau), `TRONQUE` |
| 2. Arêtes | `SRC_NOD_ID` → `DST_NOD_ID`, `NB_LIENS` (lignes de `LINE_VIS_EDG`), `NB_PROGRAMMES` |

## `LINE_VIS_Impact` — analyse d'impact

« Si je modifie cette colonne, qu'est-ce qui est touché ? »

```sql
EXEC dbo.LINE_VIS_Impact
    @p_lnauid = '...', @p_linuid = '...', @p_edgdir = 'O',
    @p_sens = 'O',            -- aval par défaut ; 'I' = d'où viennent les données
    @p_profondeur = 10, @p_maxnoeuds = 2000;
```

| Jeu de résultats | Colonnes |
|---|---|
| 1. Résumé (1 ligne) | `NOEUD_TROUVE`, `NB_NOEUDS`, `NB_TABLES`, `NB_SCHEMAS`, `NB_ENVIRONNEMENTS`, `NB_APPLICATIONS`, `NB_PROGRAMMES`, `NB_EXECUTIONS`, `PROFONDEUR`, `TRONQUE` |
| 2. Tables touchées | `SENS`, `DTA_4`, `DTA_3`, `DTA_2`, `NB_COLONNES`, `NIVEAU_MIN` |
| 3. Programmes touchés | `SENS`, `RON_APP`, `PCK_PGM_NME`, `EXE_PGM_NME`, `APP_ENV`, `NB_EXECUTIONS`, `NB_LIENS`, `NIVEAU_MIN`, `DERNIERE_EXECUTION` |

Le nœud de départ n'est jamais compté. Un programme = (`RON_APP`,
`PCK_PGM_NME`, `EXE_PGM_NME`, `APP_ENV`) ; chaque `LNA_UID` en est une exécution.

## `LINE_VIS_Chemin` — plus courts chemins entre deux nœuds

« Comment A alimente-t-il B ? »

```sql
EXEC dbo.LINE_VIS_Chemin
    'LNA_A', 'L1', 'O',     -- nœud A (LNA_UID, LIN_UID, EDG_DIR)
    'LNA_B', 'L9', 'O',     -- nœud B
    @p_profondeur = 10, @p_maxnoeuds = 5000;
```

| Jeu de résultats | Colonnes |
|---|---|
| 1. Résumé (1 ligne) | `SRC_TROUVE`, `DST_TROUVE`, `CHEMIN_TROUVE`, `LONGUEUR` (nombre de liens), `NB_CHEMINS`, `NB_NOEUDS_PARCOURUS`, `TRONQUE` |
| 2. Nœuds du chemin | `NOD_ID`, `POSITION` (0 = A … `LONGUEUR` = B), `DTA_1..4`, `NOM_NOEUD`, `NB_CHEMINS` |
| 3. Arêtes du chemin | `SRC_NOD_ID` → `DST_NOD_ID`, `POSITION`, `NB_LIENS`, `NB_PROGRAMMES`, `PROGRAMMES` (liste des `EXE_PGM_NME`) |

- Seuls les **plus courts** chemins sont renvoyés ; s'il y en a plusieurs de
  même longueur, ils y sont **tous**. Les détours sont écartés.
- Uniquement dans le sens du flux **A → B**. Pour savoir si B alimente A,
  inverser les deux nœuds.
- Le parcours s'arrête dès que B est atteint.

## `LINE_VIS_LineageTables` — lineage table → table

```sql
EXEC dbo.LINE_VIS_LineageTables
    @p_table  = 'MA_TABLE',     -- obligatoire (DTA_2)
    @p_schema = 'MON_SCHEMA',   -- facultatif (DTA_3), NULL = tous
    @p_env    = 'PROD',         -- facultatif (DTA_4), NULL = tous
    @p_sens = 'O', @p_profondeur = 5, @p_maxnoeuds = 5000;
```

| Jeu de résultats | Colonnes |
|---|---|
| 1. Tables | `TAB_ID`, `NIVEAU`, `SENS` (`-` / `O` / `I` / `B`), `DTA_4`, `DTA_3`, `DTA_2`, `NOM_TABLE`, `NB_COLONNES`, `TRONQUE` |
| 2. Liens | `SRC_TAB_ID` → `DST_TAB_ID`, `NB_COLONNES_LIEES`, `NB_LIENS`, `NB_PROGRAMMES`, `PROGRAMMES` |

Le calcul part de **toutes les colonnes** de la table, suit le lineage colonne
par colonne, puis regroupe par table. Le résultat est exact : si T1 n'alimente
que la colonne `a` de T2 et que seule la colonne `b` de T2 alimente T3, T3
n'apparaît pas en aval de T1. Les liens d'une table vers elle-même ne sont pas
affichés.

## `LINE_VIS_ControleQualite` — contrôle qualité des données

« Les données de lineage sont-elles fiables ? »

```sql
EXEC dbo.LINE_VIS_ControleQualite @p_exemples = 5;   -- ~2 min 40 sur 7,2 M lignes
```

| Jeu de résultats | Colonnes |
|---|---|
| 1. Synthèse (1 ligne par contrôle) | `ORDRE`, `CONTROLE`, `DESCRIPTION`, `NB_LIGNES`, `NB_DISTINCTS`, `NB_LIGNES_TOTAL`, `POURCENT`, `STATUT` (`OK` / `ANOMALIE`) |
| 2. Exemples | `CONTROLE`, `LNA_UID`, `LIN_UID`, `EDG_DIR`, `DTA_1..4`, `EDG_1..4` (au plus `@p_exemples` par contrôle) |

| Contrôle | Anomalie cherchée | Conséquence |
|---|---|---|
| `SYM_O_SANS_I` / `SYM_I_SANS_O` | lien `A -O-> B` sans la ligne inverse `B -I-> A` (et l'inverse) | Proches de 0 % : chaque lien est stocké des deux côtés, cohérent avec « `O` = successeur, `I` = prédécesseur ». Proches de 100 % : un lien = une seule ligne. |
| `SANS_ENTETE` | `LNA_UID` absent de `LINE_VIS_HEA` | ces lignes sont **ignorées** par toutes les procédures de lineage |
| `ENTETE_INUTILISEE` | en-tête sans aucune ligne dans `LINE_VIS_EDG` | programme déclaré mais sans lineage capturé |
| `VOISIN_VIDE` | `EDG_1..4` tous vides | la ligne ne mène nulle part |
| `VOISIN_INCOMPLET` / `NOEUD_INCOMPLET` | une partie de `EDG_n` / `DTA_n` vide | identification partielle de la colonne |
| `VOISIN_FANTOME` | voisin qui n'est le nœud d'aucune ligne | le lineage s'arrête là (erreur de capture ou vraie sortie finale) |
| `DOUBLON` | même lien plusieurs fois pour le même programme | `NB_LIENS` gonflés |

La table est lue **une seule fois** ; les contrôles travaillent ensuite sur
des empreintes `CHECKSUM` dans tempdb (~250 Mo pour 7,2 M lignes). Une
anomalie signalée est toujours réelle ; une collision d'empreintes peut en
cacher quelques-unes : les nombres sont des minimums (écart ≤ 0,2 %, mesuré
à 0,15 % sur `VOISIN_FANTOME`).

Résultat sur les données de test (2026-10-15) : 100 % `SYM_*` (chaque lien
n'y est stocké qu'une fois), **12,5 % `SANS_ENTETE`** (900 000 lignes,
30 000 `LNA_UID`, ignorées par le lineage), 66,7 % `VOISIN_INCOMPLET` et
~100 % `VOISIN_FANTOME` (voulus par le générateur). Détail dans
`tests/experiences_LINE_VIS.sql`, expérience 5.

**`SANS_ENTETE` : origine et correction** (expérience 6). `LINE_VIS_EDG` a
été rechargée par bcp (`Sql-bcp-staging/LINE_VIS_EDG_8M.data`, 240 000
`LNA_UID`) sans relancer la génération de l'en-tête, restée à 210 000
`LNA_UID`. Correction : `LINE_VIS_HEA_manquants.sql` ajoute seulement les
en-têtes manquants (30 000, 10 s), sans toucher aux existants ;
`SANS_ENTETE` est maintenant à 0. **Après chaque rechargement de
`LINE_VIS_EDG`, lancer `LINE_VIS_HEA_manquants.sql`.**

À noter : la table contient 7 200 000 lignes alors que le fichier en a
8 000 000 (import incomplet, cause non établie).

## Lire et retravailler les résultats en SQL

Dans SSMS, un appel affiche tous ses jeux de résultats l'un sous l'autre.
Pour filtrer, trier ou joindre un résultat, demander **un seul** jeu avec
`@p_sortie` et le récupérer avec `INSERT ... EXEC` :

| Procédure | `@p_sortie` |
|---|---|
| `LINE_VIS_Lineage` | `T` tout · `N` nœuds · `A` arêtes |
| `LINE_VIS_Impact` | `T` tout · `R` résumé · `O` tables · `P` programmes |
| `LINE_VIS_Chemin` | `T` tout · `R` résumé · `N` nœuds · `A` arêtes |
| `LINE_VIS_LineageTables` | `T` tout · `N` tables · `A` liens |
| `LINE_VIS_ControleQualite` | `T` tout · `S` synthèse · `E` exemples |

```sql
DECLARE @pgm TABLE (
    SENS CHAR(1), RON_APP VARCHAR(4), PCK_PGM_NME VARCHAR(500), EXE_PGM_NME VARCHAR(500),
    APP_ENV VARCHAR(20), NB_EXECUTIONS INT, NB_LIENS INT, NIVEAU_MIN INT,
    DERNIERE_EXECUTION DATETIME2);

INSERT INTO @pgm EXEC dbo.LINE_VIS_Impact 'LNA_A', 'L1', 'O', @p_sortie = 'P';

SELECT * FROM @pgm WHERE APP_ENV = 'PROD' ORDER BY NB_LIENS DESC;
```

## Fonctionnement et performances

Les quatre procédures s'appuient sur une procédure interne commune,
`LINE_VIS_Lineage_Parcours`. Elle ne renvoie rien : elle remplit les tables
`#noeuds` et `#liens` créées par la procédure qui l'appelle (le modèle de ces
tables est dans son en-tête).

- **Parcours en largeur, un niveau à la fois** (boucle `WHILE`), plutôt qu'une
  CTE récursive, qui repasserait par tous les chemins et exploserait sur les cycles.
- **Chaque niveau = une recherche dans l'index** `IX_LINE_VIS_EDG_DIR_HASH`
  (`EDG_DIR`, `DTA_HASH`), imposée par `FORCESEEK` : sans ce hint, SQL Server
  lisait les 7 M lignes (~40 s par appel au lieu de quelques ms).
- **Rien n'est écrit dans la base** ni dans son journal : tout le travail se
  fait dans des tables `#temporaires` (tempdb). Aucune table ni aucun index
  n'a été ajouté.

Temps mesurés sur 7,2 M lignes (SQL Server 2022 Express) :

| Procédure | Temps |
|---|---|
| `LINE_VIS_Lineage` | 30 à 50 ms |
| `LINE_VIS_Impact` | ~50 ms |
| `LINE_VIS_Chemin` | ~10 ms |
| `LINE_VIS_LineageTables` (table + schéma + env.) | 5 à 14 s |
| `LINE_VIS_ControleQualite` (table entière) | ~160 s |

`LINE_VIS_LineageTables` doit lire toute la table une fois pour trouver les
colonnes de départ : aucun index ne permet de chercher par table. Un index sur
`DTA_2` la ferait descendre sous la seconde, pour environ 1,1 Go de plus
(taille comparable à `IX_LINE_VIS_EDG_DIR_HASH`) ; il n'est **pas** créé.

> Limite des données de test : dans les 7 M lignes générées, un voisin
> (`EDG_1..4`) n'est jamais lui-même le point de départ d'une autre ligne, et
> toutes les lignes ont la même table (`DTA_2 = 'ZJ'`). Le parcours s'y arrête
> donc au niveau 1. Les cas sur plusieurs niveaux (cycles, plusieurs chemins,
> regroupement par table) sont vérifiés par les tests unitaires.

## Déploiement

Ordre (chaque script est rejouable) :

```bash
sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_Lineage_Parcours.sql   # d'abord : utilisée par les autres
sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_Lineage.sql
sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_Impact.sql
sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_Chemin.sql
sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_LineageTables.sql
sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_ControleQualite.sql
```

`-I` est obligatoire (`QUOTED_IDENTIFIER ON`) : sans lui, la procédure ne
peut pas utiliser l'index sur la colonne calculée `DTA_HASH`.

## Tests

```bash
SERVER='.\SQLEXPRESS01' bash tests/run_tests.sh   # KEEP=1 pour garder la base de test
```

Le script crée une base jetable (`RestitutionGrapheProd_Test`), y déploie
tables et procédures, exécute chaque `tests/test_*.sql` (une ligne
`PASS` / `FAIL` par vérification) puis supprime la base.

## Place disque (mesurée le 2026-10-15)

| Fichier | Taille | Utilisé |
|---|---|---|
| Données `RestitutionGrapheProd.mdf` | 4 680 Mo | 3 621 Mo |
| Journal `RestitutionGrapheProd_log.ldf` | 7 112 Mo | 27 Mo (0,4 %) |

- La limite de 10 Go de SQL Server Express porte sur les **fichiers de
  données** seulement : 3,6 Go utilisés, il reste **~6,5 Go** de marge.
- Le journal (7,1 Go) est presque vide : la base est en mode `SIMPLE`, il a
  grossi lors du chargement des 7 M lignes en une seule transaction.
- `LINE_VIS_EDG` occupe 3,6 Go : table (`PK_LINE_VIS_EDG`) 2,5 Go + index
  `IX_LINE_VIS_EDG_DIR_HASH` 1,1 Go.

## Ne pas remplir le journal

Les procédures de lineage n'écrivent **rien** dans le journal (lecture seule,
tables `#temporaires` dans tempdb). Le journal ne grossit que pendant les
**chargements** de `LINE_VIS_EDG`.

En mode `SIMPLE`, la place du journal est réutilisée dès qu'une transaction
est validée : **la taille du journal ≈ la plus grosse transaction**. Règles :

1. **Charger par lots**, jamais tout en une transaction. `LINE_VIS_EDG_bcp.cmd`
   et `LINE_VIS_EDG_bcp.ps1` valident tous les 100 000 lignes (`-b 100000`) ;
   `LINE_VIS_EDG_data.sql` (données de test) aussi : 70 lots de 100 000 lignes,
   un `CHECKPOINT` après chaque lot. Mesuré sur une base vide : journal de
   136 Mo pour 1 M lignes, 200 Mo pour 2 M lignes (l'ancienne version, en une
   seule transaction, avait fait monter le journal à 7,1 Go pour 7 M lignes).
2. **Désactiver l'index `IX_LINE_VIS_EDG_DIR_HASH` avant un gros chargement**
   et le reconstruire après : chaque ligne insérée met à jour l'index et
   ajoute au journal ; la reconstruction en mode `SIMPLE` est minimalement
   journalisée.
   ```sql
   ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG DISABLE;
   -- ... chargement bcp ...
   ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG REBUILD;
   ```
3. **Vider par `TRUNCATE TABLE`** plutôt que `DELETE` sans filtre (un `DELETE`
   écrit chaque ligne supprimée dans le journal). Pour supprimer une partie
   des lignes, le faire par lots (`DELETE TOP (50000) ... WHERE ...` en boucle).
4. **Ne pas plafonner le journal** (`MAXSIZE`) : un journal plein arrête toute
   écriture (erreur 9002). La bonne protection, ce sont les lots.
5. Vérifier l'occupation du journal :
   ```sql
   DBCC SQLPERF(LOGSPACE);   -- taille et % utilisé de chaque journal
   SELECT recovery_model_desc, log_reuse_wait_desc
   FROM sys.databases WHERE name = 'RestitutionGrapheProd';   -- SIMPLE / NOTHING attendus
   ```
