-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_NodesList
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh  (deploie schema + procedure puis execute ce
--           fichier), ou  sqlcmd -S ... -E -C -i test_LINE_VIS_NodesList.sql
--           apres avoir deploye LINE_VIS_EDG.sql et LINE_VIS_NodesList.sql
--           dans $(TestDb).
--
--  Principe : on remplit la table avec une fixture deterministe de 6 lignes
--  reparties en 3 groupes (DTA_1..DTA_4), puis on appelle la procedure et on
--  verifie le nombre de lignes, la colonne TotalLignes, le filtre 'f%' du
--  Cas 1, les filtres dynamiques du Cas 2, @p_maxres et le tri.
--
--  Comportement attendu :
--    - Cas 1 (aucun parametre) : DTA_1 LIKE 'f%' (insensible a la casse) ;
--    - 1 seule ligne par groupe (DTA_1..DTA_4) grace au ROW_NUMBER : la 1re
--      selon LIN_UID, LNA_UID, EDG_DIR ;
--    - Cas 1 : seulement les 1000 premieres lignes 'f%' trouvees, puis les
--      100 premiers groupes distincts ; TotalLignes = NULL (calcul en
--      commentaire pour le moment) ;
--    - Cas 2 : une seule lecture (au plus 1001 lignes filtrees) puis 100
--      groupes ; TotalLignes = nb EXACT de groupes distincts si <= 1000
--      lignes filtrees, sinon 1001 ("plus de 1000") ;
--    - recherche insensible a la casse ET aux accents (CP1_CI_AI).
--
--  Sortie : une ligne PASS / FAIL par assertion ; si au moins une assertion
--  echoue, le script leve une erreur (THROW) -> code retour sqlcmd != 0.
--
--  Fixture (LNA_UID / LIN_UID / DTA_1 / DTA_2 / DTA_3 / DTA_4 / EDG_DIR) :
--    Groupe A  FIADODSWRK / ZJ / D3A / ENV1   -> L003(X,O)  L001(A,O)  L002(M,I)
--    Groupe B  FIADODSOUT / ZJ / D3B / ENV2   -> L010(B,O)
--    Groupe C  ABCDATA    / ZJ / D3C / ENV1   -> L020(C,O)  L021(C,I)
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
    -- Groupe A : 3 lignes, DTA_1 commence par 'F'
    ('LNA_X', 'L003', 'FIADODSWRK', 'ZJ', 'D3A', 'ENV1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_A', 'L001', 'FIADODSWRK', 'ZJ', 'D3A', 'ENV1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_M', 'L002', 'FIADODSWRK', 'ZJ', 'D3A', 'ENV1', 'I', NULL, NULL, NULL, NULL, NULL, NULL),
    -- Groupe B : 1 ligne, DTA_1 commence par 'F'
    ('LNA_B', 'L010', 'FIADODSOUT', 'ZJ', 'D3B', 'ENV2', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    -- Groupe C : 2 lignes, DTA_1 commence par 'A' (exclu du Cas 1 'f%')
    ('LNA_C', 'L020', 'ABCDATA',    'ZJ', 'D3C', 'ENV1', 'O', NULL, NULL, NULL, NULL, NULL, NULL),
    ('LNA_C', 'L021', 'ABCDATA',    'ZJ', 'D3C', 'ENV1', 'I', NULL, NULL, NULL, NULL, NULL, NULL);
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
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 2 PRINT '  PASS 1.1  2 lignes retournees (groupes A et B, dedoublonnes)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  attendu 2, obtenu ' + CAST(@n AS VARCHAR); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE DTA_1 = 'FIADODSWRK' AND LIN_UID = 'L001'
                              AND LNA_UID = 'LNA_A' AND EDG_DIR = 'O') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 1.1b 1re ligne du groupe A = L001 / LNA_A / O';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1b mauvaise 1re ligne pour le groupe A'; END

-- Cas 1 : le calcul du total est en commentaire -> TotalLignes = NULL.
IF NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes IS NOT NULL)
    PRINT '  PASS 1.2  TotalLignes = NULL (calcul du total en commentaire)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.2  TotalLignes attendu NULL'; END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE DTA_1 = 'ABCDATA') THEN 0 ELSE 1 END;
