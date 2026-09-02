-- =============================================================================
--  LINE_VIS_EDG : table + index de couverture
--  Cible : SQL Server — base dédiée RestitutionGrapheProd
--  (la base RestitutionGraphe contient déjà une table LINE_VIS_EDG de test
--   au schéma différent : on isole ce schéma "prod" dans sa propre base)
-- =============================================================================

-- 0. Base dédiée
IF DB_ID(N'RestitutionGrapheProd') IS NULL
    CREATE DATABASE RestitutionGrapheProd;
GO
USE RestitutionGrapheProd;
GO

-- 1. Création de LINE_VIS_EDG si elle n'existe pas
IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG]') IS NULL
BEGIN
    CREATE TABLE dbo.LINE_VIS_EDG (
        LNA_UID       VARCHAR(200)  NOT NULL,
        LIN_UID       VARCHAR(500)  NOT NULL,
        DTA_1         VARCHAR(1000),
        DTA_2         VARCHAR(1000),
        DTA_3         VARCHAR(8000),
        DTA_4         VARCHAR(1000),
        EDG_DIR       CHAR(1)       NOT NULL,
        EDG_1         VARCHAR(1000),
        EDG_2         VARCHAR(1000),
        EDG_3         VARCHAR(8000),
        EDG_4         VARCHAR(1000),
        TXN_DTA       VARCHAR(MAX),
        PRX_TXN_DTA   VARCHAR(MAX),
        CONSTRAINT PK_LINE_VIS_EDG PRIMARY KEY (LNA_UID, LIN_UID, EDG_DIR)
    )
END
GO

-- Index composite sur DTA_1-4, EDG_DIR pour GetNodesSuccessorsPredecessors
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_DTA_EDG_DIR' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG')
)
BEGIN
    CREATE INDEX IX_LINE_VIS_EDG_DTA_EDG_DIR
    ON dbo.LINE_VIS_EDG(DTA_1, DTA_2, DTA_3, DTA_4, EDG_DIR)
    INCLUDE (LNA_UID, LIN_UID, EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
END

-- Index sur LNA_UID pour JOIN avec LINE_VIS_HEA
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_LNA_UID' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG')
)
BEGIN
    CREATE INDEX IX_LINE_VIS_EDG_LNA_UID
    ON dbo.LINE_VIS_EDG(LNA_UID)
    INCLUDE (LIN_UID, EDG_DIR, DTA_1, DTA_2, DTA_3, DTA_4, EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
END

-- Index pour NodeList (recherche sur DTA_1)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_DTA_1' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG')
)
BEGIN
    CREATE INDEX IX_LINE_VIS_EDG_DTA_1
    ON dbo.LINE_VIS_EDG(DTA_1)
    INCLUDE (DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR)
END

-- Index pour NodeList (recherche sur DTA_1)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_2_Covering' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG')
)
BEGIN
    CREATE INDEX [IX_LINE_VIS_EDG_2_Covering]
    ON [dbo].[LINE_VIS_EDG] (DTA_1, DTA_2, DTA_3, DTA_4, LIN_UID, LNA_UID, EDG_DIR)
    WITH (
        ONLINE = OFF,
        SORT_IN_TEMPDB = ON,
        FILLFACTOR = 90
    );
END
GO
