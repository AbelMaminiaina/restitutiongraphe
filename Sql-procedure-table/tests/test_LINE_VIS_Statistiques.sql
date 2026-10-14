-- =============================================================================
--  Test unitaire : dbo.LINE_VIS_Statistiques
-- =============================================================================
--  Cible  : base jetable $(TestDb) (defaut : RestitutionGrapheProd_Test)
--  Lancer : tests/run_tests.sh
--
--  Graphe (colonne.TABLE, environnement PROD sauf T4 en DEV) :
--
--    S1.s1a --> T2.t2a  (APP1)        S1.s1b --> T2.t2a  (APP1)
--    S1.s1a --> T2.t2b  (APP1)
--    T2.t2a --> T3.t3a  (APP2)
--    T3.t3a --> T4.t4a  (APP3)   PROD -> DEV
--    T4.t4a --> T5.t5a  (APP3)   DEV  -> PROD  (anomalie)
--    T3.t3a --> T2.t2b  (APP2)   flux de retour : cycle T2 <-> T3
--
--  Chaque lien est stocke des deux cotes ('O' et 'I', meme LNA_UID).
--  Lignes ignorees : un lien du programme LNA_X (sans en-tete) et une
--  ligne au voisin vide.
--
--  Attendu :
--    lignes comptees 14 / 16 ; colonnes 7 (sources s1a s1b, sorties t2b t5a) ;
--    liens colonne 7 ; tables 5 (source S1, sortie T5) ; liens table 5 ;
--    profondeur 4 (S1 0, T2 1, T3 2, T4 3, T5 4) ; cycle T2 <-> T3 ;
--    applications 3, programmes 3 ;
--    flux applis : APP1 -> APP2 (via T2), APP2 -> APP3 (via T3) ;
--    environnements : PROD->PROD 5, PROD->DEV 1, DEV->PROD 1 (ANOMALIE).
-- =============================================================================
:setvar TestDb "RestitutionGrapheProd_Test"

USE [$(TestDb)];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-------------------------------------------------------------------------------
-- Fixture : chaque lien (src -> dst, programme) donne 2 lignes
-------------------------------------------------------------------------------
TRUNCATE TABLE dbo.LINE_VIS_EDG;
DELETE FROM dbo.LINE_VIS_HEA;

DECLARE @liens TABLE (ID INT, LNA VARCHAR(20),
    SC VARCHAR(10), ST VARCHAR(10), SE VARCHAR(10),
    DC VARCHAR(10), DT VARCHAR(10), DE VARCHAR(10));
INSERT INTO @liens VALUES
    (1, 'LNA_1', 's1a', 'S1', 'PROD', 't2a', 'T2', 'PROD'),
    (2, 'LNA_1', 's1b', 'S1', 'PROD', 't2a', 'T2', 'PROD'),
    (3, 'LNA_1', 's1a', 'S1', 'PROD', 't2b', 'T2', 'PROD'),
    (4, 'LNA_2', 't2a', 'T2', 'PROD', 't3a', 'T3', 'PROD'),
    (5, 'LNA_3', 't3a', 'T3', 'PROD', 't4a', 'T4', 'DEV'),
    (6, 'LNA_3', 't4a', 'T4', 'DEV',  't5a', 'T5', 'PROD'),
    (7, 'LNA_2', 't3a', 'T3', 'PROD', 't2b', 'T2', 'PROD'),
    (8, 'LNA_X', 's1b', 'S1', 'PROD', 't5a', 'T5', 'PROD');   -- sans en-tete : ignore

