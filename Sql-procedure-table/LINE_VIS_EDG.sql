-- =============================================================================
--  LINE_VIS_EDG : table des aretes
--  Cible : SQL Server - base dediee RestitutionGrapheProd
--  (la base RestitutionGraphe contient deja une table LINE_VIS_EDG de test
--   au schema different : on isole ce schema "prod" dans sa propre base)
--
--  Code transcrit de la photo M1/1.jpeg (fichier LINE_VIS_EDG.sql).
--  La photo ne montre que les lignes 22 a 49 : le bloc de suppression de
--  l'index IX_LINE_VIS_EDG_COV (debut du fichier) est reconstruit a partir
--  de la seule ligne lisible "DROP INDEX [IX_LINE_VIS_EDG_COV] ON [dbo].[LINE_VIS_EDG]".
--  Ajouts : l'en-tete CREATE DATABASE / USE ci-dessous, et la colonne
--  calculee DTA_HASH directement dans le CREATE TABLE (auparavant ajoutee
--  par ALTER TABLE dans LINE_VIS_EDG_IndexHash.sql).
--
--  Recreation complete (drop + 7 M lignes) - ordre :
--    1. DROP TABLE dbo.LINE_VIS_EDG;
--    2. LINE_VIS_EDG.sql            (ce fichier)
--    3. LINE_VIS_EDG_data.sql       (insertion sans index secondaire : plus rapide)
--    4. LINE_VIS_EDG_IndexHash.sql  (index (EDG_DIR, DTA_HASH) construit en une passe)
-- =============================================================================

-- Options requises pour qu'un futur index sur DTA_HASH soit utilisable
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_ID(N'RestitutionGrapheProd') IS NULL
    CREATE DATABASE RestitutionGrapheProd;
GO
USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG]') IS NOT NULL
BEGIN
    IF EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE name = 'IX_LINE_VIS_EDG_COV' AND object_id = OBJECT_ID(N'[dbo].[LINE_VIS_EDG]')
    )
    BEGIN
        DROP INDEX [IX_LINE_VIS_EDG_COV] ON [dbo].[LINE_VIS_EDG]
    END
END
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG]') IS NULL
BEGIN
    CREATE TABLE dbo.LINE_VIS_EDG (
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
        -- Empreinte de DTA_1..DTA_4 (colonne calculee non persistee),
        -- indexee par LINE_VIS_EDG_IndexHash.sql (IX_LINE_VIS_EDG_DIR_HASH).
        DTA_HASH    AS CHECKSUM(DTA_1, DTA_2, DTA_3, DTA_4),
        CONSTRAINT PK_LINE_VIS_EDG PRIMARY KEY (LNA_UID, LIN_UID, EDG_DIR)
    )
END
GO
