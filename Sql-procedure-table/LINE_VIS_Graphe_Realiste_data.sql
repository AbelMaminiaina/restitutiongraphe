-- =============================================================================
--  Generateur d'un graphe de lineage REALISTE dans LINE_VIS_EDG / LINE_VIS_HEA
--  Base : RestitutionGrapheRealiste (base dediee, creee par graphe_realiste.sh)
--
--  Pourquoi : les donnees de RestitutionGrapheProd (generateur
--  LINE_VIS_EDG_data.sql / fichier bcp) n'ont qu'un seul niveau, une seule
--  table ('ZJ') et des liens stockes d'un seul cote : on ne peut y verifier
--  ni le lineage multi-niveaux, ni l'impact, ni les chemins, ni le controle
--  de symetrie. Ce generateur produit un systeme d'information plausible.
--
--  Modele genere :
--    - @NbApps applications (RON_APP 'A001'...), chacune dans un
--      environnement (PROD, sauf quelques-unes en RECETTE ou DEV), avec
--      @SchemasParApp schemas et @TablesParSchema tables par schema ;
--    - 6 COUCHES de traitement, reparties dans l'ordre sur les tables de
--      l'application : SRC (sources) -> STG -> ODS -> DWH -> DM -> RPT (rapports) ;
--    - @NbReferentiels tables de REFERENCE communes (REF_DEVISE, REF_AGENCE...),
--      lues par beaucoup de programmes (noeuds "pivots") ;
--    - un PROGRAMME (job ETL) par table hors SRC : il alimente sa table a partir
--      de 1 a 3 tables de la couche precedente de la meme application, d'une
--      table de reference (40 % des programmes) et d'une table d'une AUTRE
--      application (10 % des programmes : flux inter-applications) ;
--    - chaque colonne alimentee recoit 1 colonne source (2 dans 30 % des cas) :
--      la 1re est la colonne de meme rang d'une des tables sources (les
--      colonnes se propagent de couche en couche jusqu'aux rapports), la
--      2e est prise au hasard ;
--    - @Executions executions par programme (un LNA_UID et un en-tete
--      LINE_VIS_HEA chacune, une par jour) : la 1re moitie en version v1.0,
--      la 2e en v2.0, qui retire ~3 % des liens et en ajoute ~3 % ;
--    - chaque lien est stocke des DEUX cotes, avec le meme LIN_UID :
--      ligne 'O' chez la colonne source (voisin = destination) et
--      ligne 'I' chez la colonne destination (voisin = source) ;
--    - @NbCycles flux de RETOUR (une colonne de DM/RPT realimente une
--      colonne de STG de la meme application) -> boucles possibles.
--    DTA_1 = colonne, DTA_2 = table, DTA_3 = schema, DTA_4 = environnement.
--
--  Anomalies VOLONTAIRES (pour verifier LINE_VIS_ControleQualite) :
--    - @PmAsymetrique pour mille des liens n'ont que la ligne 'O' ;
--    - @PmSansEntete pour mille des executions n'ont pas d'en-tete ;
--    - @PmDoublon pour mille des lignes 'O' sont en double (LIN_UID '..._DUP').
--  Le bilan final affiche le nombre EXACT de lignes attendu pour chaque
--  controle concerne.
--
--  Reproductible : tous les choix "au hasard" viennent d'une empreinte MD5
--  de (@Graine, valeurs) : memes parametres -> exactement les memes donnees.
--
--  Volume (parametres par defaut) : ~1 100 tables, ~25 000 colonnes,
--  ~900 programmes, ~9 000 executions, ~0,5 M lignes dans LINE_VIS_EDG
--  (~300 Mo). Pour ~7 M lignes : @NbApps = 100, @Executions = 40.
--
--  Journal : comme LINE_VIS_EDG_data.sql, une transaction + CHECKPOINT par
--  numero d'execution, index IX_LINE_VIS_EDG_DIR_HASH desactive pendant le
--  chargement puis reconstruit.
--
--  Lancement : ./graphe_realiste.sh (cree la base, deploie tables et
--  procedures, puis lance ce script). Les parametres se reglent ci-dessous
--  (section "Parametres").
-- =============================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheRealiste;
GO

