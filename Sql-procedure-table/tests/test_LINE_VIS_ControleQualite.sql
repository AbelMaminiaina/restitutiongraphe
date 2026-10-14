-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_ControleQualite
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Noeuds : A, B, C, D, G (jamais noeud), H (NULL,h2,h3,h4 : jamais noeud),
--           N (n1,NULL,n3,n4 : noeud incomplet).
--
--   L1   LNA_1  A  -O->  B     symetrique (L2)
--   L2   LNA_1  B  -I->  A     symetrique (L1) ; B ecrit 'B1','B2 ','b3','b4'
--   L3   LNA_1  B  -O->  C     pas de C -I-> B          -> SYM_O_SANS_I
--   L4   LNA_1  C  -O->  vide                           -> VOISIN_VIDE
--   L5   LNA_2  D  -I->  A     pas de A -O-> D          -> SYM_I_SANS_O
--   L6   LNA_X  A  -O->  B     LNA_X absent de HEA      -> SANS_ENTETE
--   L7   LNA_1  A  -O->  G     G jamais noeud           -> SYM_O_SANS_I, VOISIN_FANTOME
--   L8   LNA_1  A  -O->  H     H incomplet, jamais noeud-> SYM_O_SANS_I, VOISIN_FANTOME,
--                                                         VOISIN_INCOMPLET
--   L9   LNA_1  A  -O->  B     meme lien que L1         -> DOUBLON (1 ligne en trop)
--   L10  LNA_1  N  -O->  D     N incomplet, pas de D -I-> N
--                                                       -> NOEUD_INCOMPLET, SYM_O_SANS_I
--   LINE_VIS_HEA : LNA_1, LNA_2, LNA_9 (LNA_9 sans ligne -> ENTETE_INUTILISEE)
--
--  Attendu : SYM_O_SANS_I 4 / 7 lignes O non vides, SYM_I_SANS_O 1 / 2,
--            SANS_ENTETE 1, ENTETE_INUTILISEE 1 / 3, VOISIN_VIDE 1,
--            VOISIN_INCOMPLET 1, NOEUD_INCOMPLET 1, VOISIN_FANTOME 2, DOUBLON 1.
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
    ('LNA_1', 'L1',  'a1', 'a2', 'a3', 'a4',   'O', 'b1', 'b2', 'b3', 'b4', NULL, NULL),
    ('LNA_1', 'L2',  'B1', 'B2 ', 'b3', 'b4',  'I', 'a1', 'a2', 'a3', 'a4', NULL, NULL),
    ('LNA_1', 'L3',  'b1', 'b2', 'b3', 'b4',   'O', 'c1', 'c2', 'c3', 'c4', NULL, NULL),
    ('LNA_1', 'L4',  'c1', 'c2', 'c3', 'c4',   'O', NULL, '',   NULL, NULL, NULL, NULL),
    ('LNA_2', 'L5',  'd1', 'd2', 'd3', 'd4',   'I', 'a1', 'a2', 'a3', 'a4', NULL, NULL),
    ('LNA_X', 'L6',  'a1', 'a2', 'a3', 'a4',   'O', 'b1', 'b2', 'b3', 'b4', NULL, NULL),
    ('LNA_1', 'L7',  'a1', 'a2', 'a3', 'a4',   'O', 'g1', 'g2', 'g3', 'g4', NULL, NULL),
    ('LNA_1', 'L8',  'a1', 'a2', 'a3', 'a4',   'O', NULL, 'h2', 'h3', 'h4', NULL, NULL),
    ('LNA_1', 'L9',  'a1', 'a2', 'a3', 'a4',   'O', 'b1', 'b2', 'b3', 'b4', NULL, NULL),
    ('LNA_1', 'L10', 'n1', NULL, 'n3', 'n4',   'O', 'd1', 'd2', 'd3', 'd4', NULL, NULL);

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_1', 'APP1', 'PCK1', 'EXE1', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_2', 'APP2', 'PCK2', 'EXE2', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_9', 'APP9', 'PCK9', 'EXE9', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1);
GO

