-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_Lineage
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Graphe de la fixture (un noeud = DTA_1..DTA_4 ; on le reconnait a DTA_2) :
--
--        Q --> P --> A ==> B --> C --> D --> (voisin vide : ignore)
--                    ^           |  \
--                    +-----------+   +--> N(NULL,n2,n3,n4) --> M
--                       (cycle)
--        B --> E : lien du programme LNA_C, absent de LINE_VIS_HEA -> ignore
--        A ==> B : 2 lignes (LNA_A et LNA_B) -> NB_LIENS = 2, NB_PROGRAMMES = 2
--        La ligne de B est ecrite ('B1 ','B2','B3','B4') alors que le lien
--        A -> B donne (b1,b2,b3,b4) : casse et espaces de fin ignores.
--        P et Q ne sont lies que par des lignes 'I' (predecesseurs).
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
    -- noeud       DTA_1..DTA_4               dir  voisin EDG_1..EDG_4
    ('LNA_A', 'L1',  'a1', 'a2', 'a3', 'a4',   'O', 'b1', 'b2', 'b3', 'b4', NULL, NULL),  -- A -> B
    ('LNA_B', 'L2',  'a1', 'a2', 'a3', 'a4',   'O', 'b1', 'b2', 'b3', 'b4', NULL, NULL),  -- A -> B (2e programme)
    ('LNA_A', 'L3',  'B1 ', 'B2', 'B3', 'B4',  'O', 'c1', 'c2', 'c3', 'c4', NULL, NULL),  -- B -> C
    ('LNA_C', 'L4',  'b1', 'b2', 'b3', 'b4',   'O', 'e1', 'e2', 'e3', 'e4', NULL, NULL),  -- B -> E (sans en-tete)
    ('LNA_A', 'L5',  'c1', 'c2', 'c3', 'c4',   'O', 'd1', 'd2', 'd3', 'd4', NULL, NULL),  -- C -> D
    ('LNA_A', 'L6',  'c1', 'c2', 'c3', 'c4',   'O', 'a1', 'a2', 'a3', 'a4', NULL, NULL),  -- C -> A (cycle)
    ('LNA_A', 'L7',  'c1', 'c2', 'c3', 'c4',   'O', NULL, 'n2', 'n3', 'n4', NULL, NULL),  -- C -> N
    ('LNA_A', 'L8',  NULL, 'n2', 'n3', 'n4',   'O', 'm1', 'm2', 'm3', 'm4', NULL, NULL),  -- N -> M
    ('LNA_A', 'L9',  'd1', 'd2', 'd3', 'd4',   'O', NULL, NULL, '',   NULL, NULL, NULL),  -- D -> (vide)
    ('LNA_A', 'L10', 'a1', 'a2', 'a3', 'a4',   'I', 'p1', 'p2', 'p3', 'p4', NULL, NULL),  -- P -> A
    ('LNA_A', 'L11', 'p1', 'p2', 'p3', 'p4',   'I', 'q1', 'q2', 'q3', 'q4', NULL, NULL);  -- Q -> P

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_A', 'A1', 'PCK_A', 'EXE_A', 'v1.0', 'PROD', '2024-01-02T03:04:05', '2024-01-02T03:04:05', 'TEC_A', 'lna1', 1),
    ('LNA_B', 'B1', 'PCK_B', 'EXE_B', 'v2.0', 'DEV',  '2024-02-03T04:05:06', '2024-02-03T04:05:06', 'TEC_B', 'lna2', 0);
GO

