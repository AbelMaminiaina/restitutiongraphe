-- =============================================================================
--  Procedure dbo.LINE_VIS_GetNodesSuccessorsPredecessors (version DTA_HASH)
--  Base : RestitutionGrapheProd (adapter le USE si besoin, ex. LINE_VIS_NI)
--
--  Reprise de Sql-procedure-table/LINE_VIS_GetNodesSuccessorsPredecessors.sql
--  (memes parametres, memes colonnes, meme ordre en sortie), optimisee
--  autour de la colonne calculee DTA_HASH = CHECKSUM(DTA_1, DTA_2, DTA_3, DTA_4).
--
--  But : a partir d'un noeud (LNA_UID, LIN_UID, EDG_DIR = @p_edgdir), lire
--  ses coordonnees DTA_1..DTA_4 (ou EDG_1..EDG_4 si @p_useEdg = 1), puis
--  renvoyer les aretes qui ont ces coordonnees et EDG_DIR = @p_type, jointes
--  a LINE_VIS_HEA, limitees a @p_maxres lignes, avec le total (TotalLignes).
--
--  -------------------------------------------------------------------------
--  Optimisations par rapport a la version Sql-procedure-table :
--
--    1. Hash lu dans la table, pas recalcule sur des variables.
--       Avant : @h = CHECKSUM(@DTA1, @DTA2, @DTA3, @DTA4) sur des variables.
--       Or CHECKSUM depend de la collation : les variables prennent celle de
--       la BASE, DTA_HASH celle des COLONNES. Si elles different, @h ne
--       retrouve aucune ligne (resultat vide, silencieusement).
--       Maintenant, a l'etape 1 (lecture du noeud par la cle primaire) :
--         @p_useEdg = 0 -> @h = DTA_HASH du noeud (deja calcule) ;
--         @p_useEdg = 1 -> @h = CHECKSUM(EDG_1, EDG_2, EDG_3, EDG_4), calcule
--                          sur les colonnes -> meme collation que DTA_HASH.
--
--    2. Index couvrant (LINE_VIS_EDG.sql de ce dossier) :
--         IX_LINE_VIS_EDG_DIR_HASH (EDG_DIR, DTA_HASH) INCLUDE (DTA_1..DTA_4)
--       Le controle anti-collision (DTA_n = @DTAn) et le COUNT(*) se font
--       dans l'index seul : plus de lecture de la table ligne par ligne
--       (avant : 1 lookup par ligne trouvee, soit des milliers pour un noeud
--       tres partage). Seules les @p_maxres lignes affichees sont relues
--       dans la table (pour TXN_DTA, EDG_*, PRX_TXN_DTA).
--
--    3. Chemin rapide en 2 temps, comme le chemin general : on ne garde
--       d'abord que les CLES des @p_maxres premieres lignes (lues dans
--       l'index, deja dans l'ordre LNA_UID, LIN_UID : aucun tri), puis on
--       relit les colonnes larges pour ces seules lignes.
--
--    Inchange : chemin general (noeud introuvable, ou coordonnees EDG en
--    partie NULL avec @p_useEdg = 1 : une coordonnee NULL = pas de filtre,
--    le hash ne peut pas servir), etape 3 (jointure LINE_VIS_HEA +
--    CURRENT_NODE sur les <= @p_maxres lignes).
--
--  Rappel : DTA_HASH peut etre identique pour deux noeuds differents
--  (collision de CHECKSUM) ; l'egalite exacte DTA_n = @DTAn est gardee,
--  le resultat est donc toujours juste.
--
--  Dependances : dbo.LINE_VIS_EDG + index IX_LINE_VIS_EDG_DIR_HASH
--                (LINE_VIS_EDG.sql de ce dossier), dbo.LINE_VIS_HEA
--                (LINE_VIS_HEA.sql de ce dossier)
-- =============================================================================

