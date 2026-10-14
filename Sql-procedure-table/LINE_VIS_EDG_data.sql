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
--    - insertion PAR LOTS de 100 000 lignes (70 lots), chaque lot dans sa
--      propre transaction.
--  LIN_UID contient le compteur global -> clé primaire garantie unique.
--
--  Journal : la base est en mode SIMPLE -> la place du journal est
--  réutilisée dès qu'une transaction est validée ; le journal ne grossit
--  donc qu'à la taille d'UN lot, et non des 7 M lignes. (L'ancienne version
--  insérait les 7 M lignes en une seule transaction : le journal de
--  RestitutionGrapheProd était monté à 7,1 Go.)
--    - CHECKPOINT après chaque lot : libère tout de suite la place du lot
--      dans le journal, sans attendre le checkpoint automatique ;
--    - l'index IX_LINE_VIS_EDG_DIR_HASH est désactivé pendant le chargement
--      (sinon chaque ligne insérée le met à jour et écrit dans le journal),
--      puis reconstruit en une passe à la fin (minimalement journalisé en
--      mode SIMPLE) ;
--    - TABLOCK : insertion plus rapide, minimalement journalisée dans la
--      table vide.
--  Plus de "tout ou rien" : en cas d'erreur, les lots déjà validés restent
--  dans la table. Le script recommence par un TRUNCATE : il suffit de le
--  relancer. ATTENTION : tant que le script n'est pas allé au bout, l'index
--  IX_LINE_VIS_EDG_DIR_HASH reste DESACTIVE et les procedures de lineage
--  (FORCESEEK sur cet index) echouent. Relancer le script, ou reconstruire
--  l'index a la main :
--      ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG REBUILD;
--
--  Volume disque : ~2,5 Go pour la table + ~1,1 Go pour l'index.
--  Durée : quelques minutes sur SQL Server Express.
-- =============================================================================

-- Obligatoire depuis l'index IX_LINE_VIS_EDG_DIR_HASH (LINE_VIS_EDG_IndexHash.sql) :
-- sans ces options, l'INSERT echoue ("SET options have incorrect settings").
-- sqlcmd met QUOTED_IDENTIFIER a OFF par defaut (sauf avec l'option -I).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

-- 1. Vider la table (TRUNCATE : quasiment rien dans le journal,
--    contrairement à un DELETE qui y écrirait chaque ligne)
TRUNCATE TABLE dbo.LINE_VIS_EDG;
GO

-- 2. Désactiver l'index de recherche pendant le chargement (il est
--    reconstruit à l'étape 4). Absent si LINE_VIS_EDG_IndexHash.sql n'a pas
--    encore été lancé : rien à faire.
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH'
             AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG DISABLE;
GO

-- 3. Insérer les 7 000 000 lignes par lots de 100 000
SET XACT_ABORT ON;   -- une erreur annule le lot en cours et arrête le script
SET NOCOUNT ON;      -- pas de "(100000 rows affected)" à chaque lot

DECLARE @TotalRows INT = 7000000
DECLARE @NbLnaUid  INT = 210000   -- nb de LNA_UID distincts (= nb de lignes de LINE_VIS_HEA)
DECLARE @BatchSize INT = 100000   -- lignes par lot (= par transaction)
DECLARE @Debut     DATETIME2 = SYSDATETIME()
DECLARE @DebutLot  INT = 0        -- compteur c de la dernière ligne du lot précédent
DECLARE @NumLot    INT = 0
DECLARE @Message   VARCHAR(200)

PRINT 'Début de l''insertion de ' + CAST(@TotalRows AS VARCHAR) + ' lignes par lots de '
    + CAST(@BatchSize AS VARCHAR) + '...'

WHILE @DebutLot < @TotalRows
BEGIN
SET @NumLot += 1

BEGIN TRANSACTION;

-- Générateur de nombres 1..@BatchSize sans table : 10 chiffres combinés
-- 5 fois (10^5 combinaisons), coupés à @BatchSize par TOP, puis décalés
-- de @DebutLot -> compteur global c = @DebutLot + 1 .. @DebutLot + @BatchSize.
WITH Chiffres (d) AS (
    SELECT d FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v (d)
),
Compteur (c) AS (
    SELECT TOP (@BatchSize) @DebutLot + ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM Chiffres a CROSS JOIN Chiffres b CROSS JOIN Chiffres c2 CROSS JOIN Chiffres d
         CROSS JOIN Chiffres e
),
Numbers (c, n) AS (
    -- c : compteur global 1..7 000 000
    -- n : numéro de la ligne dans son lot de 100 000 (1..100 000)
    SELECT CAST(c AS INT), CAST((c - 1) % @BatchSize + 1 AS INT)
    FROM Compteur
    WHERE c <= @TotalRows          -- dernier lot incomplet si @TotalRows
)                                  -- n'est pas un multiple de @BatchSize
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

-- Lot validé : sa place dans le journal peut être réutilisée tout de suite
CHECKPOINT;

SET @DebutLot += @BatchSize

-- Avancement tous les 10 lots (RAISERROR ... WITH NOWAIT : affiché tout
-- de suite, alors que PRINT attend la fin du script)
IF @NumLot % 10 = 0
BEGIN
    SET @Message = CAST(@NumLot AS VARCHAR) + ' lots ('
        + CAST(CASE WHEN @DebutLot > @TotalRows THEN @TotalRows ELSE @DebutLot END AS VARCHAR)
        + ' lignes), ' + CAST(DATEDIFF(SECOND, @Debut, SYSDATETIME()) AS VARCHAR) + ' s'
    RAISERROR (@Message, 0, 1) WITH NOWAIT
END
END

PRINT 'Insertion terminée en ' + CAST(DATEDIFF(SECOND, @Debut, SYSDATETIME()) AS VARCHAR) + ' s.'

-- Vérification
DECLARE @FinalCount INT
SELECT @FinalCount = COUNT(*) FROM dbo.LINE_VIS_EDG
PRINT 'Nombre total : ' + CAST(@FinalCount AS VARCHAR)
GO

-- 4. Reconstruire l'index désactivé à l'étape 2 (une seule passe ; garde
--    la compression choisie à sa création)
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH'
             AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
BEGIN
    PRINT 'Reconstruction de IX_LINE_VIS_EDG_DIR_HASH...';
    ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG REBUILD WITH (SORT_IN_TEMPDB = ON);
END
GO

-- 5. Rafraichir le cache d'agregats dbo.LINE_VIS_EDG_Stats (plus lu par
--    LINE_VIS_NodesList depuis la version des photos M1, garde a jour quand meme).
-- 6. Ensuite : lancer LINE_VIS_HEA_data.sql pour remplir LINE_VIS_HEA.
IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG_RefreshStats]') IS NOT NULL
    EXEC dbo.LINE_VIS_EDG_RefreshStats;
GO
