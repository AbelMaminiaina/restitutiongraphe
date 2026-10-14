-- =============================================================================
--  Experiences de test des procedures de lineage LINE_VIS_* et resultats
-- =============================================================================
--  Ce fichier regroupe TOUTES les mesures faites sur les procedures de
--  lineage (LINE_VIS_Lineage, LINE_VIS_Impact, LINE_VIS_Chemin,
--  LINE_VIS_LineageTables) et sur le chargement de LINE_VIS_EDG, avec les
--  resultats obtenus le 2026-10-15, en commentaire a cote de chaque mesure.
--
--  Environnement des resultats :
--    SQL Server 2022 Express (16.0.1000.6), instance .\SQLEXPRESS01
--    Base RestitutionGrapheProd : 7 200 000 lignes dans LINE_VIS_EDG,
--    210 000 dans LINE_VIS_HEA (donnees generees par LINE_VIS_EDG_data.sql
--    et LINE_VIS_HEA_data.sql).
--
--  Lancer (lecture seule sur RestitutionGrapheProd, ~20 s) :
--    sqlcmd -S .\SQLEXPRESS01 -E -C -I -i tests\experiences_LINE_VIS.sql
--  -I obligatoire (QUOTED_IDENTIFIER ON, index sur la colonne calculee).
--
--  Sommaire :
--    Experience 1 : tests unitaires (resultats ; lances par run_tests.sh)
--    Experience 2 : place disque et journal
--    Experience 3 : temps de reponse des procedures sur 7,2 M lignes
--    Experience 4 : chargement de LINE_VIS_EDG par lots (journal)
--
--  Limite des donnees de test (a garder en tete pour lire les temps) :
--  dans les 7,2 M lignes generees, un voisin (EDG_1..4) n'est jamais
--  lui-meme le point de depart d'une autre ligne -> le parcours s'arrete au
--  niveau 1 ; et toutes les lignes ont la meme table (DTA_2 = 'ZJ').
--  Sur de vraies donnees a plusieurs niveaux, les temps augmentent avec le
--  nombre de noeuds parcourus (bornes par @p_profondeur et @p_maxnoeuds).
-- =============================================================================

USE RestitutionGrapheProd;
GO

SET NOCOUNT ON;
GO

/* =============================================================================
   EXPERIENCE 1 : TESTS UNITAIRES
   =============================================================================
   Les tests unitaires ne se lancent pas depuis ce fichier : ils ont besoin
   d'une base jetable (creee, remplie avec de petits graphes connus, puis
   supprimee). Commande :

       SERVER='.\SQLEXPRESS01' bash tests/run_tests.sh

   Resultats (2026-10-15) : TOUS LES TESTS PASSENT, 86 verifications,
   15,5 s au total dont 4,0 s de deploiement.

     Fichier de test                                    Verif.  Duree
     ------------------------------------------------   ------  -----
     test_LINE_VIS_Chemin.sql                           12 PASS  2,4 s
     test_LINE_VIS_GetNodesSuccessorsPredecessors.sql   18 PASS  2,0 s
     test_LINE_VIS_NodesList.sql                        18 PASS  1,9 s
     test_LINE_VIS_Lineage.sql                          15 PASS  1,6 s
     test_LINE_VIS_LineageTables.sql                     9 PASS  1,2 s
     test_LINE_VIS_Impact.sql                            9 PASS  1,1 s
     test_LINE_VIS_NodeById.sql                          5 PASS  1,1 s

   Ce que les tests verifient :
     - parcours multi-niveaux, aval / amont / deux sens ;
     - cycles : pas de boucle infinie, le lien qui ferme le cycle est renvoye ;
     - casse, espaces de fin, coordonnee NULL ;
     - liens d'un programme absent de LINE_VIS_HEA ignores ;
     - limites @p_profondeur / @p_maxnoeuds respectees, signalees par TRONQUE ;
     - Chemin : tous les plus courts chemins, detour ecarte, arret des que B
       est atteint ;
     - Impact : comptes de tables, programmes, executions, derniere date ;
     - LineageTables : pas de faux lien table -> table via une autre colonne ;
     - noeud / table inconnus, parametres invalides (erreurs 50001 a 50003) ;
     - non-regression des anciennes procedures (NodesList, NodeById,
       GetNodesSuccessorsPredecessors).
   ========================================================================== */

