-- =============================================================================
--  Génération de données de test pour dbo.LINE_VIS_EDG
--  Base : RestitutionGrapheProd
--
--  Transcrit des captures IMG_5677..IMG_5680, puis adapté :
--    - table cible LINE_VIS_EDG (et non LINE_VIS_EDG_2) ;
--    - volume : 7 000 000 lignes (compteur 1..7000000) ;
--    - LNA_UID : 210 000 valeurs distinctes (5 préfixes x 42 000 numéros),
--      soit ~33 lignes par LNA_UID. LINE_VIS_HEA_data.sql crée ensuite une
--      ligne d'en-tête par LNA_UID distinct -> 210 000 lignes dans LINE_VIS_HEA ;
--    - lots de 100 000 lignes en WITH (TABLOCK) (insertion minimalement
--      journalisée en mode de récupération SIMPLE) au lieu de 10 000.
--  LIN_UID contient le compteur global -> clé primaire garantie unique.
--
--  Volume disque : ~1,7 Go pour la table (clé primaire seule, sans index
--  secondaire). Durée : quelques minutes sur SQL Server Express.
-- =============================================================================

-- Obligatoire depuis l'index IX_LINE_VIS_EDG_DIR_HASH (LINE_VIS_EDG_IndexHash.sql) :
-- sans ces options, l'INSERT echoue ("SET options have incorrect settings").
-- sqlcmd met QUOTED_IDENTIFIER a OFF par defaut (sauf avec l'option -I).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

-- 1. Vider la table (optionnel)
TRUNCATE TABLE dbo.LINE_VIS_EDG;

-- 2. Générer les lignes avec des clés primaires uniques garanties
DECLARE @i INT = 1
DECLARE @BatchSize INT = 100000
DECLARE @TotalRows INT = 7000000
DECLARE @NbLnaUid  INT = 210000   -- nb de LNA_UID distincts (= nb de lignes de LINE_VIS_HEA)
DECLARE @GlobalCounter INT = 1    -- Compteur global pour garantir l'unicité absolue

-- Table de numéros 1..@BatchSize, construite UNE seule fois : la regénérer
-- à chaque lot (ROW_NUMBER sur un produit croisé de vues système) coûtait
-- plus d'une minute de CPU par lot de 100 000 lignes.
IF OBJECT_ID('tempdb..#Nums') IS NOT NULL DROP TABLE #Nums
CREATE TABLE #Nums (n INT NOT NULL PRIMARY KEY)
INSERT INTO #Nums (n)
SELECT TOP (@BatchSize) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
FROM sys.all_objects a CROSS JOIN sys.all_objects b

PRINT 'Début de l''insertion de ' + CAST(@TotalRows AS VARCHAR) + ' lignes...'

WHILE @i <= @TotalRows
BEGIN
    INSERT INTO dbo.LINE_VIS_EDG WITH (TABLOCK) (
        LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4,
        EDG_DIR, EDG_1, EDG_2, EDG_3, EDG_4,
        TXN_DTA, PRX_TXN_DTA
    )
    SELECT
        -- LNA_UID (@NbLnaUid = 210 000 valeurs possibles) :
        -- préfixe (5 valeurs) + '_' + numéro sur 5 chiffres (42 000 valeurs).
        -- Le couple (préfixe, numéro) ne dépend que de compteur % 210 000
        -- -> exactement 210 000 LNA_UID distincts, p. ex. 'ABC_LIS_PCE_00017'.
        CASE ((@GlobalCounter + n - 1) % 5 + 1)
            WHEN 1 THEN 'ABN_HCL_VALINP'
            WHEN 2 THEN 'ABC_LIS_PCE'
            WHEN 3 THEN 'DEF_TRN_PROC'
            WHEN 4 THEN 'GHI_DAT_LOAD'
            ELSE 'JKL_MIG_TOOL'
        END + '_' + RIGHT('00000' + CAST(((@GlobalCounter + n - 1) % @NbLnaUid) / 5 AS VARCHAR(5)), 5),

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
    FROM #Nums AS Numbers
    WHERE (@GlobalCounter + n - 1) <= @TotalRows
    OPTION (MAXDOP 1)

    SET @i = @i + @BatchSize
    SET @GlobalCounter = @GlobalCounter + @BatchSize
    DECLARE @msgLot VARCHAR(200) = 'Lot ' + CAST(@i / @BatchSize AS VARCHAR) + '/' + CAST(CEILING(@TotalRows * 1.0 / @BatchSize) AS VARCHAR) +
        ' : ' + CAST(@i - @BatchSize AS VARCHAR) + ' à ' + CAST(@i - 1 AS VARCHAR) + ' lignes insérées'
    RAISERROR(@msgLot, 0, 1) WITH NOWAIT  -- affiche la progression tout de suite (PRINT est mis en tampon)
END

-- 3. Vérification finale
DECLARE @FinalCount INT
SELECT @FinalCount = COUNT(*) FROM dbo.LINE_VIS_EDG
PRINT 'Nombre total : ' + CAST(@FinalCount AS VARCHAR)
GO

-- 4. Rafraichir le cache d'agregats dbo.LINE_VIS_EDG_Stats (plus lu par
--    LINE_VIS_NodesList depuis la version des photos M1, garde a jour quand meme).
-- 5. Ensuite : lancer LINE_VIS_HEA_data.sql pour remplir LINE_VIS_HEA.
IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG_RefreshStats]') IS NOT NULL
    EXEC dbo.LINE_VIS_EDG_RefreshStats;
GO
