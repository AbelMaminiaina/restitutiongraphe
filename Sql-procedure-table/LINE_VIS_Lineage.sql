-- =============================================================================
--  Procedure dbo.LINE_VIS_Lineage
--  Base : RestitutionGrapheProd
--
--  But : lineage sur PLUSIEURS niveaux a partir d'un noeud.
--  LINE_VIS_GetNodesSuccessorsPredecessors ne donne que les voisins directs
--  (1 niveau) ; cette procedure suit les liens niveau par niveau, en aval
--  (successeurs), en amont (predecesseurs) ou dans les deux sens.
--
--  Le parcours lui-meme (modele, methode, regles de comparaison) est dans
--  dbo.LINE_VIS_Lineage_Parcours, partage avec dbo.LINE_VIS_Impact.
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
--  Dependances : dbo.LINE_VIS_Lineage_Parcours (LINE_VIS_Lineage_Parcours.sql)
-- =============================================================================

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

    IF @p_sortie IS NULL OR @p_sortie NOT IN ('T', 'N', 'A')
        THROW 50002, 'LINE_VIS_Lineage : @p_sortie doit valoir T (tout), N (noeuds) ou A (aretes).', 1;

    SET @p_profondeur = COALESCE(@p_profondeur, 5)
    SET @p_maxnoeuds  = COALESCE(@p_maxnoeuds, 500)

    -- Tables remplies par LINE_VIS_Lineage_Parcours (voir son en-tete)
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

    DECLARE @tronque BIT

    EXEC dbo.LINE_VIS_Lineage_Parcours
        @p_lnauid, @p_linuid, @p_edgdir, @p_sens,
        @p_profondeur, @p_maxnoeuds, @tronque OUTPUT

    /* Resultats */
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

    /* Une ligne par arete. En mode 'B', un meme lien (source, destination,
       programme) peut avoir ete lu des 2 cotes : MAX le compte une fois,
       puis SUM additionne les programmes. */
    IF @p_sortie IN ('T', 'A')
        SELECT
            l.SRC_ID         AS SRC_NOD_ID,
            l.DST_ID         AS DST_NOD_ID,
            SUM(l.NB_LIENS)  AS NB_LIENS,
            COUNT(*)         AS NB_PROGRAMMES
        FROM (
            SELECT SRC_ID, DST_ID, LNA_UID, MAX(NB_LIENS) AS NB_LIENS
            FROM #liens
            GROUP BY SRC_ID, DST_ID, LNA_UID
        ) l
        GROUP BY l.SRC_ID, l.DST_ID
        ORDER BY l.SRC_ID, l.DST_ID
END
GO
