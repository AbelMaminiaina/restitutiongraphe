-- =============================================================================
--  Procedure dbo.LINE_VIS_Lineage_Parcours  (procedure INTERNE)
--  Base : RestitutionGrapheProd
--
--  Parcours du graphe commun a dbo.LINE_VIS_Lineage et dbo.LINE_VIS_Impact.
--  Elle n'affiche rien : elle remplit 2 tables temporaires que l'APPELANT a
--  creees avant de l'appeler (une table #temporaire est visible dans les
--  procedures appelees). On evite ainsi un INSERT ... EXEC dans l'appelant,
--  qui empecherait de capturer a son tour sa sortie par INSERT ... EXEC
--  ("An INSERT EXEC statement cannot be nested").
--
--  Tables a creer par l'appelant (memes colonnes, memes types) :
--
--    CREATE TABLE #noeuds (
--        NOD_ID   INT IDENTITY(1, 1) PRIMARY KEY,
--        NOD_HASH INT NOT NULL,
--        DTA_1    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
--        DTA_2    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
--        DTA_3    VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
--        DTA_4    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
--        NIVEAU   INT     NOT NULL,
--        SENS     CHAR(1) NOT NULL
--    )
--    CREATE INDEX IX_noeuds_hash ON #noeuds (NOD_HASH)  -- noeuds deja vus
--    CREATE TABLE #liens (
--        SRC_ID   INT NOT NULL,
--        DST_ID   INT NOT NULL,
--        LNA_UID  VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
--        NB_LIENS INT NOT NULL
--    )
--
--  Resultat :
--    #noeuds : noeuds trouves. NIVEAU 0 = depart ; SENS '-' depart,
--              'O' aval, 'I' amont.
--    #liens  : une ligne par (source, destination, programme LNA_UID), dans
--              le sens du flux de donnees ; NB_LIENS = lignes de
--              LINE_VIS_EDG derriere. En mode 'B', un meme lien peut etre
--              lu des 2 cotes (ligne 'O' de la source et ligne 'I' de la
--              destination) : il apparait alors 2 fois, a l'appelant de
--              prendre le MAX.
--    @p_tronque = 1 si la limite @p_maxnoeuds a ecarte des noeuds.
--
--  Parametres : voir dbo.LINE_VIS_Lineage. En plus, facultatif :
--    @p_cible_hash, @p_cible_1..4 : noeud cible (CHECKSUM et DTA_1..DTA_4).
--        Le parcours s'arrete a la fin du niveau ou la cible est trouvee
--        (utilise par dbo.LINE_VIS_Chemin). NULL = pas de cible.
--
--  Modele : un noeud = DTA_1..DTA_4 ; une ligne de LINE_VIS_EDG relie le
--  noeud DTA_1..DTA_4 au voisin EDG_1..EDG_4 ; EDG_DIR = 'O' : le voisin est
--  un successeur, 'I' : un predecesseur. Seuls les liens dont le LNA_UID
--  existe dans LINE_VIS_HEA sont suivis.
--
--  Methode (7 M lignes, base proche de 10 Go, petit journal) :
--    - parcours en largeur, un niveau a la fois (boucle WHILE), plutot
--      qu'une CTE recursive : une CTE ne sait pas ecarter les noeuds deja
--      vus, elle repasse par tous les chemins et explose sur les cycles ;
--    - chaque niveau = une recherche dans l'index IX_LINE_VIS_EDG_DIR_HASH
--      (EDG_DIR, DTA_HASH) par noeud de la frontiere : aucun parcours de
--      table. FORCESEEK : sans lui, SQL Server lisait les 7 M lignes
--      (~40 s par appel au lieu de ~10 ms) ;
--    - un noeud deja vu n'est jamais ajoute ni explore une 2e fois : les
--      cycles s'arretent d'eux-memes (le lien de retour est bien garde) ;
--    - tout se passe dans des tables #temporaires (tempdb) : rien n'est
--      ecrit dans la base ni dans son journal.
--
--  Comparaison des coordonnees :
--    - meme regle que "=" sur les colonnes (casse et espaces de fin ignores) ;
--    - NULL = NULL : une coordonnee NULL fait partie de l'identite du noeud ;
--      un voisin dont EDG_1..EDG_4 sont tous NULL ou vides est ignore ;
--    - CHECKSUM peut donner la meme valeur a 2 noeuds differents : l'egalite
--      exacte des 4 coordonnees est toujours verifiee en plus du hash.
--    - COLLATE DATABASE_DEFAULT sur les tables #temporaires : sans lui, les
--      colonnes prendraient la collation de tempdb (conflit de collation
--      possible avec LINE_VIS_EDG).
--
--  En mode 'B', un noeud trouve des 2 cotes (cycle passant par le depart)
--  n'apparait qu'une fois, avec le sens par lequel il a ete trouve en premier.
--
--  Dependances : dbo.LINE_VIS_EDG, index IX_LINE_VIS_EDG_DIR_HASH,
--                dbo.LINE_VIS_HEA
-- =============================================================================

