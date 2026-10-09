-- =============================================================================
--  LINE_VIS_EDG_2_STG : table d'arrivee bcp -> transfert auto vers LINE_VIS_EDG
--  Base : RestitutionGrapheProd (adapter le USE si besoin, ex. LINE_VIS_NI)
--
--  Probleme : les fichiers .data ont 13 champs, alors que dbo.LINE_VIS_EDG a
--  14 colonnes (la 14e, DTA_HASH, est calculee). On ne veut pas modifier la
--  commande bcp, qui vise dbo.LINE_VIS_EDG_2_STG :
--    bcp dbo.LINE_VIS_EDG_2_STG in fichier.data -c -C 65001 -t0x7F7F7F
--        -r0x07080D0A -k -h "FIRE_TRIGGERS" -q -T -S <serveur> -d <base>
--
--  Solution :
--    1. LINE_VIS_EDG_2_STG a exactement les 13 colonnes du fichier ;
--    2. un trigger INSTEAD OF INSERT intercepte l'insertion faite par bcp
--       (grace a -h "FIRE_TRIGGERS" : sans cette option, bcp ne declenche
--       aucun trigger) et envoie les lignes directement dans dbo.LINE_VIS_EDG.
--       DTA_HASH y est calculee par SQL Server.
--  Les lignes ne sont donc jamais stockees dans LINE_VIS_EDG_2_STG : pas de
--  donnees en double, pas de TRUNCATE a faire apres chaque import.
--
--  Tout ou rien : si une ligne viole la cle primaire de LINE_VIS_EDG (fichier
--  importe deux fois, par exemple), le lot entier est annule.
--
--  Volume : sans -b, bcp envoie tout le fichier en UN lot. Le trigger recoit
--  alors toutes les lignes d'un coup (pseudo-table "inserted", gardee dans
--  tempdb : ~2 Go pour 8 M lignes) et les insere en une seule transaction
--  entierement journalisee (~10 Go de journal pour 8 M lignes).
-- =============================================================================

-- Le trigger memorise ces options a sa creation ; QUOTED_IDENTIFIER ON est
-- exige par l'index sur la colonne calculee DTA_HASH de LINE_VIS_EDG.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE RestitutionGrapheProd;
GO

-- 1. Table d'arrivee : les 13 colonnes du fichier .data, dans le meme ordre.
--    Nom de cle primaire propre a cette table : PK_LINE_VIS_EDG est deja
--    utilise par dbo.LINE_VIS_EDG (deux contraintes ne peuvent pas avoir le
--    meme nom dans un schema).
IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG_2_STG]') IS NULL
BEGIN
    CREATE TABLE dbo.LINE_VIS_EDG_2_STG (
        LNA_UID     VARCHAR(200) NOT NULL ,
        LIN_UID     VARCHAR(500) NOT NULL ,
        DTA_1       VARCHAR(1000),
        DTA_2       VARCHAR(1000),
        DTA_3       VARCHAR(8000),
        DTA_4       VARCHAR(1000),
        EDG_DIR     CHAR(1) NOT NULL,
        EDG_1       VARCHAR(1000),
        EDG_2       VARCHAR(1000),
        EDG_3       VARCHAR(8000),
        EDG_4       VARCHAR(1000),
        TXN_DTA     VARCHAR(MAX),
        PRX_TXN_DTA VARCHAR(MAX),
        CONSTRAINT PK_LINE_VIS_EDG_2_STG PRIMARY KEY (LNA_UID, LIN_UID, EDG_DIR)
    )
END
GO

-- 2. Trigger : chaque insertion dans LINE_VIS_EDG_2_STG part dans LINE_VIS_EDG.
--    "inserted" contient les lignes que bcp essayait d'inserer.
CREATE OR ALTER TRIGGER dbo.TR_LINE_VIS_EDG_2_STG_Transfer
ON dbo.LINE_VIS_EDG_2_STG
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.LINE_VIS_EDG (
        LNA_UID, LIN_UID, DTA_1, DTA_2, DTA_3, DTA_4,
        EDG_DIR, EDG_1, EDG_2, EDG_3, EDG_4,
        TXN_DTA, PRX_TXN_DTA
        -- pas de DTA_HASH : colonne calculee, remplie par SQL Server
    )
    SELECT
        i.LNA_UID, i.LIN_UID, i.DTA_1, i.DTA_2, i.DTA_3, i.DTA_4,
        i.EDG_DIR, i.EDG_1, i.EDG_2, i.EDG_3, i.EDG_4,
        i.TXN_DTA, i.PRX_TXN_DTA
    FROM inserted i;
END
GO
