-- =============================================================================
--  LINE_VIS_EDG — variante "clé dérivée" (dossier Sql-procedure-table-hash)
--  Cible : SQL Server — base dédiée RestitutionGrapheProdHash
--
--  BUT : supprimer l'avertissement "index key > 1700 bytes" SANS toucher aux
--  colonnes DTA_1..DTA_4 (restent VARCHAR(1000)/VARCHAR(8000)), ni aux
--  paramètres de la procédure, ni aux clauses WHERE, et EN GARDANT le même
--  résultat et la même performance qu'après optimisation du dossier
--  Sql-procedure-table.
--
--  PRINCIPE (= "option 2", adaptée) : on ajoute 4 colonnes calculées PERSISTED
--  qui sont les préfixes des colonnes DTA (assez longs pour contenir la valeur
--  entière : données réelles <= 42 car., préfixes 80..500). Les index passent
--  leur clé sur ces colonnes courtes -> clé < 1700 octets, plus d'avertissement.
--
--    DTA_1_k VARCHAR(150) = SUBSTRING(DTA_1,1,150)
--    DTA_2_k VARCHAR(80)  = SUBSTRING(DTA_2,1,80)
--    DTA_3_k VARCHAR(500) = SUBSTRING(DTA_3,1,500)
--    DTA_4_k VARCHAR(150) = SUBSTRING(DTA_4,1,150)
--
--  Pourquoi un PRÉFIXE et pas un HASH (HASHBYTES) : un hash n'est pas
--  ordonné. La procédure se termine par ORDER BY DTA_1..DTA_4 ; avec un index
--  ordonné sur un hash il faudrait un tri Top-N de toute la table à chaque
--  appel du Cas 1 (10 ms -> ~2-3 s). Un préfixe conserve l'ordre lexical, donc
--  l'index couvre à la fois PARTITION BY, ORDER BY interne ET ORDER BY final.
--
--  Équivalence des résultats : tant qu'aucune valeur DTA ne dépasse la
--  longueur de son préfixe, SUBSTRING(DTA_x,1,N) = DTA_x, donc
--  GROUP BY / PARTITION BY / ORDER BY sur les colonnes _k == sur les colonnes
--  d'origine (NULL inclus : SUBSTRING(NULL,..) = NULL).
-- =============================================================================

-- 0. Base dédiée
IF DB_ID(N'RestitutionGrapheProdHash') IS NULL
    CREATE DATABASE RestitutionGrapheProdHash;
GO
USE RestitutionGrapheProdHash;
GO

-- Jeu de SET requis pour qu'un index sur colonne calculée PERSISTED soit
-- créé ET RÉUTILISÉ par l'optimiseur (sinon il recalcule la colonne et perd
-- l'ordre de l'index -> opérateur Sort). Ces 7 options doivent être identiques
-- à la création de la colonne, aux INSERT/UPDATE, et à l'exécution des requêtes.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
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
        -- Clés dérivées (préfixes) : servent UNIQUEMENT de colonnes de clé
        -- d'index à la place des DTA_x larges. PERSISTED -> stockées, indexables.
        DTA_1_k AS CONVERT(VARCHAR(150), SUBSTRING(DTA_1, 1, 150)) PERSISTED,
        DTA_2_k AS CONVERT(VARCHAR(80),  SUBSTRING(DTA_2, 1, 80))  PERSISTED,
        DTA_3_k AS CONVERT(VARCHAR(500), SUBSTRING(DTA_3, 1, 500)) PERSISTED,
        DTA_4_k AS CONVERT(VARCHAR(150), SUBSTRING(DTA_4, 1, 150)) PERSISTED,
        CONSTRAINT PK_LINE_VIS_EDG PRIMARY KEY (LNA_UID, LIN_UID, EDG_DIR)
    )
END
GO

-- Index composite sur les préfixes DTA + EDG_DIR (pour GetNodesSuccessorsPredecessors)
-- Clé : 150+80+500+150+1 = 881 octets  (< 1700 -> aucun avertissement)
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_DTA_EDG_DIR' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG')
)
BEGIN
    CREATE INDEX IX_LINE_VIS_EDG_DTA_EDG_DIR
    ON dbo.LINE_VIS_EDG(DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k, EDG_DIR)
    INCLUDE (DTA_1, DTA_2, DTA_3, DTA_4,
             LNA_UID, LIN_UID, EDG_1, EDG_2, EDG_3, EDG_4, TXN_DTA, PRX_TXN_DTA)
END

-- Index sur LNA_UID pour JOIN avec LINE_VIS_HEA (inchangé)
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

-- Index pour NodeList (recherche sur DTA_1) — inchangé (clé DTA_1 = 1000 o, pas d'avertissement)
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

-- Index de couverture principal, utilisé par LINE_VIS_NodesListV2.
-- Clé : DTA_1_k..DTA_4_k (préfixes) + LIN_UID + LNA_UID + EDG_DIR
--       150+80+500+150+500+200+1 = 1581 octets  (< 1700 -> aucun avertissement)
-- Ordre (préfixes, LIN_UID, LNA_UID, EDG_DIR) -> couvre PARTITION BY,
-- ORDER BY interne du ROW_NUMBER et ORDER BY final : aucun opérateur Sort.
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_2_Covering' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG')
)
BEGIN
    CREATE INDEX [IX_LINE_VIS_EDG_2_Covering]
    ON [dbo].[LINE_VIS_EDG] (DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k, LIN_UID, LNA_UID, EDG_DIR)
    INCLUDE (DTA_1, DTA_2, DTA_3, DTA_4)
    WITH (
        ONLINE = OFF,
        SORT_IN_TEMPDB = ON,
        FILLFACTOR = 90
    );
END
GO
