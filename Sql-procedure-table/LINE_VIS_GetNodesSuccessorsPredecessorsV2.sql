-- =============================================================================
--  Procedure dbo.LINE_VIS_GetNodesSuccessorsPredecessorsV2
--  Base : RestitutionGrapheProd
--
--  Transcrite des captures IMG_5674 / IMG_5675 / IMG_5676, puis optimisee.
--
--  But : a partir d'un noeud (LNA_UID, LIN_UID, EDG_DIR) passe en parametre,
--        on lit ses coordonnees DTA_1..DTA_4 (ou EDG_1..EDG_4 si @p_useEdg = 1),
--        puis on renvoie toutes les aretes de LINE_VIS_EDG qui partagent ces
--        memes coordonnees et dont EDG_DIR = @p_type (successeurs OU
--        predecesseurs selon la direction demandee), jointes a l'en-tete
--        LINE_VIS_HEA, paginees (@p_maxres), triees par DTA_1..DTA_4, avec le
--        nombre total de lignes correspondantes (@TotalLignes).
--
--  Adaptations vs captures :
--    - table dbo.LINE_VIS_EDG_2 -> dbo.LINE_VIS_EDG (convention de ce projet,
--      cf. l'entete de LINE_VIS_NodesListV2.sql).
--    - dbo.LINE_VIS_HEA : schema dans LINE_VIS_HEA.sql (transcrit de IMG_5671),
--      + un generateur. Sa cle primaire (LNA_UID) garantit le 1:1 : la
--      jointure ne multiplie jamais les lignes de LINE_VIS_EDG.
--
--  -------------------------------------------------------------------------
--  Pourquoi la version des captures est lente (mesure sur 1,8 M lignes) :
--
--    1. #TempResults materialise TOUT le resultat filtre+joint+la chaine
--       CURRENT_NODE calculee, PUIS compte, PUIS renvoie le TOP(@p_maxres).
--       Cas "parametres NULL" : ~900 000 lignes larges (DTA_3/EDG_3
--       VARCHAR(8000) + 2 VARCHAR(MAX)) ecrites dans tempdb pour n'en
--       afficher que 100  ->  ~25-30 s.
--
--    2. Predicat "catch-all" (e.DTA_1 = @DTA1 OR @DTA1 IS NULL) x4 : SQL
--       Server ne "deplie" pas cette forme, meme sous OPTION(RECOMPILE), et
--       garde un SCAN. Un appel sur un noeud precis coute donc ~0,6 s alors
--       qu'un Index Seek suffirait.
--
--  Optimisations appliquees (100 % SQL statique, sans sp_executesql) :
--
--    A. #TempResults remplace par une table variable @page qui ne contient
--       que <= @p_maxres lignes (la pagination est faite AVANT). La jointure
--       LINE_VIS_HEA et la construction de CURRENT_NODE (CASE/RTRIM/LTRIM)
--       ne s'executent donc que pour ~@p_maxres lignes, dans un unique
--       SELECT final.
--
--    B. Le total (@TotalLignes) vient d'une requete COUNT(*) etroite (aucune
--       colonne large, pas de CURRENT_NODE, pas de colonnes LINE_VIS_HEA).
--       EXISTS(LINE_VIS_HEA) reproduit la semantique de l'INNER JOIN sans en
--       projeter les colonnes.
--
--    C. Deux chemins selon que le noeud est entierement resolu ou non :
--         - @DTA1..4 tous connus (cas d'appel normal, @p_useEdg = 0) :
--           egalite STRICTE  e.DTA_n = @DTAn  ->  Index Seek, ~1-3 ms.
--         - resolution partielle (@p_useEdg = 1, EDG_2..4 souvent vides) ou
--           noeud absent : predicats "catch-all". Le cas "noeud absent"
--           revient a scanner une direction (incompressible) ; le cas
--           partiel scanne avec residu (~0,5-1 s).
--       Dans les deux chemins l'ordre ORDER BY DTA_1..DTA_4 est fourni par
--       l'index IX_LINE_VIS_EDG_DTA_EDG_DIR (aucun operateur Sort) et le
--       "row goal" du TOP arrete le parcours tot.
--
--  Fidelite : lignes renvoyees, valeurs et @TotalLignes identiques a
--  l'original tant que LINE_VIS_HEA est 1:1 sur LNA_UID. Le
--  COALESCE(<datetime2>, '') de l'original (en-tete manquant -> 1900-01-01)
--  est conserve tel quel.
--
--  Remarque fonctionnelle (non modifiee) : le noeud de depart est cherche
--  avec EDG_DIR = @p_edgdir, mais les aretes renvoyees sont filtrees avec
--  EDG_DIR = @p_type. Les deux parametres sont distincts et volontaires.
--
--  Mesures (RestitutionGrapheProd, 1,8 M lignes, LINE_VIS_HEA 5 lignes,
--  @p_maxres = 100), version "captures" vs version ci-dessous :
--    noeud precis (LNA_UID/LIN_UID/EDG_DIR fournis) : ~0,6-0,9 s  -> ~2-5 ms
--    parametres NULL (@p_type seul)                 : ~25-30 s    -> ~1 s
--    @p_useEdg=1 avec resolution partielle          : ~1-1,5 s (scan avec residu)
--  Correctness verifiee ligne a ligne (EXCEPT) sur 4 scenarios : jeux de
--  lignes et @TotalLignes identiques.
--
--  Dependances : dbo.LINE_VIS_EDG (LINE_VIS_EDG.sql),
--                dbo.LINE_VIS_HEA  (LINE_VIS_HEA.sql)
-- =============================================================================

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_GetNodesSuccessorsPredecessorsV2]') IS NOT NULL
    DROP PROCEDURE [dbo].[LINE_VIS_GetNodesSuccessorsPredecessorsV2]
