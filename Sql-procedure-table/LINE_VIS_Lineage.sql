-- =============================================================================
--  Procedure dbo.LINE_VIS_Lineage
--  Base : RestitutionGrapheProd
--
--  But : lineage sur PLUSIEURS niveaux a partir d'un noeud.
--  LINE_VIS_GetNodesSuccessorsPredecessors ne donne que les voisins directs
--  (1 niveau) ; cette procedure suit les aretes niveau par niveau, en aval
--  (successeurs), en amont (predecesseurs) ou dans les deux sens.
--
--  Modele (le meme que les autres procedures LINE_VIS_*) :
--    - un NOEUD = une combinaison DTA_1..DTA_4 (colonne, table, schema, env.) ;
--    - une ligne de LINE_VIS_EDG = un lien entre le noeud DTA_1..DTA_4 et le
--      voisin EDG_1..EDG_4 ;
--    - EDG_DIR = 'O' : le voisin est un SUCCESSEUR  (noeud -> voisin) ;
--      EDG_DIR = 'I' : le voisin est un PREDECESSEUR (voisin -> noeud).
--    Seuls les liens dont le LNA_UID existe dans LINE_VIS_HEA sont suivis
--    (meme regle que les autres procedures : INNER JOIN / EXISTS sur HEA).
--
--  Parametres :
--    @p_lnauid, @p_linuid, @p_edgdir : une ligne de LINE_VIS_EDG (cle
--        primaire, comme renvoyee par LINE_VIS_NodesList) ; le noeud de
--        depart est son DTA_1..DTA_4.
--    @p_sens       : 'O' = aval, 'I' = amont, 'B' = les deux.
--    @p_profondeur : nombre maximum de niveaux parcourus (defaut 5).
--    @p_maxnoeuds  : nombre maximum de noeuds renvoyes, depart compris
--                    (defaut 500). Au-dela, le parcours s'arrete et la
--                    colonne TRONQUE vaut 1.
--    @p_sortie     : 'T' = les 2 jeux de resultats (defaut),
--                    'N' = les noeuds seulement, 'A' = les aretes seulement
--                    (utile pour INSERT ... EXEC, qui ne sait lire qu'un jeu).
--
--  Resultats :
--    1. NOEUDS : NOD_ID (numero dans ce resultat), NIVEAU (0 = depart),
--       SENS ('-' depart, 'O' aval, 'I' amont), DTA_1..DTA_4, NOM_NOEUD
--       ("DTA_4.DTA_3.DTA_2.DTA_1"), EXPLORE (0 = noeud du dernier niveau,
--       ses voisins n'ont pas ete lus), TRONQUE (1 = limite @p_maxnoeuds
--       atteinte : des noeuds manquent).
--    2. ARETES : SRC_NOD_ID -> DST_NOD_ID (toujours dans le sens du flux de
--       donnees, quel que soit EDG_DIR), NB_LIENS (lignes de LINE_VIS_EDG
--       derriere cette arete), NB_PROGRAMMES (LNA_UID distincts).
--       Le detail des lignes s'obtient avec
--       LINE_VIS_GetNodesSuccessorsPredecessors.
--
--  Methode (pensee pour 7 M lignes, une base proche de 10 Go et un petit
--  journal) :
--    - parcours en largeur, un niveau a la fois (boucle WHILE), plutot
--      qu'une CTE recursive : une CTE ne sait pas ecarter les noeuds deja
--      vus, elle repasse par tous les chemins et explose sur les cycles ;
--    - chaque niveau = une recherche dans l'index IX_LINE_VIS_EDG_DIR_HASH
--      (EDG_DIR, DTA_HASH) par noeud de la frontiere (comme le chemin rapide
--      de LINE_VIS_GetNodesSuccessorsPredecessors) : aucun parcours de table ;
--    - un noeud deja vu n'est jamais ajoute ni explore une 2e fois : les
--      cycles s'arretent d'eux-memes (l'arete de retour est bien renvoyee) ;
--    - travail dans des tables #temporaires : elles vivent dans tempdb, rien
--      n'est ecrit dans la base ni dans son journal ; aucun index ni table
--      ajoutes a la base.
--
--  Comparaison des coordonnees :
--    - meme regle que "=" sur les colonnes (casse et espaces de fin ignores) ;
--    - NULL = NULL : une coordonnee NULL fait partie de l'identite du noeud
--      (ex. (NULL, t, s, e)) ; un voisin dont EDG_1..EDG_4 sont tous NULL
--      ou vides n'est pas un noeud : la ligne est ignoree.
--    - CHECKSUM peut donner la meme valeur a 2 noeuds differents : l'egalite
--      exacte des 4 coordonnees est toujours verifiee en plus du hash.
--
--  En mode 'B', un noeud trouve des 2 cotes (cycle passant par le depart)
--  n'apparait qu'une fois, avec le sens par lequel il a ete trouve en premier.
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

IF OBJECT_ID(N'[dbo].[LINE_VIS_Lineage]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_Lineage
GO

CREATE PROCEDURE [dbo].LINE_VIS_Lineage
    @p_lnauid     VARCHAR(200) = NULL,
    @p_linuid     VARCHAR(500) = NULL,
    @p_edgdir     CHAR(1)      = NULL,
    @p_sens       CHAR(1)      = 'O',
    @p_profondeur INT          = 5,
    @p_maxnoeuds  INT          = 500,
    @p_sortie     CHAR(1)      = 'T'

AS
BEGIN
    SET NOCOUNT ON

    IF @p_sens IS NULL OR @p_sens NOT IN ('O', 'I', 'B')
        THROW 50001, 'LINE_VIS_Lineage : @p_sens doit valoir O (aval), I (amont) ou B (les deux).', 1;
    IF @p_sortie IS NULL OR @p_sortie NOT IN ('T', 'N', 'A')
        THROW 50002, 'LINE_VIS_Lineage : @p_sortie doit valoir T (tout), N (noeuds) ou A (aretes).', 1;

    SET @p_profondeur = COALESCE(@p_profondeur, 5)
    SET @p_maxnoeuds  = COALESCE(@p_maxnoeuds, 500)

    /* Noeuds trouves. NOD_HASH = CHECKSUM(DTA_1..DTA_4), calcule sur les
       colonnes de LINE_VIS_EDG (meme valeur que DTA_HASH) : il sert a
       chercher dans l'index et a reconnaitre un noeud deja vu.
       COLLATE DATABASE_DEFAULT : sans lui, les colonnes prendraient la
       collation de tempdb, et les comparaisons avec LINE_VIS_EDG pourraient
       echouer (conflit de collation) ou suivre d'autres regles. */
    CREATE TABLE #noeuds (
        NOD_ID   INT IDENTITY(1, 1) PRIMARY KEY,
        NOD_HASH INT NOT NULL,
        DTA_1    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_2    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        DTA_3    VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        DTA_4    VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        NIVEAU   INT     NOT NULL,
        SENS     CHAR(1) NOT NULL       -- '-' depart, 'O' aval, 'I' amont
    )
    CREATE INDEX IX_noeuds_hash ON #noeuds (NOD_HASH)

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

    /* Voisins lus au niveau courant, regroupes par (noeud de depart, sens,
       voisin) : un voisin relie par 1 000 lignes ne fait qu'une ligne ici. */
    CREATE TABLE #voisins (
        DEP_ID        INT     NOT NULL,  -- noeud explore (NOD_ID de #noeuds)
        SENS          CHAR(1) NOT NULL,  -- EDG_DIR suivi : 'O' ou 'I'
        VOI_HASH      INT     NOT NULL,  -- CHECKSUM(EDG_1..EDG_4)
        VOI_1         VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        VOI_2         VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        VOI_3         VARCHAR(8000) COLLATE DATABASE_DEFAULT NULL,
        VOI_4         VARCHAR(1000) COLLATE DATABASE_DEFAULT NULL,
        NB_LIENS      INT NOT NULL,
        NB_PROGRAMMES INT NOT NULL
    )

    -- Aretes trouvees, dans le sens du flux (source -> destination)
    CREATE TABLE #aretes (
        SRC_ID        INT NOT NULL,
        DST_ID        INT NOT NULL,
        NB_LIENS      INT NOT NULL,
        NB_PROGRAMMES INT NOT NULL
    )

    /* 1. Noeud de depart (niveau 0), lu par la cle primaire.
          Introuvable -> #noeuds reste vide, la boucle ne fait rien. */
    INSERT INTO #noeuds (NOD_HASH, DTA_1, DTA_2, DTA_3, DTA_4, NIVEAU, SENS)
    SELECT TOP (1) e.DTA_HASH, e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4, 0, '-'
    FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
    WHERE e.LNA_UID = @p_lnauid
      AND e.LIN_UID = @p_linuid
      AND e.EDG_DIR = @p_edgdir

    DECLARE @niveau   INT = 0
    DECLARE @reste    INT
    DECLARE @nbAjouts INT
    DECLARE @tronque  BIT = 0

    /* 2. Parcours en largeur : a chaque tour, on explore les noeuds du
          niveau @niveau et on ajoute leurs voisins au niveau @niveau + 1. */
    WHILE @niveau < @p_profondeur AND EXISTS (SELECT 1 FROM #noeuds WHERE NIVEAU = @niveau)
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

        /* 2b. Voisins de la frontiere.
               EDG_DIR + DTA_HASH -> recherche dans IX_LINE_VIS_EDG_DIR_HASH
               (FORCESEEK : sans lui, SQL Server choisit parfois de lire les
               7 M lignes, ~40 s) ; l'egalite des 4 coordonnees ecarte les
               collisions du hash. */
        INSERT INTO #voisins
            (DEP_ID, SENS, VOI_HASH, VOI_1, VOI_2, VOI_3, VOI_4, NB_LIENS, NB_PROGRAMMES)
        SELECT
            f.NOD_ID,
            f.SENS,
            CHECKSUM(e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4),
            e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4,
            COUNT(*),
            COUNT(DISTINCT e.LNA_UID)
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
        GROUP BY f.NOD_ID, f.SENS, e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4

        /* 2c. Nouveaux noeuds (pas encore dans #noeuds), dans la limite de
               @p_maxnoeuds. Ordre fixe (table, colonne...) : le meme appel
               renvoie toujours les memes noeuds quand la limite coupe.
               Un voisin trouve par 2 chemins au meme niveau n'est ajoute
               qu'une fois (GROUP BY). */
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
        SET @nbAjouts = @@ROWCOUNT

        /* 2d. Aretes vers les voisins presents dans #noeuds (nouveaux ou
               deja vus : l'arete qui ferme un cycle est gardee). Un voisin
               ecarte par la limite n'a pas d'arete -> TRONQUE = 1. */
        INSERT INTO #aretes (SRC_ID, DST_ID, NB_LIENS, NB_PROGRAMMES)
        SELECT
            CASE WHEN v.SENS = 'O' THEN v.DEP_ID ELSE n.NOD_ID END,   -- 'I' : le voisin
            CASE WHEN v.SENS = 'O' THEN n.NOD_ID ELSE v.DEP_ID END,   -- alimente le noeud
            v.NB_LIENS,
            v.NB_PROGRAMMES
        FROM #voisins v
        INNER JOIN #noeuds n
                ON n.NOD_HASH = v.VOI_HASH
               AND (n.DTA_1 = v.VOI_1 OR (n.DTA_1 IS NULL AND v.VOI_1 IS NULL))
               AND (n.DTA_2 = v.VOI_2 OR (n.DTA_2 IS NULL AND v.VOI_2 IS NULL))
               AND (n.DTA_3 = v.VOI_3 OR (n.DTA_3 IS NULL AND v.VOI_3 IS NULL))
               AND (n.DTA_4 = v.VOI_4 OR (n.DTA_4 IS NULL AND v.VOI_4 IS NULL))

        IF @@ROWCOUNT < (SELECT COUNT(*) FROM #voisins)
            SET @tronque = 1

        SET @niveau += 1
    END

    /* 3. Resultats */
    IF @p_sortie IN ('T', 'N')
        SELECT
            n.NOD_ID,
            n.NIVEAU,
            n.SENS,
            n.DTA_1,
            n.DTA_2,
            n.DTA_3,
            n.DTA_4,
            -- "DTA_4.DTA_3.DTA_2.DTA_1", sans les parties vides
            CONCAT_WS('.', NULLIF(n.DTA_4, ''), NULLIF(n.DTA_3, ''),
                           NULLIF(n.DTA_2, ''), NULLIF(n.DTA_1, ''))  AS NOM_NOEUD,
            CAST(CASE WHEN n.NIVEAU < @p_profondeur THEN 1 ELSE 0 END AS BIT) AS EXPLORE,
            @tronque AS TRONQUE
        FROM #noeuds n
        ORDER BY n.NIVEAU, n.NOD_ID

    /* En mode 'B', une meme arete peut etre lue des 2 cotes (ligne 'O' du
       noeud source et ligne 'I' du noeud destination) : on la garde une
       fois (MAX, et non SUM, pour ne pas compter les liens en double). */
    IF @p_sortie IN ('T', 'A')
        SELECT
            a.SRC_ID             AS SRC_NOD_ID,
            a.DST_ID             AS DST_NOD_ID,
            MAX(a.NB_LIENS)      AS NB_LIENS,
            MAX(a.NB_PROGRAMMES) AS NB_PROGRAMMES
        FROM #aretes a
        GROUP BY a.SRC_ID, a.DST_ID
        ORDER BY a.SRC_ID, a.DST_ID
END
GO
