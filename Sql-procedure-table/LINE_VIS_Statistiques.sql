-- =============================================================================
--  Procedure dbo.LINE_VIS_Statistiques
--  Base : RestitutionGrapheProd (ou toute base ayant LINE_VIS_EDG / LINE_VIS_HEA)
--
--  But : statistiques globales du graphe de lineage.
--    - combien de colonnes, tables, liens, applications, programmes ;
--    - les SOURCES (rien en amont) et les SORTIES (rien en aval) ;
--    - les noeuds PIVOTS : colonnes et tables par lesquelles passe le plus
--      de lineage (une modification a cet endroit touche beaucoup de choses) ;
--    - les FLUX ENTRE APPLICATIONS : l'application A ecrit une table que
--      l'application B lit ;
--    - les FLUX ENTRE ENVIRONNEMENTS (ex. DEV -> PROD : anomalie de conformite) ;
--    - les CYCLES entre tables (des donnees qui reviennent a leur point de depart).
--
--  Regles (les memes que les procedures de lineage) :
--    - seules les lignes dont le LNA_UID a un en-tete (LINE_VIS_HEA) et dont
--      le voisin EDG_1..EDG_4 n'est pas vide sont comptees ;
--    - un lien est ramene au SENS DU FLUX : 'O' = noeud -> voisin,
--      'I' = voisin -> noeud ; un lien stocke des deux cotes ne compte
--      qu'une fois ;
--    - colonne = DTA_1..DTA_4 ; table = (DTA_2, DTA_3, DTA_4) ;
--      application = RON_APP de l'en-tete du programme qui porte le lien ;
--    - noeuds identifies par des empreintes CHECKSUM (comme
--      LINE_VIS_ControleQualite) : 2 noeuds differents peuvent, tres
--      rarement, etre confondus ; les comptes sont exacts a ~0,2 % pres.
--
--  Methode : UNE lecture de LINE_VIS_EDG vers tempdb (empreintes), puis
--  calculs sur ces entiers ; une 2e lecture, partielle, retrouve les noms
--  des seules tables a afficher. Rien n'est ecrit dans la base.
--  Les calculs au niveau TABLE (pivots, profondeur, cycles, flux entre
--  applications) sont sautes au
--  dela de @p_max_tables tables distinctes : c'est le cas des donnees
--  generees de RestitutionGrapheProd, ou DTA_3 est aleatoire (chaque ligne
--  y est une "table" differente).
--
--  Parametres :
--    @p_top        : nombre de colonnes / tables pivots renvoyees (defaut 20).
--    @p_max_tables : au-dela, pas de calculs au niveau table (defaut 100 000).
--    @p_sortie     : 'TOUT' (defaut) ou un seul jeu : 'RESUME', 'COLONNES',
--                    'TABLES', 'APPLIS', 'ENV', 'CYCLES' (pour INSERT ... EXEC).
--
--  Resultats :
--    1. RESUME     : ORDRE, INDICATEUR, VALEUR, COMMENTAIRE.
--    2. COLONNES   : colonnes pivots : DTA_1..DTA_4, NB_AMONT (colonnes qui
--                    l'alimentent), NB_AVAL (colonnes qu'elle alimente),
--                    NB_LIENS (= NB_AMONT + NB_AVAL), TYPE (SOURCE / SORTIE /
--                    INTERMEDIAIRE).
--    3. TABLES     : tables pivots : DTA_4, DTA_3, DTA_2, NB_TABLES_AMONT,
--                    NB_TABLES_AVAL, NB_COLONNES, NIVEAU (distance la plus
--                    courte depuis une table source ; NULL si seulement
--                    atteignable par un cycle), TYPE.
--    4. APPLIS     : APP_SOURCE (ecrit la table), APP_CIBLE (la lit),
--                    NB_TABLES (tables partagees), NB_LIENS (liens colonne
--                    lus par APP_CIBLE dans ces tables).
--    5. ENV        : ENV_SOURCE, ENV_CIBLE, NB_LIENS, STATUT ('OK' meme
--                    environnement, 'A_VERIFIER' environnements differents,
--                    'ANOMALIE' d'un environnement non PROD vers PROD).
--    6. CYCLES     : DTA_4, DTA_3, DTA_2 des tables prises dans un cycle,
--                    TAILLE_CYCLE (nombre de tables du cycle).
--
--  Dependances : dbo.LINE_VIS_EDG (colonne DTA_HASH, index
--                IX_LINE_VIS_EDG_DIR_HASH pour les noms des colonnes),
--                dbo.LINE_VIS_HEA
-- =============================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_Statistiques]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_Statistiques
GO