GO

CREATE PROCEDURE [dbo].[LINE_VIS_GetNodesSuccessorsPredecessorsV2]
    @p_lnauid   VARCHAR(200)  = NULL,
    @p_linuid   VARCHAR(500)  = NULL,
    @p_edgdir   CHAR(1)       = NULL,
    @p_type     CHAR(1)       = NULL,
    @p_useEdg   BIT           = 0,
    @p_maxres   INT           = 100
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------------
    -- 1. Resoudre les coordonnees DTA_1..DTA_4 du noeud passe en parametre.
    --    PK de LINE_VIS_EDG = (LNA_UID, LIN_UID, EDG_DIR) -> seek exact.
    --    @p_useEdg = 1 : on lit EDG_1..EDG_4 au lieu de DTA_1..DTA_4 (dans ce
    --    cas @DTA2..4 peuvent rester NULL, EDG_2..4 etant souvent vides).
    --    Noeud absent / parametres NULL -> @DTA1..4 restent NULL.
    -------------------------------------------------------------------------
    DECLARE @DTA1 VARCHAR(1000),
            @DTA2 VARCHAR(1000),
            @DTA3 VARCHAR(8000),
            @DTA4 VARCHAR(1000);

    SELECT TOP (1)
        @DTA1 = CASE WHEN @p_useEdg = 0 THEN DTA_1 ELSE EDG_1 END,
        @DTA2 = CASE WHEN @p_useEdg = 0 THEN DTA_2 ELSE EDG_2 END,
        @DTA3 = CASE WHEN @p_useEdg = 0 THEN DTA_3 ELSE EDG_3 END,
        @DTA4 = CASE WHEN @p_useEdg = 0 THEN DTA_4 ELSE EDG_4 END
    FROM dbo.LINE_VIS_EDG WITH (NOLOCK)
    WHERE LNA_UID = @p_lnauid
      AND LIN_UID = @p_linuid
      AND EDG_DIR = @p_edgdir;

    -------------------------------------------------------------------------
    -- 2. Page de resultats : au plus @p_maxres lignes, colonnes de "e"
    --    uniquement (la jointure d'en-tete se fait a l'etape 4).
    -------------------------------------------------------------------------
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
        PRX_TXN_DTA VARCHAR(MAX)
    );

    DECLARE @TotalLignes INT;

    IF @DTA1 IS NOT NULL AND @DTA2 IS NOT NULL
   AND @DTA3 IS NOT NULL AND @DTA4 IS NOT NULL
    BEGIN
        ---------------------------------------------------------------------
        -- 2a / 3a. CHEMIN RAPIDE : noeud entierement resolu.
        --          Egalite stricte sur DTA_1..4 -> Index Seek sur
        --          IX_LINE_VIS_EDG_DTA_EDG_DIR (~1-3 ms).
        ---------------------------------------------------------------------
        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID);

        INSERT INTO @page
            (LNA_UID, LIN_UID, EDG_DIR, DTA_1, DTA_2, DTA_3, DTA_4,
             TXN_DTA, EDG_1, EDG_2, EDG_3, EDG_4, PRX_TXN_DTA)
        SELECT TOP (@p_maxres)
               e.LNA_UID, e.LIN_UID, e.EDG_DIR,
               e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4,
               e.TXN_DTA, e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4, e.PRX_TXN_DTA
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND e.DTA_1 = @DTA1 AND e.DTA_2 = @DTA2
          AND e.DTA_3 = @DTA3 AND e.DTA_4 = @DTA4
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID)
        ORDER BY e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4;
    END
    ELSE
    BEGIN
        ---------------------------------------------------------------------
        -- 2b / 3b. CHEMIN GENERAL : resolution partielle (@p_useEdg = 1) ou
        --          noeud absent. Predicats "tout accepter si NULL".
        --          Noeud absent -> tous NULL -> scan d'une direction
        --          (incompressible). Cas partiel -> scan avec residu.
        ---------------------------------------------------------------------
        SELECT @TotalLignes = COUNT(*)
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID);

        INSERT INTO @page
            (LNA_UID, LIN_UID, EDG_DIR, DTA_1, DTA_2, DTA_3, DTA_4,
             TXN_DTA, EDG_1, EDG_2, EDG_3, EDG_4, PRX_TXN_DTA)
        SELECT TOP (@p_maxres)
               e.LNA_UID, e.LIN_UID, e.EDG_DIR,
               e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4,
               e.TXN_DTA, e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4, e.PRX_TXN_DTA
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.EDG_DIR = @p_type
          AND (@DTA1 IS NULL OR e.DTA_1 = @DTA1)
          AND (@DTA2 IS NULL OR e.DTA_2 = @DTA2)
          AND (@DTA3 IS NULL OR e.DTA_3 = @DTA3)
          AND (@DTA4 IS NULL OR e.DTA_4 = @DTA4)
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID)
        ORDER BY e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4;
    END

    -------------------------------------------------------------------------
    -- 4. Sortie unique : jointure d'en-tete + CURRENT_NODE, pour les
    --    <= @p_maxres lignes de @page seulement.
    -------------------------------------------------------------------------
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
        COALESCE(h.EXE_PGM_NME, '')  AS EXE_PGM_NME,
        COALESCE(h.VRS_EXE_PGM, '')  AS VRS_EXE_PGM,
        COALESCE(h.APP_ENV, '')      AS APP_ENV,
        COALESCE(h.DLY_PGM_TSP, '')  AS DLY_PGM_TSP,   -- datetime2 : NULL -> 1900-01-01 (comportement d'origine)
        COALESCE(h.LNA_TSP, '')      AS LNA_TSP,       -- idem
        COALESCE(h.PGM_TEC, '')      AS PGM_TEC,
        COALESCE(h.VRS_LNA_TOO, '')  AS VRS_LNA_TOO,
        COALESCE(h.TUS_IND, 0)       AS TUS_IND,
        -- CURRENT_NODE : "EDG_4.EDG_3.EDG_2.EDG_1", en s'arretant au premier
        -- niveau manquant. Logique reprise telle quelle des captures.
        CASE
            WHEN COALESCE(p.EDG_4, '') = '' AND COALESCE(p.EDG_3, '') = ''
             AND COALESCE(p.EDG_2, '') = '' AND COALESCE(p.EDG_1, '') = ''
            THEN ''
            ELSE RTRIM(LTRIM(
                 CASE WHEN p.EDG_4 IS NOT NULL AND p.EDG_4 <> '' THEN p.EDG_4 ELSE '' END
               + CASE WHEN p.EDG_3 IS NOT NULL AND p.EDG_3 <> ''
                       AND (p.EDG_4 IS NOT NULL AND p.EDG_4 <> '') THEN '.' + p.EDG_3 ELSE '' END
               + CASE WHEN p.EDG_2 IS NOT NULL AND p.EDG_2 <> ''
                       AND (p.EDG_3 IS NOT NULL AND p.EDG_3 <> '') THEN '.' + p.EDG_2 ELSE '' END
               + CASE WHEN p.EDG_1 IS NOT NULL AND p.EDG_1 <> ''
                       AND (p.EDG_2 IS NOT NULL AND p.EDG_2 <> '') THEN '.' + p.EDG_1 ELSE '' END
            ))
        END AS CURRENT_NODE,
        @TotalLignes AS TotalLignes
    FROM @page p
    INNER JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = p.LNA_UID
    ORDER BY p.DTA_1, p.DTA_2, p.DTA_3, p.DTA_4;
END
GO
