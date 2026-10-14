-- =============================================================================
--  Procedure dbo.LINE_VIS_Impact
--  Base : RestitutionGrapheProd
--
--  But : analyse d'impact. "Si je modifie ce noeud (colonne), qu'est-ce qui
--  est touche ?" -> les tables, schemas, environnements et programmes en
--  aval (ou en amont : "d'ou viennent les donnees ?").
--
--  Le parcours est celui de dbo.LINE_VIS_Lineage (procedure partagee
--  dbo.LINE_VIS_Lineage_Parcours) ; cette procedure ne fait que regrouper
--  les noeuds et les liens trouves.
--
--  Signification des coordonnees (comme dans LINE_VIS_NodesList) :
--    DTA_1 = colonne, DTA_2 = table, DTA_3 = schema, DTA_4 = environnement.
--  Un programme = (RON_APP, PCK_PGM_NME, EXE_PGM_NME, APP_ENV) de
--  LINE_VIS_HEA ; chaque LNA_UID en est une execution.
--
--  Parametres :
--    @p_lnauid, @p_linuid, @p_edgdir : noeud de depart (une ligne de
--        LINE_VIS_EDG, comme pour LINE_VIS_Lineage).
--    @p_sens       : 'O' = aval (defaut : ce qui est impacte),
--                    'I' = amont (d'ou viennent les donnees), 'B' = les deux.
--    @p_profondeur : nombre maximum de niveaux (defaut 10).
--    @p_maxnoeuds  : nombre maximum de noeuds parcourus (defaut 2000) ;
--                    au-dela TRONQUE = 1 et les comptes sont des minimums.
--    @p_sortie     : 'T' = les 3 jeux de resultats (defaut),
--                    'R' = resume, 'O' = objets (tables), 'P' = programmes
--                    (un seul jeu : utile pour INSERT ... EXEC).
--
--  Resultats (le noeud de depart lui-meme n'est jamais compte) :
--    1. RESUME (toujours 1 ligne) : NOEUD_TROUVE, NB_NOEUDS, NB_TABLES,
--       NB_SCHEMAS, NB_ENVIRONNEMENTS, NB_APPLICATIONS, NB_PROGRAMMES,
--       NB_EXECUTIONS, PROFONDEUR (niveau le plus loin atteint), TRONQUE.
--    2. OBJETS : une ligne par table touchee (SENS, DTA_4, DTA_3, DTA_2),
--       avec NB_COLONNES et NIVEAU_MIN (distance la plus courte au depart).
--    3. PROGRAMMES : une ligne par programme qui transporte au moins un
--       lien parcouru (SENS, RON_APP, PCK_PGM_NME, EXE_PGM_NME, APP_ENV),
--       avec NB_EXECUTIONS (LNA_UID distincts), NB_LIENS (lignes de
--       LINE_VIS_EDG), NIVEAU_MIN et DERNIERE_EXECUTION (MAX(LNA_TSP)).
--       Le niveau / sens d'un lien = ceux de son extremite la plus loin
--       du depart.
--
--  Base et journal : rien n'est ecrit (tables #temporaires dans tempdb).
--
--  Dependances : dbo.LINE_VIS_Lineage_Parcours (LINE_VIS_Lineage_Parcours.sql),
--                dbo.LINE_VIS_HEA (LINE_VIS_HEA.sql)
-- =============================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_Impact]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_Impact
GO

CREATE PROCEDURE [dbo].LINE_VIS_Impact
    @p_lnauid     VARCHAR(200) = NULL,
    @p_linuid     VARCHAR(500) = NULL,
    @p_edgdir     CHAR(1)      = NULL,
    @p_sens       CHAR(1)      = 'O',
    @p_profondeur INT          = 10,
    @p_maxnoeuds  INT          = 2000,
    @p_sortie     CHAR(1)      = 'T'

AS
BEGIN
    SET NOCOUNT ON

    IF @p_sortie IS NULL OR @p_sortie NOT IN ('T', 'R', 'O', 'P')
        THROW 50002, 'LINE_VIS_Impact : @p_sortie doit valoir T (tout), R (resume), O (objets) ou P (programmes).', 1;

    SET @p_profondeur = COALESCE(@p_profondeur, 10)
    SET @p_maxnoeuds  = COALESCE(@p_maxnoeuds, 2000)

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

    DECLARE @tronque BIT

    EXEC dbo.LINE_VIS_Lineage_Parcours
        @p_lnauid, @p_linuid, @p_edgdir, @p_sens,
        @p_profondeur, @p_maxnoeuds, @tronque OUTPUT

    /* Liens avec leur programme (en-tete LINE_VIS_HEA), leur niveau et leur
       sens. En mode 'B', un meme lien (source, destination, LNA_UID) peut
       avoir ete lu des 2 cotes : MAX le compte une fois. */
    CREATE TABLE #liens_pgm (
        LNA_UID     VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        NB_LIENS    INT     NOT NULL,
        NIVEAU      INT     NOT NULL,
        SENS        CHAR(1) NOT NULL,
        RON_APP     VARCHAR(4)   COLLATE DATABASE_DEFAULT NOT NULL,
        PCK_PGM_NME VARCHAR(500) COLLATE DATABASE_DEFAULT NOT NULL,
        EXE_PGM_NME VARCHAR(500) COLLATE DATABASE_DEFAULT NOT NULL,
        APP_ENV     VARCHAR(20)  COLLATE DATABASE_DEFAULT NOT NULL,
        LNA_TSP     DATETIME2 NULL
    )

    INSERT INTO #liens_pgm
        (LNA_UID, NB_LIENS, NIVEAU, SENS, RON_APP, PCK_PGM_NME, EXE_PGM_NME, APP_ENV, LNA_TSP)
    SELECT
        l.LNA_UID,
        l.NB_LIENS,
        -- extremite la plus loin du depart
        CASE WHEN d.NIVEAU >= s.NIVEAU THEN d.NIVEAU ELSE s.NIVEAU END,
        CASE WHEN d.NIVEAU >= s.NIVEAU THEN d.SENS   ELSE s.SENS   END,
        COALESCE(h.RON_APP, ''),
        COALESCE(h.PCK_PGM_NME, ''),
        COALESCE(h.EXE_PGM_NME, ''),
        COALESCE(h.APP_ENV, ''),
        h.LNA_TSP
    FROM (
        SELECT SRC_ID, DST_ID, LNA_UID, MAX(NB_LIENS) AS NB_LIENS
        FROM #liens
        GROUP BY SRC_ID, DST_ID, LNA_UID
    ) l
    INNER JOIN #noeuds s ON s.NOD_ID = l.SRC_ID
    INNER JOIN #noeuds d ON d.NOD_ID = l.DST_ID
    INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = l.LNA_UID

    /* 1. RESUME */
    IF @p_sortie IN ('T', 'R')
        SELECT
            CAST(CASE WHEN EXISTS (SELECT 1 FROM #noeuds) THEN 1 ELSE 0 END AS BIT) AS NOEUD_TROUVE,
            (SELECT COUNT(*) FROM #noeuds WHERE NIVEAU > 0)                         AS NB_NOEUDS,
            (SELECT COUNT(*) FROM (SELECT DISTINCT DTA_4, DTA_3, DTA_2
                                   FROM #noeuds WHERE NIVEAU > 0) t)                AS NB_TABLES,
            (SELECT COUNT(*) FROM (SELECT DISTINCT DTA_4, DTA_3
                                   FROM #noeuds WHERE NIVEAU > 0) t)                AS NB_SCHEMAS,
            (SELECT COUNT(*) FROM (SELECT DISTINCT DTA_4
                                   FROM #noeuds WHERE NIVEAU > 0) t)                AS NB_ENVIRONNEMENTS,
            (SELECT COUNT(DISTINCT RON_APP) FROM #liens_pgm)                        AS NB_APPLICATIONS,
            (SELECT COUNT(*) FROM (SELECT DISTINCT RON_APP, PCK_PGM_NME, EXE_PGM_NME, APP_ENV
                                   FROM #liens_pgm) p)                              AS NB_PROGRAMMES,
            (SELECT COUNT(DISTINCT LNA_UID) FROM #liens_pgm)                        AS NB_EXECUTIONS,
            COALESCE((SELECT MAX(NIVEAU) FROM #noeuds), 0)                          AS PROFONDEUR,
            COALESCE(@tronque, 0)                                                   AS TRONQUE

    /* 2. OBJETS : tables touchees */
    IF @p_sortie IN ('T', 'O')
        SELECT
            n.SENS,
            n.DTA_4,
            n.DTA_3,
            n.DTA_2,
            COUNT(*)      AS NB_COLONNES,
            MIN(n.NIVEAU) AS NIVEAU_MIN
        FROM #noeuds n
        WHERE n.NIVEAU > 0
        GROUP BY n.SENS, n.DTA_4, n.DTA_3, n.DTA_2
        ORDER BY NIVEAU_MIN, n.SENS, n.DTA_4, n.DTA_3, n.DTA_2

    /* 3. PROGRAMMES */
    IF @p_sortie IN ('T', 'P')
        SELECT
            p.SENS,
            p.RON_APP,
            p.PCK_PGM_NME,
            p.EXE_PGM_NME,
            p.APP_ENV,
            COUNT(DISTINCT p.LNA_UID) AS NB_EXECUTIONS,
            SUM(p.NB_LIENS)           AS NB_LIENS,
            MIN(p.NIVEAU)             AS NIVEAU_MIN,
            MAX(p.LNA_TSP)            AS DERNIERE_EXECUTION
        FROM #liens_pgm p
        GROUP BY p.SENS, p.RON_APP, p.PCK_PGM_NME, p.EXE_PGM_NME, p.APP_ENV
        ORDER BY NIVEAU_MIN, p.SENS, p.RON_APP, p.EXE_PGM_NME
END
GO