/* =============================================================================
   EXPERIENCE 2 : PLACE DISQUE ET JOURNAL
   ========================================================================== */
PRINT '=== EXPERIENCE 2 : place disque et journal ===';

-- 2a. Fichiers de la base : taille sur disque et place reellement utilisee
SELECT
    name,
    type_desc,
    size / 128                          AS taille_Mo,
    FILEPROPERTY(name, 'SpaceUsed') / 128 AS utilise_Mo
FROM sys.database_files;
/* Resultat (2026-10-15) :
     name                       type_desc  taille_Mo  utilise_Mo
     RestitutionGrapheProd      ROWS            4680        3621
     RestitutionGrapheProd_log  LOG             7112          27
   -> La limite de 10 Go de SQL Server Express porte sur les DONNEES
      seulement : 3,6 Go utilises, ~6,5 Go de marge.
   -> Le journal (7,1 Go) est presque vide (0,4 %) : il avait grossi lors
      de l'ancien chargement des 7 M lignes en une seule transaction
      (voir experience 4). */

-- 2b. Mode de recuperation et ce qui empeche de reutiliser le journal
SELECT recovery_model_desc, log_reuse_wait_desc
FROM sys.databases
WHERE name = DB_NAME();
/* Resultat : SIMPLE / NOTHING
   -> le journal est reutilise des qu'une transaction est validee. */

-- 2c. Taille de chaque table
SELECT t.name, SUM(a.total_pages) / 128 AS reserve_Mo
FROM sys.tables t
INNER JOIN sys.partitions p        ON p.object_id = t.object_id
INNER JOIN sys.allocation_units a  ON a.container_id = p.partition_id
GROUP BY t.name
ORDER BY reserve_Mo DESC;
/* Resultat :
     LINE_VIS_EDG          3584 Mo
     LINE_VIS_HEA            30 Mo
     LINE_VIS_EDG_2_STG       0 Mo   (table de staging vide, restee dans la
                                     base apres le commit 59d29db)
     LINE_VIS_EDG_Stats       0 Mo */

-- 2d. Taille de chaque index de LINE_VIS_EDG
SELECT i.name, SUM(a.total_pages) / 128 AS Mo
FROM sys.indexes i
INNER JOIN sys.partitions p        ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN sys.allocation_units a  ON a.container_id = p.partition_id
WHERE i.object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG')
GROUP BY i.name;
/* Resultat :
     PK_LINE_VIS_EDG             2466 Mo   (la table elle-meme)
     IX_LINE_VIS_EDG_DIR_HASH    1118 Mo
   -> un index supplementaire sur DTA_2 (pour accelerer LineageTables)
      couterait du meme ordre : ~1,1 Go. Non cree. */

-- 2e. Occupation du journal de chaque base
DBCC SQLPERF(LOGSPACE);
/* Resultat pour RestitutionGrapheProd : 7112 Mo, 0,39 % utilise. */
GO

/* =============================================================================
   EXPERIENCE 3 : TEMPS DE REPONSE DES PROCEDURES (7,2 M lignes)
   =============================================================================
   Chaque cas est appele 6 fois (3 fois pour LineageTables, qui lit toute la
   table). Le 1er appel est compte a part : SQL Server y prepare le plan
   d'execution et charge les pages en memoire. Le resultat est capture par
   INSERT ... EXEC (@p_sortie = un seul jeu de resultats).
   ========================================================================== */
PRINT '=== EXPERIENCE 3 : temps de reponse des procedures ===';