INSERT INTO dbo.LINE_VIS_EDG
    (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR, EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
SELECT LNA, 'L' + CAST(ID AS VARCHAR), SC, ST, 'sch', SE, 'O', DC, DT, 'sch', DE, NULL, NULL FROM @liens WHERE ID <= 7
UNION ALL
SELECT LNA, 'L' + CAST(ID AS VARCHAR), DC, DT, 'sch', DE, 'I', SC, ST, 'sch', SE, NULL, NULL FROM @liens WHERE ID <= 7
UNION ALL
SELECT LNA, 'L8', SC, ST, 'sch', SE, 'O', DC, DT, 'sch', DE, NULL, NULL FROM @liens WHERE ID = 8
UNION ALL
SELECT 'LNA_1', 'L9', 's1a', 'S1', 'sch', 'PROD', 'O', NULL, '', NULL, NULL, NULL, NULL;   -- voisin vide : ignore

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
VALUES
    ('LNA_1', 'APP1', 'PCK1', 'EXE1', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_2', 'APP2', 'PCK2', 'EXE2', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1),
    ('LNA_3', 'APP3', 'PCK3', 'EXE3', 'v1', 'PROD', '2024-01-01', '2024-01-01', 'T', 'l', 1);
GO

-------------------------------------------------------------------------------
-- Tables de reception
-------------------------------------------------------------------------------
DECLARE @fail INT = 0;
DECLARE @ok BIT;

DECLARE @res TABLE (ORDRE INT, INDICATEUR VARCHAR(60), VALEUR BIGINT, COMMENTAIRE VARCHAR(300));
DECLARE @col TABLE (RANG INT, DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
                    NB_AMONT INT, NB_AVAL INT, NB_LIENS INT, TYPE VARCHAR(20));
DECLARE @tab TABLE (DTA_4 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_2 VARCHAR(1000),
                    NB_TABLES_AMONT INT, NB_TABLES_AVAL INT, NB_COLONNES INT, NIVEAU INT, TYPE VARCHAR(20));
DECLARE @app TABLE (APP_SOURCE VARCHAR(4), APP_CIBLE VARCHAR(4), NB_TABLES INT, NB_LIENS INT);
DECLARE @env TABLE (ENV_SOURCE VARCHAR(1000), ENV_CIBLE VARCHAR(1000), NB_LIENS BIGINT, STATUT VARCHAR(20));
DECLARE @cyc TABLE (DTA_4 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_2 VARCHAR(1000), TAILLE_CYCLE INT);

INSERT INTO @res EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'RESUME';
INSERT INTO @col EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'COLONNES';
INSERT INTO @tab EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'TABLES';
INSERT INTO @app EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'APPLIS';
INSERT INTO @env EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'ENV';
INSERT INTO @cyc EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'CYCLES';

-------------------------------------------------------------------------------
PRINT '--- TEST 1 : resume ---';
DECLARE @att TABLE (INDICATEUR VARCHAR(60), VALEUR BIGINT);
INSERT INTO @att VALUES
    ('Lignes LINE_VIS_EDG', 16), ('Lignes comptees', 14), ('Colonnes', 7),
    ('Colonnes sources', 2), ('Colonnes de sortie', 2), ('Liens colonne -> colonne', 7),
    ('Tables', 5), ('Tables sources', 1), ('Tables de sortie', 1), ('Liens table -> table', 5),
    ('Profondeur (tables)', 4), ('Tables dans un cycle', 2), ('Applications', 3), ('Programmes', 3),
    ('Flux entre applications', 2), ('Liens entre environnements', 2), ('Liens non PROD -> PROD', 1);

DECLARE @ko VARCHAR(MAX) = (
    SELECT STRING_AGG(a.INDICATEUR + ' (attendu ' + CAST(a.VALEUR AS VARCHAR) + ', obtenu '
                      + ISNULL(CAST(r.VALEUR AS VARCHAR), 'NULL') + ')', ' ; ')
    FROM @att a LEFT JOIN @res r ON r.INDICATEUR = a.INDICATEUR
    WHERE r.VALEUR IS NULL OR r.VALEUR <> a.VALEUR);
IF @ko IS NULL PRINT '  PASS 1.1  17 indicateurs du resume conformes';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 1.1  ' + @ko; END

-------------------------------------------------------------------------------
PRINT '--- TEST 2 : colonnes pivots ---';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @col) = 7
               AND EXISTS (SELECT 1 FROM @col WHERE DTA_1 = 't3a' AND NB_AMONT = 1 AND NB_AVAL = 2 AND TYPE = 'INTERMEDIAIRE')
               AND EXISTS (SELECT 1 FROM @col WHERE DTA_1 = 't2a' AND NB_AMONT = 2 AND NB_AVAL = 1)
               AND EXISTS (SELECT 1 FROM @col WHERE DTA_1 = 's1a' AND NB_AMONT = 0 AND NB_AVAL = 2 AND TYPE = 'SOURCE')
               AND EXISTS (SELECT 1 FROM @col WHERE DTA_1 = 't5a' AND TYPE = 'SORTIE' AND DTA_2 = 'T5')
               AND (SELECT MIN(NB_LIENS) FROM @col WHERE RANG <= 2) = 3
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 2.1  t3a et t2a en tete (3 liens), s1a SOURCE, t5a SORTIE, noms retrouves';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.1  colonnes pivots inattendues'; SELECT * FROM @col; END

DELETE FROM @col;
INSERT INTO @col EXEC dbo.LINE_VIS_Statistiques @p_top = 2, @p_sortie = 'COLONNES';
IF (SELECT COUNT(*) FROM @col) = 2 PRINT '  PASS 2.2  @p_top = 2 respecte';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 2.2  @p_top non respecte'; END

-------------------------------------------------------------------------------
PRINT '--- TEST 3 : tables pivots ---';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @tab) = 5
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'S1' AND NIVEAU = 0 AND TYPE = 'SOURCE' AND NB_COLONNES = 2)
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T2' AND NIVEAU = 1 AND NB_TABLES_AMONT = 2 AND NB_TABLES_AVAL = 1)
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T3' AND NIVEAU = 2 AND NB_TABLES_AMONT = 1 AND NB_TABLES_AVAL = 2)
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T4' AND NIVEAU = 3 AND DTA_4 = 'DEV')
               AND EXISTS (SELECT 1 FROM @tab WHERE DTA_2 = 'T5' AND NIVEAU = 4 AND TYPE = 'SORTIE')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 3.1  niveaux S1 0, T2 1, T3 2, T4 3, T5 4 ; amont / aval / type / noms';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 3.1  tables inattendues'; SELECT * FROM @tab; END

