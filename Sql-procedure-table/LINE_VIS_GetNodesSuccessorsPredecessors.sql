-- =============================================================================
--  Procedure dbo.LINE_VIS_GetNodesSuccessorsPredecessors
--  Base : RestitutionGrapheProd
--
--  Code transcrit des photos M1/5.jpeg, M1/6.jpeg et M1/7.jpeg
--  (fichier LINE_VIS_GetNodesSuccessorsPredecessors.sql).
--  Seul ajout : l'en-tete USE ci-dessous.
--
--  Dependances : dbo.LINE_VIS_EDG (LINE_VIS_EDG.sql),
--                dbo.LINE_VIS_HEA (LINE_VIS_HEA.sql)
-- =============================================================================

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_GetNodesSuccessorsPredecessors]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_GetNodesSuccessorsPredecessors
GO

CREATE PROCEDURE [dbo].LINE_VIS_GetNodesSuccessorsPredecessors
    @p_lnauid   VARCHAR(200) = NULL,
    @p_linuid   VARCHAR(500) = NULL,
    @p_edgdir   CHAR(1)      = NULL,
    @p_type     CHAR(1)      = NULL,
    @p_useEdg   BIT          = 0,
    @p_maxres   INT          = 100

AS
BEGIN
    SET NOCOUNT ON

    /* Récupération DTA1, DTA2, DTA3, DTA4 à partir des primary key LNA_UID, LIN_UID, EDG_DIR in parameter */
    DECLARE @DTA1 VARCHAR(1000)
    DECLARE @DTA2 VARCHAR(1000)
    DECLARE @DTA3 VARCHAR(8000)
    DECLARE @DTA4 VARCHAR(1000)

    SELECT TOP(1)
        @DTA1 = CASE WHEN @p_useEdg = 0 THEN DTA_1 ELSE EDG_1 END,
        @DTA2 = CASE WHEN @p_useEdg = 0 THEN DTA_2 ELSE EDG_2 END,
        @DTA3 = CASE WHEN @p_useEdg = 0 THEN DTA_3 ELSE EDG_3 END,
        @DTA4 = CASE WHEN @p_useEdg = 0 THEN DTA_4 ELSE EDG_4 END
    FROM dbo.LINE_VIS_EDG
    WHERE LNA_UID  = @p_lnauid
      AND LIN_UID  = @p_linuid
      AND EDG_DIR  = @p_edgdir

    /* Création de la table temporaire avec index */
    CREATE TABLE #TempResults (
        LNA_UID VARCHAR(200),
        LIN_UID VARCHAR(500),
        EDG_DIR CHAR(1),
        DTA_1 VARCHAR(1000),
        DTA_2 VARCHAR(1000),
        DTA_3 VARCHAR(8000),
        DTA_4 VARCHAR(1000),
        TXN_DTA VARCHAR(max),
        EDG_1 VARCHAR(1000),
        EDG_2 VARCHAR(1000),
        EDG_3 VARCHAR(8000),
        EDG_4 VARCHAR(1000),
        PRX_TXN_DTA VARCHAR(max),
        RON_APP VARCHAR(4),
        PCK_PGM_NME VARCHAR(500),
        EXE_PGM_NME VARCHAR(500),
        VRS_EXE_PGM VARCHAR(100),
        APP_ENV VARCHAR(20),
        DLY_PGM_TSP DATETIME2,
        LNA_TSP DATETIME2,
        PGM_TEC VARCHAR(20),
        VRS_LNA_TOO VARCHAR(100),
        TUS_IND INT,
        CURRENT_NODE VARCHAR(MAX)
    )

    /* Insertion des résultats dans la table temporaire avec pagination */
    INSERT INTO #TempResults
    SELECT
        e.LNA_UID,
        e.LIN_UID,
        e.EDG_DIR,
        e.DTA_1,
        e.DTA_2,
        e.DTA_3,
        e.DTA_4,
        e.TXN_DTA,
        e.EDG_1,
        e.EDG_2,
        e.EDG_3,
        e.EDG_4,
        e.PRX_TXN_DTA,
        COALESCE(h.RON_APP, ''),
        COALESCE(h.PCK_PGM_NME, ''),
        COALESCE(h.EXE_PGM_NME,''),
        COALESCE(h.VRS_EXE_PGM,''),
        COALESCE(h.APP_ENV, ''),
        COALESCE(h.DLY_PGM_TSP, ''),
        COALESCE(h.LNA_TSP, ''),
        COALESCE(h.PGM_TEC, ''),
        COALESCE(h.VRS_LNA_TOO, ''),
        COALESCE(h.TUS_IND, 0),
        CASE
            WHEN COALESCE(EDG_4, '') = '' AND COALESCE(EDG_3, '') = '' AND
                 COALESCE(EDG_2, '') = '' AND COALESCE(EDG_1, '') = '' THEN ''
            ELSE RTRIM(LTRIM(
                CASE WHEN EDG_4 IS NOT NULL AND EDG_4 <> '' THEN EDG_4 ELSE '' END +
                CASE WHEN EDG_3 IS NOT NULL AND EDG_3 <> '' AND (EDG_4 IS NOT NULL AND EDG_4 <> '') THEN '.' + EDG_3 ELSE '' END +
                CASE WHEN EDG_2 IS NOT NULL AND EDG_2 <> '' AND (EDG_3 IS NOT NULL AND EDG_3 <> '') THEN '.' + EDG_2 ELSE '' END +
                CASE WHEN EDG_1 IS NOT NULL AND EDG_1 <> '' AND (EDG_2 IS NOT NULL AND EDG_2 <> '') THEN '.' + EDG_1 ELSE '' END
            ))
        END
    FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
    INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON e.LNA_UID = h.LNA_UID
    WHERE (e.DTA_1 COLLATE French_CI_AS = @DTA1 COLLATE French_CI_AS OR @DTA1 IS NULL)
      AND (e.DTA_2 COLLATE French_CI_AS = @DTA2 COLLATE French_CI_AS OR @DTA2 IS NULL)
      AND (e.DTA_3 COLLATE French_CI_AS = @DTA3 COLLATE French_CI_AS OR @DTA3 IS NULL)
      AND (e.DTA_4 COLLATE French_CI_AS = @DTA4 COLLATE French_CI_AS OR @DTA4 IS NULL)
      AND e.EDG_DIR = @p_type

    /* Récupération du nombre total de lignes */
    DECLARE @TotalLignes INT
    SELECT @TotalLignes = COUNT(*) FROM #TempResults

    /* Retour des résultats avec le nombre total de lignes */
    SELECT
        LNA_UID,
        LIN_UID,
        EDG_DIR,
        DTA_1,
        DTA_2,
        DTA_3,
        DTA_4,
        TXN_DTA,
        EDG_1,
        EDG_2,
        EDG_3,
        EDG_4,
        PRX_TXN_DTA,
        RON_APP,
        PCK_PGM_NME,
        EXE_PGM_NME,
        VRS_EXE_PGM,
        APP_ENV,
        DLY_PGM_TSP,
        LNA_TSP,
        PGM_TEC,
        VRS_LNA_TOO,
        TUS_IND,
        CURRENT_NODE,
        @TotalLignes AS TotalLignes
    FROM #TempResults
    ORDER BY DTA_1, DTA_2, DTA_3, DTA_4
    OFFSET 0 ROWS
    FETCH FIRST @p_maxres ROWS ONLY

    /* Nettoyage */
    DROP TABLE #TempResults
END
GO
