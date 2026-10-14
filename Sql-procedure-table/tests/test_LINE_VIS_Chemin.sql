-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_Chemin
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Graphe de la fixture (un noeud = c / table / s / PROD ; on le reconnait
--  a sa table DTA_2) :
--
--          +--> TB --+
--          |         v
--     TA --+--> TC --> TD --> TE --> TW        2 plus courts chemins A -> E
--          |                  ^                (longueur 3)
--          +--> TX --> TY --> TZ               chemin plus long (4) : ecarte
--
--     TF --> TG                                isole de A
--
--  Programmes : TA -> TB : LNA_1 (EXE1) ; TA -> TC : LNA_1 + LNA_2 (EXE1, EXE2) ;
--               tous les autres liens : LNA_1.
--  TE -> TW sert a verifier l'arret anticipe : W (niveau 4) n'est jamais lu.
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
    ('LNA_1', 'L1',  'c', 'TA', 's', 'PROD', 'O', 'c', 'TB', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L2',  'c', 'TA', 's', 'PROD', 'O', 'c', 'TC', 's', 'PROD', NULL, NULL),
    ('LNA_2', 'L3',  'c', 'TA', 's', 'PROD', 'O', 'c', 'TC', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L4',  'c', 'TA', 's', 'PROD', 'O', 'c', 'TX', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L5',  'c', 'TB', 's', 'PROD', 'O', 'c', 'TD', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L6',  'c', 'TC', 's', 'PROD', 'O', 'c', 'TD', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L7',  'c', 'TD', 's', 'PROD', 'O', 'c', 'TE', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L8',  'c', 'TX', 's', 'PROD', 'O', 'c', 'TY', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L9',  'c', 'TY', 's', 'PROD', 'O', 'c', 'TZ', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L10', 'c', 'TZ', 's', 'PROD', 'O', 'c', 'TE', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L11', 'c', 'TE', 's', 'PROD', 'O', 'c', 'TW', 's', 'PROD', NULL, NULL),
    ('LNA_1', 'L12', 'c', 'TF', 's', 'PROD', 'O', 'c', 'TG', 's', 'PROD', NULL, NULL);

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_1', 'APP1', 'PCK1', 'EXE1', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_2', 'APP2', 'PCK2', 'EXE2', 'v1', 'PROD', '2024-02-01', '2024-02-01', 'T', 'l', 1);
GO

-------------------------------------------------------------------------------
-- Tables de reception (une par jeu de resultats, demande seul avec @p_sortie)
-- Noeuds de la fixture (cle primaire d'une ligne dont il est le DTA) :
--   A = LNA_1/L1/O   E = LNA_1/L11/O   F = LNA_1/L12/O
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @ok BIT;

DECLARE @res TABLE (
    SRC_TROUVE BIT, DST_TROUVE BIT, CHEMIN_TROUVE BIT, LONGUEUR INT,
    NB_CHEMINS BIGINT, NB_NOEUDS_PARCOURUS INT, TRONQUE BIT
);
DECLARE @nod TABLE (
    NOD_ID INT, POSITION INT,
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    NOM_NOEUD VARCHAR(MAX), NB_CHEMINS BIGINT
);
DECLARE @are TABLE (
    SRC_NOD_ID INT, DST_NOD_ID INT, POSITION INT,
    NB_LIENS INT, NB_PROGRAMMES INT, PROGRAMMES VARCHAR(MAX)
);
-- Aretes lisibles "TA>TB"
DECLARE @lien TABLE (LIEN VARCHAR(50), NB_PROGRAMMES INT, PROGRAMMES VARCHAR(MAX));

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : A -> E (2 plus courts chemins de longueur 3) ---';
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L11', 'O', @p_sortie = 'R';
INSERT INTO @nod EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L11', 'O', @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L11', 'O', @p_sortie = 'A';
INSERT INTO @lien
SELECT s.DTA_2 + '>' + d.DTA_2, a.NB_PROGRAMMES, a.PROGRAMMES
FROM @are a JOIN @nod s ON s.NOD_ID = a.SRC_NOD_ID JOIN @nod d ON d.NOD_ID = a.DST_NOD_ID;

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE SRC_TROUVE = 1 AND DST_TROUVE = 1
                              AND CHEMIN_TROUVE = 1 AND LONGUEUR = 3 AND NB_CHEMINS = 2 AND TRONQUE = 0)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.1  chemin trouve, LONGUEUR = 3, NB_CHEMINS = 2';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  resume inattendu'; SELECT * FROM @res; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @nod) = 5
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'TA' AND POSITION = 0 AND NB_CHEMINS = 1)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'TB' AND POSITION = 1)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'TC' AND POSITION = 1)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'TD' AND POSITION = 2 AND NB_CHEMINS = 2)
               AND EXISTS (SELECT 1 FROM @nod WHERE DTA_2 = 'TE' AND POSITION = 3 AND NB_CHEMINS = 2)
               AND NOT EXISTS (SELECT 1 FROM @nod WHERE DTA_2 IN ('TX', 'TY', 'TZ'))
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.2  noeuds A(0) B(1) C(1) D(2) E(3) ; le detour X-Y-Z est ecarte';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  noeuds du chemin inattendus'; SELECT * FROM @nod; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @are) = 5
               AND (SELECT COUNT(*) FROM @lien WHERE LIEN IN ('TA>TB', 'TA>TC', 'TB>TD', 'TC>TD', 'TD>TE')) = 5
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.3  aretes A>B A>C B>D C>D D>E';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  aretes du chemin inattendues'; SELECT * FROM @lien; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'TA>TC' AND NB_PROGRAMMES = 2 AND PROGRAMMES = 'EXE1, EXE2')
               AND EXISTS (SELECT 1 FROM @lien WHERE LIEN = 'TA>TB' AND NB_PROGRAMMES = 1 AND PROGRAMMES = 'EXE1')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.4  PROGRAMMES : A>C "EXE1, EXE2", A>B "EXE1"';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.4  colonne PROGRAMMES inattendue'; END

