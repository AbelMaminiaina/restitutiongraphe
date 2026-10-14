-- =============================================================================
--  Procedure dbo.LINE_VIS_LineageTables
--  Base : RestitutionGrapheProd
--
--  But : lineage au niveau des TABLES (table -> table), plus lisible que le
--  lineage colonne par colonne quand une table a des centaines de colonnes.
--
--  Signification des coordonnees (comme dans LINE_VIS_NodesList) :
--    DTA_1 = colonne, DTA_2 = table, DTA_3 = schema, DTA_4 = environnement.
--    Une table = (DTA_4, DTA_3, DTA_2).
--
--  Methode :
--    1. colonnes de depart = toutes les colonnes de la (ou des) table(s)
--       demandee(s), lues dans LINE_VIS_EDG. C'est la SEULE etape qui lit
--       toute la table LINE_VIS_EDG : aucun index ne permet de chercher par
--       table (l'index IX_LINE_VIS_EDG_DIR_HASH porte sur l'empreinte des 4
--       coordonnees, colonne comprise) ;
--    2. lineage colonne par colonne depuis toutes ces colonnes a la fois
--       (dbo.LINE_VIS_Lineage_Parcours : recherches dans l'index, rapide) ;
--    3. regroupement des colonnes trouvees par table, et des liens par
--       couple de tables.
--  Partir des colonnes (et non suivre directement les tables) donne un
--  resultat EXACT : si T1 n'alimente que la colonne a de T2, et que seule
--  la colonne b de T2 alimente T3, alors T3 n'est pas en aval de T1.
--  Rien n'est ecrit dans la base (tables #temporaires dans tempdb).
--
--  Parametres :
--    @p_table      : table de depart (DTA_2), obligatoire, egalite exacte
--                    (casse et espaces de fin ignores).
--    @p_schema     : schema (DTA_3) ; NULL = tous les schemas.
--    @p_env        : environnement (DTA_4) ; NULL = tous.
--                    Plusieurs tables correspondent -> toutes sont au depart.
--    @p_sens       : 'O' = aval (defaut), 'I' = amont, 'B' = les deux.
--    @p_profondeur : niveaux maximum, comptes en liens colonne -> colonne
--                    (defaut 5).
--    @p_maxnoeuds  : nombre maximum de COLONNES parcourues, depart compris
--                    (defaut 5000) ; atteint -> TRONQUE = 1.
--    @p_sortie     : 'T' = les 2 jeux de resultats (defaut),
--                    'N' = tables seulement, 'A' = liens seulement
--                    (un seul jeu : pour INSERT ... EXEC).
--
--  Resultats :
--    1. TABLES : TAB_ID, NIVEAU (0 = depart ; sinon distance la plus courte
--       en liens colonne -> colonne), SENS ('-' depart, 'O' aval, 'I' amont,
--       'B' trouvee des 2 cotes), DTA_4, DTA_3, DTA_2, NOM_TABLE
--       ("DTA_4.DTA_3.DTA_2"), NB_COLONNES (colonnes de la table presentes
--       dans le parcours), TRONQUE.
--    2. LIENS : SRC_TAB_ID -> DST_TAB_ID (sens du flux de donnees),
--       NB_COLONNES_LIEES (couples colonne -> colonne), NB_LIENS (lignes de
--       LINE_VIS_EDG), NB_PROGRAMMES (LNA_UID distincts), PROGRAMMES (liste
--       des EXE_PGM_NME, LINE_VIS_HEA). Les liens d'une table vers
--       elle-meme (colonne -> colonne de la meme table) ne sont pas montres.
--
--  Dependances : dbo.LINE_VIS_Lineage_Parcours, dbo.LINE_VIS_EDG,
--                dbo.LINE_VIS_HEA
-- =============================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_LineageTables]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_LineageTables
GO

CREATE PROCEDURE [dbo].LINE_VIS_LineageTables
    @p_table      VARCHAR(1000) = NULL,
    @p_schema     VARCHAR(8000) = NULL,
    @p_env        VARCHAR(1000) = NULL,
    @p_sens       CHAR(1)       = 'O',
    @p_profondeur INT           = 5,
    @p_maxnoeuds  INT           = 5000,
    @p_sortie     CHAR(1)       = 'T'

