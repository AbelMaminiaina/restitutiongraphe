-- =============================================================================
--  Procedure dbo.LINE_VIS_ControleQualite
--  Base : RestitutionGrapheProd
--
--  But : controle qualite des donnees de lineage (LINE_VIS_EDG + LINE_VIS_HEA).
--  Une ligne de synthese par controle (nombre d'anomalies, %, statut) et
--  quelques lignes d'exemple par controle pour aller voir sur pieces.
--
--  Controles :
--    SYM_O_SANS_I      ligne 'O' (A -> B) sans ligne 'I' inverse chez B (B <- A)
--    SYM_I_SANS_O      ligne 'I' (B <- A) sans ligne 'O' inverse chez A (A -> B)
--        -> Si ces 2 controles sont proches de 0 %, chaque lien est stocke
--           des DEUX cotes, avec des sens opposes : c'est coherent avec
--           l'hypothese utilisee par les procedures de lineage
--           ('O' = successeur, 'I' = predecesseur). Ils ne PROUVENT pas quel
--           sens est le bon (seul un exemple metier connu le peut) ; ils
--           montrent si le modele "un lien = 2 lignes" tient.
--           S'ils sont proches de 100 % : chaque lien n'est stocke qu'une
--           fois ; l'aval et l'amont viennent alors de lignes differentes.
--    SANS_ENTETE       LNA_UID absent de LINE_VIS_HEA : ces lignes sont
--                      IGNOREES par toutes les procedures de lineage.
--    ENTETE_INUTILISEE ligne de LINE_VIS_HEA sans aucune ligne dans LINE_VIS_EDG.
--    VOISIN_VIDE       EDG_1..EDG_4 tous NULL ou vides : la ligne ne mene nulle part.
--    VOISIN_INCOMPLET  voisin renseigne en partie (une des EDG_n NULL ou vide).
--    NOEUD_INCOMPLET   noeud renseigne en partie (une des DTA_n NULL ou vide).
--    VOISIN_FANTOME    voisin qui n'apparait jamais comme noeud (DTA_1..4)
--                      d'une autre ligne : le lineage s'arrete la (erreur
--                      de capture, ou vraie sortie finale).
--    DOUBLON           meme lien (meme programme, meme sens, meme noeud, meme
--                      voisin) present plusieurs fois (LIN_UID differents) ;
--                      NB_LIGNES = lignes EN TROP.
--
--  Methode (7 M lignes, SQL Server Express, disque presque plein) :
--    - UNE seule lecture de LINE_VIS_EDG, vers la table #lignes (tempdb) :
--      cle de chaque ligne + 3 empreintes de 4 octets (CHECKSUM) du noeud
--      (= DTA_HASH), du voisin et du programme + les indicateurs simples.
--      Tous les controles travaillent ensuite sur ces entiers : aucune
--      comparaison de VARCHAR(8000), aucune autre lecture de la table
--      (sauf la relecture, par la cle primaire, des quelques exemples).
--    - tempdb : ~60 octets par ligne, soit ~500 Mo pour 7 M lignes,
--      liberes a la fin de la procedure.
--    - Empreintes : 2 valeurs differentes peuvent avoir le meme CHECKSUM.
--      Consequence : une anomalie trouvee est toujours reelle, mais une
--      anomalie peut, tres rarement, etre manquee (son voisin "ressemble" a
--      un autre noeud). Les nombres sont donc des MINIMUMS ; l'ecart est
--      negligeable pour SYM_* et DOUBLON (il faut 2 collisions a la fois),
--      au plus ~0,2 % pour VOISIN_FANTOME (une seule collision suffit).
--      Les regles de comparaison sont celles de "=" (casse et espaces de
--      fin ignores, comme partout ailleurs).
--    - Rien n'est ecrit dans la base.
--
--  Parametres :
--    @p_exemples : nombre de lignes d'exemple par controle (defaut 5, 0 = aucun).
--    @p_sortie   : 'T' = les 2 jeux de resultats (defaut), 'S' = synthese,
--                  'E' = exemples (un seul jeu : pour INSERT ... EXEC).
--
--  Resultats :
--    1. SYNTHESE : ORDRE, CONTROLE, DESCRIPTION, NB_LIGNES (lignes en
--       anomalie), NB_DISTINCTS (liens / programmes / voisins distincts,
--       voir DESCRIPTION), NB_LIGNES_TOTAL (base du pourcentage), POURCENT,
--       STATUT ('OK' ou 'ANOMALIE').
--    2. EXEMPLES : CONTROLE, LNA_UID, LIN_UID, EDG_DIR, DTA_1..DTA_4,
--       EDG_1..EDG_4 (pour ENTETE_INUTILISEE : LNA_UID seulement).
--
--  Dependances : dbo.LINE_VIS_EDG (colonne DTA_HASH), dbo.LINE_VIS_HEA
-- =============================================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_ControleQualite]') IS NOT NULL
DROP PROCEDURE [dbo].LINE_VIS_ControleQualite
GO

