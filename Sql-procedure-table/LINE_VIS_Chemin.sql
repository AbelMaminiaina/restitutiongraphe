-- =============================================================================
--  Procedure dbo.LINE_VIS_Chemin
--  Base : RestitutionGrapheProd
--
--  But : "comment le noeud A alimente-t-il le noeud B ?"
--  Renvoie les PLUS COURTS chemins de A vers B, dans le sens du flux de
--  donnees (A -> ... -> B, en suivant les successeurs). Pour savoir si B
--  alimente A, inverser les deux noeuds.
--
--  Methode :
--    1. parcours en largeur depuis A, en aval (dbo.LINE_VIS_Lineage_Parcours,
--       le meme que LINE_VIS_Lineage), arrete des que B est atteint : le
--       niveau de B = longueur du plus court chemin ;
--    2. a partir de B, on remonte les liens d'un niveau vers le niveau
--       precedent : on garde exactement les noeuds et liens qui sont sur
--       UN des plus courts chemins (s'il y en a plusieurs, ils sont tous la) ;
--    3. NB_CHEMINS = nombre de plus courts chemins differents (calcule
--       niveau par niveau, sans les enumerer).
--  Rien n'est ecrit dans la base (tables #temporaires dans tempdb).
--
--  Parametres :
--    @p_src_lnauid, @p_src_linuid, @p_src_edgdir : noeud A (une ligne de
--        LINE_VIS_EDG, comme renvoyee par LINE_VIS_NodesList).
--    @p_dst_lnauid, @p_dst_linuid, @p_dst_edgdir : noeud B (idem).
--    @p_profondeur : longueur maximum cherchee (defaut 10).
--    @p_maxnoeuds  : nombre maximum de noeuds parcourus (defaut 5000) ;
--                    atteint -> TRONQUE = 1 (un chemin plus long peut
--                    exister au-dela).
--    @p_sortie     : 'T' = les 3 jeux de resultats (defaut), 'R' = resume,
--                    'N' = noeuds, 'A' = aretes (un seul jeu : pour
--                    INSERT ... EXEC).
--
--  Resultats :
--    1. RESUME (toujours 1 ligne) : SRC_TROUVE, DST_TROUVE (lignes de
--       depart / d'arrivee presentes dans LINE_VIS_EDG), CHEMIN_TROUVE,
--       LONGUEUR (nombre de liens, NULL si pas de chemin), NB_CHEMINS,
--       NB_NOEUDS_PARCOURUS, TRONQUE.
--    2. NOEUDS du ou des chemins : NOD_ID, POSITION (0 = A, LONGUEUR = B),
--       DTA_1..DTA_4, NOM_NOEUD, NB_CHEMINS (plus courts chemins de A
--       jusqu'a ce noeud).
--    3. ARETES du ou des chemins : SRC_NOD_ID -> DST_NOD_ID, POSITION
--       (celle de la source), NB_LIENS, NB_PROGRAMMES, PROGRAMMES (liste
--       des EXE_PGM_NME qui portent ce lien, LINE_VIS_HEA).
--
--  Dependances : dbo.LINE_VIS_Lineage_Parcours, dbo.LINE_VIS_EDG,
--                dbo.LINE_VIS_HEA
-- =============================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_Chemin]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_Chemin
GO

CREATE PROCEDURE [dbo].LINE_VIS_Chemin
    @p_src_lnauid VARCHAR(200) = NULL,
    @p_src_linuid VARCHAR(500) = NULL,
    @p_src_edgdir CHAR(1)      = NULL,
    @p_dst_lnauid VARCHAR(200) = NULL,
    @p_dst_linuid VARCHAR(500) = NULL,
    @p_dst_edgdir CHAR(1)      = NULL,
    @p_profondeur INT          = 10,
    @p_maxnoeuds  INT          = 5000,
    @p_sortie     CHAR(1)      = 'T'

AS
BEGIN
    SET NOCOUNT ON

    IF @p_sortie IS NULL OR @p_sortie NOT IN ('T', 'R', 'N', 'A')
        THROW 50002, 'LINE_VIS_Chemin : @p_sortie doit valoir T (tout), R (resume), N (noeuds) ou A (aretes).', 1;

    SET @p_profondeur = COALESCE(@p_profondeur, 10)
    SET @p_maxnoeuds  = COALESCE(@p_maxnoeuds, 5000)

    /* 1. Noeud d'arrivee B : ses coordonnees, lues par la cle primaire */
    DECLARE @dstTrouve BIT = 0
    DECLARE @dstHash   INT
    DECLARE @dst1 VARCHAR(1000), @dst2 VARCHAR(1000), @dst3 VARCHAR(8000), @dst4 VARCHAR(1000)

    SELECT TOP (1)
        @dstTrouve = 1,
        @dstHash   = e.DTA_HASH,
        @dst1 = e.DTA_1, @dst2 = e.DTA_2, @dst3 = e.DTA_3, @dst4 = e.DTA_4
    FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
    WHERE e.LNA_UID = @p_dst_lnauid
      AND e.LIN_UID = @p_dst_linuid
      AND e.EDG_DIR = @p_dst_edgdir

    /* 2. Parcours en aval depuis A, arrete quand B est atteint.
          Tables remplies par LINE_VIS_Lineage_Parcours (voir son en-tete). */
    CREATE TABLE #noeuds (
        NOD_ID   INT IDENTITY(1, 1) PRIMARY KEY,
        NOD_HASH INT NOT NULL,
        DTA_1    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_2    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_3    VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        DTA_4    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        NIVEAU   INT     NOT NULL,
        SENS     CHAR(1) NOT NULL
    )
    CREATE INDEX IX_noeuds_hash ON #noeuds (NOD_HASH)

    CREATE TABLE #liens (
        SRC_ID   INT NOT NULL,
        DST_ID   INT NOT NULL,
        LNA_UID  VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        NB_LIENS INT NOT NULL
    )

    DECLARE @tronque BIT = 0

    -- B introuvable : inutile de parcourir (aucun chemin possible)
    IF @dstTrouve = 1
        EXEC dbo.LINE_VIS_Lineage_Parcours
            @p_src_lnauid, @p_src_linuid, @p_src_edgdir, 'O',
            @p_profondeur, @p_maxnoeuds, @tronque OUTPUT,
            @dstHash, @dst1, @dst2, @dst3, @dst4
    ELSE
        -- seulement pour savoir si A existe (resume)
        INSERT INTO #noeuds (NOD_HASH, DTA_1, DTA_2, DTA_3, DTA_4, NIVEAU, SENS)
        SELECT TOP (1) e.DTA_HASH, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4, 0, '-'
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.LNA_UID = @p_src_lnauid
          AND e.LIN_UID = @p_src_linuid
          AND e.EDG_DIR = @p_src_edgdir

    DECLARE @srcTrouve BIT = CASE WHEN EXISTS (SELECT 1 FROM #noeuds) THEN 1 ELSE 0 END

    -- B dans les noeuds parcourus ? son niveau = longueur du plus court chemin
    DECLARE @dstId    INT
    DECLARE @longueur INT

    IF @dstTrouve = 1
        SELECT @dstId = n.NOD_ID, @longueur = n.NIVEAU
        FROM #noeuds n
        WHERE n.NOD_HASH = @dstHash
          AND (n.DTA_1 = @dst1 OR (n.DTA_1 IS NULL AND @dst1 IS NULL))
          AND (n.DTA_2 = @dst2 OR (n.DTA_2 IS NULL AND @dst2 IS NULL))
          AND (n.DTA_3 = @dst3 OR (n.DTA_3 IS NULL AND @dst3 IS NULL))
          AND (n.DTA_4 = @dst4 OR (n.DTA_4 IS NULL AND @dst4 IS NULL))

    /* 3. Liens "utiles" : d'un niveau au niveau suivant. Seuls ceux-la
          peuvent etre sur un plus court chemin (un lien vers un noeud de
          meme niveau ou plus proche de A rallongerait le chemin). */
    CREATE TABLE #pas (
        SRC_ID   INT NOT NULL,
        DST_ID   INT NOT NULL,
        POSITION INT NOT NULL      -- niveau de la source
    )
    INSERT INTO #pas (SRC_ID, DST_ID, POSITION)
    SELECT DISTINCT l.SRC_ID, l.DST_ID, s.NIVEAU
    FROM #liens l
    INNER JOIN #noeuds s ON s.NOD_ID = l.SRC_ID
    INNER JOIN #noeuds d ON d.NOD_ID = l.DST_ID
    WHERE d.NIVEAU = s.NIVEAU + 1

    /* 4. Remontee depuis B : noeuds sur un plus court chemin, niveau par
          niveau (B, puis ses sources au niveau LONGUEUR-1, etc.). */
    CREATE TABLE #chemin (
        NOD_ID     INT PRIMARY KEY,
        POSITION   INT NOT NULL,
        NB_CHEMINS BIGINT NULL     -- plus courts chemins de A jusqu'ici
    )

    DECLARE @pos INT

    IF @dstId IS NOT NULL
    BEGIN
        INSERT INTO #chemin (NOD_ID, POSITION) VALUES (@dstId, @longueur)

        SET @pos = @longueur
        WHILE @pos > 0
        BEGIN
            INSERT INTO #chemin (NOD_ID, POSITION)
            SELECT DISTINCT p.SRC_ID, @pos - 1
            FROM #pas p
            INNER JOIN #chemin c ON c.NOD_ID = p.DST_ID AND c.POSITION = @pos
            SET @pos -= 1
        END

        /* 5. Nombre de plus courts chemins : 1 pour A, puis pour chaque
              noeud la somme de ceux de ses sources du niveau precedent. */
        UPDATE #chemin SET NB_CHEMINS = 1 WHERE POSITION = 0

        SET @pos = 1
        WHILE @pos <= @longueur
        BEGIN
            UPDATE c
            SET NB_CHEMINS = (SELECT SUM(src.NB_CHEMINS)
                              FROM #pas p
                              INNER JOIN #chemin src ON src.NOD_ID = p.SRC_ID
                              WHERE p.DST_ID = c.NOD_ID)
            FROM #chemin c
            WHERE c.POSITION = @pos
            SET @pos += 1
        END
    END

    /* 6. Resultats */
    IF @p_sortie IN ('T', 'R')
        SELECT
            @srcTrouve                                                 AS SRC_TROUVE,
            @dstTrouve                                                 AS DST_TROUVE,
            CAST(CASE WHEN @dstId IS NULL THEN 0 ELSE 1 END AS BIT)    AS CHEMIN_TROUVE,
            @longueur                                                  AS LONGUEUR,
            COALESCE((SELECT NB_CHEMINS FROM #chemin WHERE NOD_ID = @dstId), 0) AS NB_CHEMINS,
            (SELECT COUNT(*) FROM #noeuds)                             AS NB_NOEUDS_PARCOURUS,
            COALESCE(@tronque, 0)                                      AS TRONQUE

    IF @p_sortie IN ('T', 'N')
        SELECT
            c.NOD_ID,
            c.POSITION,
            n.DTA_1,
            n.DTA_2,
            n.DTA_3,
            n.DTA_4,
            CONCAT_WS('.', NULLIF(n.DTA_4, ''), NULLIF(n.DTA_3, ''),
                           NULLIF(n.DTA_2, ''), NULLIF(n.DTA_1, ''))  AS NOM_NOEUD,
            c.NB_CHEMINS
        FROM #chemin c
        INNER JOIN #noeuds n ON n.NOD_ID = c.NOD_ID
        ORDER BY c.POSITION, n.DTA_4, n.DTA_3, n.DTA_2, n.DTA_1

    /* Aretes du chemin, avec les programmes (LINE_VIS_HEA) qui les portent */
    IF @p_sortie IN ('T', 'A')
        SELECT
            p.SRC_ID                  AS SRC_NOD_ID,
            p.DST_ID                  AS DST_NOD_ID,
            p.POSITION,
            SUM(l.NB_LIENS)           AS NB_LIENS,
            COUNT(*)                  AS NB_PROGRAMMES,
            (SELECT STRING_AGG(x.EXE_PGM_NME, ', ') WITHIN GROUP (ORDER BY x.EXE_PGM_NME)
             FROM (SELECT DISTINCT COALESCE(h.EXE_PGM_NME, '') AS EXE_PGM_NME
                   FROM #liens l2
                   INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = l2.LNA_UID
                   WHERE l2.SRC_ID = p.SRC_ID AND l2.DST_ID = p.DST_ID) x) AS PROGRAMMES
        FROM #pas p
        INNER JOIN #chemin cs ON cs.NOD_ID = p.SRC_ID AND cs.POSITION = p.POSITION
        INNER JOIN #chemin cd ON cd.NOD_ID = p.DST_ID AND cd.POSITION = p.POSITION + 1
        INNER JOIN #liens l   ON l.SRC_ID = p.SRC_ID AND l.DST_ID = p.DST_ID
        GROUP BY p.SRC_ID, p.DST_ID, p.POSITION
        ORDER BY p.POSITION, p.SRC_ID, p.DST_ID
END
GO
