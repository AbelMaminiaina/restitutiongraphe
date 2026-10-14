-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_Impact
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Graphe de la fixture (noeud = colonne.TABLE / schema / environnement) :
--
--    UP.colU (sch0/PROD) --> S.col1 (sch1/PROD)        [ligne 'I' de S, LNA_1]
--
--    S.col1 --> MID.colA  (sch1/PROD)   LNA_1 + LNA_1b (2 executions)
--    S.col1 --> MID.colB  (sch1/PROD)   LNA_1
--    MID.colA --> OUT.colX (sch2/PROD)  LNA_2
--    MID.colB --> OUT.colY (sch2/PROD)  LNA_2
--    OUT.colX --> FIN.colZ (sch2/DEV)   LNA_2
--
--  Programmes (LINE_VIS_HEA) :
--    LNA_1, LNA_1b : APP1 / PCK1 / EXE1 / PROD (2 executions du meme programme)
--    LNA_2         : APP2 / PCK2 / EXE2 / PROD
--
--  Sortie : une ligne PASS / FAIL par assertion ; THROW si au moins un echec.
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
    ('LNA_1',  'L1', 'col1', 'S',   'sch1', 'PROD', 'O', 'colA', 'MID', 'sch1', 'PROD', NULL, NULL),
    ('LNA_1b', 'L2', 'col1', 'S',   'sch1', 'PROD', 'O', 'colA', 'MID', 'sch1', 'PROD', NULL, NULL),
    ('LNA_1',  'L3', 'col1', 'S',   'sch1', 'PROD', 'O', 'colB', 'MID', 'sch1', 'PROD', NULL, NULL),
    ('LNA_2',  'L4', 'colA', 'MID', 'sch1', 'PROD', 'O', 'colX', 'OUT', 'sch2', 'PROD', NULL, NULL),
    ('LNA_2',  'L5', 'colB', 'MID', 'sch1', 'PROD', 'O', 'colY', 'OUT', 'sch2', 'PROD', NULL, NULL),
    ('LNA_2',  'L6', 'colX', 'OUT', 'sch2', 'PROD', 'O', 'colZ', 'FIN', 'sch2', 'DEV',  NULL, NULL),
    ('LNA_1',  'L7', 'col1', 'S',   'sch1', 'PROD', 'I', 'colU', 'UP',  'sch0', 'PROD', NULL, NULL);

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_1',  'APP1', 'PCK1', 'EXE1', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_1b', 'APP1', 'PCK1', 'EXE1', 'v1', 'PROD', '2024-03-01', '2024-03-01', 'T', 'l', 1),
    ('LNA_2',  'APP2', 'PCK2', 'EXE2', 'v1', 'PROD', '2024-02-01', '2024-02-01', 'T', 'l', 1);
GO

-------------------------------------------------------------------------------
-- Tables de reception (une par jeu de resultats ; chaque jeu est demande
-- seul avec @p_sortie, INSERT ... EXEC ne sachant lire qu'un jeu).
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @ok BIT;

DECLARE @res TABLE (
    NOEUD_TROUVE BIT, NB_NOEUDS INT, NB_TABLES INT, NB_SCHEMAS INT,
    NB_ENVIRONNEMENTS INT, NB_APPLICATIONS INT, NB_PROGRAMMES INT,
    NB_EXECUTIONS INT, PROFONDEUR INT, TRONQUE BIT
);
DECLARE @obj TABLE (
    SENS CHAR(1), DTA_4 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_2 VARCHAR(1000),
    NB_COLONNES INT, NIVEAU_MIN INT
);
DECLARE @pgm TABLE (
    SENS CHAR(1), RON_APP VARCHAR(4), PCK_PGM_NME VARCHAR(500), EXE_PGM_NME VARCHAR(500),
    APP_ENV VARCHAR(20), NB_EXECUTIONS INT, NB_LIENS INT, NIVEAU_MIN INT,
    DERNIERE_EXECUTION DATETIME2
);

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : impact aval depuis S.col1 ---';
INSERT INTO @res EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sortie = 'R';
INSERT INTO @obj EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sortie = 'O';
INSERT INTO @pgm EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sortie = 'P';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res
                            WHERE NOEUD_TROUVE = 1 AND NB_NOEUDS = 5 AND NB_TABLES = 3
                              AND NB_SCHEMAS = 3 AND NB_ENVIRONNEMENTS = 2
                              AND NB_APPLICATIONS = 2 AND NB_PROGRAMMES = 2
                              AND NB_EXECUTIONS = 3 AND PROFONDEUR = 3 AND TRONQUE = 0)
               AND (SELECT COUNT(*) FROM @res) = 1
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.1  resume : 5 colonnes, 3 tables, 3 schemas, 2 env., 2 applis, 2 programmes, 3 executions, profondeur 3';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  resume inattendu'; SELECT * FROM @res; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @obj) = 3
               AND EXISTS (SELECT 1 FROM @obj WHERE DTA_2 = 'MID' AND NB_COLONNES = 2 AND NIVEAU_MIN = 1 AND SENS = 'O')
               AND EXISTS (SELECT 1 FROM @obj WHERE DTA_2 = 'OUT' AND NB_COLONNES = 2 AND NIVEAU_MIN = 2)
               AND EXISTS (SELECT 1 FROM @obj WHERE DTA_2 = 'FIN' AND NB_COLONNES = 1 AND NIVEAU_MIN = 3 AND DTA_4 = 'DEV')
               AND NOT EXISTS (SELECT 1 FROM @obj WHERE DTA_2 IN ('S', 'UP'))
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.2  objets : MID (2 col., niv. 1), OUT (2, niv. 2), FIN (1, niv. 3) ; ni S (depart) ni UP (amont)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  objets inattendus'; SELECT * FROM @obj; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @pgm) = 2
               AND EXISTS (SELECT 1 FROM @pgm WHERE RON_APP = 'APP1' AND EXE_PGM_NME = 'EXE1'
                             AND NB_EXECUTIONS = 2 AND NB_LIENS = 3 AND NIVEAU_MIN = 1
                             AND DERNIERE_EXECUTION = '2024-03-01')
               AND EXISTS (SELECT 1 FROM @pgm WHERE RON_APP = 'APP2' AND EXE_PGM_NME = 'EXE2'
                             AND NB_EXECUTIONS = 1 AND NB_LIENS = 3 AND NIVEAU_MIN = 2)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.3  programmes : APP1 (2 executions, 3 liens, niv. 1, derniere 2024-03-01), APP2 (1, 3, niv. 2)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  programmes inattendus'; SELECT * FROM @pgm; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : amont (I) ---';
