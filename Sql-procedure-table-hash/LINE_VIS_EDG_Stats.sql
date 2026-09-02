-- =============================================================================
--  Cache d'agrégats pour dbo.LINE_VIS_EDG
--  Base : RestitutionGrapheProdHash
--
--  Objectif : LINE_VIS_NodesListV2 (Cas 1, aucun critère) a besoin du nombre
--  de combinaisons (DTA_1..DTA_4) distinctes. Le calculer à chaque appel
--  (COUNT(DISTINCT) sur 1,8 M lignes) coûte ~2,4 s. Aucun index n'y change
--  quoi que ce soit (testé : index étroit = idem, columnstore = pire, car
--  DTA_3 est quasi unique -> ~1,8 M valeurs à dédupliquer de toute façon).
--
--  Solution : matérialiser la valeur dans une table à 1 ligne, lue en O(1),
--  et la recalculer explicitement après chaque chargement / purge de la table
--  via dbo.LINE_VIS_EDG_RefreshStats.
--
--  Compromis : la valeur peut être légèrement périmée entre deux refresh
--  (acceptable pour un total affiché dans une UI de recherche).
-- =============================================================================

USE RestitutionGrapheProdHash;
GO

-- Jeu de SET par convention (identique aux autres scripts du dossier).
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG_Stats]') IS NULL
BEGIN
    CREATE TABLE dbo.LINE_VIS_EDG_Stats (
        Id                INT           NOT NULL
            CONSTRAINT PK_LINE_VIS_EDG_Stats     PRIMARY KEY
            CONSTRAINT CK_LINE_VIS_EDG_Stats_Id  CHECK (Id = 1),   -- 1 seule ligne
        DistinctDTACount  INT           NOT NULL,
        RowCountTotal     BIGINT        NOT NULL,
        RefreshedAt       DATETIME2(0)  NOT NULL
            CONSTRAINT DF_LINE_VIS_EDG_Stats_RefreshedAt DEFAULT SYSUTCDATETIME()
    )
END
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_EDG_RefreshStats]') IS NOT NULL
    DROP PROCEDURE [dbo].[LINE_VIS_EDG_RefreshStats]
GO

-- Recalcule le cache. À exécuter après tout INSERT/DELETE massif sur LINE_VIS_EDG
-- (p. ex. à la fin de LINE_VIS_EDG_data.sql, ou via une tâche planifiée Windows
--  puisque SQL Server Express n'a pas l'Agent SQL).
CREATE PROCEDURE dbo.LINE_VIS_EDG_RefreshStats
AS
BEGIN
    SET NOCOUNT ON;
    SET ARITHABORT ON;
    SET ANSI_WARNINGS ON;
    SET CONCAT_NULL_YIELDS_NULL ON;

    DECLARE @distinct INT, @total BIGINT;

    -- Sur les colonnes de clé dérivées (== DTA_1..4 puisque les valeurs
    -- tiennent dans les préfixes) : scan de l'index couvrant, agrégat en flux.
    SELECT @distinct = COUNT(*)
    FROM (SELECT DISTINCT DTA_1_k, DTA_2_k, DTA_3_k, DTA_4_k FROM dbo.LINE_VIS_EDG) AS d;

    SELECT @total = COUNT_BIG(*) FROM dbo.LINE_VIS_EDG;

    MERGE dbo.LINE_VIS_EDG_Stats AS tgt
    USING (SELECT 1 AS Id) AS src ON tgt.Id = src.Id
    WHEN MATCHED THEN UPDATE SET
        DistinctDTACount = @distinct,
        RowCountTotal    = @total,
        RefreshedAt      = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (Id, DistinctDTACount, RowCountTotal, RefreshedAt)
        VALUES (1, @distinct, @total, SYSUTCDATETIME());
END
GO

-- Premier remplissage (idempotent).
EXEC dbo.LINE_VIS_EDG_RefreshStats;
GO