CREATE PROCEDURE [dbo].LINE_VIS_ControleQualite
    @p_exemples INT     = 5,
    @p_sortie   CHAR(1) = 'T'

AS
BEGIN
    SET NOCOUNT ON

    IF @p_sortie IS NULL OR @p_sortie NOT IN ('T', 'S', 'E')
        THROW 50002, 'LINE_VIS_ControleQualite : @p_sortie doit valoir T (tout), S (synthese) ou E (exemples).', 1;

    SET @p_exemples = COALESCE(@p_exemples, 5)
    IF @p_exemples < 0 SET @p_exemples = 0

    /* 1. Lecture unique de LINE_VIS_EDG.
          H_DTA = empreinte du noeud (DTA_HASH), H_EDG = du voisin,
          H_LNA = du programme. Les indicateurs valent 1 si la ligne est
          dans le cas. */
    CREATE TABLE #lignes (
        LNA_UID          VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        LIN_UID          VARCHAR(500) COLLATE DATABASE_DEFAULT NOT NULL,
        EDG_DIR          CHAR(1) NOT NULL,
        H_DTA            INT     NOT NULL,
        H_EDG            INT     NOT NULL,
        H_LNA            INT     NOT NULL,
        SANS_ENTETE      BIT     NOT NULL,
        VOISIN_VIDE      BIT     NOT NULL,
        VOISIN_INCOMPLET BIT     NOT NULL,
        NOEUD_INCOMPLET  BIT     NOT NULL
    )

    -- TABLOCK : insertion minimalement journalisee dans tempdb
    INSERT INTO #lignes WITH (TABLOCK)
        (LNA_UID, LIN_UID, EDG_DIR, H_DTA, H_EDG, H_LNA,
         SANS_ENTETE, VOISIN_VIDE, VOISIN_INCOMPLET, NOEUD_INCOMPLET)
    SELECT
        e.LNA_UID,
        e.LIN_UID,
        e.EDG_DIR,
        e.DTA_HASH,
        CHECKSUM(e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4),
        CHECKSUM(e.LNA_UID),
        CASE WHEN h.LNA_UID IS NULL THEN 1 ELSE 0 END,
        -- voisin vide : les 4 parties NULL ou ''
        CASE WHEN COALESCE(e.EDG_1, '') = '' AND COALESCE(e.EDG_2, '') = ''
              AND COALESCE(e.EDG_3, '') = '' AND COALESCE(e.EDG_4, '') = '' THEN 1 ELSE 0 END,
        -- voisin incomplet : au moins une partie vide, mais pas toutes
        CASE WHEN (COALESCE(e.EDG_1, '') = '' OR COALESCE(e.EDG_2, '') = ''
                OR COALESCE(e.EDG_3, '') = '' OR COALESCE(e.EDG_4, '') = '')
              AND NOT (COALESCE(e.EDG_1, '') = '' AND COALESCE(e.EDG_2, '') = ''
                   AND COALESCE(e.EDG_3, '') = '' AND COALESCE(e.EDG_4, '') = '') THEN 1 ELSE 0 END,
        -- noeud incomplet : au moins une partie vide
        CASE WHEN COALESCE(e.DTA_1, '') = '' OR COALESCE(e.DTA_2, '') = ''
               OR COALESCE(e.DTA_3, '') = '' OR COALESCE(e.DTA_4, '') = '' THEN 1 ELSE 0 END
    FROM dbo.LINE_VIS_EDG e WITH (NOLOCK)
    LEFT JOIN dbo.LINE_VIS_HEA h WITH (NOLOCK) ON h.LNA_UID = e.LNA_UID

    DECLARE @total BIGINT = (SELECT COUNT_BIG(*) FROM #lignes)
    DECLARE @totO  BIGINT = (SELECT COUNT_BIG(*) FROM #lignes WHERE EDG_DIR = 'O' AND VOISIN_VIDE = 0)
    DECLARE @totI  BIGINT = (SELECT COUNT_BIG(*) FROM #lignes WHERE EDG_DIR = 'I' AND VOISIN_VIDE = 0)
    DECLARE @totH  BIGINT = (SELECT COUNT_BIG(*) FROM dbo.LINE_VIS_HEA WITH (NOLOCK))

    /* 2. Controles. Chacun donne NB_LIGNES et NB_DISTINCTS ; la synthese
          est completee a l'etape 3 (pourcentage, statut). */
    CREATE TABLE #synthese (
        ORDRE           INT          NOT NULL,
        CONTROLE        VARCHAR(30)  NOT NULL,
        DESCRIPTION     VARCHAR(300) NOT NULL,
        NB_LIGNES       BIGINT       NOT NULL,
        NB_DISTINCTS    BIGINT       NOT NULL,
        NB_LIGNES_TOTAL BIGINT       NOT NULL
    )

    -- SYM_O_SANS_I : A -O-> B sans B -I-> A
    -- (l'inverse a pour noeud le voisin de A et pour voisin le noeud A)
    INSERT INTO #synthese
    SELECT 1, 'SYM_O_SANS_I',
           'Lignes O (A -> B) sans ligne I inverse chez B ; distincts = liens A -> B distincts',
           COALESCE(SUM(x.n), 0), COUNT_BIG(*), @totO
    FROM (
        SELECT o.H_DTA, o.H_EDG, COUNT_BIG(*) AS n
        FROM #lignes o
        WHERE o.EDG_DIR = 'O' AND o.VOISIN_VIDE = 0
          AND NOT EXISTS (SELECT 1 FROM #lignes i
                          WHERE i.EDG_DIR = 'I' AND i.VOISIN_VIDE = 0
                            AND i.H_DTA = o.H_EDG AND i.H_EDG = o.H_DTA)
        GROUP BY o.H_DTA, o.H_EDG
    ) x

    -- SYM_I_SANS_O : B -I-> A sans A -O-> B
    INSERT INTO #synthese
    SELECT 2, 'SYM_I_SANS_O',
           'Lignes I (B <- A) sans ligne O inverse chez A ; distincts = liens distincts',
           COALESCE(SUM(x.n), 0), COUNT_BIG(*), @totI
    FROM (
        SELECT i.H_DTA, i.H_EDG, COUNT_BIG(*) AS n
        FROM #lignes i
        WHERE i.EDG_DIR = 'I' AND i.VOISIN_VIDE = 0
          AND NOT EXISTS (SELECT 1 FROM #lignes o
                          WHERE o.EDG_DIR = 'O' AND o.VOISIN_VIDE = 0
                            AND o.H_DTA = i.H_EDG AND o.H_EDG = i.H_DTA)
        GROUP BY i.H_DTA, i.H_EDG
    ) x

    -- SANS_ENTETE
    INSERT INTO #synthese
    SELECT 3, 'SANS_ENTETE',
           'LNA_UID absent de LINE_VIS_HEA (lignes ignorees par le lineage) ; distincts = LNA_UID',
           COUNT_BIG(*), COUNT_BIG(DISTINCT LNA_UID), @total
    FROM #lignes
    WHERE SANS_ENTETE = 1

    -- ENTETE_INUTILISEE
    INSERT INTO #synthese
    SELECT 4, 'ENTETE_INUTILISEE',
           'Lignes de LINE_VIS_HEA sans aucune ligne dans LINE_VIS_EDG ; base = lignes de LINE_VIS_HEA',
           COUNT_BIG(*), COUNT_BIG(*), @totH
    FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #lignes l WHERE l.LNA_UID = h.LNA_UID)

    -- VOISIN_VIDE, VOISIN_INCOMPLET, NOEUD_INCOMPLET (distincts = LNA_UID)
    INSERT INTO #synthese
    SELECT 5, 'VOISIN_VIDE',
           'EDG_1..EDG_4 tous NULL ou vides (la ligne ne mene nulle part) ; distincts = LNA_UID',
           COUNT_BIG(*), COUNT_BIG(DISTINCT LNA_UID), @total
    FROM #lignes WHERE VOISIN_VIDE = 1

    INSERT INTO #synthese
    SELECT 6, 'VOISIN_INCOMPLET',
           'Voisin renseigne en partie (une des EDG_n NULL ou vide) ; distincts = LNA_UID',
           COUNT_BIG(*), COUNT_BIG(DISTINCT LNA_UID), @total
    FROM #lignes WHERE VOISIN_INCOMPLET = 1

    INSERT INTO #synthese
    SELECT 7, 'NOEUD_INCOMPLET',
           'Noeud renseigne en partie (une des DTA_n NULL ou vide) ; distincts = LNA_UID',
           COUNT_BIG(*), COUNT_BIG(DISTINCT LNA_UID), @total
    FROM #lignes WHERE NOEUD_INCOMPLET = 1

    -- VOISIN_FANTOME : voisin jamais vu comme noeud
    INSERT INTO #synthese
    SELECT 8, 'VOISIN_FANTOME',
           'Voisin qui n''est le noeud d''aucune ligne (fin du lineage) ; distincts = voisins',
           COUNT_BIG(*), COUNT_BIG(DISTINCT v.H_EDG), @total
    FROM #lignes v
    WHERE v.VOISIN_VIDE = 0
      AND NOT EXISTS (SELECT 1 FROM #lignes n WHERE n.H_DTA = v.H_EDG)

    -- DOUBLON : meme programme, sens, noeud, voisin
    INSERT INTO #synthese
    SELECT 9, 'DOUBLON',
           'Meme lien en plusieurs lignes (meme programme, sens, noeud, voisin) ; lignes = lignes en trop, distincts = liens doublonnes',
           COALESCE(SUM(x.n - 1), 0), COUNT_BIG(*), @total
    FROM (
        SELECT COUNT_BIG(*) AS n
        FROM #lignes
        GROUP BY H_LNA, EDG_DIR, H_DTA, H_EDG
        HAVING COUNT_BIG(*) > 1
    ) x

    /* 3. Exemples : quelques cles par controle, puis relecture des lignes
          completes par la cle primaire. */
    CREATE TABLE #ex_cles (
        CONTROLE VARCHAR(30)  NOT NULL,
        LNA_UID  VARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL,
        LIN_UID  VARCHAR(500) COLLATE DATABASE_DEFAULT NULL,
        EDG_DIR  CHAR(1) NULL
    )

    IF @p_exemples > 0 AND @p_sortie IN ('T', 'E')
    BEGIN
        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'SYM_O_SANS_I', o.LNA_UID, o.LIN_UID, o.EDG_DIR
        FROM #lignes o
        WHERE o.EDG_DIR = 'O' AND o.VOISIN_VIDE = 0
          AND NOT EXISTS (SELECT 1 FROM #lignes i
                          WHERE i.EDG_DIR = 'I' AND i.VOISIN_VIDE = 0
                            AND i.H_DTA = o.H_EDG AND i.H_EDG = o.H_DTA)
        ORDER BY o.LNA_UID, o.LIN_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'SYM_I_SANS_O', i.LNA_UID, i.LIN_UID, i.EDG_DIR
        FROM #lignes i
        WHERE i.EDG_DIR = 'I' AND i.VOISIN_VIDE = 0
          AND NOT EXISTS (SELECT 1 FROM #lignes o
                          WHERE o.EDG_DIR = 'O' AND o.VOISIN_VIDE = 0
                            AND o.H_DTA = i.H_EDG AND o.H_EDG = i.H_DTA)
        ORDER BY i.LNA_UID, i.LIN_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'SANS_ENTETE', LNA_UID, LIN_UID, EDG_DIR
        FROM #lignes WHERE SANS_ENTETE = 1
        ORDER BY LNA_UID, LIN_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'ENTETE_INUTILISEE', h.LNA_UID, NULL, NULL
        FROM dbo.LINE_VIS_HEA h WITH (NOLOCK)
        WHERE NOT EXISTS (SELECT 1 FROM #lignes l WHERE l.LNA_UID = h.LNA_UID)
        ORDER BY h.LNA_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'VOISIN_VIDE', LNA_UID, LIN_UID, EDG_DIR
        FROM #lignes WHERE VOISIN_VIDE = 1
        ORDER BY LNA_UID, LIN_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'VOISIN_INCOMPLET', LNA_UID, LIN_UID, EDG_DIR
        FROM #lignes WHERE VOISIN_INCOMPLET = 1
        ORDER BY LNA_UID, LIN_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'NOEUD_INCOMPLET', LNA_UID, LIN_UID, EDG_DIR
        FROM #lignes WHERE NOEUD_INCOMPLET = 1
        ORDER BY LNA_UID, LIN_UID

        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'VOISIN_FANTOME', v.LNA_UID, v.LIN_UID, v.EDG_DIR
        FROM #lignes v
        WHERE v.VOISIN_VIDE = 0
          AND NOT EXISTS (SELECT 1 FROM #lignes n WHERE n.H_DTA = v.H_EDG)
        ORDER BY v.LNA_UID, v.LIN_UID

        -- Doublons : toutes les lignes des premiers liens doublonnes
        INSERT INTO #ex_cles
        SELECT TOP (@p_exemples) 'DOUBLON', l.LNA_UID, l.LIN_UID, l.EDG_DIR
        FROM #lignes l
        INNER JOIN (SELECT H_LNA, EDG_DIR, H_DTA, H_EDG
                    FROM #lignes
                    GROUP BY H_LNA, EDG_DIR, H_DTA, H_EDG
                    HAVING COUNT_BIG(*) > 1) d
                ON d.H_LNA = l.H_LNA AND d.EDG_DIR = l.EDG_DIR
               AND d.H_DTA = l.H_DTA AND d.H_EDG = l.H_EDG
        ORDER BY l.LNA_UID, l.H_DTA, l.H_EDG, l.LIN_UID
    END

    /* 4. Resultats */
    IF @p_sortie IN ('T', 'S')
        SELECT
            s.ORDRE,
            s.CONTROLE,
            s.DESCRIPTION,
            s.NB_LIGNES,
            s.NB_DISTINCTS,
            s.NB_LIGNES_TOTAL,
            CAST(CASE WHEN s.NB_LIGNES_TOTAL = 0 THEN 0
                      ELSE 100.0 * s.NB_LIGNES / s.NB_LIGNES_TOTAL END AS DECIMAL(6, 2)) AS POURCENT,
            CASE WHEN s.NB_LIGNES = 0 THEN 'OK' ELSE 'ANOMALIE' END AS STATUT
        FROM #synthese s
        ORDER BY s.ORDRE

    IF @p_sortie IN ('T', 'E')
        SELECT
            k.CONTROLE,
            k.LNA_UID,
            k.LIN_UID,
            k.EDG_DIR,
            e.DTA_1, e.DTA_2, e.DTA_3, e.DTA_4,
            e.EDG_1, e.EDG_2, e.EDG_3, e.EDG_4
        FROM #ex_cles k
        INNER JOIN #synthese s ON s.CONTROLE = k.CONTROLE
        LEFT JOIN dbo.LINE_VIS_EDG e WITH (NOLOCK)
               ON e.LNA_UID = k.LNA_UID AND e.LIN_UID = k.LIN_UID AND e.EDG_DIR = k.EDG_DIR
        ORDER BY s.ORDRE, k.LNA_UID, k.LIN_UID
END
GO