-- Empreinte pseudo-aleatoire reproductible : 0 .. 4 294 967 295
CREATE OR ALTER FUNCTION dbo.GEN_H (@g INT, @tag VARCHAR(20), @a BIGINT, @b BIGINT)
RETURNS BIGINT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(CAST(HASHBYTES('MD5', CONCAT(@g, '|', @tag, '|', @a, '|', @b)) AS BINARY(4)) AS BIGINT)
END
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* ============================== Parametres ============================== */
DECLARE @Graine          INT = 42;
DECLARE @NbApps          INT = 30;    -- applications
DECLARE @SchemasParApp   INT = 3;
DECLARE @TablesParSchema INT = 12;
DECLARE @ColMin          INT = 5;     -- colonnes par table (max 40)
DECLARE @ColMax          INT = 40;
DECLARE @NbReferentiels  INT = 8;     -- tables de reference communes (max 8)
DECLARE @Executions      INT = 10;    -- executions par programme
DECLARE @NbCycles        INT = 10;    -- flux de retour DM/RPT -> STG
DECLARE @DateFin         DATETIME2(0) = '2026-10-01T06:00:00';  -- derniere execution
DECLARE @PmAsymetrique   INT = 10;    -- pour mille des liens sans ligne 'I'
DECLARE @PmSansEntete    INT = 5;     -- pour mille des executions sans en-tete
DECLARE @PmDoublon       INT = 2;     -- pour mille des lignes 'O' en double
/* ======================================================================== */

DECLARE @Debut DATETIME2 = SYSDATETIME();
DECLARE @Message VARCHAR(300);
DECLARE @NbCouches INT = 6;

-- Listes de noms
DECLARE @couche TABLE (COUCHE INT PRIMARY KEY, PREFIXE VARCHAR(5));
INSERT INTO @couche VALUES (0, 'SRC'), (1, 'STG'), (2, 'ODS'), (3, 'DWH'), (4, 'DM'), (5, 'RPT');

DECLARE @domaine TABLE (N INT PRIMARY KEY, NOM VARCHAR(20));
INSERT INTO @domaine VALUES (0, 'CRM'), (1, 'COMPTA'), (2, 'RISQUE'), (3, 'PAIE'), (4, 'CREDIT'),
                            (5, 'EPARGNE'), (6, 'ASSUR'), (7, 'FACTU'), (8, 'MARKETING'), (9, 'RH');

DECLARE @entite TABLE (N INT PRIMARY KEY, NOM VARCHAR(20));
INSERT INTO @entite VALUES (0, 'CLIENT'), (1, 'CONTRAT'), (2, 'COMPTE'), (3, 'OPERATION'), (4, 'PRODUIT'),
                           (5, 'TIERS'), (6, 'ECHEANCE'), (7, 'SINISTRE'), (8, 'FACTURE'), (9, 'PAIEMENT'),
                           (10, 'AGENCE'), (11, 'SALARIE'), (12, 'GARANTIE'), (13, 'PRET'), (14, 'LIVRET'),
                           (15, 'MOUVEMENT'), (16, 'ADRESSE'), (17, 'CANAL'), (18, 'CAMPAGNE'), (19, 'DOSSIER');

DECLARE @referentiel TABLE (N INT PRIMARY KEY, NOM VARCHAR(20));
INSERT INTO @referentiel VALUES (1, 'DEVISE'), (2, 'AGENCE'), (3, 'CALENDRIER'), (4, 'PRODUIT'),
                                (5, 'PAYS'), (6, 'SEGMENT'), (7, 'CANAL'), (8, 'TIERS');

DECLARE @radical TABLE (N INT PRIMARY KEY, NOM VARCHAR(30));
INSERT INTO @radical VALUES
    (0, 'ID_CLIENT'), (1, 'NUM_CONTRAT'), (2, 'NUM_COMPTE'), (3, 'MNT_OPERATION'), (4, 'MNT_SOLDE'),
    (5, 'DAT_EFFET'), (6, 'DAT_ECHEANCE'), (7, 'DAT_CREATION'), (8, 'COD_DEVISE'), (9, 'COD_AGENCE'),
    (10, 'COD_PRODUIT'), (11, 'LIB_PRODUIT'), (12, 'COD_PAYS'), (13, 'COD_SEGMENT'), (14, 'TX_INTERET'),
    (15, 'MNT_CAPITAL'), (16, 'MNT_INTERETS'), (17, 'NB_ECHEANCES'), (18, 'COD_STATUT'), (19, 'LIB_STATUT'),
    (20, 'NOM_CLIENT'), (21, 'PRN_CLIENT'), (22, 'DAT_NAISSANCE'), (23, 'ADR_POSTALE'), (24, 'COD_POSTAL'),
    (25, 'NUM_TELEPHONE'), (26, 'ADR_EMAIL'), (27, 'COD_CANAL'), (28, 'MNT_PRIME'), (29, 'MNT_SINISTRE'),
    (30, 'DAT_SINISTRE'), (31, 'COD_GARANTIE'), (32, 'NUM_FACTURE'), (33, 'MNT_HT'), (34, 'MNT_TTC'),
    (35, 'TX_TVA'), (36, 'ID_SALARIE'), (37, 'MNT_SALAIRE'), (38, 'COD_CAMPAGNE'), (39, 'IND_ACTIF');

