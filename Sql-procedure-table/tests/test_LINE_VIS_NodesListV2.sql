-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_NodesListV2
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh  (deploie schema + procedure puis execute ce
--           fichier), ou  sqlcmd -S ... -E -C -i test_LINE_VIS_NodesListV2.sql
--           apres avoir deploye LINE_VIS_EDG.sql et LINE_VIS_NodesListV2.sql
--           dans $(TestDb).
--
--  Principe : on remplit la table avec une fixture deterministe de 5 lignes
--  reparties en 3 groupes (DTA_1..DTA_4), puis on appelle la procedure et on
--  verifie le nombre de lignes, la colonne TotalLignes, le filtre 'f%' du
--  Cas 1, les filtres dynamiques du Cas 2, @p_maxres et le tri.
--
--  Sortie : une ligne PASS / FAIL par assertion ; si au moins une assertion
--  echoue, le script leve une erreur (THROW) -> code retour sqlcmd != 0.
--
--  Fixture (LNA_UID / LIN_UID / DTA_1 / DTA_2 / DTA_3 / DTA_4 / EDG_DIR) :
--    Groupe A  FIADODSWRK / ZJ / D3A / ENV1   -> L003(X,O)  L001(A,O)  L002(M,I)
--    Groupe B  FIADODSOUT / ZJ / D3B / ENV2   -> L010(B,O)
--    Groupe C  XYZDATA    / ZJ / D3C / ENV1   -> L020(C,O)
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

INSERT INTO dbo.LINE_VIS_EDG
    (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR,
     EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
VALUES
    -- Groupe A : 3 lignes. Tri interne ORDER BY LIN_UID, LNA_UID, EDG_DIR
    --            => 1re ligne attendue = L001 / LNA_A / O
    ('LNA_X', 'L003', 'FIADODSWRK', 'ZJ', 'D3A', 'ENV1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_A', 'L001', 'FIADODSWRK', 'ZJ', 'D3A', 'ENV1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_M', 'L002', 'FIADODSWRK', 'ZJ', 'D3A', 'ENV1', 'I', NULL, NULL, NULL, NULL, NULL, NULL),
    -- Groupe B : 1 ligne, DTA_1 commence par 'f'
    ('LNA_B', 'L010', 'FIADODSOUT', 'ZJ', 'D3B', 'ENV2', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    -- Groupe C : 1 ligne, DTA_1 ne commence PAS par 'f'
    ('LNA_C', 'L020', 'XYZDATA',    'ZJ', 'D3C', 'ENV1', 'O', NULL, NULL, NULL, NULL, NULL, NULL);
GO

-- Le Cas 1 lit @TotalLignes dans le cache dbo.LINE_VIS_EDG_Stats -> on le
-- recalcule apres avoir charge la fixture.
EXEC dbo.LINE_VIS_EDG_RefreshStats;
GO

-------------------------------------------------------------------------------
-- Assertions
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @n INT;             -- nb de lignes retournees
DECLARE @t INT;             -- valeur de TotalLignes observee
DECLARE @ok BIT;            -- resultat d'une assertion "contenu"
DECLARE @res TABLE (
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    LIN_UID VARCHAR(500), LNA_UID VARCHAR(200), EDG_DIR CHAR(1), TotalLignes INT
);

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : Cas 1 (aucun parametre) => filtre DTA_1 LIKE ''f%'' ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesListV2;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 2 PRINT '  PASS 1.1  2 lignes retournees (groupes A et B)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  attendu 2, obtenu ' + CAST(@n AS VARCHAR); END

-- Cas 1 : TotalLignes = nb total de combinaisons (DTA_1..4) distinctes de TOUTE
-- la table (non filtre par 'f%') => 3 groupes A, B, C. Valeur servie par le
-- cache dbo.LINE_VIS_EDG_Stats (rafraichi juste apres la fixture).
SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 3 AND NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes <> 3)
    PRINT '  PASS 1.2  TotalLignes = 3 (cache, toutes combinaisons distinctes)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  TotalLignes attendu 3, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-- 1.3 : repli si le cache est vide -> la procedure recalcule en direct.
DELETE FROM dbo.LINE_VIS_EDG_Stats;
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesListV2;
SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 3 PRINT '  PASS 1.3  repli COUNT(DISTINCT) direct quand le cache est vide';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  repli cache vide : TotalLignes attendu 3, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END
EXEC dbo.LINE_VIS_EDG_RefreshStats;  -- on remet le cache en place pour la suite

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res
                            WHERE DTA_1 = 'FIADODSWRK' AND LIN_UID = 'L001'
                              AND LNA_UID = 'LNA_A' AND EDG_DIR = 'O') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.4  1re ligne du groupe A = L001 / LNA_A / O';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.4  mauvaise 1re ligne pour le groupe A'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE DTA_1 = 'XYZDATA') THEN 0 ELSE 1 END;
IF @ok = 1 PRINT '  PASS 1.5  groupe C (DTA_1 non ''f%'') exclu du resultat';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.5  le groupe C ne devrait pas apparaitre'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : Cas 2  @p_column = ''FIADODSWRK''  => groupe A seul ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesListV2 @p_column = 'FIADODSWRK';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 PRINT '  PASS 2.1  1 ligne retournee';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  attendu 1, obtenu ' + CAST(@n AS VARCHAR); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L001' AND TotalLignes = 1) THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.2  L001 + TotalLignes = 1';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.2  contenu inattendu (LIN_UID / TotalLignes)'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : Cas 2  @p_env = ''ENV1'' (groupes A + C), @p_maxres = 1 ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesListV2 @p_env = 'ENV1', @p_maxres = 1;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 PRINT '  PASS 3.1  @p_maxres = 1 respecte';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  attendu 1, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 2 PRINT '  PASS 3.2  TotalLignes = 2 (A + C) malgre la limite';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.2  TotalLignes attendu 2, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE DTA_1 = 'FIADODSWRK') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.3  1re ligne = groupe A (tri ORDER BY DTA_1..4)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.3  ordre de tri inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : Cas 2  @p_table = ''ZJ'' (3 groupes), @p_maxres = 2 ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesListV2 @p_table = 'ZJ', @p_maxres = 2;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 2 PRINT '  PASS 4.1  2 lignes retournees (limite @p_maxres)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  attendu 2, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 3 AND NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes <> 3)
    PRINT '  PASS 4.2  TotalLignes = 3 (A + B + C)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.2  TotalLignes attendu 3, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

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