-------------------------------------------------------------------------------
PRINT '--- TEST 4 : flux entre applications et environnements ---';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @app) = 2
               AND EXISTS (SELECT 1 FROM @app WHERE APP_SOURCE = 'APP1' AND APP_CIBLE = 'APP2' AND NB_TABLES = 1)
               AND EXISTS (SELECT 1 FROM @app WHERE APP_SOURCE = 'APP2' AND APP_CIBLE = 'APP3' AND NB_TABLES = 1)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 4.1  APP1 -> APP2 (via T2), APP2 -> APP3 (via T3) ; pas APP2 -> APP2';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.1  flux applis inattendus'; SELECT * FROM @app; END

SET @ok = CASE WHEN (SELECT COUNT(*) FROM @env) = 3
               AND EXISTS (SELECT 1 FROM @env WHERE ENV_SOURCE = 'PROD' AND ENV_CIBLE = 'PROD' AND NB_LIENS = 5 AND STATUT = 'OK')
               AND EXISTS (SELECT 1 FROM @env WHERE ENV_SOURCE = 'PROD' AND ENV_CIBLE = 'DEV'  AND NB_LIENS = 1 AND STATUT = 'A_VERIFIER')
               AND EXISTS (SELECT 1 FROM @env WHERE ENV_SOURCE = 'DEV'  AND ENV_CIBLE = 'PROD' AND NB_LIENS = 1 AND STATUT = 'ANOMALIE')
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 4.2  PROD->PROD 5 OK, PROD->DEV 1 A_VERIFIER, DEV->PROD 1 ANOMALIE';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 4.2  flux environnements inattendus'; SELECT * FROM @env; END

-------------------------------------------------------------------------------
PRINT '--- TEST 5 : cycles ---';
SET @ok = CASE WHEN (SELECT COUNT(*) FROM @cyc) = 2
               AND NOT EXISTS (SELECT 1 FROM @cyc WHERE DTA_2 NOT IN ('T2', 'T3') OR TAILLE_CYCLE <> 2)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 5.1  T2 et T3 dans un cycle de 2 tables';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 5.1  cycles inattendus'; SELECT * FROM @cyc; END

-------------------------------------------------------------------------------
PRINT '--- TEST 6 : limite @p_max_tables, parametres ---';
DELETE FROM @res;
INSERT INTO @res EXEC dbo.LINE_VIS_Statistiques @p_max_tables = 3, @p_sortie = 'RESUME';
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM @res WHERE INDICATEUR = 'Tables' AND VALEUR = 5)
               AND EXISTS (SELECT 1 FROM @res WHERE INDICATEUR = 'Tables sources' AND VALEUR IS NULL AND COMMENTAIRE LIKE 'non calcule%')
               AND EXISTS (SELECT 1 FROM @res WHERE INDICATEUR = 'Flux entre applications' AND VALEUR IS NULL)
               AND EXISTS (SELECT 1 FROM @res WHERE INDICATEUR = 'Colonnes' AND VALEUR = 7)
          THEN 1 ELSE 0 END;
IF @ok = 1 PRINT '  PASS 6.1  @p_max_tables = 3 : niveau table et flux applis non calcules (signale), colonnes calculees';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.1  limite @p_max_tables mal geree'; SELECT * FROM @res; END

SET @ok = 0;
BEGIN TRY
    EXEC dbo.LINE_VIS_Statistiques @p_sortie = 'X';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002 SET @ok = 1;
END CATCH
IF @ok = 1 PRINT '  PASS 6.2  erreur 50002 pour @p_sortie = X';
ELSE BEGIN SET @fail += 1; PRINT '  FAIL 6.2  @p_sortie = X aurait du lever l''erreur 50002'; END

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