CREATE PROCEDURE [dbo].LINE_VIS_Statistiques
    @p_top        INT         = 20,
    @p_max_tables INT         = 100000,
    @p_sortie     VARCHAR(10) = 'TOUT'

AS
BEGIN
    SET NOCOUNT ON

    IF @p_sortie IS NULL OR @p_sortie NOT IN ('TOUT', 'RESUME', 'COLONNES', 'TABLES', 'APPLIS', 'ENV', 'CYCLES')
        THROW 50002, 'LINE_VIS_Statistiques : @p_sortie doit valoir TOUT, RESUME, COLONNES, TABLES, APPLIS, ENV ou CYCLES.', 1;

    SET @p_top        = COALESCE(@p_top, 20)
    SET @p_max_tables = COALESCE(@p_max_tables, 100000)

    /* 1. Lecture unique : chaque ligne valide, ramenee au sens du flux.
          H_SRC / H_DST = empreintes des colonnes source / destination,
          T_SRC / T_DST = empreintes de leurs tables. */
    CREATE TABLE #l (
        H_SRC   INT NOT NULL,
        H_DST   INT NOT NULL,
        T_SRC   INT NOT NULL,
        T_DST   INT NOT NULL,
        ENV_SRC VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        ENV_DST VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        RON_APP VARCHAR(4)    COLLATE DATABASE_DEFAULT NULL,
        PGM     VARCHAR(500)  COLLATE DATABASE_DEFAULT NULL
    )

    INSERT INTO #l WITH (TABLOCK) (H_SRC, H_DST, T_SRC, T_DST, ENV_SRC, ENV_DST, RON_APP, PGM)
    SELECT
        CASE WHEN e.EDG_DIR = 'O' THEN e.DTA_HASH ELSE CHECKSUM(e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4) END,
        CASE WHEN e.EDG_DIR = 'O' THEN CHECKSUM(e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4) ELSE e.DTA_HASH END,
        CASE WHEN e.EDG_DIR = 'O' THEN CHECKSUM(e.DTA_2, e.DTA_3, e.DTA_4) ELSE CHECKSUM(e.EDG_2, e.EDG_3, e.EDG_4) END,
        CASE WHEN e.EDG_DIR = 'O' THEN CHECKSUM(e.EDG_2, e.EDG_3, e.EDG_4) ELSE CHECKSUM(e.DTA_2, e.DTA_3, e.DTA_4) END,
        CASE WHEN e.EDG_DIR = 'O' THEN e.DTA_4 ELSE e.EDG_4 END,
        CASE WHEN e.EDG_DIR = 'O' THEN e.EDG_4 ELSE e.DTA_4 END,
        h.RON_APP,
        h.EXE_PGM_NME
    FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
    INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = e.LNA_UID
    WHERE NOT (COALESCE(e.EDG_1, '') = '' AND COALESCE(e.EDG_2, '') = ''
           AND COALESCE(e.EDG_3, '') = '' AND COALESCE(e.EDG_4, '') = '')

    DECLARE @lignesValides BIGINT = (SELECT COUNT_BIG(*) FROM #l)
    DECLARE @lignesTotal   BIGINT = (SELECT COUNT_BIG(*) FROM dbo.LINE_VIS_EDG WITH (NOLOCK))

    /* 2. Liens colonne -> colonne distincts */
    CREATE TABLE #lc (
        H_SRC   INT NOT NULL,
        H_DST   INT NOT NULL,
        T_SRC   INT NOT NULL,
        T_DST   INT NOT NULL,
        ENV_SRC VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        ENV_DST VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        PRIMARY KEY (H_SRC, H_DST)
    )
    INSERT INTO #lc
    SELECT H_SRC, H_DST, MIN(T_SRC), MIN(T_DST), MIN(ENV_SRC), MIN(ENV_DST)
    FROM #l
    GROUP BY H_SRC, H_DST

    -- Colonnes : nombre de colonnes en amont / en aval
    CREATE TABLE #nc (
        H        INT NOT NULL PRIMARY KEY,
        T        INT NOT NULL,
        NB_AMONT INT NOT NULL,
        NB_AVAL  INT NOT NULL
    )
    INSERT INTO #nc
    SELECT x.H, MIN(x.T), SUM(x.AMONT), SUM(x.AVAL)
    FROM (
        SELECT H_SRC AS H, T_SRC AS T, 0 AS AMONT, 1 AS AVAL FROM #lc
        UNION ALL
        SELECT H_DST, T_DST, 1, 0 FROM #lc
    ) x
    GROUP BY x.H

    /* 3. Niveau TABLE (si le nombre de tables le permet) */
    DECLARE @nbTables BIGINT = (SELECT COUNT_BIG(DISTINCT T) FROM #nc)
    DECLARE @calculTables BIT = CASE WHEN @nbTables <= @p_max_tables THEN 1 ELSE 0 END

    CREATE TABLE #lt (T_SRC INT NOT NULL, T_DST INT NOT NULL, NB_LIENS INT NOT NULL, PRIMARY KEY (T_SRC, T_DST))
    CREATE TABLE #nt (
        T               INT NOT NULL PRIMARY KEY,
        NB_TABLES_AMONT INT NOT NULL,
        NB_TABLES_AVAL  INT NOT NULL,
        NB_COLONNES     INT NOT NULL,
        NIVEAU          INT NULL
    )
    CREATE TABLE #acces (T_DE INT NOT NULL, T_A INT NOT NULL, PRIMARY KEY (T_DE, T_A))
    CREATE TABLE #cycle (T INT NOT NULL PRIMARY KEY, TAILLE INT NOT NULL)

    DECLARE @profondeur INT, @iter INT, @ajouts INT

    IF @calculTables = 1
    BEGIN
        -- Liens table -> table (sans les liens d'une table vers elle-meme)
        INSERT INTO #lt
        SELECT T_SRC, T_DST, COUNT(*) FROM #lc WHERE T_SRC <> T_DST GROUP BY T_SRC, T_DST

        INSERT INTO #nt (T, NB_TABLES_AMONT, NB_TABLES_AVAL, NB_COLONNES)
        SELECT c.T, COALESCE(am.NB, 0), COALESCE(av.NB, 0), c.NB
        FROM (SELECT T, COUNT(*) AS NB FROM #nc GROUP BY T) c
        LEFT JOIN (SELECT T_DST AS T, COUNT(*) AS NB FROM #lt GROUP BY T_DST) am ON am.T = c.T
        LEFT JOIN (SELECT T_SRC AS T, COUNT(*) AS NB FROM #lt GROUP BY T_SRC) av ON av.T = c.T

        -- Niveau : distance la plus courte depuis une table source
        -- (parcours en largeur, un niveau a la fois)
        UPDATE #nt SET NIVEAU = 0 WHERE NB_TABLES_AMONT = 0
        SET @iter = 0
        SET @ajouts = 1
        WHILE @ajouts > 0
        BEGIN
            UPDATE n SET NIVEAU = @iter + 1
            FROM #nt n
            WHERE n.NIVEAU IS NULL
              AND EXISTS (SELECT 1 FROM #lt l INNER JOIN #nt s ON s.T = l.T_SRC
                          WHERE l.T_DST = n.T AND s.NIVEAU = @iter)
            SET @ajouts = @@ROWCOUNT
            SET @iter += 1
        END
        SET @profondeur = (SELECT MAX(NIVEAU) FROM #nt)

        -- Cycles, en 2 temps :
        --  a) on retire, passe apres passe, les tables qui ne peuvent pas
        --     etre dans un cycle (rien en amont ou rien en aval parmi les
        --     tables restantes) ; il ne reste que les cycles et les
        --     tables situees entre deux cycles (en general tres peu) ;
        --  b) sur ce reste seulement : fermeture transitive (qui atteint
        --     qui) ; une table qui s'atteint elle-meme est dans un cycle.
        --  (La fermeture sur tout le graphe pourrait compter des milliards
        --   de couples sur un grand graphe.)
        CREATE TABLE #reste (T INT NOT NULL PRIMARY KEY)
        INSERT INTO #reste SELECT T FROM #nt
        SET @ajouts = 1
        WHILE @ajouts > 0
        BEGIN
            DELETE r FROM #reste r
            WHERE NOT EXISTS (SELECT 1 FROM #lt l INNER JOIN #reste x ON x.T = l.T_SRC WHERE l.T_DST = r.T)
               OR NOT EXISTS (SELECT 1 FROM #lt l INNER JOIN #reste x ON x.T = l.T_DST WHERE l.T_SRC = r.T)
            SET @ajouts = @@ROWCOUNT
        END

        INSERT INTO #acces
        SELECT l.T_SRC, l.T_DST
        FROM #lt l
        WHERE l.T_SRC IN (SELECT T FROM #reste) AND l.T_DST IN (SELECT T FROM #reste)
        SET @ajouts = 1
        WHILE @ajouts > 0
        BEGIN
            INSERT INTO #acces (T_DE, T_A)
            SELECT DISTINCT a.T_DE, l.T_DST
            FROM #acces a
            INNER JOIN #lt l ON l.T_SRC = a.T_A
            WHERE l.T_DST IN (SELECT T FROM #reste)
              AND NOT EXISTS (SELECT 1 FROM #acces x WHERE x.T_DE = a.T_DE AND x.T_A = l.T_DST)
            SET @ajouts = @@ROWCOUNT
        END

        -- Taille du cycle = tables qui atteignent T et que T atteint (T compris)
        INSERT INTO #cycle
        SELECT a.T_DE, COUNT(*)
        FROM #acces a
        INNER JOIN #acces b ON b.T_DE = a.T_A AND b.T_A = a.T_DE
        WHERE EXISTS (SELECT 1 FROM #acces s WHERE s.T_DE = a.T_DE AND s.T_A = a.T_DE)
        GROUP BY a.T_DE
    END

    /* 4. Flux entre applications : A ecrit T (T destination d'un lien de A),
          B lit T (T source d'un lien de B), A <> B. Calcul par table : saute
          lui aussi au-dela de @p_max_tables tables (sur 7,2 M "tables",
          la jointure remplissait tempdb : arretee apres 146 s et 1,5 Go). */
    CREATE TABLE #applis (APP_SOURCE VARCHAR(4) COLLATE DATABASE_DEFAULT, APP_CIBLE VARCHAR(4) COLLATE DATABASE_DEFAULT,
                          NB_TABLES INT, NB_LIENS INT)
    IF @calculTables = 1
    INSERT INTO #applis
    SELECT w.RON_APP, r.RON_APP, COUNT(DISTINCT w.T), SUM(r.NB)
    FROM (SELECT DISTINCT T_DST AS T, RON_APP FROM #l) w
    INNER JOIN (SELECT T_SRC AS T, RON_APP, COUNT(DISTINCT CONCAT(H_SRC, '>', H_DST)) AS NB
                FROM #l GROUP BY T_SRC, RON_APP) r
            ON r.T = w.T AND r.RON_APP <> w.RON_APP
    GROUP BY w.RON_APP, r.RON_APP

    /* 5. Noms des tables a afficher (pivots + cycles) : 2e lecture partielle */
    CREATE TABLE #besoin (T INT NOT NULL PRIMARY KEY)
    IF @calculTables = 1
        INSERT INTO #besoin
        SELECT T FROM (SELECT TOP (@p_top) T FROM #nt
                       ORDER BY NB_TABLES_AMONT + NB_TABLES_AVAL DESC, NB_COLONNES DESC, T) x
        UNION
        SELECT T FROM #cycle

    CREATE TABLE #tnom (
        T     INT NOT NULL PRIMARY KEY,
        DTA_2 VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_3 VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        DTA_4 VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
    )
    IF EXISTS (SELECT 1 FROM #besoin)
        INSERT INTO #tnom
        SELECT x.T, MIN(x.D2), MIN(x.D3), MIN(x.D4)
        FROM (
            SELECT CHECKSUM(e.DTA_2, e.DTA_3, e.DTA_4) AS T, e.DTA_2 AS D2, e.DTA_3 AS D3, e.DTA_4 AS D4
            FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
            UNION ALL
            SELECT CHECKSUM(e.EDG_2, e.EDG_3, e.EDG_4), e.EDG_2, e.EDG_3, e.EDG_4
            FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        ) x
        WHERE x.T IN (SELECT T FROM #besoin)
        GROUP BY x.T

    /* 6. Colonnes pivots et leurs noms (recherche par l'index de hash) */
    CREATE TABLE #cpiv (
        RANG     INT NOT NULL PRIMARY KEY,
        H        INT NOT NULL,
        NB_AMONT INT NOT NULL,
        NB_AVAL  INT NOT NULL
    )
    INSERT INTO #cpiv
    SELECT TOP (@p_top)
        ROW_NUMBER() OVER (ORDER BY NB_AMONT + NB_AVAL DESC, NB_AVAL DESC, H), H, NB_AMONT, NB_AVAL
    FROM #nc
    ORDER BY NB_AMONT + NB_AVAL DESC, NB_AVAL DESC, H

    /* 7. Resultats */
    IF @p_sortie IN ('TOUT', 'RESUME')
    BEGIN
        DECLARE @res TABLE (ORDRE INT, INDICATEUR VARCHAR(60), VALEUR BIGINT, COMMENTAIRE VARCHAR(300))
        INSERT INTO @res VALUES
            (1,  'Lignes LINE_VIS_EDG', @lignesTotal, NULL),
            (2,  'Lignes comptees', @lignesValides, 'avec en-tete et voisin renseigne'),
            (3,  'Colonnes', (SELECT COUNT_BIG(*) FROM #nc), NULL),
            (4,  'Colonnes sources', (SELECT COUNT_BIG(*) FROM #nc WHERE NB_AMONT = 0), 'rien en amont'),
            (5,  'Colonnes de sortie', (SELECT COUNT_BIG(*) FROM #nc WHERE NB_AVAL = 0), 'rien en aval'),
            (6,  'Liens colonne -> colonne', (SELECT COUNT_BIG(*) FROM #lc), 'distincts, sens du flux'),
            (7,  'Tables', @nbTables, NULL),
            (8,  'Tables sources', CASE WHEN @calculTables = 1 THEN (SELECT COUNT_BIG(*) FROM #nt WHERE NB_TABLES_AMONT = 0) END,
                 CASE WHEN @calculTables = 0 THEN 'non calcule : plus de @p_max_tables tables' END),
            (9,  'Tables de sortie', CASE WHEN @calculTables = 1 THEN (SELECT COUNT_BIG(*) FROM #nt WHERE NB_TABLES_AVAL = 0) END,
                 CASE WHEN @calculTables = 0 THEN 'non calcule : plus de @p_max_tables tables' END),
            (10, 'Liens table -> table', CASE WHEN @calculTables = 1 THEN (SELECT COUNT_BIG(*) FROM #lt) END,
                 CASE WHEN @calculTables = 0 THEN 'non calcule : plus de @p_max_tables tables' END),
            (11, 'Profondeur (tables)', @profondeur, 'plus grand NIVEAU : nombre de liens table -> table entre une table source et la table la plus eloignee (par le plus court chemin)'),
            (12, 'Tables dans un cycle', CASE WHEN @calculTables = 1 THEN (SELECT COUNT_BIG(*) FROM #cycle) END, NULL),
            (13, 'Applications', (SELECT COUNT_BIG(DISTINCT RON_APP) FROM #l), 'RON_APP des programmes'),
            (14, 'Programmes', (SELECT COUNT_BIG(DISTINCT PGM) FROM #l), 'EXE_PGM_NME distincts'),
            (15, 'Flux entre applications', CASE WHEN @calculTables = 1 THEN (SELECT COUNT_BIG(*) FROM #applis) END,
                 CASE WHEN @calculTables = 1 THEN 'couples (application qui ecrit, application qui lit)'
                      ELSE 'non calcule : plus de @p_max_tables tables' END),
            (16, 'Liens entre environnements', (SELECT COUNT_BIG(*) FROM #lc WHERE COALESCE(ENV_SRC, '') <> COALESCE(ENV_DST, '')), NULL),
            (17, 'Liens non PROD -> PROD', (SELECT COUNT_BIG(*) FROM #lc WHERE ENV_DST = 'PROD' AND COALESCE(ENV_SRC, '') <> 'PROD'), 'anomalie de conformite');

        SELECT ORDRE, INDICATEUR, VALEUR, COMMENTAIRE FROM @res ORDER BY ORDRE
    END

    IF @p_sortie IN ('TOUT', 'COLONNES')
        SELECT
            p.RANG,
            e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4,
            p.NB_AMONT,
            p.NB_AVAL,
            p.NB_AMONT + p.NB_AVAL AS NB_LIENS,
            CASE WHEN p.NB_AMONT = 0 THEN 'SOURCE' WHEN p.NB_AVAL = 0 THEN 'SORTIE' ELSE 'INTERMEDIAIRE' END AS TYPE
        FROM #cpiv p
        -- nom de la colonne : une ligne dont elle est le noeud (index de hash)
        OUTER APPLY (SELECT TOP (1) x.DTA_1, x.DTA_2, x.DTA_3, x.DTA_4
                     FROM dbo.LINE_VIS_EDG x WITH (NOLOCK)
                     WHERE x.EDG_DIR IN ('O', 'I') AND x.DTA_HASH = p.H) e
        ORDER BY p.RANG

    IF @p_sortie IN ('TOUT', 'TABLES')
        SELECT TOP (@p_top)
            tn.DTA_4, tn.DTA_3, tn.DTA_2,
            n.NB_TABLES_AMONT,
            n.NB_TABLES_AVAL,
            n.NB_COLONNES,
            n.NIVEAU,
            CASE WHEN n.NB_TABLES_AMONT = 0 THEN 'SOURCE' WHEN n.NB_TABLES_AVAL = 0 THEN 'SORTIE' ELSE 'INTERMEDIAIRE' END AS TYPE
        FROM #nt n
        LEFT JOIN #tnom tn ON tn.T = n.T
        ORDER BY n.NB_TABLES_AMONT + n.NB_TABLES_AVAL DESC, n.NB_COLONNES DESC, n.T

    IF @p_sortie IN ('TOUT', 'APPLIS')
        SELECT APP_SOURCE, APP_CIBLE, NB_TABLES, NB_LIENS
        FROM #applis
        ORDER BY NB_LIENS DESC, APP_SOURCE, APP_CIBLE

    IF @p_sortie IN ('TOUT', 'ENV')
        SELECT
            ENV_SRC AS ENV_SOURCE,
            ENV_DST AS ENV_CIBLE,
            COUNT_BIG(*) AS NB_LIENS,
            CASE WHEN COALESCE(ENV_SRC, '') = COALESCE(ENV_DST, '')                  THEN 'OK'
                 WHEN ENV_DST = 'PROD' AND COALESCE(ENV_SRC, '') <> 'PROD'           THEN 'ANOMALIE'
                 ELSE 'A_VERIFIER' END AS STATUT
        FROM #lc
        GROUP BY ENV_SRC, ENV_DST
        ORDER BY CASE WHEN ENV_DST = 'PROD' AND COALESCE(ENV_SRC, '') <> 'PROD' THEN 0
                      WHEN COALESCE(ENV_SRC, '') <> COALESCE(ENV_DST, '') THEN 1 ELSE 2 END,
                 NB_LIENS DESC

    IF @p_sortie IN ('TOUT', 'CYCLES')
        SELECT tn.DTA_4, tn.DTA_3, tn.DTA_2, c.TAILLE AS TAILLE_CYCLE
        FROM #cycle c
        LEFT JOIN #tnom tn ON tn.T = c.T
        ORDER BY c.TAILLE DESC, tn.DTA_4, tn.DTA_3, tn.DTA_2
END
GO
