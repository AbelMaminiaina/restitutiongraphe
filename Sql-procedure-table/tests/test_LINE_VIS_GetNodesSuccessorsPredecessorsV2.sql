-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh  (deploie schema + LINE_VIS_HEA + procedure
--           puis execute ce fichier).
--
--  Principe : fixture deterministe de quelques aretes reparties en 2 "noeuds"
--  (jeux DTA_1..DTA_4), puis appels de la procedure et verification du nombre
--  de lignes, de TotalLignes, du filtre EDG_DIR = @p_type, de l'exclusion des
--  aretes sans en-tete LINE_VIS_HEA (INNER JOIN), de @p_useEdg, de @p_maxres,
--  du tri et de la colonne calculee CURRENT_NODE.
--
--  Sortie : une ligne PASS / FAIL par assertion ; THROW si au moins un echec.
--
--  Fixture LINE_VIS_EDG (LNA_UID / LIN_UID / EDG_DIR / DTA_1..4 / EDG_1..4) :
--    R1  LNA_A / L1 / O / c1,t1,s1,e1 / n1,n2,n3,n4   -> noeud N1, succ.
--    R2  LNA_A / L2 / O / c1,t1,s1,e1 / NULL          -> noeud N1, succ.
--    R3  LNA_B / L3 / I / c1,t1,s1,e1 / NULL          -> noeud N1, pred.
--    R4  LNA_A / L4 / O / c2,t2,s2,e2 / NULL          -> noeud N2, succ.
--    R5  LNA_C / L5 / O / c1,t1,s1,e1 / NULL          -> LNA_C absent de HEA
--    R6  LNA_B / L6 / O / n1,n2,n3,n4 / NULL          -> cible de @p_useEdg=1
--
--  Fixture LINE_VIS_HEA : LNA_A et LNA_B seulement (pas LNA_C).
-- =============================================================================
:setvar TestDb "RestitutionGrapheProd_Test"