DECLARE @regle TABLE (N INT PRIMARY KEY, NOM VARCHAR(20));
INSERT INTO @regle VALUES (0, 'DIRECT'), (1, 'CAST'), (2, 'CONCAT'), (3, 'SUM'), (4, 'LOOKUP'), (5, 'CASE');

DECLARE @techno TABLE (N INT PRIMARY KEY, NOM VARCHAR(20));
INSERT INTO @techno VALUES (0, 'SSIS'), (1, 'DATASTAGE'), (2, 'PYTHON'), (3, 'SQL');

PRINT 'Generation du graphe realiste (graine ' + CAST(@Graine AS VARCHAR) + ')...';

/* 1. Nombres 1..100 000 */
CREATE TABLE #n (I INT PRIMARY KEY);
WITH c (d) AS (SELECT d FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) v (d))
INSERT INTO #n (I)
SELECT a.d * 10000 + b.d * 1000 + c2.d * 100 + d.d * 10 + e.d + 1
FROM c a CROSS JOIN c b CROSS JOIN c c2 CROSS JOIN c d CROSS JOIN c e;

/* 2. Applications (APP_ID 0 = referentiels communs) */
CREATE TABLE #app (APP_ID INT PRIMARY KEY, RON_APP VARCHAR(4), DOMAINE VARCHAR(20), ENV VARCHAR(20));
INSERT INTO #app
SELECT n.I, 'A' + RIGHT('000' + CAST(n.I AS VARCHAR(4)), 3), d.NOM,
       CASE WHEN n.I % 15 = 0 THEN 'DEV' WHEN n.I % 10 = 0 THEN 'RECETTE' ELSE 'PROD' END
FROM #n n
INNER JOIN @domaine d ON d.N = (n.I - 1) % 10
WHERE n.I <= @NbApps;
INSERT INTO #app VALUES (0, 'A000', 'REF', 'PROD');

/* 3. Tables : couche 0..5 dans l'ordre des positions de l'application */
CREATE TABLE #tab (
    TAB_ID     INT IDENTITY(1, 1) PRIMARY KEY,
    APP_ID     INT, ENV VARCHAR(20), SCHEMA_NOM VARCHAR(100), TABLE_NOM VARCHAR(100),
    COUCHE     INT, NB_COL INT, EST_REF BIT
);
INSERT INTO #tab (APP_ID, ENV, SCHEMA_NOM, TABLE_NOM, COUCHE, NB_COL, EST_REF)
SELECT a.APP_ID, a.ENV,
       CASE ((s.I - 1) * 3) / @SchemasParApp WHEN 0 THEN 'STG' WHEN 1 THEN 'DWH' ELSE 'DM' END
           + '_' + a.DOMAINE + '_' + a.RON_APP,
       c.PREFIXE + '_' + e.NOM + '_' + CAST(s.I AS VARCHAR(3)) + RIGHT('0' + CAST(t.I AS VARCHAR(3)), 2),
       x.COUCHE,
       @ColMin + dbo.GEN_H(@Graine, 'nbcol', a.APP_ID, x.POS) % (@ColMax - @ColMin + 1),
       0
FROM #app a
CROSS JOIN #n s
CROSS JOIN #n t
CROSS APPLY (SELECT (s.I - 1) * @TablesParSchema + (t.I - 1) AS POS) p
CROSS APPLY (SELECT p.POS AS POS, (p.POS * @NbCouches) / (@SchemasParApp * @TablesParSchema) AS COUCHE) x
INNER JOIN @couche c ON c.COUCHE = x.COUCHE
INNER JOIN @entite e ON e.N = dbo.GEN_H(@Graine, 'entite', a.APP_ID, x.POS) % 20
WHERE a.APP_ID > 0 AND s.I <= @SchemasParApp AND t.I <= @TablesParSchema
ORDER BY a.APP_ID, x.POS;

-- Referentiels communs (couche 0, lus par toutes les applications)
INSERT INTO #tab (APP_ID, ENV, SCHEMA_NOM, TABLE_NOM, COUCHE, NB_COL, EST_REF)
SELECT 0, 'PROD', 'REF_COMMUN', 'REF_' + r.NOM, 0,
       5 + dbo.GEN_H(@Graine, 'nbcolref', r.N, 0) % 11, 1
