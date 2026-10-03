-- =============================================================================
--  Procedure dbo.LINE_VIS_GetNodesSuccessorsPredecessors
--  Base : RestitutionGrapheProd
--
--  Code d'origine transcrit des photos M1/5.jpeg, M1/6.jpeg et M1/7.jpeg,
--  puis optimise (memes parametres, memes colonnes en sortie).
--
--  But : a partir d'un noeud (LNA_UID, LIN_UID, EDG_DIR = @p_edgdir), lire
--  ses coordonnees DTA_1..DTA_4 (ou EDG_1..EDG_4 si @p_useEdg = 1), puis
--  renvoyer les aretes qui ont ces coordonnees et EDG_DIR = @p_type, jointes
--  a LINE_VIS_HEA, limitees a @p_maxres lignes, avec le total (TotalLignes).
--
--  -------------------------------------------------------------------------
--  Pourquoi la version d'origine etait lente (~20 s sur 7 M lignes) :
--    1. aucun index ne permettait de chercher par DTA_1..DTA_4 : chaque
--       appel lisait toute la table ;
--    2. "e.DTA_1 COLLATE French_CI_AS = ..." : le COLLATE sur la colonne
--       empeche tout index et coute ~3 s de conversion par parcours ;
--    3. "(... = @DTA1 OR @DTA1 IS NULL)" : cette forme force un parcours ;
--    4. #TempResults recopiait TOUTES les lignes trouvees (avec les
--       VARCHAR(MAX)), faisait la jointure et calculait CURRENT_NODE pour
--       chacune, pour n'en afficher que @p_maxres.
--
--  Optimisations :
--    A. CHEMIN RAPIDE (DTA_1..DTA_4 du noeud tous connus : toujours le cas
--       avec @p_useEdg = 0) : recherche dans l'index IX_LINE_VIS_EDG_DIR_HASH
--       (EDG_DIR, DTA_HASH) -> quelques ms au lieu de ~20 s.
--       DTA_HASH = CHECKSUM(DTA_1..DTA_4) peut donner la meme valeur pour
--       deux noeuds differents : l'egalite exacte DTA_n = @DTAn est gardee,
--       le resultat est donc toujours juste.
--    B. CHEMIN GENERAL (noeud introuvable, ou coordonnees EDG en partie
--       NULL avec @p_useEdg = 1) : meme regle qu'avant (une coordonnee NULL
--       = pas de filtre dessus). Toujours un parcours de la table (aucun
--       index ne peut servir), mais sans COLLATE ni table temporaire.
--    C. Plus de #TempResults : on garde d'abord les @p_maxres lignes a
--       afficher (table variable @page), et la jointure LINE_VIS_HEA +
--       CURRENT_NODE ne se font que pour elles.
--    D. TotalLignes vient d'un COUNT(*) etroit (EXISTS au lieu de la
--       jointure : meme resultat, LINE_VIS_HEA ayant 1 ligne par LNA_UID).
--
--  Ecarts volontaires avec l'original :
--    - COLLATE French_CI_AS retire : les colonnes sont deja insensibles a la
--      casse (SQL_Latin1_General_CP1_CI_AS). Seule difference possible :
--      French_CI_AS (collation Windows) considere egaux certains caracteres
--      "doubles" ('œ' = 'oe', 'æ' = 'ae') ; la collation des colonnes non.
--      Sans effet sur des noms de colonnes / tables / schemas techniques.
--    - Tri : chemin rapide -> toutes les lignes ont les memes DTA_1..DTA_4,
--      l'ORDER BY DTA_1..DTA_4 d'origine ne departageait rien (ordre au
--      hasard). On trie par LNA_UID, LIN_UID (ordre stable, fourni par
--      l'index sans tri). Chemin general -> DTA_1..DTA_4 puis LNA_UID,
--      LIN_UID.
--
--  Dependances : dbo.LINE_VIS_EDG (LINE_VIS_EDG.sql),
--                index IX_LINE_VIS_EDG_DIR_HASH (LINE_VIS_EDG_IndexHash.sql),
--                dbo.LINE_VIS_HEA (LINE_VIS_HEA.sql)
-- =============================================================================

-- Obligatoire pour que la procedure puisse utiliser l'index sur la colonne
-- calculee DTA_HASH (ces 2 options sont memorisees a la creation).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_GetNodesSuccessorsPredecessors]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_GetNodesSuccessorsPredecessors
GO