USE [$(TestDb)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-------------------------------------------------------------------------------
-- Fixture
-------------------------------------------------------------------------------
TRUNCATE TABLE dbo.LINE_VIS_EDG;
DELETE FROM dbo.LINE_VIS_HEA;

INSERT INTO dbo.LINE_VIS_EDG
    (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR,
     EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
VALUES
    ('LNA_A', 'L1', 'c1', 't1', 's1', 'e1', 'O', 'n1', 'n2', 'n3', 'n4', NULL, NULL),
    ('LNA_A', 'L2', 'c1', 't1', 's1', 'e1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_B', 'L3', 'c1', 't1', 's1', 'e1', 'I', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_A', 'L4', 'c2', 't2', 's2', 'e2', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_C', 'L5', 'c1', 't1', 's1', 'e1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_B', 'L6', 'n1', 'n2', 'n3', 'n4', 'O', NULL, NULL, NULL, NULL, NULL, NULL);

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_A', 'A1', 'PCK_A', 'EXE_A', 'v1.0', 'PROD', '2024-01-02T03:04:05', '2024-01-02T03:04:05', 'TEC_A', 'lna1', 1),
    ('LNA_B', 'B1', 'PCK_B', 'EXE_B', 'v2.0', 'DEV',  '2024-02-03T04:05:06', '2024-02-03T04:05:06', 'TEC_B', 'lna2', 0);
GO

-------------------------------------------------------------------------------
-- Table de reception (colonnes = sortie de la procedure)
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @n INT, @t INT, @ok BIT;

DECLARE @res TABLE (
    LNA_UID VARCHAR(200), LIN_UID VARCHAR(500), EDG_DIR CHAR(1),
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    TXN_DTA VARCHAR(MAX),
    EDG_1 VARCHAR(1000), EDG_2 VARCHAR(1000), EDG_3 VARCHAR(8000), EDG_4 VARCHAR(1000),
    PRX_TXN_DTA VARCHAR(MAX),
    RON_APP VARCHAR(4), PCK_PGM_NME VARCHAR(500), EXE_PGM_NME VARCHAR(500),
    VRS_EXE_PGM VARCHAR(100), APP_ENV VARCHAR(20),
    DLY_PGM_TSP DATETIME2, LNA_TSP DATETIME2,
    PGM_TEC VARCHAR(20), VRS_LNA_TOO VARCHAR(100), TUS_IND INT,
    CURRENT_NODE VARCHAR(MAX), TotalLignes INT
);

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : noeud N1, successeurs (@p_type = O) ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
    @p_lnauid = 'LNA_A', @p_linuid = 'L1', @p_edgdir = 'O', @p_type = 'O';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 2 PRINT '  PASS 1.1  2 lignes (R1 + R2 ; R5 exclu car LNA_C absent de HEA)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  attendu 2, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 2 AND NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes <> 2)
    PRINT '  PASS 1.2  TotalLignes = 2';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  TotalLignes attendu 2, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L5') THEN 0 ELSE 1 END;
IF @ok = 1 PRINT '  PASS 1.3  R5 (sans en-tete) exclu par l''INNER JOIN LINE_VIS_HEA';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  R5 ne devrait pas apparaitre'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L1' AND CURRENT_NODE = 'n4.n3.n2.n1')
               AND EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L2' AND CURRENT_NODE = '')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.4  CURRENT_NODE : "n4.n3.n2.n1" (R1) et "" (R2)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.4  CURRENT_NODE inattendu'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L1'
                            AND RON_APP = 'A1' AND APP_ENV = 'PROD' AND TUS_IND = 1) THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.5  colonnes LINE_VIS_HEA jointes (RON_APP / APP_ENV / TUS_IND)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.5  jointure LINE_VIS_HEA incorrecte'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : noeud N1, predecesseurs (@p_type = I) ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
    @p_lnauid = 'LNA_A', @p_linuid = 'L1', @p_edgdir = 'O', @p_type = 'I';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 AND EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L3' AND EDG_DIR = 'I')
    PRINT '  PASS 2.1  1 ligne (R3), EDG_DIR = I';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  attendu 1 ligne R3, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 1 PRINT '  PASS 2.2  TotalLignes = 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.2  TotalLignes attendu 1, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : @p_maxres = 1 sur le noeud N1 (2 successeurs) ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
    @p_lnauid = 'LNA_A', @p_linuid = 'L1', @p_edgdir = 'O', @p_type = 'O', @p_maxres = 1;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 PRINT '  PASS 3.1  @p_maxres = 1 respecte';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  attendu 1, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 2 PRINT '  PASS 3.2  TotalLignes = 2 malgre la limite a 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.2  TotalLignes attendu 2, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : @p_useEdg = 1 (coordonnees lues sur EDG_1..EDG_4 de R1) ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
    @p_lnauid = 'LNA_A', @p_linuid = 'L1', @p_edgdir = 'O', @p_type = 'O', @p_useEdg = 1;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 AND EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L6')
    PRINT '  PASS 4.1  1 ligne (R6 : DTA_1..4 = n1,n2,n3,n4)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  attendu 1 ligne R6, obtenu ' + CAST(@n AS VARCHAR); END

-------------------------------------------------------------------------------
PRINT '--- TEST 5 : noeud inexistant => coordonnees NULL => toutes les aretes O ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
    @p_lnauid = 'NOPE', @p_linuid = 'NOPE', @p_edgdir = 'O', @p_type = 'O';

-- aretes O ayant un en-tete : R1, R2, R4 (LNA_A), R6 (LNA_B) ; R5 exclu (LNA_C).
SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 4 PRINT '  PASS 5.1  4 lignes (R1,R2,R4,R6 ; R5 exclu faute d''en-tete)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.1  attendu 4, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 4 PRINT '  PASS 5.2  TotalLignes = 4';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.2  TotalLignes attendu 4, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-- tri : ORDER BY DTA_1..4 => 'c1' avant 'c2' avant 'n1'
SET @ok = CASE WHEN (SELECT TOP 1 DTA_1 FROM @res ORDER BY DTA_1, DTA_2, DTA_3, DTA_4) = 'c1'
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.3  tri ORDER BY DTA_1..DTA_4 respecte';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.3  ordre de tri inattendu'; END

-------------------------------------------------------------------------------
PRINT '';
IF @fail = 0
    PRINT '>>> RESULTAT : TOUS LES TESTS PASSENT';
ELSE
BEGIN
    DECLARE @msg VARCHAR(200) = '>>> RESULTAT : ' + CAST(@fail AS VARCHAR) + ' assertion(s) en echec';
    PRINT @msg;
    THROW 50001, @msg, 1;
END
GO
