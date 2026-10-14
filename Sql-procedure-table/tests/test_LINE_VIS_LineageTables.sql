-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_LineageTables
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Fixture (colonne.TABLE, schema, environnement) :
--
--    PROD : T1.a --> T2.a2   (LNA_1)     T1 -> T2 par 2 colonnes,
--           T1.b --> T2.a2   (LNA_2)     2 programmes
--           T1.a --> T1.b    (LNA_1)     lien interne a T1 : non montre
--           T2.a2 --> T4.d4  (LNA_1)
--           T2.b2 --> T3.c3  (LNA_1)     b2 n'est PAS alimentee par T1 :
--                                        T3 n'est pas en aval de T1
--           UP.u --> T1.a    (ligne 'I' de T1.a, LNA_1)
--    DEV  : T1.a --> T5.e    (LNA_1)     T1 existe aussi en DEV
--
--  Programmes : LNA_1 = EXE1, LNA_2 = EXE2.
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
    ('LNA_1', 'L1', 'a',  'T1', 's1', 'PROD', 'O', 'a2', 'T2', 's2', 'PROD', NULL, NULL),
    ('LNA_2', 'L2', 'b',  'T1', 's1', 'PROD', 'O', 'a2', 'T2', 's2', 'PROD', NULL, NULL),
    ('LNA_1', 'L3', 'a',  'T1', 's1', 'PROD', 'O', 'b',  'T1', 's1', 'PROD', NULL, NULL),
    ('LNA_1', 'L4', 'a2', 'T2', 's2', 'PROD', 'O', 'd4', 'T4', 's4', 'PROD', NULL, NULL),
    ('LNA_1', 'L5', 'b2', 'T2', 's2', 'PROD', 'O', 'c3', 'T3', 's3', 'PROD', NULL, NULL),
    ('LNA_1', 'L6', 'a',  'T1', 's1', 'PROD', 'I', 'u',  'UP', 's0', 'PROD', NULL, NULL),
    ('LNA_1', 'L7', 'a',  'T1', 's1', 'DEV',  'O', 'e',  'T5', 's5', 'DEV',  NULL, NULL);

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_1', 'APP1', 'PCK1', 'EXE1', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_2', 'APP2', 'PCK2', 'EXE2', 'v1', 'PROD', '2024-02-01', '2024-02-01', 'T', 'l', 1);
GO

-------------------------------------------------------------------------------
-- Tables de reception (une par jeu de resultats, demande seul avec @p_sortie)
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @ok BIT;

DECLARE @tab TABLE (
    TAB_ID INT, NIVEAU INT, SENS CHAR(1),
    DTA_4 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_2 VARCHAR(1000),
    NOM_TABLE VARCHAR(MAX), NB_COLONNES INT, TRONQUE BIT
);
DECLARE @lia TABLE (
    SRC_TAB_ID INT, DST_TAB_ID INT, NB_COLONNES_LIEES INT,
    NB_LIENS INT, NB_PROGRAMMES INT, PROGRAMMES VARCHAR(MAX)
);
-- Liens lisibles "T1>T2"
DECLARE @lien TABLE (LIEN VARCHAR(50), NB_COLONNES_LIEES INT, NB_PROGRAMMES INT, PROGRAMMES VARCHAR(MAX));

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : aval de PROD.s1.T1 ---';
INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables 'T1', 's1', 'PROD', @p_sortie = 'N';
INSERT INTO @lia EXEC dbo.LINE_VIS_LineageTables 'T1', 's1', 'PROD', @p_sortie = 'A';
INSERT INTO @lien
SELECT s.DTA_2 + '>' + d.DTA_2, l.NB_COLONNES_LIEES, l.NB_PROGRAMMES, l.PROGRAMMES
FROM @lia l JOIN @tab s ON s.TAB_ID = l.SRC_TAB_ID JOIN @tab d ON d.TAB_ID = l.DST_TAB_ID;

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @tab) = 3
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T1' AND NIVEAU = 0 AND SENS = '-' AND NB_COLONNES = 2 AND NOM_TABLE = 'PROD.s1.T1')
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T2' AND NIVEAU = 1 AND SENS = 'O' AND NB_COLONNES = 1)
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T4' AND NIVEAU = 2)
               AND NOT EXISTS (SELECT 1 FROM @tab WHERE TRONQUE = 1)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.1  tables T1 (depart, 2 col.), T2 (niv. 1, 1 col.), T4 (niv. 2)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  tables inattendues'; SELECT * FROM @tab; END

SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @tab WHERE DTA_2 IN ('T3', 'T5', 'UP')) THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.2  T3 absente (T2.b2 n''est pas alimentee par T1), ni T5 (DEV) ni UP (amont)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  T3, T5 ou UP ne devraient pas apparaitre'; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @lia) = 2
               AND EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'T1>T2' AND NB_COLONNES_LIEES = 2
                             AND NB_PROGRAMMES = 2 AND PROGRAMMES = 'EXE1, EXE2')
               AND EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'T2>T4' AND NB_COLONNES_LIEES = 1)
               AND NOT EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'T1>T1')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.3  liens T1>T2 (2 col., "EXE1, EXE2") et T2>T4 ; pas de T1>T1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  liens inattendus'; SELECT * FROM @lien; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : T1 sans schema ni environnement (PROD + DEV) ---';
DELETE FROM @tab; DELETE FROM @lia;
INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables 'T1', @p_sortie = 'N';
INSERT INTO @lia EXEC dbo.LINE_VIS_LineageTables 'T1', @p_sortie = 'A';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @tab) = 5 AND (SELECT COUNT(*) FROM @lia) = 3
               AND (SELECT COUNT(*) FROM @tab WHERE DTA_2 = 'T1' AND NIVEAU = 0) = 2
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T5' AND DTA_4 = 'DEV' AND NIVEAU = 1)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  T1 PROD + T1 DEV au depart ; T2, T4, T5 ; 3 liens';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  resultat inattendu sans filtre'; SELECT * FROM @tab; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : amont (I) ---';
DELETE FROM @tab; DELETE FROM @lia; DELETE FROM @lien;
INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables 'T1', 's1', 'PROD', @p_sens = 'I', @p_sortie = 'N';
INSERT INTO @lia EXEC dbo.LINE_VIS_LineageTables 'T1', 's1', 'PROD', @p_sens = 'I', @p_sortie = 'A';
INSERT INTO @lien
SELECT s.DTA_2 + '>' + d.DTA_2, l.NB_COLONNES_LIEES, l.NB_PROGRAMMES, l.PROGRAMMES
FROM @lia l JOIN @tab s ON s.TAB_ID = l.SRC_TAB_ID JOIN @tab d ON d.TAB_ID = l.DST_TAB_ID;

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @tab) = 2
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'UP' AND NIVEAU = 1 AND SENS = 'I')
               AND (SELECT COUNT(*) FROM @lia) = 1
               AND EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'UP>T1')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.1  amont : UP (niv. 1, sens I), lien UP>T1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  amont inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : les deux sens (B) ---';
DELETE FROM @tab;
INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables 'T1', 's1', 'PROD', @p_sens = 'B', @p_sortie = 'N';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @tab) = 4
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'UP' AND SENS = 'I')
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T2' AND SENS = 'O')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 4.1  T1, T2, T4 (aval) + UP (amont)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  mode B inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 5 : profondeur 1, nom en minuscules ---';
DELETE FROM @tab;
INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables 't1', 'S1', 'prod', @p_profondeur = 1, @p_sortie = 'N';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @tab) = 2
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T2')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.1  T1 + T2 (casse ignoree, 1 niveau)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.1  profondeur 1 / casse inattendue'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 6 : table inconnue, parametre manquant ---';
DELETE FROM @tab; DELETE FROM @lia;
INSERT INTO @tab EXEC dbo.LINE_VIS_LineageTables 'TX', @p_sortie = 'N';
INSERT INTO @lia EXEC dbo.LINE_VIS_LineageTables 'TX', @p_sortie = 'A';
IF NOT EXISTS (SELECT 1 FROM @tab) AND NOT EXISTS (SELECT 1 FROM @lia)
    PRINT '  PASS 6.1  table inconnue : 0 table, 0 lien';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.1  resultat non vide pour une table inconnue'; END

SET @ok = 0;
BEGIN TRY
    EXEC dbo.LINE_VIS_LineageTables NULL;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 SET @ok = 1;
END CATCH
IF @ok = 1 PRINT '  PASS 6.2  erreur 50003 sans @p_table';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.2  @p_table NULL aurait du lever l''erreur 50003'; END

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