DELETE FROM @res; DELETE FROM @obj; DELETE FROM @pgm;
INSERT INTO @res EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sens = 'I', @p_sortie = 'R';
INSERT INTO @obj EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sens = 'I', @p_sortie = 'O';
INSERT INTO @pgm EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sens = 'I', @p_sortie = 'P';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE NB_NOEUDS = 1 AND NB_TABLES = 1 AND NB_PROGRAMMES = 1 AND PROFONDEUR = 1)
               AND EXISTS (SELECT 1 FROM @obj WHERE DTA_2 = 'UP' AND SENS = 'I')
               AND EXISTS (SELECT 1 FROM @pgm WHERE RON_APP = 'APP1' AND SENS = 'I' AND NB_EXECUTIONS = 1)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  amont : UP.colU via APP1 (1 execution)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  impact amont inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : profondeur 1 ---';
DELETE FROM @res; DELETE FROM @pgm;
INSERT INTO @res EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_profondeur = 1, @p_sortie = 'R';
INSERT INTO @pgm EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_profondeur = 1, @p_sortie = 'P';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE NB_NOEUDS = 2 AND NB_TABLES = 1 AND PROFONDEUR = 1)
               AND (SELECT COUNT(*) FROM @pgm) = 1
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.1  MID.colA + MID.colB, seul APP1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  impact en profondeur 1 inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : limite @p_maxnoeuds = 2 ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_maxnoeuds = 2, @p_sortie = 'R';

IF EXISTS (SELECT 1 FROM @res WHERE NB_NOEUDS = 1 AND TRONQUE = 1)
    PRINT '  PASS 4.1  1 noeud en plus du depart, TRONQUE = 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  limite non signalee'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 5 : noeud de depart introuvable ---';
DELETE FROM @res; DELETE FROM @obj; DELETE FROM @pgm;
INSERT INTO @res EXEC dbo.LINE_VIS_Impact 'LNA_X', 'Lx', 'O', @p_sortie = 'R';
INSERT INTO @obj EXEC dbo.LINE_VIS_Impact 'LNA_X', 'Lx', 'O', @p_sortie = 'O';
INSERT INTO @pgm EXEC dbo.LINE_VIS_Impact 'LNA_X', 'Lx', 'O', @p_sortie = 'P';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE NOEUD_TROUVE = 0 AND NB_NOEUDS = 0 AND PROFONDEUR = 0)
               AND (SELECT COUNT(*) FROM @res) = 1
               AND NOT EXISTS (SELECT 1 FROM @obj)
               AND NOT EXISTS (SELECT 1 FROM @pgm)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.1  resume avec NOEUD_TROUVE = 0, objets et programmes vides';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.1  resultat inattendu pour un noeud inconnu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 6 : parametres invalides ---';
SET @ok = 0;
BEGIN TRY
    EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sortie = 'X';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 SET @ok = 1;
END CATCH
IF @ok = 1 PRINT '  PASS 6.1  erreur 50002 pour @p_sortie = X';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.1  @p_sortie = X aurait du lever l''erreur 50002'; END

SET @ok = 0;
BEGIN TRY
    EXEC dbo.LINE_VIS_Impact 'LNA_1', 'L1', 'O', @p_sens = 'X';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 SET @ok = 1;
END CATCH
IF @ok = 1 PRINT '  PASS 6.2  erreur 50001 pour @p_sens = X';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.2  @p_sens = X aurait du lever l''erreur 50001'; END

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