-------------------------------------------------------------------------------
-- Tables de reception
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @ok BIT;

DECLARE @syn TABLE (
    ORDRE INT, CONTROLE VARCHAR(30), DESCRIPTION VARCHAR(300),
    NB_LIGNES BIGINT, NB_DISTINCTS BIGINT, NB_LIGNES_TOTAL BIGINT,
    POURCENT DECIMAL(6, 2), STATUT VARCHAR(10)
);
DECLARE @ex TABLE (
    CONTROLE VARCHAR(30), LNA_UID VARCHAR(200), LIN_UID VARCHAR(500), EDG_DIR CHAR(1),
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    EDG_1 VARCHAR(1000), EDG_2 VARCHAR(1000), EDG_3 VARCHAR(8000), EDG_4 VARCHAR(1000)
);

INSERT INTO @syn EXEC dbo.LINE_VIS_ControleQualite @p_sortie = 'S';
INSERT INTO @ex  EXEC dbo.LINE_VIS_ControleQualite @p_sortie = 'E';

-- Attendu : (controle, lignes, distincts, total)
DECLARE @att TABLE (CONTROLE VARCHAR(30), NB_LIGNES BIGINT, NB_DISTINCTS BIGINT, NB_LIGNES_TOTAL BIGINT);
INSERT INTO @att VALUES
    ('SYM_O_SANS_I',      4, 4,  7),
    ('SYM_I_SANS_O',      1, 1,  2),
    ('SANS_ENTETE',       1, 1, 10),
    ('ENTETE_INUTILISEE', 1, 1,  3),
    ('VOISIN_VIDE',       1, 1, 10),
    ('VOISIN_INCOMPLET',  1, 1, 10),
    ('NOEUD_INCOMPLET',   1, 1, 10),
    ('VOISIN_FANTOME',    2, 2, 10),
    ('DOUBLON',           1, 1, 10);

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : synthese ---';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @syn) = 9 THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.1  9 controles dans la synthese';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  nombre de controles inattendu'; END

-- Une assertion par controle
DECLARE @c VARCHAR(30), @nl BIGINT, @nd BIGINT, @nt BIGINT, @gl BIGINT, @gd BIGINT, @gt BIGINT, @msg2 VARCHAR(300);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT CONTROLE, NB_LIGNES, NB_DISTINCTS, NB_LIGNES_TOTAL FROM @att;
OPEN cur;
FETCH NEXT FROM cur INTO @c, @nl, @nd, @nt;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @gl = NULL, @gd = NULL, @gt = NULL;
    SELECT @gl = NB_LIGNES, @gd = NB_DISTINCTS, @gt = NB_LIGNES_TOTAL FROM @syn WHERE CONTROLE = @c;
    IF @gl = @nl AND @gd = @nd AND @gt = @nt
        PRINT '  PASS 1.x  ' + @c + ' : ' + CAST(@gl AS VARCHAR) + ' ligne(s) / ' + CAST(@gt AS VARCHAR);
    ELSE
    BEGIN
        SET @fail += 1;
        SET @msg2 = '  FAIL 1.x  ' + @c + ' : attendu ' + CAST(@nl AS VARCHAR) + '/' + CAST(@nd AS VARCHAR) + '/' + CAST(@nt AS VARCHAR)
                  + ', obtenu ' + ISNULL(CAST(@gl AS VARCHAR), 'NULL') + '/' + ISNULL(CAST(@gd AS VARCHAR), 'NULL') + '/' + ISNULL(CAST(@gt AS VARCHAR), 'NULL');
        PRINT @msg2;
    END
    FETCH NEXT FROM cur INTO @c, @nl, @nd, @nt;