CREATE PROCEDURE [dbo].LINE_VIS_GetNodesSuccessorsPredecessors
    @p_lnauid   VARCHAR(200) = NULL,
    @p_linuid   VARCHAR(500) = NULL,
    @p_edgdir   CHAR(1)      = NULL,
    @p_type     CHAR(1)      = NULL,
    @p_useEdg   BIT          = 0,
    @p_maxres   INT          = 100

AS
BEGIN
    SET NOCOUNT ON

    /* 1. Coordonnees du noeud (DTA ou EDG selon @p_useEdg), par la cle
          primaire (LNA_UID, LIN_UID, EDG_DIR) -> lecture directe.
          Noeud introuvable -> les 4 variables restent NULL. */
    DECLARE @DTA1 VARCHAR(1000)
    DECLARE @DTA2 VARCHAR(1000)
    DECLARE @DTA3 VARCHAR(8000)
    DECLARE @DTA4 VARCHAR(1000)

    SELECT TOP(1)
        @DTA1 = CASE WHEN @p_useEdg = 0 THEN DTA_1 ELSE EDG_1 END,
        @DTA2 = CASE WHEN @p_useEdg = 0 THEN DTA_2 ELSE EDG_2 END,
        @DTA3 = CASE WHEN @p_useEdg = 0 THEN DTA_3 ELSE EDG_3 END,
        @DTA4 = CASE WHEN @p_useEdg = 0 THEN DTA_4 ELSE EDG_4 END
    FROM dbo.LINE_VIS_EDG
    WHERE LNA_UID  = @p_lnauid
      AND LIN_UID  = @p_linuid
      AND EDG_DIR  = @p_edgdir

    /* 2. Lignes a afficher (au plus @p_maxres), colonnes de LINE_VIS_EDG
          seulement : la jointure LINE_VIS_HEA se fait a l'etape 3. */
    DECLARE @page TABLE (
        LNA_UID     VARCHAR(200),
        LIN_UID     VARCHAR(500),
        EDG_DIR     CHAR(1),
        DTA_1       VARCHAR(1000),
        DTA_2       VARCHAR(1000),
        DTA_3       VARCHAR(8000),
        DTA_4       VARCHAR(1000),
        TXN_DTA     VARCHAR(MAX),
        EDG_1       VARCHAR(1000),
        EDG_2       VARCHAR(1000),
        EDG_3       VARCHAR(8000),
        EDG_4       VARCHAR(1000),
        PRX_TXN_DTA VARCHAR(MAX),
        Ordre       INT            -- ordre d'affichage (1, 2, 3...)
    )

    DECLARE @TotalLignes INT

    IF @DTA1 IS NOT NULL AND @DTA2 IS NOT NULL
   AND @DTA3 IS NOT NULL AND @DTA4 IS NOT NULL
    BEGIN
        /* 2a. CHEMIN RAPIDE : les 4 coordonnees sont connues.
               DTA_HASH = @h -> recherche dans l'index IX_LINE_VIS_EDG_DIR_HASH ;
               DTA_n = @DTAn -> elimine les collisions du hash. */
        DECLARE @h INT = CHECKSUM(@DTA1, @DTA2, @DTA3, @DTA4)

        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR  = @p_type
          AND e.DTA_HASH = @h
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID)

        INSERT INTO @page
            (LNA_UID, LIN_UID, EDG_DIR, DTA_1, DTA_2, DTA_3, DTA_4,
             TXN_DTA, EDG_1, EDG_2, EDG_3, EDG_4, PRX_TXN_DTA, Ordre)
        SELECT TOP (@p_maxres)
            e.LNA_UID, e.LIN_UID, e.EDG_DIR,
            e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4,
            e.TXN_DTA, e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4, e.PRX_TXN_DTA,
            ROW_NUMBER() OVER (ORDER BY e.LNA_UID, e.LIN_UID)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR  = @p_type
          AND e.DTA_HASH = @h
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID)
        ORDER BY e.LNA_UID, e.LIN_UID
    END
    ELSE
    BEGIN
        /* 2b. CHEMIN GENERAL : noeud introuvable ou coordonnees en partie
               NULL. Une coordonnee NULL = pas de filtre (regle d'origine).
               Parcours de la table (aucun index ne peut servir ici).
               OPTION (RECOMPILE) : plan calcule avec les vraies valeurs
               de @DTA1..@DTA4 (les filtres "NULL = pas de filtre" sont
               alors simplifies).
               OPTION (HASH JOIN) : pour le EXISTS sur LINE_VIS_HEA, le plan
               choisi seul etait bien plus lent sur 3,5 M lignes
               (tri des 100 premieres : 78 s -> 24 s). */
        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID)
        OPTION (RECOMPILE, HASH JOIN)

        -- En 2 temps, pour ne trier que des colonnes etroites :
        --   1) @cles : les @p_maxres premieres CLES selon le tri (SQL Server
        --      ne garde que @p_maxres lignes en memoire pendant le tri) ;
        --   2) @page : relecture des colonnes larges (VARCHAR(MAX)...) pour
        --      ces seules lignes, par la cle primaire.
        -- (Un ROW_NUMBER() pose directement sur le parcours obligeait a
        --  trier les ~3,5 M lignes completes : plus de 10 min.)
        DECLARE @cles TABLE (
            LNA_UID VARCHAR(200),
            LIN_UID VARCHAR(500),
            EDG_DIR CHAR(1),
            Ordre   INT
        )

        -- Aucune ligne : inutile de reparcourir la table pour le tri.
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
              AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                          WHERE h.LNA_UID = c.LNA_UID)
            ORDER BY c.DTA_1, c.DTA_2, c.DTA_3, c.DTA_4, c.LNA_UID, c.LIN_UID
        ) k
        OPTION (RECOMPILE, HASH JOIN)

        INSERT INTO @page
            (LNA_UID, LIN_UID, EDG_DIR, DTA_1, DTA_2, DTA_3, DTA_4,
             TXN_DTA, EDG_1, EDG_2, EDG_3, EDG_4, PRX_TXN_DTA, Ordre)
        SELECT
            e.LNA_UID, e.LIN_UID, e.EDG_DIR,
            e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4,
            e.TXN_DTA, e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4, e.PRX_TXN_DTA,
            k.Ordre
        FROM @cles k
        INNER JOIN dbo.LINE_VIS_EDG e WITH (NOLOCK)
                ON e.LNA_UID = k.LNA_UID
               AND e.LIN_UID = k.LIN_UID
               AND e.EDG_DIR = k.EDG_DIR
    END

    /* 3. Sortie : jointure LINE_VIS_HEA + CURRENT_NODE, pour les
          <= @p_maxres lignes de @page seulement. */
    SELECT
        p.LNA_UID,
        p.LIN_UID,
        p.EDG_DIR,
        p.DTA_1,
        p.DTA_2,
        p.DTA_3,
        p.DTA_4,
        p.TXN_DTA,
        p.EDG_1,
        p.EDG_2,
        p.EDG_3,
        p.EDG_4,
        p.PRX_TXN_DTA,
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
            WHEN COALESCE(p.EDG_4, '') = '' AND COALESCE(p.EDG_3, '') = '' AND
                 COALESCE(p.EDG_2, '') = '' AND COALESCE(p.EDG_1, '') = '' THEN ''
            ELSE RTRIM(LTRIM(
                CASE WHEN p.EDG_4 IS NOT NULL AND p.EDG_4 <> '' THEN p.EDG_4 ELSE '' END +
                CASE WHEN p.EDG_3 IS NOT NULL AND p.EDG_3 <> '' AND (p.EDG_4 IS NOT NULL AND p.EDG_4 <> '') THEN '.' + p.EDG_3 ELSE '' END +
                CASE WHEN p.EDG_2 IS NOT NULL AND p.EDG_2 <> '' AND (p.EDG_3 IS NOT NULL AND p.EDG_3 <> '') THEN '.' + p.EDG_2 ELSE '' END +
                CASE WHEN p.EDG_1 IS NOT NULL AND p.EDG_1 <> '' AND (p.EDG_2 IS NOT NULL AND p.EDG_2 <> '') THEN '.' + p.EDG_1 ELSE '' END
            ))
        END AS CURRENT_NODE,
        @TotalLignes AS TotalLignes
    FROM @page p
    INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = p.LNA_UID
    ORDER BY p.Ordre
END
GO