-- Obligatoire pour que la procedure puisse utiliser l'index sur la colonne
-- calculee DTA_HASH (ces 2 options sont memorisees a la creation).
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
          Noeud introuvable -> tout reste NULL -> chemin general. */
    DECLARE @DTA1 VARCHAR(1000)
    DECLARE @DTA2 VARCHAR(1000)
    DECLARE @DTA3 VARCHAR(8000)
    DECLARE @DTA4 VARCHAR(1000)
    DECLARE @h    INT

    SELECT TOP(1)
        @DTA1 = CASE WHEN @p_useEdg = 0 THEN DTA_1 ELSE EDG_1 END,
        @DTA2 = CASE WHEN @p_useEdg = 0 THEN DTA_2 ELSE EDG_2 END,
        @DTA3 = CASE WHEN @p_useEdg = 0 THEN DTA_3 ELSE EDG_3 END,
        @DTA4 = CASE WHEN @p_useEdg = 0 THEN DTA_4 ELSE EDG_4 END,
        -- Hash calcule sur les COLONNES (meme collation que DTA_HASH)
        @h    = CASE WHEN @p_useEdg = 0 THEN DTA_HASH
                     ELSE CHECKSUM(EDG_1, EDG_2, EDG_3, EDG_4) END
    FROM dbo.LINE_VIS_EDG
    WHERE LNA_UID  = @p_lnauid
      AND LIN_UID  = @p_linuid
      AND EDG_DIR  = @p_edgdir

    /* 2. Cles des lignes a afficher (au plus @p_maxres), dans l'ordre. */
    DECLARE @cles TABLE (
        LNA_UID VARCHAR(200),
        LIN_UID VARCHAR(500),
        EDG_DIR CHAR(1),
        Ordre   INT            -- ordre d'affichage (1, 2, 3...)
    )

    DECLARE @TotalLignes INT

    IF @DTA1 IS NOT NULL AND @DTA2 IS NOT NULL
   AND @DTA3 IS NOT NULL AND @DTA4 IS NOT NULL
    BEGIN
        /* 2a. CHEMIN RAPIDE : les 4 coordonnees sont connues.
               Tout se lit dans l'index IX_LINE_VIS_EDG_DIR_HASH :
                 EDG_DIR = @p_type AND DTA_HASH = @h -> recherche (seek) ;
                 DTA_n = @DTAn -> elimine les collisions du hash (colonnes
                 incluses dans l'index, pas de lecture de la table) ;
                 LNA_UID -> dans l'index aussi (cle primaire) pour le
                 EXISTS sur LINE_VIS_HEA. */
        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH))
        WHERE e.EDG_DIR  = @p_type
          AND e.DTA_HASH = @h
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)

        -- Les @p_maxres premieres cles : l'index les rend deja triees par
        -- LNA_UID, LIN_UID (a EDG_DIR et DTA_HASH fixes) -> pas de tri.
        IF @TotalLignes > 0
        INSERT INTO @cles (LNA_UID, LIN_UID, EDG_DIR, Ordre)
        SELECT TOP (@p_maxres)
            e.LNA_UID, e.LIN_UID, e.EDG_DIR,
            ROW_NUMBER() OVER (ORDER BY e.LNA_UID, e.LIN_UID)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK, INDEX (IX_LINE_VIS_EDG_DIR_HASH))
        WHERE e.EDG_DIR  = @p_type
          AND e.DTA_HASH = @h
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
        ORDER BY e.LNA_UID, e.LIN_UID
    END
    ELSE
    BEGIN
        /* 2b. CHEMIN GENERAL : noeud introuvable ou coordonnees en partie
               NULL. Une coordonnee NULL = pas de filtre (regle d'origine) :
               le hash ne peut pas servir, parcours de la table.
               OPTION (RECOMPILE) : plan calcule avec les vraies valeurs de
               @DTA1..@DTA4 (filtres "NULL = pas de filtre" simplifies).
               OPTION (HASH JOIN) : pour le EXISTS sur LINE_VIS_HEA (le plan
               choisi seul etait bien plus lent sur 3,5 M lignes). */
        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA hh WITH (NOLOCK)
                      WHERE hh.LNA_UID = e.LNA_UID)
        OPTION (RECOMPILE, HASH JOIN)

        -- Les @p_maxres premieres cles selon le tri (colonnes etroites
        -- seulement : SQL Server ne garde que @p_maxres lignes pendant le tri).
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
              AND (@DTA1 IS NULL OR c.DTA_1 = @DTA1)
              AND (@DTA2 IS NULL OR c.DTA_2 = @DTA2)
              AND (@DTA3 IS NULL OR c.DTA_3 = @DTA3)
              AND (@DTA4 IS NULL OR c.DTA_4 = @DTA4)
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
