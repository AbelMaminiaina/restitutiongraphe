-- =============================================================================
--  LINE_VIS_EDG : table finale des aretes (13 colonnes + 5 hash calcules)
--  Base : RestitutionGrapheProd (adapter le USE si besoin, ex. LINE_VIS_NI)
--
--  Ordre d'installation du projet Sql-bcp-staging :
--    1. LINE_VIS_EDG.sql         (ce fichier : table finale + index sur les hash)
--    2. LINE_VIS_EDG_BCP_view.sql (vue d'import bcp 13 colonnes, sans trigger)
--    3. LINE_VIS_HEA.sql         (table d'en-tete, 1 ligne par LNA_UID)
--    4. LINE_VIS_GetNodesSuccessorsPredecessors.sql (procedure)
--    5. LINE_VIS_EDG_bcp.cmd     (import d'un fichier .data)
--    6. LINE_VIS_HEA_data.sql    (en-tetes de test, 1 par LNA_UID importe)
--
--  Les fichiers .data n'ont que 13 champs : les colonnes de hash n'y
--  figurent pas, SQL Server les calcule a partir de DTA_1..DTA_4.
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
        -- Empreinte de chaque coordonnee seule : recherche quand une partie
        -- des coordonnees est NULL (voir la procedure).
        DTA_1_HASH  AS CHECKSUM(DTA_1),
        DTA_2_HASH  AS CHECKSUM(DTA_2),
        DTA_3_HASH  AS CHECKSUM(DTA_3),
        DTA_4_HASH  AS CHECKSUM(DTA_4),
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

-- 3. Hash par coordonnee (DTA_1_HASH..DTA_4_HASH) : ajoutes a une table
--    creee avant cette version (colonnes calculees : aucune donnee a migrer).
IF COL_LENGTH(N'dbo.LINE_VIS_EDG', N'DTA_1_HASH') IS NULL
    ALTER TABLE dbo.LINE_VIS_EDG ADD
        DTA_1_HASH AS CHECKSUM(DTA_1),
        DTA_2_HASH AS CHECKSUM(DTA_2),
        DTA_3_HASH AS CHECKSUM(DTA_3),
        DTA_4_HASH AS CHECKSUM(DTA_4);
GO

-- 4. Un index (EDG_DIR, DTA_n_HASH) par coordonnee. La procedure ne filtre
--    que sur les coordonnees connues du noeud ; SQL Server prend alors
--    l'index le plus selectif parmi celles-ci. Pourquoi un hash plutot que
--    la colonne : DTA_3 est un VARCHAR(8000), trop long pour une cle
--    d'index (1700 octets max) ; un INT de 4 octets garde les index etroits
--    (~400 Mo chacun pour 7,2 M lignes, mesure).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH1'
               AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH1
        ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_1_HASH) WITH (SORT_IN_TEMPDB = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH2'
               AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH2
        ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_2_HASH) WITH (SORT_IN_TEMPDB = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH3'
               AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH3
        ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_3_HASH) WITH (SORT_IN_TEMPDB = ON);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH4'
               AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG'))
    CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH4
        ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_4_HASH) WITH (SORT_IN_TEMPDB = ON);
GO
