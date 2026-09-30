-- =============================================================================
--  Benchmark des procedures LINE_VIS_* sur les VRAIES donnees
-- =============================================================================
--  Cible  : RestitutionGrapheProd (7 M lignes dans LINE_VIS_EDG,
--           210 000 dans LINE_VIS_HEA -> LINE_VIS_EDG_data.sql + LINE_VIS_HEA_data.sql)
--  Pre-requis : procedures deployees dans cette base
--           (LINE_VIS_NodesList.sql, LINE_VIS_GetNodesSuccessorsPredecessors.sql,
--            LINE_VIS_NodeById.sql).
--  Lancer : sqlcmd -S .\SQLEXPRESS01 -E -C -i tests\bench_LINE_VIS.sql
--
--  Principe :
--    - une liste de cas (sans critere / avec critere(s)) par procedure ;
--    - chaque cas est execute @runs fois ; le temps de retour est mesure en
--      millisecondes (SYSDATETIME avant / apres l'appel) ;
--    - le resultat de chaque appel est capture (INSERT ... EXEC) pour compter
--      les lignes renvoyees et relever TotalLignes ;
--    - a la fin : tableau de statistiques par cas (min / moyenne / max) + un
--      resume par procedure.
--
--  Remarques :
--    - le 1er passage d'un cas peut etre plus lent (plan a compiler, pages a
--      lire sur disque) : c'est pour cela que chaque cas tourne plusieurs fois ;
--    - les cas tres couteux (scan de toute la table + table temporaire de
--      plusieurs millions de lignes) ne tournent qu'une fois (@runs = 1).
-- =============================================================================

USE RestitutionGrapheProd;
GO

SET NOCOUNT ON;

-------------------------------------------------------------------------------
-- 1. Un noeud reel pris dans la table, pour les procedures "par noeud".
--    On prend une arete 'O' dont EDG_1..EDG_4 sont tous renseignes.
-------------------------------------------------------------------------------
DECLARE @lna VARCHAR(200), @lin VARCHAR(500), @dir CHAR(1);

SELECT TOP (1) @lna = LNA_UID, @lin = LIN_UID, @dir = EDG_DIR
FROM dbo.LINE_VIS_EDG
WHERE EDG_DIR = 'O'
  AND EDG_1 IS NOT NULL AND EDG_2 IS NOT NULL
  AND EDG_3 IS NOT NULL AND EDG_4 IS NOT NULL;

PRINT 'Noeud de reference : LNA_UID = ' + @lna + ' / LIN_UID = ' + @lin + ' / EDG_DIR = ' + @dir;

-- Petite fonction "texte SQL" : met des quotes autour d'une valeur.
DECLARE @qLna VARCHAR(300) = '''' + @lna + '''',
        @qLin VARCHAR(600) = '''' + @lin + '''';

-------------------------------------------------------------------------------
-- 2. Liste des cas a mesurer
-------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#cases') IS NOT NULL DROP TABLE #cases;
CREATE TABLE #cases (
    id      INT IDENTITY PRIMARY KEY,
    proc_   VARCHAR(60),     -- procedure testee
    cas     VARCHAR(120),    -- description lisible du cas
    sql_    NVARCHAR(MAX),   -- appel exact
    runs    INT              -- nb d'executions
);

INSERT INTO #cases (proc_, cas, sql_, runs) VALUES
-- ---- LINE_VIS_NodesList ------------------------------------------------------
('NodesList', 'sans critere',                              N'EXEC dbo.LINE_VIS_NodesList', 3),
('NodesList', '@p_column = FIADODSWRK (1/3 des lignes)',   N'EXEC dbo.LINE_VIS_NodesList @p_column = ''FIADODSWRK''', 3),
('NodesList', '@p_column = fiadods (minuscules, tout)',    N'EXEC dbo.LINE_VIS_NodesList @p_column = ''fiadods''', 3),
('NodesList', '@p_schema = SPSS_LS2DC2 (1/5)',             N'EXEC dbo.LINE_VIS_NodesList @p_schema = ''SPSS_LS2DC2''', 3),
('NodesList', '@p_env = _123_WRK (selectif)',              N'EXEC dbo.LINE_VIS_NodesList @p_env = ''_123_WRK''', 3),
('NodesList', 'column + table + env (combine)',            N'EXEC dbo.LINE_VIS_NodesList @p_column = ''FIADODSOUT'', @p_table = ''ZJ'', @p_env = ''C_INSCTR''', 3),
('NodesList', 'aucun resultat (ZZZ_INTROUVABLE)',          N'EXEC dbo.LINE_VIS_NodesList @p_column = ''ZZZ_INTROUVABLE''', 3),
('NodesList', '@p_column = FIADODSWRK, @p_maxres = 1000',  N'EXEC dbo.LINE_VIS_NodesList @p_column = ''FIADODSWRK'', @p_maxres = 1000', 3),
-- ---- LINE_VIS_GetNodesSuccessorsPredecessors ---------------------------------
('GetNodesSuccPred', 'noeud precis, successeurs (@p_type = O)',
    N'EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessors @p_lnauid = ' + @qLna + N', @p_linuid = ' + @qLin + N', @p_edgdir = ''O'', @p_type = ''O''', 3),
