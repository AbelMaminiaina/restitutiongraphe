-- =============================================================================
--  LINE_VIS_EDG_BCP : vue d'import bcp pour dbo.LINE_VIS_EDG
--  Base : RestitutionGrapheProd
--
--  Pourquoi : depuis l'ajout de la colonne calculee DTA_HASH (14e colonne),
--  bcp sans fichier de format attend 14 champs par ligne alors que les
--  fichiers .data n'en ont que 13 -> les champs se decalent et l'import
--  echoue. Cette vue expose uniquement les 13 colonnes reelles, dans le
--  meme ordre que les fichiers .data : il suffit de viser la vue au lieu
--  de la table dans la commande bcp, sans rien changer d'autre
--  (memes options -c / -t / -r qu'avant).
--
--  Les lignes inserees dans la vue vont dans dbo.LINE_VIS_EDG et
--  DTA_HASH y est calculee automatiquement.
--
--  Exemple :
--    bcp RestitutionGrapheProd.dbo.LINE_VIS_EDG_BCP in fichier.data
--        -S .\SQLEXPRESS01 -T -c -t "<separateur>" -q
--  (-q obligatoire : l'index sur DTA_HASH exige QUOTED_IDENTIFIER ON)
-- =============================================================================

USE RestitutionGrapheProd;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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
FROM dbo.LINE_VIS_EDG;
GO