END
CLOSE cur; DEALLOCATE cur;

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @syn WHERE CONTROLE = 'SYM_I_SANS_O' AND POURCENT = 50.00 AND STATUT = 'ANOMALIE')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.2  POURCENT (1 / 2 = 50,00) et STATUT = ANOMALIE';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  POURCENT / STATUT inattendus'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : exemples ---';

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @ex WHERE CONTROLE = 'SYM_O_SANS_I') = 4
               AND NOT EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'SYM_O_SANS_I' AND LIN_UID IN ('L1', 'L6', 'L9'))
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  SYM_O_SANS_I : L3 L7 L8 L10 ; L1 / L6 / L9 reconnus symetriques (B ecrit en majuscules)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  exemples SYM_O_SANS_I inattendus'; SELECT * FROM @ex WHERE CONTROLE = 'SYM_O_SANS_I'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'SYM_I_SANS_O'      AND LIN_UID = 'L5')
               AND EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'SANS_ENTETE'       AND LIN_UID = 'L6' AND DTA_1 = 'a1')
               AND EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'ENTETE_INUTILISEE' AND LNA_UID = 'LNA_9' AND LIN_UID IS NULL)
               AND EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'VOISIN_VIDE'       AND LIN_UID = 'L4')
               AND EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'VOISIN_INCOMPLET'  AND LIN_UID = 'L8')
               AND EXISTS (SELECT 1 FROM @ex WHERE CONTROLE = 'NOEUD_INCOMPLET'   AND LIN_UID = 'L10')
               AND (SELECT COUNT(*) FROM @ex WHERE CONTROLE = 'VOISIN_FANTOME' AND LIN_UID IN ('L7', 'L8')) = 2
               AND (SELECT COUNT(*) FROM @ex WHERE CONTROLE = 'DOUBLON' AND LIN_UID IN ('L1', 'L9')) = 2
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.2  exemples de chaque controle (lignes completes relues)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.2  exemples inattendus'; SELECT * FROM @ex; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : @p_exemples, parametres ---';
DELETE FROM @ex;
INSERT INTO @ex EXEC dbo.LINE_VIS_ControleQualite @p_exemples = 1, @p_sortie = 'E';
IF NOT EXISTS (SELECT CONTROLE FROM @ex GROUP BY CONTROLE HAVING COUNT(*) > 1)
   AND (SELECT COUNT(*) FROM @ex) = 9
    PRINT '  PASS 3.1  @p_exemples = 1 : 1 exemple par controle';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  @p_exemples non respecte'; END

DELETE FROM @ex;
INSERT INTO @ex EXEC dbo.LINE_VIS_ControleQualite @p_exemples = 0, @p_sortie = 'E';
IF NOT EXISTS (SELECT 1 FROM @ex)
    PRINT '  PASS 3.2  @p_exemples = 0 : aucun exemple';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.2  des exemples avec @p_exemples = 0'; END

SET @ok = 0;
BEGIN TRY
    EXEC dbo.LINE_VIS_ControleQualite @p_sortie = 'X';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 SET @ok = 1;
END CATCH
IF @ok = 1 PRINT '  PASS 3.3  erreur 50002 pour @p_sortie = X';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.3  @p_sortie = X aurait du lever l''erreur 50002'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : donnees propres ---';
TRUNCATE TABLE dbo.LINE_VIS_EDG;
DELETE FROM dbo.LINE_VIS_HEA WHERE LNA_UID <> 'LNA_1';
INSERT INTO dbo.LINE_VIS_EDG
    (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR, EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
VALUES
    ('LNA_1', 'L1', 'a1', 'a2', 'a3', 'a4', 'O', 'b1', 'b2', 'b3', 'b4', NULL, NULL),
    ('LNA_1', 'L2', 'b1', 'b2', 'b3', 'b4', 'I', 'a1', 'a2', 'a3', 'a4', NULL, NULL);
DELETE FROM @syn;
INSERT INTO @syn EXEC dbo.LINE_VIS_ControleQualite @p_sortie = 'S';
IF NOT EXISTS (SELECT 1 FROM @syn WHERE STATUT <> 'OK') AND (SELECT COUNT(*) FROM @syn) = 9
    PRINT '  PASS 4.1  lien stocke des 2 cotes, tout est OK (9 controles)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  anomalie signalee sur des donnees propres'; SELECT * FROM @syn; END

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