FROM @referentiel r
WHERE r.N <= @NbReferentiels;

/* 4. Colonnes (noms metier, uniques dans la table) */
CREATE TABLE #col (
    COL_ID INT IDENTITY(1, 1) PRIMARY KEY,
    TAB_ID INT, ORDINAL INT, COL_NOM VARCHAR(100),
    -- coordonnees completes (DTA_1..DTA_4) recopiees pour les jointures
    TABLE_NOM VARCHAR(100), SCHEMA_NOM VARCHAR(100), ENV VARCHAR(20)
);
INSERT INTO #col (TAB_ID, ORDINAL, COL_NOM, TABLE_NOM, SCHEMA_NOM, ENV)
SELECT t.TAB_ID, n.I,
       r.NOM + CASE WHEN n.I > 40 THEN '_' + CAST((n.I - 1) / 40 AS VARCHAR(3)) ELSE '' END,
       t.TABLE_NOM, t.SCHEMA_NOM, t.ENV
FROM #tab t
INNER JOIN #n n ON n.I <= t.NB_COL
INNER JOIN @radical r ON r.N = (n.I - 1 + dbo.GEN_H(@Graine, 'radical', t.TAB_ID, 0) % 40) % 40
ORDER BY t.TAB_ID, n.I;
CREATE INDEX IX_col_tab ON #col (TAB_ID, ORDINAL);

/* 5. Programmes : un par table alimentee (hors SRC et referentiels) */
CREATE TABLE #prog (PGM_ID INT PRIMARY KEY, APP_ID INT, COUCHE INT, NOM VARCHAR(120), TECHNO VARCHAR(20));
INSERT INTO #prog
SELECT t.TAB_ID, t.APP_ID, t.COUCHE, 'JOB_' + a.RON_APP + '_' + t.TABLE_NOM, te.NOM
FROM #tab t
INNER JOIN #app a ON a.APP_ID = t.APP_ID   -- nom unique : 2 applications peuvent avoir une table de meme nom
INNER JOIN @techno te ON te.N = dbo.GEN_H(@Graine, 'techno', t.TAB_ID, 0) % 4
WHERE t.COUCHE > 0 AND t.EST_REF = 0;

/* 6. Tables sources de chaque programme */
CREATE TABLE #src (PGM_ID INT, SRC_TAB_ID INT, PRIMARY KEY (PGM_ID, SRC_TAB_ID));

-- 6a. 1 a 3 tables de la couche precedente, meme application
INSERT INTO #src
SELECT x.PGM_ID, x.TAB_ID
FROM (
    SELECT p.PGM_ID, t.TAB_ID,
           ROW_NUMBER() OVER (PARTITION BY p.PGM_ID ORDER BY dbo.GEN_H(@Graine, 'src', p.PGM_ID, t.TAB_ID)) AS RN,
           1 + dbo.GEN_H(@Graine, 'nbsrc', p.PGM_ID, 0) % 3 AS NB
    FROM #prog p
    INNER JOIN #tab t ON t.APP_ID = p.APP_ID AND t.COUCHE = p.COUCHE - 1 AND t.EST_REF = 0
) x
WHERE x.RN <= x.NB;

-- 6b. une table de reference pour 40 % des programmes
INSERT INTO #src
SELECT x.PGM_ID, x.TAB_ID
FROM (
    SELECT p.PGM_ID, t.TAB_ID,
           ROW_NUMBER() OVER (PARTITION BY p.PGM_ID ORDER BY dbo.GEN_H(@Graine, 'ref', p.PGM_ID, t.TAB_ID)) AS RN
    FROM #prog p
    INNER JOIN #tab t ON t.EST_REF = 1
    WHERE dbo.GEN_H(@Graine, 'avecref', p.PGM_ID, 0) % 100 < 40
) x
WHERE x.RN = 1;

