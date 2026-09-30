-- =============================================================================
--  Procedure dbo.LINE_VIS_NodesList
--  Base : RestitutionGrapheProd
--
--  Code transcrit des photos M1/3.jpeg et M1/4.jpeg (fichier LINE_VIS_NodesList.sql).
--  Ajouts : l'en-tete USE ci-dessous + le ROW_NUMBER + le retrait du
--  COLLATE du Cas 1 + Cas 1 limite aux 1000 premieres lignes trouvees
--  (voir plus bas).
--
--  A noter :
--    - ecart volontaire avec la photo : le code de la photo filtre le Cas 1
--      sur "LIKE 'a%'" alors que son commentaire dit "LIKE 'f%'". On suit le
--      commentaire ('f%') : avec 'a%', aucune ligne ne correspondait et la
--      table (7 M lignes) etait lue en entier (~10 s) ;
--    - ecart volontaire avec la photo : sur la photo RowNum vaut la constante
--      0 (plus de dedoublonnage). On a remis le ROW_NUMBER() + WHERE RowNum = 1
--      -> une seule ligne par combinaison (DTA_1..DTA_4), la 1re selon
--      LIN_UID, LNA_UID, EDG_DIR. Le SELECT DISTINCT du Cas 2 devient inutile
--      (et est retire).
--    - ecart volontaire (performance) pour le Cas 1 :
--      "DTA_1 COLLATE French_CI_AS LIKE ..." devient "DTA_1 LIKE ..." :
--      la colonne est deja insensible a la casse
--      (SQL_Latin1_General_CP1_CI_AS) et le COLLATE coutait ~3 s de
--      conversion par parcours des 7 M lignes.
--    - ecart volontaire (performance, SANS index) pour le Cas 1 :
--        * on recupere seulement les 1000 premieres lignes trouvees en base
--          avec DTA_1 LIKE 'f%' (TOP 1000 sans ORDER BY : SQL Server arrete
--          la lecture de la table des qu'il en a 1000), puis on garde les
--          100 premieres combinaisons (DTA_1..DTA_4) distinctes de ces 1000
--          lignes, triees par DTA_1..DTA_4.
--          Attention : ce sont les 100 premieres PARMI ces 1000 lignes, pas
--          forcement les 100 premieres de toute la table ; et si moins de
--          1000 lignes correspondent, la table est lue en entier ;
--        * le calcul de TotalLignes du Cas 1 est mis en commentaire pour le
--          moment (COUNT DISTINCT sur 7 M lignes = 2 a 3 min sans index) :
--          TotalLignes vaut NULL dans le Cas 1.
--
--  Dependances : dbo.LINE_VIS_EDG (LINE_VIS_EDG.sql), aucun index requis.
-- =============================================================================

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_NodesList]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_NodesList
GO

CREATE PROCEDURE [dbo].[LINE_VIS_NodesList]
    @p_column   VARCHAR(1000) = NULL,
    @p_table    VARCHAR(1000) = NULL,
    @p_schema   VARCHAR(8000)  = NULL,
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
        -- Calcul du total mis en commentaire pour le moment (trop lent sans
        -- index : 2 a 3 min sur 7 M lignes). TotalLignes reste NULL.
        -- IF @TotalLignes IS NULL
        --     SELECT @TotalLignes = COUNT(*)
        --     FROM (SELECT DISTINCT DTA_1, DTA_2, DTA_3, DTA_4 FROM dbo.LINE_VIS_EDG) AS AllDistinct
        SET @TotalLignes = NULL
    END
    ELSE
        -- Cas 2 : comptage des combinaisons distinctes qui passent les filtres.
        -- 1 seul scan de l'index couvrant (agrégat en flux, sans tri).
        SELECT @TotalLignes = COUNT(*)
        FROM (
            SELECT DTA_1, DTA_2, DTA_3, DTA_4
            FROM dbo.LINE_VIS_EDG WITH (NOLOCK)
            WHERE
                (@p_column IS NULL OR @p_column = '' OR DTA_1 COLLATE French_CI_AS LIKE '%' + @p_column + '%')
            AND (@p_table  IS NULL OR @p_table  = '' OR DTA_2 COLLATE French_CI_AS LIKE '%' + @p_table  + '%')
            AND (@p_schema IS NULL OR @p_schema = '' OR DTA_3 COLLATE French_CI_AS LIKE '%' + @p_schema + '%')
            AND (@p_env    IS NULL OR @p_env    = '' OR DTA_4 COLLATE French_CI_AS LIKE '%' + @p_env    + '%')
            GROUP BY DTA_1, DTA_2, DTA_3, DTA_4
        ) AS FilteredDistinct

    IF @AllParamsEmpty = 1
    BEGIN
        -- Cas 1 : Tous les paramètres sont vides -> Filtre DTA_1 LIKE 'f%'
        -- 1) les 1000 premieres lignes trouvees en base avec DTA_1 LIKE 'f%'
        --    (pas d'ORDER BY : la lecture s'arrete des qu'on en a 1000) ;
        -- 2) dedoublonnage par combinaison (DTA_1..DTA_4) sur ces 1000 lignes ;
        -- 3) les @p_maxres (100) premieres combinaisons, triees.
        WITH Premieres1000 AS (
            SELECT TOP (1000)
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR
            FROM dbo.LINE_VIS_EDG
            WHERE DTA_1 LIKE 'f%'
        ),
        FilteredData AS (
            SELECT
                DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR,
                ROW_NUMBER() OVER (
                    PARTITION BY DTA_1, DTA_2, DTA_3, DTA_4
                    ORDER BY LIN_UID ASC, LNA_UID ASC, EDG_DIR ASC
                ) AS RowNum
            FROM Premieres1000
        )
        SELECT
            DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR, @TotalLignes AS TotalLignes
        FROM FilteredData
        WHERE RowNum = 1
        ORDER BY DTA_1, DTA_2, DTA_3, DTA_4
        OFFSET 0 ROWS FETCH FIRST @p_maxres ROWS ONLY
        OPTION (RECOMPILE)

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
        OPTION (RECOMPILE, FAST 100) -- <- Optimise pour les 100 premières lignes
    END
END
GO
