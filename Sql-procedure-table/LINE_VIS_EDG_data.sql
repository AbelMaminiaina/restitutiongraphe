-- =============================================================================
--  Génération de données de test pour dbo.LINE_VIS_EDG
--  Base : RestitutionGrapheProd
--
--  Transcrit des captures IMG_5677..IMG_5680, puis adapté :
--    - table cible LINE_VIS_EDG (et non LINE_VIS_EDG_2) ;
--    - volume : 7 000 000 lignes (compteur c = 1..7000000) ;
--    - LNA_UID : 210 000 valeurs distinctes (5 préfixes x 42 000 numéros),
--      soit ~33 lignes par LNA_UID. LINE_VIS_HEA_data.sql crée ensuite une
--      ligne d'en-tête par LNA_UID distinct -> 210 000 lignes dans LINE_VIS_HEA ;
--    - insertion en UNE SEULE TRANSACTION : un seul INSERT ... SELECT de
--      7 M lignes (plus de boucle par lots), l'index IX_LINE_VIS_EDG_DIR_HASH
--      restant actif.
--  LIN_UID contient le compteur global -> clé primaire garantie unique.
--
--  Journal : la table est vidée (TRUNCATE) juste avant, et l'INSERT se fait
--  WITH (TABLOCK) sur une table VIDE -> insertion minimalement journalisée
--  (seules les allocations de pages vont dans le journal) : quelques
--  centaines de Mo de journal au lieu de ~8-10 Go en journalisation complète.
--  En échange, SQL Server trie les 7 M lignes dans l'ordre de la clé avant
--  de les écrire : prévoir ~2 Go libres dans tempdb.
--  Tout ou rien : en cas d'erreur, la transaction est annulée et la table
--  reste vide.
--
--  Volume disque : ~1,7 Go pour la table + quelques centaines de Mo pour
--  l'index. Durée : quelques minutes sur SQL Server Express.
-- =============================================================================