('GetNodesSuccPred', 'noeud precis, predecesseurs (@p_type = I)',
    N'EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessors @p_lnauid = ' + @qLna + N', @p_linuid = ' + @qLin + N', @p_edgdir = ''O'', @p_type = ''I''', 3),
('GetNodesSuccPred', 'noeud precis, @p_useEdg = 1',
    N'EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessors @p_lnauid = ' + @qLna + N', @p_linuid = ' + @qLin + N', @p_edgdir = ''O'', @p_type = ''O'', @p_useEdg = 1', 3),
('GetNodesSuccPred', 'noeud inexistant',
    N'EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessors @p_lnauid = ''NOPE'', @p_linuid = ''NOPE'', @p_edgdir = ''O'', @p_type = ''O''', 1),
('GetNodesSuccPred', 'sans critere (seulement @p_type = O)',
    N'EXEC dbo.LINE_VIS_GetNodesSuccessorsPredecessors @p_type = ''O''', 1),
-- ---- LINE_VIS_NodeById -------------------------------------------------------
('NodeById', 'noeud precis (cle primaire)',
    N'EXEC dbo.LINE_VIS_NodeById @p_lnauid = ' + @qLna + N', @p_linuid = ' + @qLin + N', @p_edgdir = ''O''', 3),
('NodeById', 'noeud inexistant',
    N'EXEC dbo.LINE_VIS_NodeById @p_lnauid = ''NOPE'', @p_linuid = ''NOPE'', @p_edgdir = ''O''', 3),
('NodeById', 'sans critere (tous parametres NULL)',
    N'EXEC dbo.LINE_VIS_NodeById', 3);

-------------------------------------------------------------------------------
-- 3. Tables de reception (une par forme de resultat)
-------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#rNodesList') IS NOT NULL DROP TABLE #rNodesList;
CREATE TABLE #rNodesList (
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    LIN_UID VARCHAR(500), LNA_UID VARCHAR(200), EDG_DIR CHAR(1), TotalLignes INT
);

IF OBJECT_ID('tempdb..#rGetNodes') IS NOT NULL DROP TABLE #rGetNodes;
CREATE TABLE #rGetNodes (
    LNA_UID VARCHAR(200), LIN_UID VARCHAR(500), EDG_DIR CHAR(1),
    DTA_1 VARCHAR(1000), DTA_2 VARCHAR(1000), DTA_3 VARCHAR(8000), DTA_4 VARCHAR(1000),
    TXN_DTA VARCHAR(MAX),
    EDG_1 VARCHAR(1000), EDG_2 VARCHAR(1000), EDG_3 VARCHAR(8000), EDG_4 VARCHAR(1000),
    PRX_TXN_DTA VARCHAR(MAX),
    RON_APP VARCHAR(4), PCK_PGM_NME VARCHAR(500), EXE_PGM_NME VARCHAR(500),
    VRS_EXE_PGM VARCHAR(100), APP_ENV VARCHAR(20),
    DLY_PGM_TSP DATETIME2, LNA_TSP DATETIME2,
    PGM_TEC VARCHAR(20), VRS_LNA_TOO VARCHAR(100), TUS_IND INT,
    CURRENT_NODE VARCHAR(MAX), TotalLignes INT
);

IF OBJECT_ID('tempdb..#rNodeById') IS NOT NULL DROP TABLE #rNodeById;
CREATE TABLE #rNodeById (
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

