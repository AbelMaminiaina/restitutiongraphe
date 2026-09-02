-- =============================================================================
--  Génération de données de test pour dbo.LINE_VIS_EDG
--  Base : RestitutionGrapheProd
--
--  Transcrit des captures IMG_5677..IMG_5680.
--  Seule adaptation : la table cible est LINE_VIS_EDG (et non LINE_VIS_EDG_2).
--
--  Volume : @TotalRows = 2 000 000, mais le compteur démarre à 200001, donc
--  la boucle insère en pratique ~1 800 000 lignes (plage 200001..2000000).
--  LIN_UID contient le compteur global -> clé primaire garantie unique.
-- =============================================================================

USE RestitutionGrapheProd;
GO

-- 1. Vider la table (optionnel)
TRUNCATE TABLE dbo.LINE_VIS_EDG;

-- 2. Générer les lignes avec des clés primaires uniques garanties
DECLARE @i INT = 1
DECLARE @BatchSize INT = 10000
DECLARE @TotalRows INT = 2000000
DECLARE @GlobalCounter INT = 200001 -- Compteur global pour garantir l'unicité absolue

PRINT 'Début de l''insertion de ' + CAST(@TotalRows AS VARCHAR) + ' lignes...'

WHILE @i <= @TotalRows
BEGIN
    INSERT INTO dbo.LINE_VIS_EDG (
        LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4,
        EDG_DIR, EDG_1, EDG_2, EDG_3, EDG_4,
        TXN_DTA, PRX_TXN_DTA
    )
    SELECT
        -- LNA_UID (5 valeurs possibles)
        CASE ((@GlobalCounter + n - 1) % 5 + 1)
            WHEN 1 THEN 'ABN_HCL_VALINP'
            WHEN 2 THEN 'ABC_LIS_PCE'
            WHEN 3 THEN 'DEF_TRN_PROC'
            WHEN 4 THEN 'GHI_DAT_LOAD'
            ELSE 'JKL_MIG_TOOL'
        END,

        -- LIN_UID (unique grâce au compteur global + suffixe unique)
        CASE ((@GlobalCounter + n - 1) % 4 + 1)
            WHEN 1 THEN 'SPSW_HCL_ADD_DC2RG2_' + CAST((@GlobalCounter + n - 1) AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
            WHEN 2 THEN 'CCTW_CTRCAR_' + CAST((@GlobalCounter + n - 1) AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
            WHEN 3 THEN 'CCTX_CTRCAR_PPD_' + CAST((@GlobalCounter + n - 1) AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
            ELSE 'DAT_MIG_' + CAST((@GlobalCounter + n - 1) AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
        END,

        -- DTA_1 (3 valeurs possibles)
        CASE ((@GlobalCounter + n - 1) % 3 + 1)
            WHEN 1 THEN 'FIADODSWRK'
            WHEN 2 THEN 'FIADODSOUT'
            ELSE 'FIADODS' + CAST((@GlobalCounter + n - 1) % 10 AS VARCHAR(2))
        END,

        -- DTA_2 (toujours 'ZJ')
        'ZJ',

        -- DTA_3 (format _XXXXXXXX.YYYY.ZZZZ)
        LEFT('_' + SUBSTRING(CONVERT(VARCHAR(36), NEWID()), 1, 8) + '.' +
        CASE ((@GlobalCounter + n - 1) % 5 + 1)
            WHEN 1 THEN 'SPSS_LS2DC2'
            WHEN 2 THEN 'CCTS_CTRCAR_ADD_DWH'
            WHEN 3 THEN 'DAT_MIG_PROC'
            WHEN 4 THEN 'TRN_VAL_INP'
            ELSE 'WRK_FLOW'
        END + '.' +
        CASE ((@GlobalCounter + n - 1) % 4 + 1)
            WHEN 1 THEN 'LS2_REFDCP'
            WHEN 2 THEN 'ABC_LIS_PCE'
            WHEN 3 THEN 'DEF_TRN_PROC'
            ELSE 'GHI_DAT_LOAD'
        END, 8000),

        -- DTA_4 (format xDI_IBI_XXXX_YYY.WRK.ZZZ.ZJ)
        LEFT('xDI_IBI' +
        CASE ((@GlobalCounter + n - 1) % 3 + 1)
            WHEN 1 THEN 'S_HIRRBT'
            WHEN 2 THEN 'C_INSCTR'
            ELSE 'T_MIG'
        END + '_' + CAST((@GlobalCounter + n - 1) % 1000 AS VARCHAR(4)) + '_WRK.' +
        CAST((@GlobalCounter + n - 1) % 100 AS VARCHAR(3)) + '.ZJ', 1000),

        -- EDG_DIR (O ou I, alterné)
        CASE ((@GlobalCounter + n - 1) % 2) WHEN 0 THEN 'O' ELSE 'I' END,

        -- EDG_1 (similaire à DTA_4)
        LEFT('xDI_IBI' +
        CASE ((@GlobalCounter + n - 1) % 3 + 1)
            WHEN 1 THEN 'S_HIRRBT'
            WHEN 2 THEN 'C_INSCTR'
            ELSE 'T_MIG'
        END + '_' + CAST((@GlobalCounter + n - 1) % 1000 AS VARCHAR(4)) + '_WRK.' +
        CAST((@GlobalCounter + n - 1) % 100 AS VARCHAR(3)) + '.ZJ', 1000),

        -- EDG_2 (NULL ou valeur)
        CASE ((@GlobalCounter + n - 1) % 2) WHEN 0 THEN NULL ELSE LEFT('EDG2_' + CAST((@GlobalCounter + n - 1) % 100 AS VARCHAR(3)), 1000) END,

        -- EDG_3 (NULL ou valeur aléatoire)
        CASE ((@GlobalCounter + n - 1) % 3) WHEN 0 THEN NULL ELSE LEFT('EDG3_' + SUBSTRING(CONVERT(VARCHAR(36), NEWID()), 1, 8), 8000) END,

        -- EDG_4 (NULL ou valeur)
        CASE ((@GlobalCounter + n - 1) % 4) WHEN 0 THEN NULL ELSE LEFT('EDG4_' + CAST((@GlobalCounter + n - 1) % 100 AS VARCHAR(3)), 1000) END,

        -- TXN_DTA (JSON ou NULL)
        CASE ((@GlobalCounter + n - 1) % 5) WHEN 0 THEN NULL ELSE '{"status": "OK", "id": ' + CAST((@GlobalCounter + n - 1) AS VARCHAR(10)) + '}' END,

        -- PRX_TXN_DTA (XML ou NULL)
        CASE ((@GlobalCounter + n - 1) % 5) WHEN 0 THEN NULL ELSE '<data><value>' + CAST((@GlobalCounter + n - 1) AS VARCHAR(10)) + '</value></data>' END
    FROM (
        SELECT TOP (@BatchSize) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.objects a CROSS JOIN sys.objects b
    ) AS Numbers
    WHERE (@GlobalCounter + n - 1) <= @TotalRows

    SET @i = @i + @BatchSize
    SET @GlobalCounter = @GlobalCounter + @BatchSize
    PRINT 'Lot ' + CAST(@i / @BatchSize AS VARCHAR) + '/' + CAST(CEILING(@TotalRows * 1.0 / @BatchSize) AS VARCHAR) +
        ' : ' + CAST(@i - @BatchSize + 1 AS VARCHAR) + ' à ' + CAST(@i - 1 AS VARCHAR) + ' lignes insérées'
END

-- 3. Vérification finale
DECLARE @FinalCount INT
SELECT @FinalCount = COUNT(*) FROM dbo.LINE_VIS_EDG
PRINT 'Nombre total : ' + CAST(@FinalCount AS VARCHAR)
GO

-- 4. Rafraichir le cache d'agregats lu par LINE_VIS_NodesListV2 (Cas 1).
IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG_RefreshStats]') IS NOT NULL
    EXEC dbo.LINE_VIS_EDG_RefreshStats;
GO
