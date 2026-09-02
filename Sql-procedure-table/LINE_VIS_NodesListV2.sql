-- =============================================================================
--  Procédure dbo.LINE_VIS_NodesListV2
--  Base : RestitutionGrapheProd
--
--  Transcrite des captures IMG_5669 / IMG_5670.
--  Adaptations (cohérence avec les objets réellement créés) :
--    - table  dbo.LINE_VIS_EDG_2            -> dbo.LINE_VIS_EDG
--    - index  IX_LINE_VIS_EDG_2_DTA_EDG_DIR -> IX_LINE_VIS_EDG_DTA_EDG_DIR
--
--  Renvoie, pour chaque combinaison distincte (DTA_1..DTA_4), la 1re ligne
--  (LIN_UID/LNA_UID/EDG_DIR mini), limitée à @p_maxres, plus le nombre total
--  de combinaisons distinctes correspondantes (@TotalLignes).
--
--  Dépendance : dbo.LINE_VIS_EDG_Stats + dbo.LINE_VIS_EDG_RefreshStats
--  (LINE_VIS_EDG_Stats.sql). Le Cas 1 (aucun critère) lit @TotalLignes dans ce
--  cache en O(1) ; sans cache il retombe sur un COUNT(DISTINCT) direct (~2,4 s).
--  Penser à EXEC dbo.LINE_VIS_EDG_RefreshStats après chaque chargement de données.
-- =============================================================================

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_NodesListV2]') IS NOT NULL
    DROP PROCEDURE [dbo].[LINE_VIS_NodesListV2]
GO

CREATE PROCEDURE [dbo].[LINE_VIS_NodesListV2]
    @p_column   VARCHAR(1000) = NULL,
    @p_table    VARCHAR(1000) = NULL,
    @p_schema   VARCHAR(8000) = NULL,
    @p_env      VARCHAR(1000) = NULL,
    @p_maxres   INT           = 100
AS
BEGIN
    DECLARE @AllParamsEmpty BIT = 0
    DECLARE @TotalLignes INT

    -- Vérification si tous les paramètres sont NULL ou vides
    IF (@p_column IS NULL OR @p_column = '')
    AND (@p_table  IS NULL OR @p_table  = '')
    AND (@p_schema IS NULL OR @p_schema = '')
    AND (@p_env    IS NULL OR @p_env    = '')
        SET @AllParamsEmpty = 1

    -- Précalcul de TotalLignes
    IF @AllParamsEmpty = 1
    BEGIN
        -- Cache O(1) alimenté par dbo.LINE_VIS_EDG_RefreshStats : évite un
        -- COUNT(DISTINCT DTA_1..DTA_4) (~2,4 s de scan sur 1,8 M lignes) à
        -- chaque appel sans critère.
        SELECT @TotalLignes = DistinctDTACount
        FROM dbo.LINE_VIS_EDG_Stats WHERE Id = 1;

        -- Repli si le cache n'a jamais été alimenté : calcul direct (lent).
        IF @TotalLignes IS NULL
            SELECT @TotalLignes = COUNT(*)
            FROM (SELECT DISTINCT DTA_1, DTA_2, DTA_3, DTA_4 FROM dbo.LINE_VIS_EDG) AS AllDistinct;
    END
    ELSE
        SELECT @TotalLignes = COUNT(*)
        FROM (
            SELECT DTA_1, DTA_2, DTA_3, DTA_4
            FROM dbo.LINE_VIS_EDG WITH (NOLOCK, INDEX = [IX_LINE_VIS_EDG_DTA_EDG_DIR])
            WHERE
                (@p_column IS NULL OR @p_column = '' OR DTA_1 COLLATE French_CI_AS LIKE '%' + @p_column + '%')
            AND (@p_table  IS NULL OR @p_table  = '' OR DTA_2 COLLATE French_CI_AS LIKE '%' + @p_table  + '%')
            AND (@p_schema IS NULL OR @p_schema = '' OR DTA_3 COLLATE French_CI_AS LIKE '%' + @p_schema + '%')
            AND (@p_env    IS NULL OR @p_env    = '' OR DTA_4 COLLATE French_CI_AS LIKE '%' + @p_env    + '%')
            Group by DTA_1, DTA_2, DTA_3, DTA_4
        ) AS FilteredDistinct

    IF @AllParamsEmpty = 1
    BEGIN
        -- Cas 1 : Tous les paramètres sont vides -> Filtre DTA_1 LIKE 'f%'
        WITH FilteredData AS (
            SELECT
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR,
                ROW_NUMBER() OVER (
                    PARTITION BY DTA_1, DTA_2, DTA_3, DTA_4
                    ORDER BY LIN_UID ASC, LNA_UID ASC, EDG_DIR ASC
                ) AS RowNum
            FROM dbo.LINE_VIS_EDG
            WHERE DTA_1 COLLATE French_CI_AS LIKE 'f%'
        )
        SELECT
            DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR, @TotalLignes AS TotalLignes
        FROM FilteredData
        WHERE RowNum = 1
        ORDER BY DTA_1, DTA_2, DTA_3, DTA_4
        OFFSET 0 ROWS FETCH FIRST @p_maxres ROWS ONLY
        OPTION (RECOMPILE, FAST 100); -- <- Optimise pour les 100 premières lignes
    END
    ELSE
    BEGIN
        -- Cas 2 : Au moins un paramètre est non vide -> Filtres dynamiques
        WITH FilteredData AS (
            SELECT
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR,
                ROW_NUMBER() OVER (
                    PARTITION BY DTA_1, DTA_2, DTA_3, DTA_4
                    ORDER BY LIN_UID ASC, LNA_UID ASC, EDG_DIR ASC
                ) AS RowNum
            FROM dbo.LINE_VIS_EDG WITH (NOLOCK, INDEX = [IX_LINE_VIS_EDG_DTA_EDG_DIR])
            WHERE
                (@p_column IS NULL OR @p_column = '' OR DTA_1 COLLATE French_CI_AS LIKE '%' + @p_column + '%')
            AND (@p_table  IS NULL OR @p_table  = '' OR DTA_2 COLLATE French_CI_AS LIKE '%' + @p_table  + '%')
            AND (@p_schema IS NULL OR @p_schema = '' OR DTA_3 COLLATE French_CI_AS LIKE '%' + @p_schema + '%')
            AND (@p_env    IS NULL OR @p_env    = '' OR DTA_4 COLLATE French_CI_AS LIKE '%' + @p_env    + '%')
        )
        SELECT
            DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR, @TotalLignes AS TotalLignes
        FROM FilteredData
        WHERE RowNum = 1
        ORDER BY DTA_1, DTA_2, DTA_3, DTA_4
        OFFSET 0 ROWS FETCH FIRST @p_maxres ROWS ONLY
        OPTION (RECOMPILE, FAST 100); -- <- Optimise pour les 100 premières lignes
    END
END
GO