-- Obligatoire pour que la procedure puisse utiliser l'index sur la colonne
-- calculee DTA_HASH (ces 2 options sont memorisees a la creation).
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_Lineage_Parcours]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_Lineage_Parcours
GO

CREATE PROCEDURE [dbo].LINE_VIS_Lineage_Parcours
    @p_lnauid     VARCHAR(200),
    @p_linuid     VARCHAR(500),
    @p_edgdir     CHAR(1),
    @p_sens       CHAR(1),
    @p_profondeur INT,
    @p_maxnoeuds  INT,
    @p_tronque    BIT OUTPUT,
    @p_cible_hash INT           = NULL,
    @p_cible_1    VARCHAR(1000) = NULL,
    @p_cible_2    VARCHAR(1000) = NULL,
    @p_cible_3    VARCHAR(8000) = NULL,
    @p_cible_4    VARCHAR(1000) = NULL

AS
BEGIN
    SET NOCOUNT ON

    IF @p_sens IS NULL OR @p_sens NOT IN ('O', 'I', 'B')
        THROW 50001, 'LINE_VIS_Lineage : @p_sens doit valoir O (aval), I (amont) ou B (les deux).', 1;

    SET @p_tronque = 0

    /* Noeuds a explorer au niveau courant, avec le sens a suivre.
       SENS en CHAR(1) comme EDG_DIR : la jointure sur l'index se fait
       sans conversion. */
    CREATE TABLE #frontiere (
        NOD_ID   INT     NOT NULL,
        SENS     CHAR(1) NOT NULL,      -- EDG_DIR a suivre : 'O' ou 'I'
        NOD_HASH INT     NOT NULL,
        DTA_1    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_2    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_3    VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        DTA_4    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL
    )

    /* Voisins lus au niveau courant, regroupes par (noeud explore, sens,
       voisin, programme) : 1 000 lignes identiques ne font qu'une ligne. */
    CREATE TABLE #voisins (
        DEP_ID   INT     NOT NULL,  -- noeud explore (NOD_ID de #noeuds)
        SENS     CHAR(1) NOT NULL,  -- EDG_DIR suivi : 'O' ou 'I'
        VOI_HASH INT     NOT NULL,  -- CHECKSUM(EDG_1..EDG_4)
        VOI_1    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        VOI_2    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        VOI_3    VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        VOI_4    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        LNA_UID  VARCHAR(200)  COLLATE DATABASE_DEFAULT NOT NULL,
        NB_LIENS INT NOT NULL
    )

    /* 1. Noeud de depart (niveau 0), lu par la cle primaire.
          Introuvable -> #noeuds reste vide, la boucle ne fait rien.
          @p_lnauid NULL : l'appelant a deja mis le ou les noeuds de depart
          dans #noeuds (NIVEAU 0, SENS '-') ; cf. LINE_VIS_LineageTables. */
    IF @p_lnauid IS NOT NULL
        INSERT INTO #noeuds (NOD_HASH, DTA_1, DTA_2, DTA_3, DTA_4, NIVEAU, SENS)
        SELECT TOP (1) e.DTA_HASH, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4, 0, '-'
        FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
        WHERE e.LNA_UID = @p_lnauid
          AND e.LIN_UID = @p_linuid
          AND e.EDG_DIR = @p_edgdir

    DECLARE @niveau INT = 0
    DECLARE @reste  INT
    DECLARE @cibleAtteinte BIT = 0

    -- Depart = cible : rien a parcourir
    IF @p_cible_hash IS NOT NULL AND EXISTS (
        SELECT 1 FROM #noeuds n
        WHERE n.NOD_HASH = @p_cible_hash
          AND (n.DTA_1 = @p_cible_1 OR (n.DTA_1 IS NULL AND @p_cible_1 IS NULL))
          AND (n.DTA_2 = @p_cible_2 OR (n.DTA_2 IS NULL AND @p_cible_2 IS NULL))
          AND (n.DTA_3 = @p_cible_3 OR (n.DTA_3 IS NULL AND @p_cible_3 IS NULL))
          AND (n.DTA_4 = @p_cible_4 OR (n.DTA_4 IS NULL AND @p_cible_4 IS NULL)))
        SET @cibleAtteinte = 1

    /* 2. Parcours en largeur : a chaque tour, on explore les noeuds du
          niveau @niveau et on ajoute leurs voisins au niveau @niveau + 1. */
    WHILE @niveau < @p_profondeur AND @cibleAtteinte = 0
      AND EXISTS (SELECT 1 FROM #noeuds WHERE NIVEAU = @niveau)
    BEGIN
        TRUNCATE TABLE #voisins
        TRUNCATE TABLE #frontiere

        /* 2a. Frontiere = noeuds du niveau courant, avec le sens a suivre :
               celui du noeud (un noeud trouve en aval n'est explore qu'en
               aval) ; pour le depart, celui de @p_sens (2 lignes si 'B'). */
        INSERT INTO #frontiere (NOD_ID, SENS, NOD_HASH, DTA_1, DTA_2, DTA_3, DTA_4)
        SELECT f.NOD_ID, d.SENS, f.NOD_HASH, f.DTA_1, f.DTA_2, f.DTA_3, f.DTA_4
        FROM #noeuds f
        INNER JOIN (VALUES ('O'), ('I')) AS d (SENS)
                ON d.SENS = f.SENS
                OR (f.SENS = '-' AND (@p_sens = d.SENS OR @p_sens = 'B'))
        WHERE f.NIVEAU = @niveau

        /* 2b. Voisins de la frontiere : EDG_DIR + DTA_HASH -> recherche
               dans IX_LINE_VIS_EDG_DIR_HASH ; l'egalite des 4 coordonnees
               ecarte les collisions du hash. */
        INSERT INTO #voisins
            (DEP_ID, SENS, VOI_HASH, VOI_1, VOI_2, VOI_3, VOI_4, LNA_UID, NB_LIENS)
        SELECT
            f.NOD_ID,
            f.SENS,
            CHECKSUM(e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4),
            e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4,
            e.LNA_UID,
            COUNT(*)
        FROM #frontiere f
        INNER JOIN dbo.LINE_VIS_EDG e
                   WITH (NOLOCK, FORCESEEK (IX_LINE_VIS_EDG_DIR_HASH (EDG_DIR, DTA_HASH)))
                ON e.EDG_DIR  = f.SENS
               AND e.DTA_HASH = f.NOD_HASH
               AND (e.DTA_1 = f.DTA_1 OR (e.DTA_1 IS NULL AND f.DTA_1 IS NULL))
               AND (e.DTA_2 = f.DTA_2 OR (e.DTA_2 IS NULL AND f.DTA_2 IS NULL))
               AND (e.DTA_3 = f.DTA_3 OR (e.DTA_3 IS NULL AND f.DTA_3 IS NULL))
               AND (e.DTA_4 = f.DTA_4 OR (e.DTA_4 IS NULL AND f.DTA_4 IS NULL))
          -- voisin vide (EDG_1..EDG_4 tous NULL ou '') : pas de noeud
        WHERE NOT (COALESCE(e.EDG_1, '') = '' AND COALESCE(e.EDG_2, '') = ''
               AND COALESCE(e.EDG_3, '') = '' AND COALESCE(e.EDG_4, '') = '')
          AND EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
                      WHERE h.LNA_UID = e.LNA_UID)
        GROUP BY f.NOD_ID, f.SENS, e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4, e.LNA_UID

        /* 2c. Nouveaux noeuds (pas encore dans #noeuds), dans la limite de
               @p_maxnoeuds. Ordre fixe (table, colonne...) : le meme appel
               renvoie toujours les memes noeuds quand la limite coupe.
               Un voisin trouve par plusieurs chemins / programmes au meme
               niveau n'est ajoute qu'une fois (GROUP BY). */
        SET @reste = @p_maxnoeuds - (SELECT COUNT(*) FROM #noeuds)
        IF @reste < 0 SET @reste = 0

        INSERT INTO #noeuds (NOD_HASH, DTA_1, DTA_2, DTA_3, DTA_4, NIVEAU, SENS)
        SELECT TOP (@reste)
            v.VOI_HASH, v.VOI_1, v.VOI_2, v.VOI_3, v.VOI_4, @niveau + 1, MIN(v.SENS)
        FROM #voisins v
        WHERE NOT EXISTS (
            SELECT 1 FROM #noeuds n
            WHERE n.NOD_HASH = v.VOI_HASH
              AND (n.DTA_1 = v.VOI_1 OR (n.DTA_1 IS NULL AND v.VOI_1 IS NULL))
              AND (n.DTA_2 = v.VOI_2 OR (n.DTA_2 IS NULL AND v.VOI_2 IS NULL))
              AND (n.DTA_3 = v.VOI_3 OR (n.DTA_3 IS NULL AND v.VOI_3 IS NULL))
              AND (n.DTA_4 = v.VOI_4 OR (n.DTA_4 IS NULL AND v.VOI_4 IS NULL)))
        GROUP BY v.VOI_HASH, v.VOI_1, v.VOI_2, v.VOI_3, v.VOI_4
        ORDER BY v.VOI_2, v.VOI_1, v.VOI_4, v.VOI_HASH

        /* 2d. Liens vers les voisins presents dans #noeuds (nouveaux ou
               deja vus : le lien qui ferme un cycle est garde). Un voisin
               ecarte par la limite n'a pas de lien -> @p_tronque = 1. */
        INSERT INTO #liens (SRC_ID, DST_ID, LNA_UID, NB_LIENS)
        SELECT
            CASE WHEN v.SENS = 'O' THEN v.DEP_ID ELSE n.NOD_ID END,   -- 'I' : le voisin
            CASE WHEN v.SENS = 'O' THEN n.NOD_ID ELSE v.DEP_ID END,   -- alimente le noeud
            v.LNA_UID,
            v.NB_LIENS
        FROM #voisins v
        INNER JOIN #noeuds n
                ON n.NOD_HASH = v.VOI_HASH
               AND (n.DTA_1 = v.VOI_1 OR (n.DTA_1 IS NULL AND v.VOI_1 IS NULL))
               AND (n.DTA_2 = v.VOI_2 OR (n.DTA_2 IS NULL AND v.VOI_2 IS NULL))
               AND (n.DTA_3 = v.VOI_3 OR (n.DTA_3 IS NULL AND v.VOI_3 IS NULL))
               AND (n.DTA_4 = v.VOI_4 OR (n.DTA_4 IS NULL AND v.VOI_4 IS NULL))

        IF @@ROWCOUNT < (SELECT COUNT(*) FROM #voisins)
            SET @p_tronque = 1

        /* 2e. Cible trouvee a ce niveau -> on s'arrete : tous les plus
               courts chemins vers elle sont deja dans #liens (les liens
               de CE niveau ont tous ete enregistres en 2d). */
        IF @p_cible_hash IS NOT NULL AND EXISTS (
            SELECT 1 FROM #noeuds n
            WHERE n.NOD_HASH = @p_cible_hash
              AND (n.DTA_1 = @p_cible_1 OR (n.DTA_1 IS NULL AND @p_cible_1 IS NULL))
              AND (n.DTA_2 = @p_cible_2 OR (n.DTA_2 IS NULL AND @p_cible_2 IS NULL))
              AND (n.DTA_3 = @p_cible_3 OR (n.DTA_3 IS NULL AND @p_cible_3 IS NULL))
              AND (n.DTA_4 = @p_cible_4 OR (n.DTA_4 IS NULL AND @p_cible_4 IS NULL)))
            SET @cibleAtteinte = 1

        SET @niveau += 1
    END
END
GO