-- 6c. une table d'une AUTRE application (couche precedente) pour 10 % des programmes
INSERT INTO #src
SELECT x.PGM_ID, x.TAB_ID
FROM (
    SELECT p.PGM_ID, t.TAB_ID,
           ROW_NUMBER() OVER (PARTITION BY p.PGM_ID ORDER BY dbo.GEN_H(@Graine, 'xapp', p.PGM_ID, t.TAB_ID)) AS RN
    FROM #prog p
    INNER JOIN #tab t ON t.APP_ID <> p.APP_ID AND t.APP_ID > 0 AND t.COUCHE = p.COUCHE - 1
    WHERE dbo.GEN_H(@Graine, 'avecxapp', p.PGM_ID, 0) % 100 < 10
) x
WHERE x.RN = 1
  AND NOT EXISTS (SELECT 1 FROM #src s WHERE s.PGM_ID = x.PGM_ID AND s.SRC_TAB_ID = x.TAB_ID);

-- Numerotation des sources de chaque programme (pour en tirer une au hasard)
CREATE TABLE #srcn (PGM_ID INT, RN INT, NB INT, SRC_TAB_ID INT, NB_COL INT, PRIMARY KEY (PGM_ID, RN));
INSERT INTO #srcn
SELECT s.PGM_ID,
       ROW_NUMBER() OVER (PARTITION BY s.PGM_ID ORDER BY s.SRC_TAB_ID),
       COUNT(*) OVER (PARTITION BY s.PGM_ID),
       s.SRC_TAB_ID, t.NB_COL
FROM #src s
INNER JOIN #tab t ON t.TAB_ID = s.SRC_TAB_ID;

/* 7. Liens colonne -> colonne (MAP). Chaque colonne de la table alimentee
      recoit 1 source (2 dans 30 % des cas). Versions : VMIN..VMAX
      (3 % des liens disparaissent en v2, 3 % apparaissent en v2). */
CREATE TABLE #map (
    MAP_ID     INT IDENTITY(1, 1) PRIMARY KEY,
    PGM_ID     INT, SRC_COL_ID INT, DST_COL_ID INT,
    VMIN       INT, VMAX INT, EST_RETOUR BIT,
    ASYMETRIQUE BIT, REGLE VARCHAR(20)
);
INSERT INTO #map (PGM_ID, SRC_COL_ID, DST_COL_ID, VMIN, VMAX, EST_RETOUR, ASYMETRIQUE, REGLE)
SELECT y.PGM_ID, y.SRC_COL_ID, y.DST_COL_ID,
       CASE WHEN y.V BETWEEN 3 AND 5 THEN 2 ELSE 1 END,
       CASE WHEN y.V < 3 THEN 1 ELSE 2 END,
       0, 0, rg.NOM