-- Arret anticipe : A, B, C, X (niv. 1), D, Y (2), E, Z (3) = 8 ; W (4) jamais lu
IF EXISTS (SELECT 1 FROM @res WHERE NB_NOEUDS_PARCOURUS = 8)
    PRINT '  PASS 1.5  parcours arrete au niveau de E (8 noeuds lus, W non lu)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.5  le parcours ne s''est pas arrete au niveau de E'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : A -> A ---';
DELETE FROM @res; DELETE FROM @nod; DELETE FROM @are;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L2', 'O', @p_sortie = 'R';
INSERT INTO @nod EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L2', 'O', @p_sortie = 'N';
INSERT INTO @are EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L2', 'O', @p_sortie = 'A';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE CHEMIN_TROUVE = 1 AND LONGUEUR = 0 AND NB_CHEMINS = 1)
               AND (SELECT COUNT(*) FROM @nod) = 1
               AND NOT EXISTS (SELECT 1 FROM @are)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  meme noeud (2 lignes differentes) : LONGUEUR = 0, 1 noeud, 0 arete';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  A -> A inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : sans chemin ---';
DELETE FROM @res; DELETE FROM @nod;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L11', 'O', 'LNA_1', 'L1', 'O', @p_sortie = 'R';
INSERT INTO @nod EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L11', 'O', 'LNA_1', 'L1', 'O', @p_sortie = 'N';

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE SRC_TROUVE = 1 AND DST_TROUVE = 1
                              AND CHEMIN_TROUVE = 0 AND LONGUEUR IS NULL AND NB_CHEMINS = 0)
               AND NOT EXISTS (SELECT 1 FROM @nod)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.1  E -> A (sens inverse du flux) : pas de chemin';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  E -> A ne devrait pas avoir de chemin'; END

DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L12', 'O', @p_sortie = 'R';
IF EXISTS (SELECT 1 FROM @res WHERE CHEMIN_TROUVE = 0)
    PRINT '  PASS 3.2  A -> F (isole) : pas de chemin';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.2  A -> F ne devrait pas avoir de chemin'; END

DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L11', 'O', @p_profondeur = 2, @p_sortie = 'R';
IF EXISTS (SELECT 1 FROM @res WHERE CHEMIN_TROUVE = 0)
    PRINT '  PASS 3.3  A -> E avec @p_profondeur = 2 : pas de chemin (il en faut 3)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.3  @p_profondeur non respectee'; END

DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_1', 'L11', 'O', @p_maxnoeuds = 3, @p_sortie = 'R';
IF EXISTS (SELECT 1 FROM @res WHERE CHEMIN_TROUVE = 0 AND TRONQUE = 1)
    PRINT '  PASS 3.4  @p_maxnoeuds = 3 : pas de chemin, TRONQUE = 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.4  limite @p_maxnoeuds non signalee'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : noeuds introuvables ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_1', 'L1', 'O', 'LNA_X', 'Lx', 'O', @p_sortie = 'R';
IF EXISTS (SELECT 1 FROM @res WHERE SRC_TROUVE = 1 AND DST_TROUVE = 0 AND CHEMIN_TROUVE = 0)
    PRINT '  PASS 4.1  arrivee inconnue : DST_TROUVE = 0';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  arrivee inconnue mal signalee'; END

DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Chemin 'LNA_X', 'Lx', 'O', 'LNA_1', 'L11', 'O', @p_sortie = 'R';
IF EXISTS (SELECT 1 FROM @res WHERE SRC_TROUVE = 0 AND DST_TROUVE = 1 AND CHEMIN_TROUVE = 0)
    PRINT '  PASS 4.2  depart inconnu : SRC_TROUVE = 0';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.2  depart inconnu mal signale'; END

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
