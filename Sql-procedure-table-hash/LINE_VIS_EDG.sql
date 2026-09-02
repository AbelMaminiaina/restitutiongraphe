-- =============================================================================
--  LINE_VIS_EDG — variante "clé dérivée" (dossier Sql-procedure-table-hash)
--  Cible : SQL Server — base dédiée RestitutionGrapheProdHash
--
--  BUT : supprimer l'avertissement "index key > 1700 bytes" SANS toucher aux
--  colonnes DTA_1..DTA_4 (restent VARCHAR(1000)/VARCHAR(8000)), ni aux
--  paramètres de la procédure, ni aux clauses WHERE, et EN GARDANT le même
--  résultat ET la même performance qu'après optimisation du dossier
--  Sql-procedure-table.
--
--  PRINCIPE : 4 colonnes = préfixes des colonnes DTA (assez longs pour contenir
--  la valeur entière : données réelles <= 42 car., préfixes 80..500). Les index
--  passent leur clé sur ces colonnes courtes -> clé < 1700 octets.
--
--    DTA_1_k VARCHAR(150) = SUBSTRING(DTA_1,1,150)
--    DTA_2_k VARCHAR(80)  = SUBSTRING(DTA_2,1,80)
--    DTA_3_k VARCHAR(500) = SUBSTRING(DTA_3,1,500)
--    DTA_4_k VARCHAR(150) = SUBSTRING(DTA_4,1,150)
--
--  /!\ Colonnes RÉELLES (non calculées), maintenues par le trigger
--  dbo.TR_LINE_VIS_EDG_DerivedKeys (AFTER INSERT, UPDATE).
--
--  Pourquoi PAS des colonnes calculées PERSISTED : SQL Server insère alors un
--  opérateur "Compute Scalar" à chaque lecture de DTA_x_k depuis un index. Ce
--  Compute Scalar fait perdre à l'optimiseur l'information "le scan est déjà
--  trié par DTA_x_k" -> il ré-insère un Sort de ~1,8 M lignes avant l'ORDER BY
--  ... FETCH final du Cas 1 (10 ms -> ~8 s, avec débordement tempdb sur SQL
--  Server Express). Avec des colonnes réelles il n'y a pas de Compute Scalar :
--  l'index couvrant, physiquement ordonné sur (DTA_1_k..DTA_4_k, LIN_UID,
--  LNA_UID, EDG_DIR), alimente directement le Top-N -> aucun Sort, mêmes perfs
--  que le dossier Sql-procedure-table (Cas 1 ~10 ms mesuré).
--
--  Pourquoi un PRÉFIXE et pas un HASH (HASHBYTES) : un hash n'est pas ordonné
--  -> il casserait l'ORDER BY DTA_1..DTA_4 final (tri de 1,8 M lignes à chaque
--  appel du Cas 1, quelle que soit la forme de la requête). Un préfixe conserve
--  l'ordre lexical, donc l'index couvre PARTITION BY, ORDER BY interne ET
--  ORDER BY final.
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

-- Jeu de SET requis pour que le trigger et les requêtes sur les index de
-- LINE_VIS_EDG s'exécutent de façon cohérente. Figées ici.
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
        -- d'index à la place des DTA_x larges. Colonnes RÉELLES (pas calculées)
        -- -> pas de Compute Scalar -> l'ordre de l'index couvrant est préservé
        -- jusqu'au Top-N final. Maintenues par dbo.TR_LINE_VIS_EDG_DerivedKeys.
        DTA_1_k       VARCHAR(150),
        DTA_2_k       VARCHAR(80),
        DTA_3_k       VARCHAR(500),
        DTA_4_k       VARCHAR(150),
        CONSTRAINT PK_LINE_VIS_EDG PRIMARY KEY (LNA_UID, LIN_UID, EDG_DIR)
    )
END
GO