AS
BEGIN
    SET NOCOUNT ON

    IF @p_table IS NULL OR @p_table = ''
        THROW 50003, 'LINE_VIS_LineageTables : @p_table est obligatoire.', 1;
    IF @p_sortie IS NULL OR @p_sortie NOT IN ('T', 'N', 'A')
        THROW 50002, 'LINE_VIS_LineageTables : @p_sortie doit valoir T (tout), N (tables) ou A (liens).', 1;

    SET @p_profondeur = COALESCE(@p_profondeur, 5)
    SET @p_maxnoeuds  = COALESCE(@p_maxnoeuds, 5000)

    -- Tables remplies par LINE_VIS_Lineage_Parcours (voir son en-tete)
    CREATE TABLE #noeuds (
        NOD_ID   INT IDENTITY(1, 1) PRIMARY KEY,
        NOD_HASH INT NOT NULL,
        DTA_1    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_2    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_3    VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        DTA_4    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        NIVEAU   INT     NOT NULL,
        SENS     CHAR(1) NOT NULL
    )
    CREATE INDEX IX_noeuds_hash ON #noeuds (NOD_HASH)

    CREATE TABLE #liens (
        SRC_ID   INT NOT NULL,
        DST_ID   INT NOT NULL,
        LNA_UID  VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        NB_LIENS INT NOT NULL
    )

    DECLARE @tronque BIT = 0

    /* 1. Colonnes de depart (niveau 0) : lecture de toute LINE_VIS_EDG
          (voir en-tete). Une colonne = une combinaison DTA_1..DTA_4
          distincte. OPTION (RECOMPILE) : plan calcule avec les vraies
          valeurs, les filtres "NULL = tous" disparaissent. */
    INSERT INTO #noeuds (NOD_HASH, DTA_1, DTA_2, DTA_3, DTA_4, NIVEAU, SENS)
    SELECT TOP (@p_maxnoeuds)
        CHECKSUM(e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4),
        e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4, 0, '-'
    FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
    WHERE e.DTA_2 = @p_table
      AND (@p_schema IS NULL OR e.DTA_3 = @p_schema)
      AND (@p_env    IS NULL OR e.DTA_4 = @p_env)
    GROUP BY e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4
    ORDER BY e.DTA_4, e.DTA_3, e.DTA_1
    OPTION (RECOMPILE)

    -- Plus de colonnes de depart que @p_maxnoeuds : resultat incomplet
    IF @@ROWCOUNT >= @p_maxnoeuds
        SET @tronque = 1

    /* 2. Lineage colonne par colonne depuis ces colonnes
          (@p_lnauid NULL : les noeuds de depart sont deja dans #noeuds) */
    DECLARE @tronqueParcours BIT

    EXEC dbo.LINE_VIS_Lineage_Parcours
        NULL, NULL, NULL, @p_sens,
        @p_profondeur, @p_maxnoeuds, @tronqueParcours OUTPUT

    IF @tronqueParcours = 1
        SET @tronque = 1

    /* 3. Regroupement par table. Une table de depart reste au niveau 0
          meme si l'une de ses colonnes est retrouvee plus loin. */
    CREATE TABLE #tables (
        TAB_ID      INT IDENTITY(1, 1) PRIMARY KEY,
        DTA_4       VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_3       VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        DTA_2       VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        NIVEAU      INT     NOT NULL,
        SENS        CHAR(1) NOT NULL,
        NB_COLONNES INT     NOT NULL
    )

    INSERT INTO #tables (DTA_4, DTA_3, DTA_2, NIVEAU, SENS, NB_COLONNES)
    SELECT
        n.DTA_4, n.DTA_3, n.DTA_2,
        MIN(n.NIVEAU),
        CASE WHEN MIN(n.NIVEAU) = 0                                  THEN '-'
             WHEN MIN(n.SENS) = 'I' AND MAX(n.SENS) = 'O'            THEN 'B'
             ELSE MIN(n.SENS) END,
        COUNT(*)
    FROM #noeuds n
    GROUP BY n.DTA_4, n.DTA_3, n.DTA_2
    ORDER BY MIN(n.NIVEAU), n.DTA_4, n.DTA_3, n.DTA_2

    -- Table de chaque colonne (NULL = NULL : une partie vide reste une table)
    CREATE TABLE #col_table (
        NOD_ID INT NOT NULL PRIMARY KEY,
        TAB_ID INT NOT NULL
    )
    INSERT INTO #col_table (NOD_ID, TAB_ID)
    SELECT n.NOD_ID, t.TAB_ID
    FROM #noeuds n
    INNER JOIN #tables t
            ON (t.DTA_4 = n.DTA_4 OR (t.DTA_4 IS NULL AND n.DTA_4 IS NULL))
           AND (t.DTA_3 = n.DTA_3 OR (t.DTA_3 IS NULL AND n.DTA_3 IS NULL))
           AND (t.DTA_2 = n.DTA_2 OR (t.DTA_2 IS NULL AND n.DTA_2 IS NULL))

    /* Liens colonne -> colonne ramenes aux tables. En mode 'B', un meme
       lien (source, destination, LNA_UID) peut avoir ete lu des 2 cotes :
       MAX le compte une fois. */
    CREATE TABLE #liens_tab (
        SRC_TAB  INT NOT NULL,
        DST_TAB  INT NOT NULL,
        SRC_ID   INT NOT NULL,
        DST_ID   INT NOT NULL,
        LNA_UID  VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        NB_LIENS INT NOT NULL
    )
    INSERT INTO #liens_tab (SRC_TAB, DST_TAB, SRC_ID, DST_ID, LNA_UID, NB_LIENS)
    SELECT cs.TAB_ID, cd.TAB_ID, l.SRC_ID, l.DST_ID, l.LNA_UID, MAX(l.NB_LIENS)
    FROM #liens l
    INNER JOIN #col_table cs ON cs.NOD_ID = l.SRC_ID
    INNER JOIN #col_table cd ON cd.NOD_ID = l.DST_ID
    WHERE cs.TAB_ID <> cd.TAB_ID          -- pas de lien d'une table vers elle-meme
    GROUP BY cs.TAB_ID, cd.TAB_ID, l.SRC_ID, l.DST_ID, l.LNA_UID

    /* 4. Resultats */
    IF @p_sortie IN ('T', 'N')
        SELECT
            t.TAB_ID,
            t.NIVEAU,
            t.SENS,
            t.DTA_4,
            t.DTA_3,
            t.DTA_2,
            CONCAT_WS('.', NULLIF(t.DTA_4, ''), NULLIF(t.DTA_3, ''), NULLIF(t.DTA_2, '')) AS NOM_TABLE,
            t.NB_COLONNES,
            @tronque AS TRONQUE
        FROM #tables t
        ORDER BY t.NIVEAU, t.TAB_ID

    IF @p_sortie IN ('T', 'A')
        SELECT
            lt.SRC_TAB                                   AS SRC_TAB_ID,
            lt.DST_TAB                                   AS DST_TAB_ID,
            COUNT(DISTINCT CONCAT(lt.SRC_ID, '>', lt.DST_ID)) AS NB_COLONNES_LIEES,
            SUM(lt.NB_LIENS)                             AS NB_LIENS,
            COUNT(DISTINCT lt.LNA_UID)                   AS NB_PROGRAMMES,
            (SELECT STRING_AGG(x.EXE_PGM_NME, ', ') WITHIN GROUP (ORDER BY x.EXE_PGM_NME)
             FROM (SELECT DISTINCT COALESCE(h.EXE_PGM_NME, '') AS EXE_PGM_NME
                   FROM #liens_tab l2
                   INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = l2.LNA_UID
                   WHERE l2.SRC_TAB = lt.SRC_TAB AND l2.DST_TAB = lt.DST_TAB) x) AS PROGRAMMES
        FROM #liens_tab lt
        GROUP BY lt.SRC_TAB, lt.DST_TAB
        ORDER BY lt.SRC_TAB, lt.DST_TAB
END
GO