-- Obligatoire depuis l'index IX_LINE_VIS_EDG_DIR_HASH (LINE_VIS_EDG_IndexHash.sql) :
-- sans ces options, l'INSERT echoue ("SET options have incorrect settings").
-- sqlcmd met QUOTED_IDENTIFIER a OFF par defaut (sauf avec l'option -I).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

-- 1. Vider la table : indispensable pour la journalisation minimale
--    (TABLOCK sur une table vide)
TRUNCATE TABLE dbo.LINE_VIS_EDG;
GO

-- 2. Insérer les 7 000 000 lignes en une seule transaction
SET XACT_ABORT ON;   -- toute erreur annule la transaction entière

DECLARE @TotalRows INT = 7000000
DECLARE @NbLnaUid  INT = 210000   -- nb de LNA_UID distincts (= nb de lignes de LINE_VIS_HEA)
DECLARE @BatchSize INT = 100000   -- taille des anciens lots : sert seulement à
                                  -- garder les mêmes LIN_UID qu'avant (suffixe n)
DECLARE @Debut DATETIME2 = SYSDATETIME()

PRINT 'Début de l''insertion de ' + CAST(@TotalRows AS VARCHAR) + ' lignes (une seule transaction)...'

BEGIN TRANSACTION;

-- Générateur de nombres 1..@TotalRows sans table : 10 chiffres combinés
-- 7 fois (10^7 combinaisons), coupés à @TotalRows par TOP.
WITH Chiffres (d) AS (
    SELECT d FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v (d)
),
Compteur (c) AS (
    SELECT TOP (@TotalRows) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM Chiffres a CROSS JOIN Chiffres b CROSS JOIN Chiffres c2 CROSS JOIN Chiffres d
         CROSS JOIN Chiffres e CROSS JOIN Chiffres f CROSS JOIN Chiffres g
),
Numbers (c, n) AS (
    -- c : compteur global 1..7 000 000
    -- n : numéro de la ligne dans son ancien lot de 100 000 (1..100 000)
    SELECT CAST(c AS INT), CAST((c - 1) % @BatchSize + 1 AS INT) FROM Compteur
)
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
    CASE (c % 5 + 1)
        WHEN 1 THEN 'ABN_HCL_VALINP'
        WHEN 2 THEN 'ABC_LIS_PCE'
        WHEN 3 THEN 'DEF_TRN_PROC'
        WHEN 4 THEN 'GHI_DAT_LOAD'
        ELSE 'JKL_MIG_TOOL'
    END + '_' + RIGHT('00000' + CAST((c % @NbLnaUid) / 5 AS VARCHAR(5)), 5),

    -- LIN_UID (unique grâce au compteur global + suffixe unique)
    CASE (c % 4 + 1)
        WHEN 1 THEN 'SPSW_HCL_ADD_DC2RG2_' + CAST(c AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
        WHEN 2 THEN 'CCTW_CTRCAR_' + CAST(c AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
        WHEN 3 THEN 'CCTX_CTRCAR_PPD_' + CAST(c AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
        ELSE 'DAT_MIG_' + CAST(c AS VARCHAR(10)) + '_' + CAST(n AS VARCHAR(5))
    END,

    -- DTA_1 (3 valeurs possibles)
    CASE (c % 3 + 1)
        WHEN 1 THEN 'FIADODSWRK'
        WHEN 2 THEN 'FIADODSOUT'
        ELSE 'FIADODS' + CAST(c % 10 AS VARCHAR(2))
    END,

    -- DTA_2 (toujours 'ZJ')
    'ZJ',

    -- DTA_3 (format _XXXXXXXX.YYYY.ZZZZ)
    LEFT('_' + SUBSTRING(CONVERT(VARCHAR(36), NEWID()), 1, 8) + '.' +
    CASE (c % 5 + 1)
        WHEN 1 THEN 'SPSS_LS2DC2'
        WHEN 2 THEN 'CCTS_CTRCAR_ADD_DWH'
        WHEN 3 THEN 'DAT_MIG_PROC'
        WHEN 4 THEN 'TRN_VAL_INP'
        ELSE 'WRK_FLOW'
    END + '.' +
    CASE (c % 4 + 1)
        WHEN 1 THEN 'LS2_REFDCP'
        WHEN 2 THEN 'ABC_LIS_PCE'
        WHEN 3 THEN 'DEF_TRN_PROC'
        ELSE 'GHI_DAT_LOAD'
    END, 8000),

    -- DTA_4 (format xDI_IBI_XXXX_YYY.WRK.ZZZ.ZJ)
    LEFT('xDI_IBI' +
    CASE (c % 3 + 1)
        WHEN 1 THEN 'S_HIRRBT'
        WHEN 2 THEN 'C_INSCTR'
        ELSE 'T_MIG'
    END + '_' + CAST(c % 1000 AS VARCHAR(4)) + '_WRK.' +
    CAST(c % 100 AS VARCHAR(3)) + '.ZJ', 1000),

    -- EDG_DIR (O ou I, alterné)
    CASE (c % 2) WHEN 0 THEN 'O' ELSE 'I' END,

    -- EDG_1 (similaire à DTA_4)
    LEFT('xDI_IBI' +
    CASE (c % 3 + 1)
        WHEN 1 THEN 'S_HIRRBT'
        WHEN 2 THEN 'C_INSCTR'
        ELSE 'T_MIG'
    END + '_' + CAST(c % 1000 AS VARCHAR(4)) + '_WRK.' +
    CAST(c % 100 AS VARCHAR(3)) + '.ZJ', 1000),

    -- EDG_2 (NULL ou valeur)
    CASE (c % 2) WHEN 0 THEN NULL ELSE LEFT('EDG2_' + CAST(c % 100 AS VARCHAR(3)), 1000) END,

    -- EDG_3 (NULL ou valeur aléatoire)
    CASE (c % 3) WHEN 0 THEN NULL ELSE LEFT('EDG3_' + SUBSTRING(CONVERT(VARCHAR(36), NEWID()), 1, 8), 8000) END,

    -- EDG_4 (NULL ou valeur)
    CASE (c % 4) WHEN 0 THEN NULL ELSE LEFT('EDG4_' + CAST(c % 100 AS VARCHAR(3)), 1000) END,

    -- TXN_DTA (JSON ou NULL)
    CASE (c % 5) WHEN 0 THEN NULL ELSE '{"status": "OK", "id": ' + CAST(c AS VARCHAR(10)) + '}' END,

    -- PRX_TXN_DTA (XML ou NULL)
    CASE (c % 5) WHEN 0 THEN NULL ELSE '<data><value>' + CAST(c AS VARCHAR(10)) + '</value></data>' END
FROM Numbers
OPTION (MAXDOP 1);

COMMIT TRANSACTION;

PRINT 'Insertion validée en ' + CAST(DATEDIFF(SECOND, @Debut, SYSDATETIME()) AS VARCHAR) + ' s.'

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