-- Noeuds reels pris dans la table : A (une arete 'O' avec un voisin), B
-- (une autre), et la table de A pour LineageTables.
DECLARE @a1 VARCHAR(200), @a2 VARCHAR(500), @b1 VARCHAR(200), @b2 VARCHAR(500);
DECLARE @t2 VARCHAR(1000), @t3 VARCHAR(8000), @t4 VARCHAR(1000);

SELECT TOP (1) @a1 = LNA_UID, @a2 = LIN_UID, @t2 = DTA_2, @t3 = DTA_3, @t4 = DTA_4
FROM dbo.LINE_VIS_EDG WHERE EDG_DIR = 'O' AND EDG_1 IS NOT NULL;

SELECT TOP (1) @b1 = LNA_UID, @b2 = LIN_UID
FROM dbo.LINE_VIS_EDG WHERE EDG_DIR = 'O' AND EDG_1 IS NOT NULL ORDER BY LNA_UID DESC;

-- Mesures, et tables de reception des resultats (une par procedure)
DECLARE @mes TABLE (CAS VARCHAR(60), RUN INT, MS INT);
DECLARE @nod TABLE (NOD_ID INT, NIVEAU INT, SENS CHAR(1), DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000),
                    DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000), NOM_NOEUD VARCHAR(MAX), EXPLORE BIT, TRONQUE BIT);
DECLARE @imp TABLE (NOEUD_TROUVE BIT, NB_NOEUDS INT, NB_TABLES INT, NB_SCHEMAS INT, NB_ENVIRONNEMENTS INT,
                    NB_APPLICATIONS INT, NB_PROGRAMMES INT, NB_EXECUTIONS INT, PROFONDEUR INT, TRONQUE BIT);
DECLARE @che TABLE (SRC_TROUVE BIT, DST_TROUVE BIT, CHEMIN_TROUVE BIT, LONGUEUR INT, NB_CHEMINS BIGINT,
                    NB_NOEUDS_PARCOURUS INT, TRONQUE BIT);
DECLARE @tab TABLE (TAB_ID INT, NIVEAU INT, SENS CHAR(1), DTA_4 VARCHAR(1000), DTA_3 VARCHAR(8000),
                    DTA_2 VARCHAR(1000), NOM_TABLE VARCHAR(MAX), NB_COLONNES INT, TRONQUE BIT);

DECLARE @r INT = 1, @t DATETIME2, @runs INT = 6;

WHILE @r <= @runs
BEGIN
    DELETE FROM @nod; SET @t = SYSDATETIME();
    INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage @a1, @a2, 'O', @p_sens = 'O', @p_profondeur = 10, @p_sortie = 'N';
    INSERT INTO @mes VALUES ('Lineage aval', @r, DATEDIFF(ms, @t, SYSDATETIME()));

    DELETE FROM @nod; SET @t = SYSDATETIME();
    INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage @a1, @a2, 'O', @p_sens = 'B', @p_profondeur = 10, @p_sortie = 'N';
    INSERT INTO @mes VALUES ('Lineage deux sens', @r, DATEDIFF(ms, @t, SYSDATETIME()));

    DELETE FROM @imp; SET @t = SYSDATETIME();
    INSERT INTO @imp EXEC dbo.LINE_VIS_Impact @a1, @a2, 'O', @p_sortie = 'R';
    INSERT INTO @mes VALUES ('Impact (resume)', @r, DATEDIFF(ms, @t, SYSDATETIME()));

    DELETE FROM @che; SET @t = SYSDATETIME();
    INSERT INTO @che EXEC dbo.LINE_VIS_Chemin @a1, @a2, 'O', @b1, @b2, 'O', @p_sortie = 'R';
    INSERT INTO @mes VALUES ('Chemin A -> B', @r, DATEDIFF(ms, @t, SYSDATETIME()));

    IF @r <= 3
    BEGIN
        DELETE FROM @tab; SET @t = SYSDATETIME();
        INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables @t2, @t3, @t4, @p_sortie = 'N';
        INSERT INTO @mes VALUES ('LineageTables (table+schema+env)', @r, DATEDIFF(ms, @t, SYSDATETIME()));
    END

    SET @r += 1;
