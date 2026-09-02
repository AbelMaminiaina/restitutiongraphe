-- =============================================================================
--  Procédure dbo.LINE_VIS_NodesListV2
--  Base : RestitutionGrapheProd
--
--  Transcrite des captures IMG_5669 / IMG_5670, puis optimisée.
--  Adaptations vs captures :
--    - table  dbo.LINE_VIS_EDG_2  -> dbo.LINE_VIS_EDG
--    - suppression du hint INDEX = [IX_LINE_VIS_EDG_2_DTA_EDG_DIR] : il forçait
--      le plus gros index (645 Mo) et un opérateur Sort de plusieurs secondes.
--      Sans hint, l'optimiseur prend IX_LINE_VIS_EDG_2_Covering, dont l'ordre
--      (DTA_1..4, LIN_UID, LNA_UID, EDG_DIR) couvre PARTITION BY + ORDER BY du
--      ROW_NUMBER -> plus aucun tri.
--    - suppression de COLLATE French_CI_AS : la base est déjà en
--      SQL_Latin1_General_CP1_CI_AS (insensible à la casse) ; la clause forçait
--      un CONVERT ligne par ligne sur des colonnes larges (DTA_3). Le LIKE
--      reste insensible à la casse via la collation de la colonne.
--
--  Renvoie, pour chaque combinaison distincte (DTA_1..DTA_4), la 1re ligne
--  (LIN_UID/LNA_UID/EDG_DIR mini), limitée à @p_maxres, plus le nombre total
--  de combinaisons distinctes correspondantes (@TotalLignes).
--
--  Perf (table de 1,8 M lignes) :
--    Cas 1 (aucun critère)      : ~3 ms   -- @TotalLignes lu dans le cache
--    Cas 2 (>= 1 critère)       : ~2-3 s  -- 1 scan pour le comptage filtré ;
--                                            la requête de données s'arrête tôt
--                                            (row goal FETCH/FAST 100).
--    Le ~2 s résiduel du Cas 2 est le coût incompressible d'une recherche
--    "LIKE '%...%'" sur 1,8 M lignes (non SARGable). Pour du sous-seconde il
--    faudrait un index full-text / trigrammes.
--
--  Dépendance : dbo.LINE_VIS_EDG_Stats + dbo.LINE_VIS_EDG_RefreshStats
--  (LINE_VIS_EDG_Stats.sql). Penser à EXEC dbo.LINE_VIS_EDG_RefreshStats
--  après chaque chargement de données.
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
        -- Cas 2 : comptage des combinaisons distinctes qui passent les filtres.
        -- 1 seul scan de l'index couvrant (agrégat en flux, sans tri).
        SELECT @TotalLignes = COUNT(*)
        FROM (
            SELECT DTA_1, DTA_2, DTA_3, DTA_4
            FROM dbo.LINE_VIS_EDG WITH (NOLOCK)
            WHERE
                (@p_column IS NULL OR @p_column = '' OR DTA_1 LIKE '%' + @p_column + '%')
            AND (@p_table  IS NULL OR @p_table  = '' OR DTA_2 LIKE '%' + @p_table  + '%')
            AND (@p_schema IS NULL OR @p_schema = '' OR DTA_3 LIKE '%' + @p_schema + '%')
            AND (@p_env    IS NULL OR @p_env    = '' OR DTA_4 LIKE '%' + @p_env    + '%')
            GROUP BY DTA_1, DTA_2, DTA_3, DTA_4
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
            WHERE DTA_1 LIKE 'f%'
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
        -- Cas 2 : Au moins un paramètre est non vide -> Filtres dynamiques.
        -- Pas de hint d'index : l'optimiseur prend l'index couvrant ordonné
        -- (aucun tri) et le row goal (FETCH/FAST 100) arrête le scan tôt.
        WITH FilteredData AS (
            SELECT
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR,
                ROW_NUMBER() OVER (
                    PARTITION BY DTA_1, DTA_2, DTA_3, DTA_4
                    ORDER BY LIN_UID ASC, LNA_UID ASC, EDG_DIR ASC
                ) AS RowNum
            FROM dbo.LINE_VIS_EDG WITH (NOLOCK)
            WHERE
                (@p_column IS NULL OR @p_column = '' OR DTA_1 LIKE '%' + @p_column + '%')
            AND (@p_table  IS NULL OR @p_table  = '' OR DTA_2 LIKE '%' + @p_table  + '%')
            AND (@p_schema IS NULL OR @p_schema = '' OR DTA_3 LIKE '%' + @p_schema + '%')
            AND (@p_env    IS NULL OR @p_env    = '' OR DTA_4 LIKE '%' + @p_env    + '%')
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