-- Une ligne par execution
IF OBJECT_ID('tempdb..#mesures') IS NOT NULL DROP TABLE #mesures;
CREATE TABLE #mesures (
    case_id     INT,
    run_no      INT,
    duree_ms    INT,
    nb_lignes   INT,
    total_lig   INT       -- TotalLignes renvoye (NULL si la procedure n'en a pas)
);

-------------------------------------------------------------------------------
-- 4. Execution des cas
-------------------------------------------------------------------------------
DECLARE @id INT, @proc VARCHAR(60), @cas VARCHAR(120), @sql NVARCHAR(MAX), @runs INT;
DECLARE @r INT, @t0 DATETIME2(7), @ms INT, @n INT, @tot INT, @msg VARCHAR(400);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT id, proc_, cas, sql_, runs FROM #cases ORDER BY id;
OPEN c;
FETCH NEXT FROM c INTO @id, @proc, @cas, @sql, @runs;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @r = 1;
    WHILE @r <= @runs
    BEGIN
        TRUNCATE TABLE #rNodesList;
        TRUNCATE TABLE #rGetNodes;
        TRUNCATE TABLE #rNodeById;

        SET @t0 = SYSDATETIME();
        IF @proc = 'NodesList'        INSERT INTO #rNodesList EXEC (@sql);
        IF @proc = 'GetNodesSuccPred' INSERT INTO #rGetNodes  EXEC (@sql);
        IF @proc = 'NodeById'         INSERT INTO #rNodeById  EXEC (@sql);
        SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());

        SELECT @n = COUNT(*), @tot = MAX(TotalLignes) FROM #rNodesList WHERE @proc = 'NodesList';
        IF @proc = 'GetNodesSuccPred' SELECT @n = COUNT(*), @tot = MAX(TotalLignes) FROM #rGetNodes;
        IF @proc = 'NodeById'         SELECT @n = COUNT(*), @tot = NULL FROM #rNodeById;

        INSERT INTO #mesures VALUES (@id, @r, @ms, @n, @tot);

        SET @msg = @proc + ' | ' + @cas + ' | run ' + CAST(@r AS VARCHAR) + ' : '
                 + CAST(@ms AS VARCHAR) + ' ms, ' + CAST(@n AS VARCHAR) + ' ligne(s)';
        RAISERROR(@msg, 0, 1) WITH NOWAIT;   -- affichage immediat de la progression

        SET @r += 1;
    END
    FETCH NEXT FROM c INTO @id, @proc, @cas, @sql, @runs;
END
CLOSE c;
DEALLOCATE c;

-------------------------------------------------------------------------------
-- 5. Statistiques
-------------------------------------------------------------------------------
PRINT '';
PRINT '=== Statistiques par cas (temps de retour en ms) ===';
SELECT
    k.id                         AS [#],
    k.proc_                      AS [Procedure],
    k.cas                        AS [Cas],
    COUNT(*)                     AS [Runs],
    MIN(m.duree_ms)              AS [Min ms],
    AVG(m.duree_ms)              AS [Moy ms],
    MAX(m.duree_ms)              AS [Max ms],
    MAX(m.nb_lignes)             AS [Lignes renvoyees],
    MAX(m.total_lig)             AS [TotalLignes]
FROM #cases k
JOIN #mesures m ON m.case_id = k.id
GROUP BY k.id, k.proc_, k.cas
ORDER BY k.id;

PRINT '=== Resume par procedure ===';
SELECT
    k.proc_                      AS [Procedure],
    COUNT(DISTINCT k.id)         AS [Nb cas],
    COUNT(*)                     AS [Nb appels],
    MIN(m.duree_ms)              AS [Min ms],
    AVG(m.duree_ms)              AS [Moy ms],
    MAX(m.duree_ms)              AS [Max ms],
    SUM(m.duree_ms)              AS [Total ms]
FROM #cases k
JOIN #mesures m ON m.case_id = k.id
GROUP BY k.proc_
ORDER BY k.proc_;

PRINT '=== Volumes ===';
SELECT
    (SELECT COUNT_BIG(*) FROM dbo.LINE_VIS_EDG) AS [Lignes LINE_VIS_EDG],
    (SELECT COUNT_BIG(*) FROM dbo.LINE_VIS_HEA) AS [Lignes LINE_VIS_HEA];
GO