END

SELECT
    CAS,
    MAX(CASE WHEN RUN = 1 THEN MS END) AS PREMIER_MS,
    MIN(CASE WHEN RUN > 1 THEN MS END) AS MIN_MS,
    AVG(CASE WHEN RUN > 1 THEN MS END) AS MOYEN_MS,
    MAX(CASE WHEN RUN > 1 THEN MS END) AS MAX_MS,
    COUNT(*)                           AS NB_APPELS
FROM @mes
GROUP BY CAS
ORDER BY MOYEN_MS;
/* Resultat (2026-10-15) :
     CAS                               PREMIER_MS  MIN_MS  MOYEN_MS  MAX_MS  NB_APPELS
     Lineage deux sens                          3       0         6      19          6
     Lineage aval                             114      26        44      54          6
     Chemin A -> B                            101      52        61      68          6
     Impact (resume)                           80      38        64      89          6
     LineageTables (table+schema+env)        6266    5070      5073    5076          3

   Lecture :
     - Lineage, Impact, Chemin : < 0,1 s. Chaque niveau est une recherche
       dans l'index IX_LINE_VIS_EDG_DIR_HASH (EDG_DIR, DTA_HASH).
     - LineageTables : ~5 s, presque tout pour trouver les colonnes de la
       table de depart (lecture de toute LINE_VIS_EDG : aucun index par
       table). Un index sur DTA_2 (~1,1 Go) la ferait passer sous la seconde.
     - Dans ce jeu, "Chemin A -> B" ne trouve pas de chemin (donnees de test
       a un seul niveau) : c'est le temps d'une recherche qui echoue.

   Historique des mesures pendant le developpement :
     - LINE_VIS_Lineage, 1re version (jointure avec OR, sans FORCESEEK) :
       20 a 55 s par appel (SQL Server lisait les 7 M lignes).
       Apres la table #frontiere + FORCESEEK : ~10 ms.
     - Apres extraction du parcours dans LINE_VIS_Lineage_Parcours (procedure
       interne partagee) : 30 a 50 ms (plan recompile a chaque appel, a
       cause des tables #temporaires de l'appelant).
     - LINE_VIS_LineageTables : 8 a 14 s au 1er essai (table+schema+env),
       ~5 s ici ; 70 a 90 s avec la table seule (DTA_2 = 'ZJ' sur toutes
       les lignes -> 5 000 colonnes de depart, limite atteinte, TRONQUE = 1).
   ========================================================================== */
GO

/* =============================================================================
   EXPERIENCE 4 : CHARGEMENT DE LINE_VIS_EDG PAR LOTS (TAILLE DU JOURNAL)
   =============================================================================
   But : verifier que LINE_VIS_EDG_data.sql (70 lots de 100 000 lignes,
   CHECKPOINT apres chaque lot, index de hash desactive puis reconstruit)
   ne fait plus grossir le journal.

   L'experience se fait sur une base JETABLE (le script de chargement vide
   la table) : RestitutionGrapheProd_LogTest, en mode SIMPLE. Commandes
   (bash, depuis Sql-procedure-table/ ; les scripts visent
   RestitutionGrapheProd, sed change le nom de la base) :

     sqlcmd -S .\SQLEXPRESS01 -E -C -b -Q "CREATE DATABASE RestitutionGrapheProd_LogTest;
                                           ALTER DATABASE RestitutionGrapheProd_LogTest SET RECOVERY SIMPLE;"
     for f in LINE_VIS_EDG.sql LINE_VIS_EDG_IndexHash.sql LINE_VIS_EDG_data.sql; do
         sed "s/RestitutionGrapheProd\b/RestitutionGrapheProd_LogTest/g" $f > /tmp/$f
     done
     cd /tmp
     sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_EDG.sql -i LINE_VIS_EDG_IndexHash.sql
     sqlcmd -S .\SQLEXPRESS01 -E -C -b -I -i LINE_VIS_EDG_data.sql

   Pour un essai plus court, remplacer aussi "@TotalRows INT = 7000000".
   Place disque necessaire pour 7 M lignes : ~3,5 Go + 200 Mo de journal.
   Supprimer la base a la fin :
     DROP DATABASE RestitutionGrapheProd_LogTest;

   Les requetes ci-dessous lisent l'etat de la base jetable : pendant le
   chargement (avancement) ou apres (bilan). Sans base jetable, rien n'est fait.
   ========================================================================== */