-------------------------------------------------------------------------------
-- Tables de reception (colonnes = les 2 jeux de resultats de la procedure).
-- Chaque cas appelle la procedure 2 fois : @p_sortie = 'N' puis 'A'
-- (INSERT ... EXEC ne sait lire qu'un seul jeu de resultats).
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @n INT, @ok BIT;

DECLARE @nod TABLE (
    NOD_ID INT, NIVEAU INT, SENS CHAR(1),
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    NOM_NOEUD VARCHAR(MAX), EXPLORE BIT, TRONQUE BIT
);
DECLARE @are TABLE (SRC_NOD_ID INT, DST_NOD_ID INT, NB_LIENS INT, NB_PROGRAMMES INT);

-- Aretes lisibles "a2>b2" (DTA_2 de la source > DTA_2 de la destination)
DECLARE @lien TABLE (LIEN VARCHAR(50), NB_LIENS INT, NB_PROGRAMMES INT);

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : aval (O), profondeur 10, depuis A ---';
DELETE FROM @nod; DELETE FROM @are; DELETE FROM @lien;
INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'O', @p_profondeur = 10, @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'O', @p_profondeur = 10, @p_sortie = 'A';
INSERT INTO @lien
SELECT LOWER(s.DTA_2) + '>' + LOWER(d.DTA_2), a.NB_LIENS, a.NB_PROGRAMMES
FROM @are a JOIN @nod s ON s.NOD_ID = a.SRC_NOD_ID JOIN @nod d ON d.NOD_ID = a.DST_NOD_ID;

SET @n = (SELECT COUNT(*) FROM @nod);
IF @n = 6 PRINT '  PASS 1.1  6 noeuds (A B C D N M ; E exclu, A non repete)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  attendu 6 noeuds, obtenu ' + CAST(@n AS VARCHAR); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'a2' AND NIVEAU = 0 AND SENS = '-')
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'b2' AND NIVEAU = 1 AND SENS = 'O')
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'c2' AND NIVEAU = 2)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'd2' AND NIVEAU = 3)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'n2' AND NIVEAU = 3 AND DTA_1 IS NULL)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'm2' AND NIVEAU = 4)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.2  niveaux A0 B1 C2 D3 N3 M4 (B trouve malgre casse / espaces, N avec DTA_1 NULL)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  niveaux ou noeuds inattendus'; END

SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'e2') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.3  E exclu (lien LNA_C sans en-tete LINE_VIS_HEA)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  E ne devrait pas apparaitre'; END

SET @n = (SELECT COUNT(*) FROM @lien WHERE LIEN IN ('a2>b2', 'b2>c2', 'c2>d2', 'c2>a2', 'c2>n2', 'n2>m2'));
IF @n = 6 AND (SELECT COUNT(*) FROM @are) = 6
    PRINT '  PASS 1.4  6 aretes A>B B>C C>D C>A (cycle) C>N N>M';
ELSE BEGIN SET @fail += 1; SET @n = (SELECT COUNT(*) FROM @are); PRINT '  FAIL 1.4  aretes inattendues (' + CAST(@n AS VARCHAR) + ')'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'a2>b2' AND NB_LIENS = 2 AND NB_PROGRAMMES = 2)
               AND EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'b2>c2' AND NB_LIENS = 1 AND NB_PROGRAMMES = 1)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.5  A>B : NB_LIENS = 2, NB_PROGRAMMES = 2 ; B>C : 1 / 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.5  NB_LIENS / NB_PROGRAMMES inattendus'; END

SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @nod WHERE TRONQUE = 1 OR EXPLORE = 0) THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.6  TRONQUE = 0, tous les noeuds explores';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.6  TRONQUE / EXPLORE inattendus'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'n2' AND NOM_NOEUD = 'n4.n3.n2')
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'a2' AND NOM_NOEUD = 'a4.a3.a2.a1')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.7  NOM_NOEUD "a4.a3.a2.a1" et "n4.n3.n2" (partie NULL omise)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.7  NOM_NOEUD inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : aval, profondeur 1 ---';
DELETE FROM @nod; DELETE FROM @are;
INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'O', @p_profondeur = 1, @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'O', @p_profondeur = 1, @p_sortie = 'A';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @nod) = 2 AND (SELECT COUNT(*) FROM @are) = 1
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'a2' AND EXPLORE = 1)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'b2' AND EXPLORE = 0)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  A + B, 1 arete, B non explore (EXPLORE = 0)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  resultat inattendu en profondeur 1'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : amont (I) ---';
DELETE FROM @nod; DELETE FROM @are; DELETE FROM @lien;
INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'I', @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'I', @p_sortie = 'A';
INSERT INTO @lien
SELECT LOWER(s.DTA_2) + '>' + LOWER(d.DTA_2), a.NB_LIENS, a.NB_PROGRAMMES
FROM @are a JOIN @nod s ON s.NOD_ID = a.SRC_NOD_ID JOIN @nod d ON d.NOD_ID = a.DST_NOD_ID;

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @nod) = 3
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'p2' AND NIVEAU = 1 AND SENS = 'I')
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'q2' AND NIVEAU = 2 AND SENS = 'I')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.1  A, P (niveau 1), Q (niveau 2), sens I';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  noeuds amont inattendus'; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @are) = 2
               AND (SELECT COUNT(*) FROM @lien WHERE LIEN IN ('p2>a2', 'q2>p2')) = 2
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.2  aretes P>A et Q>P (sens du flux, pas celui de EDG_DIR)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.2  aretes amont inattendues'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : les deux sens (B) ---';
DELETE FROM @nod; DELETE FROM @are;
INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'B', @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'B', @p_sortie = 'A';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @nod) = 8 AND (SELECT COUNT(*) FROM @are) = 8
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'd2' AND SENS = 'O')
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'q2' AND SENS = 'I')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 4.1  8 noeuds / 8 aretes (aval + amont)';
ELSE BEGIN SET @fail += 1; SET @n = (SELECT COUNT(*) FROM @nod);
    DECLARE @na INT = (SELECT COUNT(*) FROM @are);
    PRINT '  FAIL 4.1  attendu 8 / 8, obtenu ' + CAST(@n AS VARCHAR) + ' / ' + CAST(@na AS VARCHAR); END

-------------------------------------------------------------------------------
PRINT '--- TEST 5 : limite @p_maxnoeuds = 3 ---';
DELETE FROM @nod; DELETE FROM @are; DELETE FROM @lien;
INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'O', @p_maxnoeuds = 3, @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'O', @p_maxnoeuds = 3, @p_sortie = 'A';
INSERT INTO @lien
SELECT LOWER(s.DTA_2) + '>' + LOWER(d.DTA_2), a.NB_LIENS, a.NB_PROGRAMMES
FROM @are a JOIN @nod s ON s.NOD_ID = a.SRC_NOD_ID JOIN @nod d ON d.NOD_ID = a.DST_NOD_ID;

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @nod) = 3
               AND NOT EXISTS (SELECT 1 FROM @nod WHERE TRONQUE = 0)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.1  3 noeuds, TRONQUE = 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.1  limite non respectee ou TRONQUE <> 1'; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @are) = 3
               AND (SELECT COUNT(*) FROM @lien WHERE LIEN IN ('a2>b2', 'b2>c2', 'c2>a2')) = 3
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.2  seulement les aretes entre noeuds gardes (A>B B>C C>A)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.2  aretes inattendues avec la limite'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 6 : noeud de depart introuvable ---';
DELETE FROM @nod; DELETE FROM @are;
INSERT INTO @nod EXEC dbo.LINE_VIS_Lineage 'LNA_X', 'Lx', 'O', @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Lineage 'LNA_X', 'Lx', 'O', @p_sortie = 'A';

IF (SELECT COUNT(*) FROM @nod) = 0 AND (SELECT COUNT(*) FROM @are) = 0
    PRINT '  PASS 6.1  0 noeud, 0 arete';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.1  resultat non vide pour un noeud inconnu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 7 : parametre @p_sens invalide ---';
SET @ok = 0;
BEGIN TRY
    EXEC dbo.LINE_VIS_Lineage 'LNA_A', 'L1', 'O', @p_sens = 'X';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001 SET @ok = 1;
END CATCH
IF @ok = 1 PRINT '  PASS 7.1  erreur 50001 pour @p_sens = X';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 7.1  @p_sens = X aurait du lever l''erreur 50001'; END

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
