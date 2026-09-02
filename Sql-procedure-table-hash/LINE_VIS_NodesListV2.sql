-- =============================================================================
--  Procédure dbo.LINE_VIS_NodesListV2 — variante "clé dérivée"
--  Base : RestitutionGrapheProdHash   (dossier Sql-procedure-table-hash)
--
--  Identique à Sql-procedure-table/LINE_VIS_NodesListV2.sql, SAUF que les
--  clauses PARTITION BY / GROUP BY / ORDER BY portent sur les colonnes
--  DTA_1_k..DTA_4_k (préfixes des DTA_x, cf. LINE_VIS_EDG.sql) au lieu de
--  DTA_1..DTA_4.
--
--  Ne changent PAS :
--    - les types des colonnes DTA_1..DTA_4 (VARCHAR(1000)/VARCHAR(8000))
--    - les paramètres (@p_column, @p_table, @p_schema, @p_env, @p_maxres)
--    - les clauses WHERE (toujours DTA_x LIKE '%' + @p_x + '%' / DTA_1 LIKE 'f%')
--    - les colonnes renvoyées (DTA_1, DTA_2, DTA_3, DTA_4 d'origine)
--    - le résultat (DTA_x_k = DTA_x tant que la valeur tient dans le préfixe)
--
--  Gain : les 4 colonnes _k sont courtes -> clé de IX_LINE_VIS_EDG_2_Covering =
--  1581 octets (< 1700) : plus d'avertissement "index key > 1700 bytes".
--  Comme les _k sont des colonnes RÉELLES (pas calculées -> aucun Compute
--  Scalar, cf. LINE_VIS_EDG.sql) et que l'index reste ordonné sur (préfixes,
--  LIN_UID, LNA_UID, EDG_DIR), il couvre PARTITION BY + ORDER BY interne +
--  ORDER BY final -> aucun Sort, mêmes perfs que Sql-procedure-table/
--  (Cas 1 ~10 ms, Cas 2 ~2-3 s sur 1,8 M lignes).
--
--  Dépendance : dbo.LINE_VIS_EDG_Stats + dbo.LINE_VIS_EDG_RefreshStats.
-- =============================================================================

USE RestitutionGrapheProdHash;
GO

-- Jeu de SET par convention (identique aux autres scripts du dossier). Les _k
-- étant des colonnes réelles, l'optimiseur n'a plus besoin d'un jeu d'options
-- particulier pour garder l'ordre de l'index ; on les fige quand même à la
-- création de la procédure pour un plan stable quel que soit l'appelant.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
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
    -- ARITHABORT / ANSI_WARNINGS ne sont pas hérités de façon fiable de la
    -- session appelante (souvent OFF côté ODBC/JDBC). Ils ne conditionnent plus
    -- le plan (les _k sont des colonnes réelles), on les force par cohérence.
    SET ARITHABORT ON;
    SET ANSI_WARNINGS ON;
    SET CONCAT_NULL_YIELDS_NULL ON;

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
        -- Cache O(1) alimenté par dbo.LINE_VIS_EDG_RefreshStats.
        SELECT @TotalLignes = DistinctDTACount
        FROM dbo.LINE_VIS_EDG_Stats WHERE Id = 1;

        -- Repli si le cache n'a jamais été alimenté : calcul direct (lent).
        IF @TotalLignes IS NULL
            SELECT @TotalLignes = COUNT(*)
            FROM (SELECT DISTINCT DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k FROM dbo.LINE_VIS_EDG) AS AllDistinct;
    END
    ELSE
        -- Cas 2 : comptage des combinaisons distinctes qui passent les filtres.
        -- 1 seul scan de l'index couvrant (agrégat en flux, sans tri).
        SELECT @TotalLignes = COUNT(*)
        FROM (
            SELECT DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
            FROM dbo.LINE_VIS_EDG WITH (NOLOCK)
            WHERE
                (@p_column IS NULL OR @p_column = '' OR DTA_1 LIKE '%' + @p_column + '%')
            AND (@p_table  IS NULL OR @p_table  = '' OR DTA_2 LIKE '%' + @p_table  + '%')
            AND (@p_schema IS NULL OR @p_schema = '' OR DTA_3 LIKE '%' + @p_schema + '%')
            AND (@p_env    IS NULL OR @p_env    = '' OR DTA_4 LIKE '%' + @p_env    + '%')
            GROUP BY DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
        ) AS FilteredDistinct

    IF @AllParamsEmpty = 1
    BEGIN
        -- Cas 1 : Tous les paramètres sont vides -> Filtre DTA_1 LIKE 'f%'
        WITH FilteredData AS (
            SELECT
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR,
                DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k,
                ROW_NUMBER() OVER (
                    PARTITION BY DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
                    ORDER BY LIN_UID ASC, LNA_UID ASC, EDG_DIR ASC
                ) AS RowNum
            FROM dbo.LINE_VIS_EDG
            WHERE DTA_1 LIKE 'f%'
        )
        SELECT
            DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR, @TotalLignes AS TotalLignes
        FROM FilteredData
        WHERE RowNum = 1
        ORDER BY DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
        OFFSET 0 ROWS FETCH FIRST @p_maxres ROWS ONLY
        OPTION (RECOMPILE, FAST 100); -- <- Optimise pour les 100 premières lignes
    END
    ELSE
    BEGIN
        -- Cas 2 : Au moins un paramètre est non vide -> Filtres dynamiques.
        WITH FilteredData AS (
            SELECT
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR,
                DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k,
                ROW_NUMBER() OVER (
                    PARTITION BY DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
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
        ORDER BY DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
        OFFSET 0 ROWS FETCH FIRST @p_maxres ROWS ONLY
        OPTION (RECOMPILE, FAST 100); -- <- Optimise pour les 100 premières lignes
    END
END
GO
