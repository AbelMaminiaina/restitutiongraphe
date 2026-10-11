-- =============================================================================
--  LINE_VIS_EDG_BCP : vue d'import bcp pour dbo.LINE_VIS_EDG (sans trigger)
--  Base : RestitutionGrapheProd (adapter le USE si besoin, ex. LINE_VIS_NI)
--
--  Probleme : les fichiers .data ont 13 champs, alors que dbo.LINE_VIS_EDG a
--  14 colonnes (la 14e, DTA_HASH, est calculee). Un bcp direct sur la table
--  attend 14 champs par ligne : les champs se decalent et les lignes sont
--  mal decoupees (teste : 500 lignes chargees au lieu de 1000).
--
--  Solution : cette vue n'expose que les 13 colonnes reelles, dans le meme
--  ordre que le fichier. bcp vise la vue ; les lignes vont directement dans
--  dbo.LINE_VIS_EDG et SQL Server y calcule DTA_HASH. Pas de trigger, donc
--  pas d'option -h "FIRE_TRIGGERS", et pas de table de staging.
--
--  Exemple :
--    bcp dbo.LINE_VIS_EDG_BCP in fichier.data -c -C 65001 -t0x7F7F7F
--        -r0x07080D0A -k -q -T -S <serveur> -d <base>
--  (-q obligatoire : l'index sur DTA_HASH exige QUOTED_IDENTIFIER ON)
-- =============================================================================

-- Options memorisees avec la vue ; l'index sur DTA_HASH les exige a ON.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

CREATE OR ALTER VIEW dbo.LINE_VIS_EDG_BCP
AS
SELECT
    LNA_UID,
    LIN_UID,
    DTA_1,
    DTA_2,
    DTA_3,
    DTA_4,
    EDG_DIR,
    EDG_1,
    EDG_2,
    EDG_3,
    EDG_4,
    TXN_DTA,
    PRX_TXN_DTA
    -- pas de DTA_HASH : colonne calculee, remplie par SQL Server
FROM dbo.LINE_VIS_EDG;
GO