-- 1b. Migration des variantes précédentes de ce script vers les colonnes _k
--     RÉELLES. On enlève d'abord les 2 index qui portaient sur les colonnes
--     calculées ; ils sont recréés plus bas par les blocs "IF NOT EXISTS".
--       - variante "préfixes calculés" : DTA_1_k..DTA_4_k en colonnes calculées
--       - variante "hash"              : colonne calculée DTA_HASH
IF EXISTS (
        SELECT 1 FROM sys.computed_columns
        WHERE object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG')
          AND name IN ('DTA_1_k', 'DTA_HASH')
)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LINE_VIS_EDG_DTA_EDG_DIR' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG'))
        DROP INDEX IX_LINE_VIS_EDG_DTA_EDG_DIR ON dbo.LINE_VIS_EDG;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_LINE_VIS_EDG_2_Covering' AND object_id = OBJECT_ID('dbo.LINE_VIS_EDG'))
        DROP INDEX IX_LINE_VIS_EDG_2_Covering ON dbo.LINE_VIS_EDG;

    IF COL_LENGTH(N'dbo.LINE_VIS_EDG', 'DTA_HASH') IS NOT NULL
        ALTER TABLE dbo.LINE_VIS_EDG DROP COLUMN DTA_HASH;
    IF EXISTS (SELECT 1 FROM sys.computed_columns WHERE object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG') AND name = 'DTA_1_k')
        ALTER TABLE dbo.LINE_VIS_EDG DROP COLUMN DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k;

    IF COL_LENGTH(N'dbo.LINE_VIS_EDG', 'DTA_1_k') IS NULL
        ALTER TABLE dbo.LINE_VIS_EDG ADD
            DTA_1_k VARCHAR(150) NULL,
            DTA_2_k VARCHAR(80)  NULL,
            DTA_3_k VARCHAR(500) NULL,
            DTA_4_k VARCHAR(150) NULL;
END
GO

-- 1c. Trigger de maintenance des clés dérivées.
--     AFTER INSERT, UPDATE : recalcule DTA_x_k = préfixe(DTA_x) pour les lignes
--     touchées. Le "EXCEPT" rend l'écriture idempotente (comparaison null-safe)
--     -> un éventuel 2e passage (bases avec RECURSIVE_TRIGGERS ON) ne touche
--     aucune ligne et la récursion s'arrête ; aucune écriture non plus quand
--     l'UPDATE ne modifiait pas les DTA_x.
CREATE OR ALTER TRIGGER dbo.TR_LINE_VIS_EDG_DerivedKeys
ON dbo.LINE_VIS_EDG
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE e
    SET DTA_1_k = v.k1,
        DTA_2_k = v.k2,
        DTA_3_k = v.k3,
        DTA_4_k = v.k4
    FROM dbo.LINE_VIS_EDG AS e
    INNER JOIN inserted AS i
        ON  e.LNA_UID = i.LNA_UID
        AND e.LIN_UID = i.LIN_UID
        AND e.EDG_DIR = i.EDG_DIR
    CROSS APPLY (VALUES (
        CONVERT(VARCHAR(150), SUBSTRING(i.DTA_1, 1, 150)),
        CONVERT(VARCHAR(80),  SUBSTRING(i.DTA_2, 1, 80)),
        CONVERT(VARCHAR(500), SUBSTRING(i.DTA_3, 1, 500)),
        CONVERT(VARCHAR(150), SUBSTRING(i.DTA_4, 1, 150))
    )) AS v(k1, k2, k3, k4)
    WHERE EXISTS (
        SELECT e.DTA_1_k, e.DTA_2_k, e.DTA_3_k, e.DTA_4_k
        EXCEPT
        SELECT v.k1,      v.k2,      v.k3,      v.k4
    );
END
GO

-- 1d. Alimentation initiale des clés dérivées pour les lignes déjà présentes
--     (migration, ou table chargée avant la pose du trigger).
UPDATE dbo.LINE_VIS_EDG
SET DTA_1_k = CONVERT(VARCHAR(150), SUBSTRING(DTA_1, 1, 150)),
    DTA_2_k = CONVERT(VARCHAR(80),  SUBSTRING(DTA_2, 1, 80)),
    DTA_3_k = CONVERT(VARCHAR(500), SUBSTRING(DTA_3, 1, 500)),
    DTA_4_k = CONVERT(VARCHAR(150), SUBSTRING(DTA_4, 1, 150))
WHERE EXISTS (
    SELECT DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k
    EXCEPT
    SELECT CONVERT(VARCHAR(150), SUBSTRING(DTA_1, 1, 150)),
           CONVERT(VARCHAR(80),  SUBSTRING(DTA_2, 1, 80)),
           CONVERT(VARCHAR(500), SUBSTRING(DTA_3, 1, 500)),
           CONVERT(VARCHAR(150), SUBSTRING(DTA_4, 1, 150))
);
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
