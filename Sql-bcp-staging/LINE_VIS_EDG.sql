-- =============================================================================
--  LINE_VIS_EDG : table finale des aretes (14 colonnes dont DTA_HASH calculee)
--  Base : RestitutionGrapheProd (adapter le USE si besoin, ex. LINE_VIS_NI)
--
--  Ordre d'installation du projet Sql-bcp-staging :
--    1. LINE_VIS_EDG.sql         (ce fichier : table finale + index sur DTA_HASH)
--    2. LINE_VIS_EDG_2_STG.sql   (table d'arrivee bcp 13 colonnes + trigger)
--    3. LINE_VIS_HEA.sql         (table d'en-tete, 1 ligne par LNA_UID)
--    4. LINE_VIS_GetNodesSuccessorsPredecessors.sql (procedure)
--    5. LINE_VIS_EDG_bcp.cmd     (import d'un fichier .data)
--    6. LINE_VIS_HEA_data.sql    (en-tetes de test, 1 par LNA_UID importe)
--
--  Les fichiers .data n'ont que 13 champs : DTA_HASH n'y figure pas, SQL
--  Server la calcule a partir de DTA_1..DTA_4.
-- =============================================================================

-- Options memorisees avec la table / l'index ; QUOTED_IDENTIFIER et
-- ANSI_NULLS ON sont obligatoires pour indexer une colonne calculee.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_ID(N'RestitutionGrapheProd') IS NULL
    CREATE DATABASE RestitutionGrapheProd;
GO
USE RestitutionGrapheProd;
GO

-- 1. Table finale (creee seulement si elle n'existe pas encore)
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
        -- 14e colonne : empreinte de DTA_1..DTA_4 (calculee, non persistee).
        -- Absente des fichiers .data : SQL Server la remplit seul.
        DTA_HASH    AS CHECKSUM(DTA_1, DTA_2, DTA_3, DTA_4),
        CONSTRAINT PK_LINE_VIS_EDG PRIMARY KEY (LNA_UID, LIN_UID, EDG_DIR)
    )
END
GO

-- 2. Index (EDG_DIR, DTA_HASH) INCLUDE (DTA_1..DTA_4) : recherche des aretes
--    par empreinte (procedure LINE_VIS_GetNodesSuccessorsPredecessors).
--    - cle (EDG_DIR, DTA_HASH) : on va directement aux lignes du bon hash ;
--      la cle primaire (LNA_UID, LIN_UID, EDG_DIR) est ajoutee d'office a
--      chaque ligne d'index -> a hash egal, lignes deja triees par
--      LNA_UID, LIN_UID ;
--    - INCLUDE (DTA_1..DTA_4) : le controle anti-collision du hash
--      (DTA_n = valeur cherchee) et le comptage se font dans l'index seul,
--      sans aller relire chaque ligne dans la table.
--    A cause de cet index, toute insertion (bcp compris) doit se faire avec
--    QUOTED_IDENTIFIER ON -> option -q de bcp, -I de sqlcmd.
--
--    Si l'index existe deja SANS les colonnes incluses (ancienne version),
--    il est reconstruit (DROP_EXISTING).
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH'
      AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG')
)
    CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH
        ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_HASH)
        INCLUDE (DTA_1, DTA_2, DTA_3, DTA_4)
        WITH (SORT_IN_TEMPDB = ON);
ELSE IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
    WHERE i.name = 'IX_LINE_VIS_EDG_DIR_HASH'
      AND i.object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG')
      AND ic.is_included_column = 1
      AND c.name = 'DTA_3'
)
    CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH
        ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_HASH)
        INCLUDE (DTA_1, DTA_2, DTA_3, DTA_4)
        WITH (DROP_EXISTING = ON, SORT_IN_TEMPDB = ON);
GO
