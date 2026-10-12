-- =============================================================================
--  Procedure dbo.LINE_VIS_GetNodesSuccessorsPredecessors (version hash generique)
--  Base : RestitutionGrapheProd (adapter le USE si besoin, ex. LINE_VIS_NI)
--
--  Reprise de Sql-procedure-table/LINE_VIS_GetNodesSuccessorsPredecessors.sql
--  (memes parametres, memes colonnes, meme ordre en sortie), optimisee
--  autour des colonnes calculees de LINE_VIS_EDG :
--    DTA_HASH   = CHECKSUM(DTA_1, DTA_2, DTA_3, DTA_4)
--    DTA_n_HASH = CHECKSUM(DTA_n)          (n = 1..4)
--
--  But : a partir d'un noeud (LNA_UID, LIN_UID, EDG_DIR = @p_edgdir), lire
--  ses coordonnees DTA_1..DTA_4 (ou EDG_1..EDG_4 si @p_useEdg = 1), puis
--  renvoyer les aretes qui ont ces coordonnees et EDG_DIR = @p_type, jointes
--  a LINE_VIS_HEA, limitees a @p_maxres lignes, avec le total (TotalLignes).
--  Une coordonnee NULL = pas de filtre dessus (regle d'origine).
--
--  -------------------------------------------------------------------------
--  Hypothese : une recherche trouve au plus quelques centaines de lignes.
--
--    1. Hash lus dans la table, pas recalcules sur des variables : CHECKSUM
--       depend de la collation (variables = collation de la BASE, colonnes =
--       collation des COLONNES). A l'etape 1 (lecture du noeud) :
--         @p_useEdg = 0 -> hash deja calcules du noeud (DTA_HASH, DTA_n_HASH) ;
--         @p_useEdg = 1 -> CHECKSUM(EDG_n) calcule sur les colonnes.
--
--    2. Sondage : pour chaque coordonnee connue, nombre de lignes de meme
--       hash compte dans son index etroit, arrete a 501 (2e passe a 20 001
--       si toutes atteignent 501). La plus selective "mene" la recherche.
--
--    3. Recherche par l'index de la coordonnee qui mene (INDEX impose, plan
--       fixe, SANS recompilation), puis egalite exacte sur toutes les
--       coordonnees connues (elimine les collisions de CHECKSUM : resultat
--       toujours juste). Les 4 connues -> index couvrant
--       IX_LINE_VIS_EDG_DIR_HASH, sans sondage.
--
--    4. Lignes trouvees -> table @trouve : total (TotalLignes) et tri des
--       @p_maxres premieres se font sur cette petite table.
--
--  Aucune coordonnee connue (noeud introuvable) : aucun filtre, parcours de
--  la table (plusieurs secondes), cas exceptionnel.
--
--  Mesure (copie de 7,2 M lignes, 30 appels par cas, temps moyen) :
--      lignes trouvees      avant          apres
--              1          1,5 a 3,4 s      0 ms
--            100              -            3 a 5 ms
--            300              -           10 a 16 ms
--            500              -           19 a 23 ms
--          2 100          3,0 a 3,8 s     90 ms
--  Au-dela, le temps croit avec le nombre de lignes trouvees (~4 ms par
--  100 lignes : lecture dans la table + envoi des colonnes VARCHAR(MAX)).
--
--  Tri : DTA_1..DTA_4 puis LNA_UID, LIN_UID (comme le chemin general
--  d'avant). Les 4 coordonnees connues -> elles sont toutes egales, l'ordre
--  revient a LNA_UID, LIN_UID (comme le chemin rapide d'avant).
--
--  Dependances : dbo.LINE_VIS_EDG + colonnes DTA_HASH, DTA_n_HASH + index
--                IX_LINE_VIS_EDG_DIR_HASH, IX_LINE_VIS_EDG_DIR_HASH1..4
--                (LINE_VIS_EDG.sql de ce dossier), dbo.LINE_VIS_HEA
--                (LINE_VIS_HEA.sql de ce dossier)
-- =============================================================================

-- Obligatoire pour que la procedure puisse utiliser les index sur les
-- colonnes calculees (ces 2 options sont memorisees a la creation).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

CREATE OR ALTER PROCEDURE dbo.LINE_VIS_GetNodesSuccessorsPredecessors
    @p_lnauid   VARCHAR(200) = NULL,
    @p_linuid   VARCHAR(500) = NULL,
    @p_edgdir   CHAR(1)      = NULL,
    @p_type     CHAR(1)      = NULL,
    @p_useEdg   BIT          = 0,
    @p_maxres   INT          = 100
AS
BEGIN
    SET NOCOUNT ON

    /* 1. Coordonnees + hash du noeud, par la cle primaire
          (LNA_UID, LIN_UID, EDG_DIR) -> lecture directe d'une ligne.
          Noeud introuvable -> tout reste NULL -> aucun filtre sur les
          coordonnees (regle d'origine). */
    DECLARE @DTA1 VARCHAR(1000)
    DECLARE @DTA2 VARCHAR(1000)
    DECLARE @DTA3 VARCHAR(8000)
    DECLARE @DTA4 VARCHAR(1000)
    DECLARE @h    INT          -- hash des 4 coordonnees
    DECLARE @h1   INT          -- hash de chaque coordonnee
    DECLARE @h2   INT
    DECLARE @h3   INT
    DECLARE @h4   INT

    SELECT TOP(1)
        @DTA1 = CASE WHEN @p_useEdg = 0 THEN DTA_1 ELSE EDG_1 END,
        @DTA2 = CASE WHEN @p_useEdg = 0 THEN DTA_2 ELSE EDG_2 END,
        @DTA3 = CASE WHEN @p_useEdg = 0 THEN DTA_3 ELSE EDG_3 END,
        @DTA4 = CASE WHEN @p_useEdg = 0 THEN DTA_4 ELSE EDG_4 END,
        -- Hash calcules sur les COLONNES (meme collation que DTA_*_HASH)
        @h    = CASE WHEN @p_useEdg = 0 THEN DTA_HASH
                     ELSE CHECKSUM(EDG_1, EDG_2, EDG_3, EDG_4) END,
        @h1   = CASE WHEN @p_useEdg = 0 THEN DTA_1_HASH ELSE CHECKSUM(EDG_1) END,
        @h2   = CASE WHEN @p_useEdg = 0 THEN DTA_2_HASH ELSE CHECKSUM(EDG_2) END,
        @h3   = CASE WHEN @p_useEdg = 0 THEN DTA_3_HASH ELSE CHECKSUM(EDG_3) END,
        @h4   = CASE WHEN @p_useEdg = 0 THEN DTA_4_HASH ELSE CHECKSUM(EDG_4) END
    FROM dbo.LINE_VIS_EDG
    WHERE LNA_UID  = @p_lnauid
      AND LIN_UID  = @p_linuid
      AND EDG_DIR  = @p_edgdir

    -- CHECKSUM(NULL) n'est pas NULL : on remet a NULL le hash de chaque
    -- coordonnee NULL (= pas de filtre), et le hash global si l'une manque.
    IF @DTA1 IS NULL SET @h1 = NULL
    IF @DTA2 IS NULL SET @h2 = NULL
    IF @DTA3 IS NULL SET @h3 = NULL
    IF @DTA4 IS NULL SET @h4 = NULL
    IF @h1 IS NULL OR @h2 IS NULL OR @h3 IS NULL OR @h4 IS NULL SET @h = NULL

    /* 2. Recherche SANS recompilation (plans stables, mis en cache) :
          on suppose qu'une recherche trouve au plus quelques centaines de
          lignes.
          a) Sondage : pour chaque coordonnee connue, nombre de lignes de
             meme hash, compte dans son index etroit et arrete a @plafond
             (TOP) -> peu de lignes d'index lues, quelques ms au plus.
             Plafond 501 d'abord ; si TOUTES les coordonnees l'atteignent,
             le sondage ne les departage pas -> 2e passe a 20 001 (sinon
             une coordonnee a 600 000 lignes pourrait mener : 10 s, mesure).
          b) La coordonnee la plus selective "mene" la recherche : seek dans
             son index (INDEX impose : plan fixe), puis egalite exacte sur
             toutes les coordonnees connues (elimine les collisions de
             CHECKSUM). Les 4 connues -> index couvrant
             IX_LINE_VIS_EDG_DIR_HASH, sans sondage.
          c) Toutes les lignes trouvees vont dans @trouve : total et tri se
             font sur cette petite table. */
    DECLARE @mene    TINYINT           -- coordonnee qui mene (1..4)
    DECLARE @nMin    INT
    DECLARE @n       INT
    DECLARE @plafond INT = 501

    WHILE @h IS NULL
    BEGIN
        SELECT @nMin = 2147483647, @mene = NULL

        IF @h1 IS NOT NULL
        BEGIN
            SELECT @n = COUNT(*) FROM (
                SELECT TOP (@plafond) 1 AS x
                FROM dbo.LINE_VIS_EDG WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH1))
                WHERE EDG_DIR = @p_type AND DTA_1_HASH = @h1) z
            IF @n < @nMin SELECT @nMin = @n, @mene = 1
        END
        IF @h2 IS NOT NULL
        BEGIN
            SELECT @n = COUNT(*) FROM (
                SELECT TOP (@plafond) 1 AS x
                FROM dbo.LINE_VIS_EDG WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH2))
                WHERE EDG_DIR = @p_type AND DTA_2_HASH = @h2) z
            IF @n < @nMin SELECT @nMin = @n, @mene = 2
        END
        IF @h3 IS NOT NULL
        BEGIN
            SELECT @n = COUNT(*) FROM (
                SELECT TOP (@plafond) 1 AS x
                FROM dbo.LINE_VIS_EDG WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH3))
                WHERE EDG_DIR = @p_type AND DTA_3_HASH = @h3) z
            IF @n < @nMin SELECT @nMin = @n, @mene = 3
        END
        IF @h4 IS NOT NULL
        BEGIN
            SELECT @n = COUNT(*) FROM (
                SELECT TOP (@plafond) 1 AS x
                FROM dbo.LINE_VIS_EDG WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH4))
                WHERE EDG_DIR = @p_type AND DTA_4_HASH = @h4) z
            IF @n < @nMin SELECT @nMin = @n, @mene = 4
        END

        -- Departagees (ou aucune coordonnee connue, ou 2e passe faite) : fini.
        IF @mene IS NULL OR @nMin < @plafond OR @plafond > 501 BREAK
        SET @plafond = 20001
    END

    DECLARE @trouve TABLE (
        LNA_UID VARCHAR(200),
        LIN_UID VARCHAR(500),
        EDG_DIR CHAR(1),
        DTA_1   VARCHAR(1000),
        DTA_2   VARCHAR(1000),
        DTA_3   VARCHAR(8000),
        DTA_4   VARCHAR(1000)
    )

    IF @h IS NOT NULL
        -- Les 4 coordonnees connues : tout se lit dans l'index couvrant.
        INSERT INTO @trouve
        SELECT e.LNA_UID, e.LIN_UID, e.EDG_DIR, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH))
        WHERE e.EDG_DIR = @p_type AND e.DTA_HASH = @h
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
    ELSE IF @mene = 1
        INSERT INTO @trouve
        SELECT e.LNA_UID, e.LIN_UID, e.EDG_DIR, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH1))
        WHERE e.EDG_DIR = @p_type AND e.DTA_1_HASH = @h1 AND e.DTA_1 = @DTA1
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
    ELSE IF @mene = 2
        INSERT INTO @trouve
        SELECT e.LNA_UID, e.LIN_UID, e.EDG_DIR, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH2))
        WHERE e.EDG_DIR = @p_type AND e.DTA_2_HASH = @h2 AND e.DTA_2 = @DTA2
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
    ELSE IF @mene = 3
        INSERT INTO @trouve
        SELECT e.LNA_UID, e.LIN_UID, e.EDG_DIR, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH3))
        WHERE e.EDG_DIR = @p_type AND e.DTA_3_HASH = @h3 AND e.DTA_3 = @DTA3
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
    ELSE IF @mene = 4
        INSERT INTO @trouve
        SELECT e.LNA_UID, e.LIN_UID, e.EDG_DIR, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH4))
        WHERE e.EDG_DIR = @p_type AND e.DTA_4_HASH = @h4 AND e.DTA_4 = @DTA4
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)

    DECLARE @TotalLignes INT
    DECLARE @cles TABLE (
        LNA_UID VARCHAR(200),
        LIN_UID VARCHAR(500),
        EDG_DIR CHAR(1),
        Ordre   INT            -- ordre d'affichage (1, 2, 3...)
    )

    IF @h IS NOT NULL OR @mene IS NOT NULL
    BEGIN
        SELECT @TotalLignes = COUNT(*) FROM @trouve

        INSERT INTO @cles (LNA_UID, LIN_UID, EDG_DIR, Ordre)
        SELECT TOP (@p_maxres)
            t.LNA_UID, t.LIN_UID, t.EDG_DIR,
            ROW_NUMBER() OVER (ORDER BY t.DTA_1, t.DTA_2, t.DTA_3, t.DTA_4,
                                        t.LNA_UID, t.LIN_UID)
        FROM @trouve t
        ORDER BY t.DTA_1, t.DTA_2, t.DTA_3, t.DTA_4, t.LNA_UID, t.LIN_UID
    END
    ELSE
    BEGIN
        /* Aucune coordonnee connue (noeud introuvable, ou EDG_1..EDG_4 tous
           NULL) : aucun filtre, toutes les aretes de type @p_type. Parcours
           de la table, lent (plusieurs secondes), cas exceptionnel.
           OPTION (HASH JOIN) : pour le EXISTS sur LINE_VIS_HEA. */
        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
        OPTION (HASH JOIN)

        -- ROW_NUMBER() hors du TOP : sinon tri de toutes les lignes.
        IF @TotalLignes > 0
        INSERT INTO @cles (LNA_UID, LIN_UID, EDG_DIR, Ordre)
        SELECT k.LNA_UID, k.LIN_UID, k.EDG_DIR,
               ROW_NUMBER() OVER (ORDER BY k.DTA_1, k.DTA_2, k.DTA_3, k.DTA_4,
                                           k.LNA_UID, k.LIN_UID)
        FROM (
            SELECT TOP (@p_maxres)
                c.LNA_UID, c.LIN_UID, c.EDG_DIR,
                c.DTA_1, c.DTA_2, c.DTA_3, c.DTA_4
            FROM dbo.LINE_VIS_EDG c WITH (NOLOCK)
            WHERE c.EDG_DIR = @p_type
              AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                          WHERE hh.LNA_UID = c.LNA_UID)
            ORDER BY c.DTA_1, c.DTA_2, c.DTA_3, c.DTA_4, c.LNA_UID, c.LIN_UID
        ) k
        OPTION (RECOMPILE, HASH JOIN)
    END

    /* 3. Sortie : relecture des colonnes larges par la cle primaire,
          jointure LINE_VIS_HEA + CURRENT_NODE, pour les <= @p_maxres
          lignes de @cles seulement. */
    SELECT
        e.LNA_UID,
        e.LIN_UID,
        e.EDG_DIR,
        e.DTA_1,
        e.DTA_2,
        e.DTA_3,
        e.DTA_4,
        e.TXN_DTA,
        e.EDG_1,
        e.EDG_2,
        e.EDG_3,
        e.EDG_4,
        e.PRX_TXN_DTA,
        COALESCE(h.RON_APP, '')      AS RON_APP,
        COALESCE(h.PCK_PGM_NME, '')  AS PCK_PGM_NME,
        COALESCE(h.EXE_PGM_NME,'')   AS EXE_PGM_NME,
        COALESCE(h.VRS_EXE_PGM,'')   AS VRS_EXE_PGM,
        COALESCE(h.APP_ENV, '')      AS APP_ENV,
        COALESCE(h.DLY_PGM_TSP, '')  AS DLY_PGM_TSP,   -- NULL -> 1900-01-01 (comme l'original)
        COALESCE(h.LNA_TSP, '')      AS LNA_TSP,       -- idem
        COALESCE(h.PGM_TEC, '')      AS PGM_TEC,
        COALESCE(h.VRS_LNA_TOO, '')  AS VRS_LNA_TOO,
        COALESCE(h.TUS_IND, 0)       AS TUS_IND,
        -- CURRENT_NODE : "EDG_4.EDG_3.EDG_2.EDG_1", logique d'origine
        CASE
            WHEN COALESCE(e.EDG_4, '') = '' AND COALESCE(e.EDG_3, '') = '' AND
                 COALESCE(e.EDG_2, '') = '' AND COALESCE(e.EDG_1, '') = '' THEN ''
            ELSE RTRIM(LTRIM(
                CASE WHEN e.EDG_4 IS NOT NULL AND e.EDG_4 <> '' THEN e.EDG_4 ELSE '' END +
                CASE WHEN e.EDG_3 IS NOT NULL AND e.EDG_3 <> '' AND (e.EDG_4 IS NOT NULL AND e.EDG_4 <> '') THEN '.' + e.EDG_3 ELSE '' END +
                CASE WHEN e.EDG_2 IS NOT NULL AND e.EDG_2 <> '' AND (e.EDG_3 IS NOT NULL AND e.EDG_3 <> '') THEN '.' + e.EDG_2 ELSE '' END +
                CASE WHEN e.EDG_1 IS NOT NULL AND e.EDG_1 <> '' AND (e.EDG_2 IS NOT NULL AND e.EDG_2 <> '') THEN '.' + e.EDG_1 ELSE '' END
            ))
        END AS CURRENT_NODE,
        @TotalLignes AS TotalLignes
    FROM @cles k
    INNER JOIN dbo.LINE_VIS_EDG e WITH (NOLOCK)
            ON e.LNA_UID = k.LNA_UID
           AND e.LIN_UID = k.LIN_UID
           AND e.EDG_DIR = k.EDG_DIR
    INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = k.LNA_UID
    ORDER BY k.Ordre
END
GO
