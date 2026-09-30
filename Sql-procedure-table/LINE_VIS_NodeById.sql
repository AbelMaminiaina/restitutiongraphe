-- =============================================================================
--  Procedure dbo.LINE_VIS_NodeById
--  Base : RestitutionGrapheProd
--
--  Code transcrit de la photo M1/8.jpeg (fichier LINE_VIS_NodeById.sql).
--  Seul ajout : l'en-tete USE ci-dessous (et le GO final).
--
--  Renvoie UNE arete identifiee par sa cle primaire (LNA_UID, LIN_UID, EDG_DIR),
--  avec son en-tete LINE_VIS_HEA et deux libelles calcules :
--    SourceNode = "DTA_4.DTA_3.DTA_2.DTA_1" (parties vides ignorees)
--    LinkedNode = "EDG_4.EDG_3.EDG_2.EDG_1" (parties vides ignorees)
-- =============================================================================

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_NodeById]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_NodeById
GO

CREATE PROCEDURE [dbo].LINE_VIS_NodeById
    @p_lnauid   VARCHAR(200) = NULL,
    @p_linuid   VARCHAR(500) = NULL,
    @p_edgdir   CHAR(1)  = NULL

AS
BEGIN
    SELECT
        e.LNA_UID AS LNA_UID,
        e.LIN_UID AS LIN_UID,
        e.EDG_DIR AS EDG_DIR,
        e.DTA_1 AS DTA_1,
        e.DTA_2 AS DTA_2,
        e.DTA_3 AS DTA_3,
        e.DTA_4 AS DTA_4,
        e.TXN_DTA AS TXN_DTA,
        e.EDG_1 AS EDG_1,
        e.EDG_2 AS EDG_2,
        e.EDG_3 AS EDG_3,
        e.EDG_4 AS EDG_4,
        e.PRX_TXN_DTA AS PRX_TXN_DTA,
        h.RON_APP     AS RON_APP,
        h.PCK_PGM_NME AS PCK_PGM_NME,
        h.EXE_PGM_NME AS EXE_PGM_NME,
        h.VRS_EXE_PGM AS VRS_EXE_PGM,
        h.APP_ENV     AS APP_ENV,
        h.DLY_PGM_TSP AS DLY_PGM_TSP,
        h.LNA_TSP     AS LNA_TSP,
        h.PGM_TEC     AS PGM_TEC,
        h.VRS_LNA_TOO AS VRS_LNA_TOO,
        h.TUS_IND     AS TUS_IND,
        -- SourceNode = ConcatParts(Dta1, Dta2, Dta3, Dta4)
        STUFF(
            CASE WHEN DTA_4 IS NOT NULL AND DTA_4 <> '' THEN '.' + DTA_4 ELSE '' END +
            CASE WHEN DTA_3 IS NOT NULL AND DTA_3 <> '' THEN '.' + DTA_3 ELSE '' END +
            CASE WHEN DTA_2 IS NOT NULL AND DTA_2 <> '' THEN '.' + DTA_2 ELSE '' END +
            CASE WHEN DTA_1 IS NOT NULL AND DTA_1 <> '' THEN '.' + DTA_1 ELSE '' END,
            1, 1, '') AS SourceNode,

        -- LinkedNode = ConcatParts(Edg1, Edg2, Edg3, Edg4)
        STUFF(
            CASE WHEN EDG_4 IS NOT NULL AND EDG_4 <> '' THEN '.' + EDG_4 ELSE '' END +
            CASE WHEN EDG_3 IS NOT NULL AND EDG_3 <> '' THEN '.' + EDG_3 ELSE '' END +
            CASE WHEN EDG_2 IS NOT NULL AND EDG_2 <> '' THEN '.' + EDG_2 ELSE '' END +
            CASE WHEN EDG_1 IS NOT NULL AND EDG_1 <> '' THEN '.' + EDG_1 ELSE '' END,
            1, 1, '') AS LinkedNode
    FROM dbo.LINE_VIS_EDG e
    INNER JOIN dbo.LINE_VIS_HEA h ON e.LNA_UID = h.LNA_UID
    WHERE e.LNA_UID = @p_lnauid AND e.LIN_UID = @p_linuid AND e.EDG_DIR = @p_edgdir
END
GO
