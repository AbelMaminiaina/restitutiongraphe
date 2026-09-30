-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_NodeById
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Principe : fixture de 3 aretes + 1 en-tete, puis verification de la ligne
--  renvoyee (cle primaire exacte), de la jointure LINE_VIS_HEA et des deux
--  libelles calcules SourceNode / LinkedNode.
--
--  Sortie : une ligne PASS / FAIL par assertion ; THROW si au moins un echec.
--
--  Fixture LINE_VIS_EDG (LNA_UID / LIN_UID / EDG_DIR / DTA_1..4 / EDG_1..4) :
--    R1  LNA_A / L1 / O / c1,t1,s1,e1 / n1,n2,n3,n4
--    R2  LNA_A / L1 / I / c1,NULL,'',e1 / NULL      (parties vides ignorees)
--    R3  LNA_Z / L9 / O / c9,t9,s9,e9 / NULL        (LNA_Z absent de HEA)
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
    ('LNA_A', 'L1', 'c1', 't1', 's1', 'e1', 'O', 'n1', 'n2', 'n3', 'n4', 'txn', 'prx'),
    ('LNA_A', 'L1', 'c1', NULL, '',   'e1', 'I', NULL, NULL, NULL, NULL, NULL,  NULL),
    ('LNA_Z', 'L9', 'c9', 't9', 's9', 'e9', 'O', NULL, NULL, NULL, NULL, NULL,  NULL);

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_A', 'A1', 'PCK_A', 'EXE_A', 'v1.0', 'PROD', '2024-01-02T03:04:05', '2024-01-02T03:04:05', 'TEC_A', 'lna1', 1);
GO

-------------------------------------------------------------------------------
-- Table de reception (colonnes = sortie de la procedure)
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @n INT, @ok BIT;

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
    SourceNode VARCHAR(MAX), LinkedNode VARCHAR(MAX)
);

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : R1 (LNA_A / L1 / O) ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodeById @p_lnauid = 'LNA_A', @p_linuid = 'L1', @p_edgdir = 'O';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 PRINT '  PASS 1.1  1 ligne (cle primaire exacte, R2 de direction I exclue)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  attendu 1, obtenu ' + CAST(@n AS VARCHAR); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE SourceNode = 'e1.s1.t1.c1'
                                              AND LinkedNode = 'n4.n3.n2.n1') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.2  SourceNode = "e1.s1.t1.c1", LinkedNode = "n4.n3.n2.n1"';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  SourceNode / LinkedNode inattendus'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE RON_APP = 'A1' AND APP_ENV = 'PROD'
                                              AND TUS_IND = 1 AND TXN_DTA = 'txn') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.3  colonnes LINE_VIS_HEA jointes + TXN_DTA';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  jointure LINE_VIS_HEA incorrecte'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : R2 (LNA_A / L1 / I) : parties NULL / vides ignorees ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodeById @p_lnauid = 'LNA_A', @p_linuid = 'L1', @p_edgdir = 'I';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE SourceNode = 'e1.c1' AND LinkedNode IS NULL)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  SourceNode = "e1.c1", LinkedNode = NULL (EDG_1..4 tous vides)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  SourceNode / LinkedNode inattendus'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : R3 sans en-tete + cle inexistante => aucune ligne ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodeById @p_lnauid = 'LNA_Z', @p_linuid = 'L9', @p_edgdir = 'O';
INSERT INTO @res EXEC dbo.LINE_VIS_NodeById @p_lnauid = 'NOPE',  @p_linuid = 'NOPE', @p_edgdir = 'O';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 0 PRINT '  PASS 3.1  0 ligne (INNER JOIN LINE_VIS_HEA + cle absente)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  attendu 0, obtenu ' + CAST(@n AS VARCHAR); END

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