FROM (
    SELECT DISTINCT p.PGM_ID, sc.COL_ID AS SRC_COL_ID, d.COL_ID AS DST_COL_ID,
           dbo.GEN_H(@Graine, 'version', d.COL_ID, sc.COL_ID) % 100 AS V
    FROM #prog p
    INNER JOIN #col d ON d.TAB_ID = p.PGM_ID
    CROSS JOIN (VALUES (1), (2)) r (R)
    INNER JOIN #srcn s ON s.PGM_ID = p.PGM_ID
                      AND s.RN = 1 + dbo.GEN_H(@Graine, 'quelsrc', d.COL_ID, r.R) % s.NB
    -- 1re source : colonne de meme rang dans la table source (reprise
    -- d'une couche a l'autre, comme dans un vrai entrepot : les colonnes
    -- se propagent jusqu'aux rapports) ; 2e source : colonne au hasard.
    INNER JOIN #col sc ON sc.TAB_ID = s.SRC_TAB_ID
                      AND sc.ORDINAL = CASE WHEN r.R = 1 THEN 1 + (d.ORDINAL - 1) % s.NB_COL
                                            ELSE 1 + dbo.GEN_H(@Graine, 'quelcol', d.COL_ID, r.R) % s.NB_COL END
    WHERE r.R = 1 OR dbo.GEN_H(@Graine, 'deuxsrc', d.COL_ID, 0) % 100 < 30
) y
INNER JOIN @regle rg ON rg.N = dbo.GEN_H(@Graine, 'regle', y.DST_COL_ID, y.SRC_COL_ID) % 6
ORDER BY y.PGM_ID, y.DST_COL_ID, y.SRC_COL_ID;

-- Flux de retour : une colonne de DM/RPT realimente une colonne de STG
-- de la meme application (programme de la table STG)
INSERT INTO #map (PGM_ID, SRC_COL_ID, DST_COL_ID, VMIN, VMAX, EST_RETOUR, ASYMETRIQUE, REGLE)
SELECT TOP (@NbCycles) dt.TAB_ID, sc.COL_ID, dc.COL_ID, 1, 2, 1, 0, 'RETOUR'
FROM #tab st
INNER JOIN #tab dt ON dt.APP_ID = st.APP_ID AND dt.COUCHE = 1 AND dt.EST_REF = 0
INNER JOIN #col sc ON sc.TAB_ID = st.TAB_ID AND sc.ORDINAL = 1
INNER JOIN #col dc ON dc.TAB_ID = dt.TAB_ID AND dc.ORDINAL = 2
WHERE st.COUCHE >= 4 AND st.EST_REF = 0
  AND NOT EXISTS (SELECT 1 FROM #map m WHERE m.SRC_COL_ID = sc.COL_ID AND m.DST_COL_ID = dc.COL_ID)
ORDER BY dbo.GEN_H(@Graine, 'retour', st.TAB_ID, dt.TAB_ID);

-- Anomalie : liens sans ligne 'I'
UPDATE #map SET ASYMETRIQUE = 1
WHERE dbo.GEN_H(@Graine, 'asym', MAP_ID, 0) % 1000 < @PmAsymetrique;

/* 8. Executions : une par jour, v1 puis v2 */
CREATE TABLE #exe (
    EXE_ID INT IDENTITY(1, 1) PRIMARY KEY,
    PGM_ID INT, NUM INT, LNA_UID VARCHAR(200), VERSION INT,
    LNA_TSP DATETIME2(0), SANS_ENTETE BIT, TUS_IND INT
);
INSERT INTO #exe (PGM_ID, NUM, LNA_UID, VERSION, LNA_TSP, SANS_ENTETE, TUS_IND)
SELECT p.PGM_ID, n.I,
       a.RON_APP + '_P' + RIGHT('00000' + CAST(p.PGM_ID AS VARCHAR(6)), 5)
                 + '_E' + RIGHT('000' + CAST(n.I AS VARCHAR(4)), 3),
       CASE WHEN n.I <= @Executions / 2 THEN 1 ELSE 2 END,
       DATEADD(MINUTE, dbo.GEN_H(@Graine, 'minute', p.PGM_ID, n.I) % 120,
               DATEADD(DAY, n.I - @Executions, @DateFin)),
       CASE WHEN dbo.GEN_H(@Graine, 'sansentete', p.PGM_ID, n.I) % 1000 < @PmSansEntete THEN 1 ELSE 0 END,
       CASE WHEN dbo.GEN_H(@Graine, 'statut', p.PGM_ID, n.I) % 100 < 2 THEN 0 ELSE 1 END
FROM #prog p
INNER JOIN #app a ON a.APP_ID = p.APP_ID
INNER JOIN #n n ON n.I <= @Executions
ORDER BY p.PGM_ID, n.I;
CREATE INDEX IX_exe_num ON #exe (NUM) INCLUDE (PGM_ID, LNA_UID, VERSION);

SET @Message = 'Modele : ' + CAST((SELECT COUNT(*) FROM #tab) AS VARCHAR) + ' tables, '
    + CAST((SELECT COUNT(*) FROM #col) AS VARCHAR) + ' colonnes, '
    + CAST((SELECT COUNT(*) FROM #prog) AS VARCHAR) + ' programmes, '
    + CAST((SELECT COUNT(*) FROM #map) AS VARCHAR) + ' liens, '
    + CAST((SELECT COUNT(*) FROM #exe) AS VARCHAR) + ' executions ('
    + CAST(DATEDIFF(SECOND, @Debut, SYSDATETIME()) AS VARCHAR) + ' s)';
RAISERROR (@Message, 0, 1) WITH NOWAIT;

/* 9. Chargement de LINE_VIS_EDG : vider, desactiver l'index de hash,
      une transaction + CHECKPOINT par numero d'execution. */
TRUNCATE TABLE dbo.LINE_VIS_EDG;
TRUNCATE TABLE dbo.LINE_VIS_HEA;

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH' AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG DISABLE;

DECLARE @e INT = 1;
WHILE @e <= @Executions
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO dbo.LINE_VIS_EDG WITH (TABLOCK)
        (LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR,
         EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
    -- ligne 'O' chez la source : voisin = destination
    SELECT x.LNA_UID, 'M' + CAST(m.MAP_ID AS VARCHAR(10)),
           s.COL_NOM, s.TABLE_NOM, s.SCHEMA_NOM, s.ENV, 'O',
           d.COL_NOM, d.TABLE_NOM, d.SCHEMA_NOM, d.ENV,
           '{"regle": "' + m.REGLE + '", "version": ' + CAST(x.VERSION AS VARCHAR(2)) + '}', NULL
    FROM #exe x
    INNER JOIN #map m ON m.PGM_ID = x.PGM_ID AND x.VERSION BETWEEN m.VMIN AND m.VMAX
    INNER JOIN #col s ON s.COL_ID = m.SRC_COL_ID
    INNER JOIN #col d ON d.COL_ID = m.DST_COL_ID
    WHERE x.NUM = @e
    UNION ALL
    -- ligne 'I' chez la destination : voisin = source (sauf liens asymetriques)
    SELECT x.LNA_UID, 'M' + CAST(m.MAP_ID AS VARCHAR(10)),
           d.COL_NOM, d.TABLE_NOM, d.SCHEMA_NOM, d.ENV, 'I',
           s.COL_NOM, s.TABLE_NOM, s.SCHEMA_NOM, s.ENV,
           '{"regle": "' + m.REGLE + '", "version": ' + CAST(x.VERSION AS VARCHAR(2)) + '}', NULL
    FROM #exe x
    INNER JOIN #map m ON m.PGM_ID = x.PGM_ID AND x.VERSION BETWEEN m.VMIN AND m.VMAX
    INNER JOIN #col s ON s.COL_ID = m.SRC_COL_ID
    INNER JOIN #col d ON d.COL_ID = m.DST_COL_ID
    WHERE x.NUM = @e AND m.ASYMETRIQUE = 0
    UNION ALL
    -- doublons : meme ligne 'O', autre LIN_UID
    SELECT x.LNA_UID, 'M' + CAST(m.MAP_ID AS VARCHAR(10)) + '_DUP',
           s.COL_NOM, s.TABLE_NOM, s.SCHEMA_NOM, s.ENV, 'O',
           d.COL_NOM, d.TABLE_NOM, d.SCHEMA_NOM, d.ENV,
           '{"regle": "' + m.REGLE + '", "version": ' + CAST(x.VERSION AS VARCHAR(2)) + '}', NULL
    FROM #exe x
    INNER JOIN #map m ON m.PGM_ID = x.PGM_ID AND x.VERSION BETWEEN m.VMIN AND m.VMAX
    INNER JOIN #col s ON s.COL_ID = m.SRC_COL_ID
    INNER JOIN #col d ON d.COL_ID = m.DST_COL_ID
    WHERE x.NUM = @e
      AND dbo.GEN_H(@Graine, 'doublon', m.MAP_ID, x.EXE_ID) % 1000 < @PmDoublon;

    COMMIT TRANSACTION;
    CHECKPOINT;

    SET @Message = 'Execution ' + CAST(@e AS VARCHAR) + '/' + CAST(@Executions AS VARCHAR) + ' chargee ('
        + CAST(DATEDIFF(SECOND, @Debut, SYSDATETIME()) AS VARCHAR) + ' s)';
    RAISERROR (@Message, 0, 1) WITH NOWAIT;
    SET @e += 1;
END

/* 10. En-tetes : un par execution (sauf anomalies "sans en-tete") */
INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
SELECT x.LNA_UID, a.RON_APP, 'PCK_' + a.DOMAINE + '_' + a.RON_APP, p.NOM,
       'v' + CAST(x.VERSION AS VARCHAR(2)) + '.0', t.ENV,
       CAST(CAST(x.LNA_TSP AS DATE) AS DATETIME2), x.LNA_TSP, p.TECHNO, 'lna3', x.TUS_IND
FROM #exe x
INNER JOIN #prog p ON p.PGM_ID = x.PGM_ID
INNER JOIN #app a ON a.APP_ID = p.APP_ID
INNER JOIN #tab t ON t.TAB_ID = p.PGM_ID
WHERE x.SANS_ENTETE = 0;

/* 11. Reconstruction de l'index de recherche */
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH' AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG REBUILD WITH (SORT_IN_TEMPDB = ON);

/* 12. Bilan : modele, volumes, et anomalies attendues par
       LINE_VIS_ControleQualite (nombre exact de lignes). */
DECLARE @lignesO BIGINT, @lignesI BIGINT, @lignesDup BIGINT,
        @asymO BIGINT, @sansEnteteLignes BIGINT, @sansEnteteExe INT;

SELECT @lignesO   = SUM(CASE WHEN EDG_DIR = 'O' AND LIN_UID NOT LIKE '%[_]DUP' THEN 1 ELSE 0 END),
       @lignesI   = SUM(CASE WHEN EDG_DIR = 'I' THEN 1 ELSE 0 END),
       @lignesDup = SUM(CASE WHEN LIN_UID LIKE '%[_]DUP' THEN 1 ELSE 0 END)
FROM dbo.LINE_VIS_EDG;

-- lignes 'O' des liens asymetriques (une par execution valide, plus les
-- doublons de ces liens)
SELECT @asymO = COUNT_BIG(*)
              + SUM(CASE WHEN dbo.GEN_H(@Graine, 'doublon', m.MAP_ID, x.EXE_ID) % 1000 < @PmDoublon
                         THEN 1 ELSE 0 END)
FROM #exe x
INNER JOIN #map m ON m.PGM_ID = x.PGM_ID AND x.VERSION BETWEEN m.VMIN AND m.VMAX
WHERE m.ASYMETRIQUE = 1;

SELECT @sansEnteteExe = COUNT(*) FROM #exe WHERE SANS_ENTETE = 1;
SELECT @sansEnteteLignes = COUNT_BIG(*)
FROM dbo.LINE_VIS_EDG e
WHERE NOT EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WHERE h.LNA_UID = e.LNA_UID);

SELECT 'MODELE' AS RUBRIQUE, 'applications'           AS ELEMENT, CAST(COUNT(*) - 1 AS BIGINT) AS NOMBRE FROM #app
UNION ALL SELECT 'MODELE', 'tables (dont referentiels)', COUNT(*) FROM #tab
UNION ALL SELECT 'MODELE', 'tables de reference', SUM(CAST(EST_REF AS INT)) FROM #tab
UNION ALL SELECT 'MODELE', 'colonnes', COUNT(*) FROM #col
UNION ALL SELECT 'MODELE', 'programmes', COUNT(*) FROM #prog
UNION ALL SELECT 'MODELE', 'liens colonne -> colonne', COUNT(*) FROM #map
UNION ALL SELECT 'MODELE', 'liens retires en v2', SUM(CASE WHEN VMAX = 1 THEN 1 ELSE 0 END) FROM #map
UNION ALL SELECT 'MODELE', 'liens ajoutes en v2', SUM(CASE WHEN VMIN = 2 THEN 1 ELSE 0 END) FROM #map
UNION ALL SELECT 'MODELE', 'flux de retour (DM/RPT -> STG)', SUM(CAST(EST_RETOUR AS INT)) FROM #map
UNION ALL SELECT 'MODELE', 'programmes avec source dans une autre application',
                 COUNT(DISTINCT s.PGM_ID) FROM #src s INNER JOIN #tab t ON t.TAB_ID = s.SRC_TAB_ID
                 INNER JOIN #prog p ON p.PGM_ID = s.PGM_ID WHERE t.APP_ID <> p.APP_ID AND t.EST_REF = 0
UNION ALL SELECT 'MODELE', 'liens entre environnements differents', COUNT(*)
                 FROM #map m INNER JOIN #col s ON s.COL_ID = m.SRC_COL_ID INNER JOIN #col d ON d.COL_ID = m.DST_COL_ID
                 WHERE s.ENV <> d.ENV
UNION ALL SELECT 'MODELE', 'executions', COUNT(*) FROM #exe
UNION ALL SELECT 'VOLUME', 'lignes LINE_VIS_EDG', (SELECT COUNT_BIG(*) FROM dbo.LINE_VIS_EDG)
UNION ALL SELECT 'VOLUME', 'lignes O (hors doublons)', @lignesO
UNION ALL SELECT 'VOLUME', 'lignes I', @lignesI
UNION ALL SELECT 'VOLUME', 'lignes LINE_VIS_HEA', (SELECT COUNT_BIG(*) FROM dbo.LINE_VIS_HEA)
UNION ALL SELECT 'ATTENDU', 'SYM_O_SANS_I (lignes)', @asymO
UNION ALL SELECT 'ATTENDU', 'SYM_I_SANS_O (lignes)', 0
UNION ALL SELECT 'ATTENDU', 'SANS_ENTETE (lignes)', @sansEnteteLignes
UNION ALL SELECT 'ATTENDU', 'SANS_ENTETE (LNA_UID = executions)', @sansEnteteExe
UNION ALL SELECT 'ATTENDU', 'DOUBLON (lignes en trop)', @lignesDup
UNION ALL SELECT 'ATTENDU', 'ENTETE_INUTILISEE / VOISIN_VIDE / VOISIN_INCOMPLET / NOEUD_INCOMPLET', 0;

PRINT 'Graphe realiste genere en ' + CAST(DATEDIFF(SECOND, @Debut, SYSDATETIME()) AS VARCHAR) + ' s.';
GO

-- La fonction ne sert qu'a la generation
DROP FUNCTION IF EXISTS dbo.GEN_H;
GO