PRINT '=== EXPERIENCE 4 : chargement par lots (base jetable) ===';

IF DB_ID(N'RestitutionGrapheProd_LogTest') IS NULL
    PRINT 'Base RestitutionGrapheProd_LogTest absente : experience 4 non lancee (voir commandes ci-dessus).';
ELSE
BEGIN
    -- 4a. Lignes deja inserees (lot en cours compris) : lecture des
    --     metadonnees, sans attendre la fin du lot en cours
    SELECT SUM(p.rows) AS lignes_inserees
    FROM RestitutionGrapheProd_LogTest.sys.partitions p
    WHERE p.object_id = OBJECT_ID(N'RestitutionGrapheProd_LogTest.dbo.LINE_VIS_EDG')
      AND p.index_id = 1;

    -- 4b. Taille des fichiers de la base jetable (le journal doit rester plat)
    SELECT name, type_desc, size / 128 AS taille_Mo
    FROM RestitutionGrapheProd_LogTest.sys.database_files;

    -- 4c. Etat de l'index de hash (is_disabled = 1 tant que le chargement
    --     n'est pas fini)
    SELECT name, is_disabled
    FROM RestitutionGrapheProd_LogTest.sys.indexes
    WHERE object_id = OBJECT_ID(N'RestitutionGrapheProd_LogTest.dbo.LINE_VIS_EDG');
END
/* Resultats (2026-10-15) :

   Taille du journal a la fin du chargement :
     Lignes chargees                               Journal     Duree du script
     1 000 000                                      136 Mo       23 s
     2 000 000                                      200 Mo      ~2 min
     7 000 000                                      200 Mo      697 s (11 min 37 s)
     7 000 000, ANCIENNE version (1 transaction)   7 112 Mo    (non mesuree)
   Bilan final du chargement de 7 M lignes (requetes 4a a 4c) :
     lignes_inserees = 7 000 000
     donnees  : 3 336 Mo (3 282 Mo utilises)
     journal  :   200 Mo (25 Mo utilises)
     PK_LINE_VIS_EDG et IX_LINE_VIS_EDG_DIR_HASH : is_disabled = 0
     (l'index de hash a bien ete reconstruit)

   -> Le journal plafonne a ~200 Mo : il ne depend plus que de la taille
      d'un lot, plus du nombre total de lignes. Il est reste a 200 Mo de
      2 M a 7 M lignes (releve en cours de chargement a 5,8 M : 200 Mo).

   Avancement du chargement de 7 M lignes (message tous les 10 lots) :
     Lots   Lignes      Temps cumule   Temps des 10 lots
      10    1 000 000        16 s           16 s
      20    2 000 000        59 s           43 s
      30    3 000 000       100 s           41 s
      40    4 000 000       135 s           35 s
      50    5 000 000       263 s          128 s
      60    6 000 000       449 s          186 s
      70    7 000 000       631 s          182 s
     + reconstruction de IX_LINE_VIS_EDG_DIR_HASH : ~66 s
     = 697 s au total.
   -> Le chargement ralentit nettement apres ~4 M lignes (35 s -> ~180 s
      par million). Explication probable : SQL Server Express limite sa
      memoire de cache a ~1,4 Go ; au-dela, la table ne tient plus en
      memoire, et comme les LIN_UID ne sont pas inseres dans l'ordre de la
      cle primaire, chaque lot doit relire des pages sur disque.
   -> Estimation pour un rechargement complet de 7 M lignes : 10 a 12 min.
   ========================================================================== */
GO