IF @ok = 1 PRINT '  PASS 1.3  groupe C (DTA_1 ''ABCDATA'', non ''f%'') exclu';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.3  le groupe C ne devrait pas apparaitre'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : Cas 2  @p_column = ''FIADODSWRK''  => groupe A seul ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList @p_column = 'FIADODSWRK';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 PRINT '  PASS 2.1  1 ligne retournee';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  attendu 1, obtenu ' + CAST(@n AS VARCHAR); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L001'
                              AND LNA_UID = 'LNA_A' AND EDG_DIR = 'O') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1b 1re ligne du groupe A = L001 / LNA_A / O (ORDER BY du ROW_NUMBER)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1b mauvaise 1re ligne pour le groupe A'; END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 1 AND NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes <> 1)
    PRINT '  PASS 2.2  TotalLignes = 1 (un seul groupe)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.2  TotalLignes attendu 1, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-- 2.3 : filtre insensible a la casse (COLLATE French_CI_AS).
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList @p_column = 'fiadodswrk';
SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 AND EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L001')
    PRINT '  PASS 2.3  recherche insensible a la casse (fiadodswrk = FIADODSWRK)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.3  casse : attendu 1 ligne L001, obtenu ' + CAST(@n AS VARCHAR); END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : Cas 2  @p_env = ''ENV1'' (groupes A + C), @p_maxres = 1 ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList @p_env = 'ENV1', @p_maxres = 1;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 1 PRINT '  PASS 3.1  @p_maxres = 1 respecte';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  attendu 1, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 2 PRINT '  PASS 3.2  TotalLignes = 2 (A + C) malgre la limite';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.2  TotalLignes attendu 2, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE DTA_1 = 'ABCDATA') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.3  1re ligne = groupe C (tri ORDER BY DTA_1..4)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.3  ordre de tri inattendu'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : Cas 2  @p_table = ''ZJ'' (3 groupes, 6 aretes), @p_maxres = 2 ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList @p_table = 'ZJ', @p_maxres = 2;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 2 PRINT '  PASS 4.1  2 lignes retournees (limite @p_maxres)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  attendu 2, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 3 AND NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes <> 3)
    PRINT '  PASS 4.2  TotalLignes = 3 (A + B + C)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.2  TotalLignes attendu 3, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-------------------------------------------------------------------------------
PRINT '--- TEST 5 : Cas 1 avec 1500 lignes ''f%'' de plus (au-dela de la limite de 1000) ---';
-- 1500 lignes supplementaires, DTA_1 = 'FALPHA', chacune son propre groupe
-- (DTA_3 = 'X0001'..'X1500').
INSERT INTO dbo.LINE_VIS_EDG
    (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR,
     EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
SELECT TOP (1500)
    'LNA_Z', 'Z' + RIGHT('0000' + CAST(n AS VARCHAR(4)), 4), 'FALPHA', 'ZJ',
    'X' + RIGHT('0000' + CAST(n AS VARCHAR(4)), 4), 'ENV9', 'O',
    NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM sys.all_objects a CROSS JOIN sys.all_objects b) AS nums;

DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList;

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 100 PRINT '  PASS 5.1  100 lignes renvoyees (@p_maxres par defaut)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.1  attendu 100, obtenu ' + CAST(@n AS VARCHAR); END

SET @ok = CASE WHEN NOT EXISTS (SELECT 1 FROM @res WHERE DTA_1 NOT LIKE 'f%')
                AND (SELECT COUNT(*) FROM (SELECT DISTINCT DTA_1, DTA_2, DTA_3, DTA_4 FROM @res) d) = 100
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.2  100 combinaisons distinctes, toutes ''f%''';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.2  lignes non distinctes ou hors filtre ''f%'''; END

-------------------------------------------------------------------------------
PRINT '--- TEST 6 : Cas 2 @p_column = ''FALPHA'' (1500 lignes) => total plafonne ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList @p_column = 'FALPHA';

SET @n = (SELECT COUNT(*) FROM @res);
IF @n = 100 PRINT '  PASS 6.1  100 lignes renvoyees';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.1  attendu 100, obtenu ' + CAST(@n AS VARCHAR); END

SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @t = 1001 AND NOT EXISTS (SELECT 1 FROM @res WHERE TotalLignes <> 1001)
    PRINT '  PASS 6.2  TotalLignes = 1001 (plus de 1000 lignes filtrees)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.2  TotalLignes attendu 1001, obtenu ' + ISNULL(CAST(@t AS VARCHAR), 'NULL'); END

-------------------------------------------------------------------------------
PRINT '--- TEST 7 : Cas 2 insensible aux accents (''etedata'' trouve ''ETEDATA'' accentue) ---';
-- CHAR(201) = 'E' accent aigu majuscule en CP1252 (evite les soucis d'encodage du fichier)
INSERT INTO dbo.LINE_VIS_EDG
    (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR,
     EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
VALUES ('LNA_E', 'L900', CHAR(201) + 'T' + CHAR(201) + 'DATA', 'ZJ', 'D3E', 'ENV1', 'O',
        NULL, NULL, NULL, NULL, NULL, NULL);

DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_NodesList @p_column = 'etedata';

SET @n = (SELECT COUNT(*) FROM @res);
SET @t = (SELECT MIN(TotalLignes) FROM @res);
IF @n = 1 AND @t = 1 AND EXISTS (SELECT 1 FROM @res WHERE LIN_UID = 'L900')
    PRINT '  PASS 7.1  accents et casse ignores (1 ligne L900, TotalLignes = 1)';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 7.1  attendu 1 ligne L900, obtenu ' + CAST(@n AS VARCHAR); END

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
