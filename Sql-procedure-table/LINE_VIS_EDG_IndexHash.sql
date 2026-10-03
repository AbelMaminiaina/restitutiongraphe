-- =============================================================================
--  Index de recherche par noeud sur dbo.LINE_VIS_EDG
--  Base : RestitutionGrapheProd
--  A deployer APRES LINE_VIS_EDG.sql. Script rejouable (idempotent).
--
--  Utilise par : dbo.LINE_VIS_GetNodesSuccessorsPredecessors (chemin rapide).
--
--  Probleme : la procedure cherche les aretes par (EDG_DIR, DTA_1..DTA_4).
--  Sans index, chaque appel lit toute la table (~20 s sur 7 M lignes).
--  Un index classique sur DTA_1..DTA_4 est impossible : DTA_3 est en
--  VARCHAR(8000) et une cle d'index est limitee a 1 700 octets.
--
--  Solution : une empreinte de 4 octets des 4 colonnes, et un index etroit
--  (EDG_DIR, DTA_HASH).
--
--    - DTA_HASH = CHECKSUM(DTA_1, DTA_2, DTA_3, DTA_4) :
--        * colonne calculee NON persistee : rien n'est ajoute dans la table
--          (ni dans le journal pour la table) ; la valeur n'est stockee que
--          dans l'index ;
--        * CHECKSUM suit la collation des colonnes, donc les MEMES regles que
--          "=" : 'abc' = 'ABC' = 'abc  ' (casse et espaces de fin ignores),
--          'abc' <> 'ábc' (accents distingues). HASHBYTES, lui, travaille
--          sur les octets bruts et raterait des lignes ('abc' <> 'ABC').
--        * deux valeurs differentes PEUVENT avoir la meme empreinte
--          (collision : il y en a des milliers sur 7 M lignes). La procedure
--          garde donc l'egalite exacte DTA_n = @DTAn en plus du hash :
--          une collision coute quelques lignes lues, jamais un faux resultat.
--
--    - Taille : ~60 octets par ligne (EDG_DIR + hash + cle primaire),
--      soit quelques centaines de Mo pour 8 M lignes. Compression PAGE si
--      le serveur la permet (toutes editions depuis SQL Server 2016 SP1).
--
--  ATTENTION (index sur colonne calculee) : toute session qui fait un INSERT,
--  UPDATE ou DELETE sur LINE_VIS_EDG doit avoir QUOTED_IDENTIFIER et
--  ANSI_NULLS a ON, sinon l'ordre echoue ("SET options have incorrect
--  settings"). C'est le cas par defaut avec ODBC / OLE DB / .NET / SSIS / SSMS,
--  mais PAS avec sqlcmd : lancer sqlcmd avec l'option -I.
--
--  Chargement massif (plusieurs millions de lignes en une transaction) :
--  desactiver l'index avant, le reconstruire apres (moins de journal) :
--      ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG DISABLE;
--      ... chargement ...
--      ALTER INDEX IX_LINE_VIS_EDG_DIR_HASH ON dbo.LINE_VIS_EDG REBUILD;
--  (le REBUILD reprend automatiquement la compression choisie ici)
-- =============================================================================

-- Options obligatoires pour creer un index sur une colonne calculee
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

USE RestitutionGrapheProd;
GO

-- 1. Colonne calculee (non persistee)
IF COL_LENGTH(N'dbo.LINE_VIS_EDG', 'DTA_HASH') IS NULL
    ALTER TABLE dbo.LINE_VIS_EDG
        ADD DTA_HASH AS CHECKSUM(DTA_1, DTA_2, DTA_3, DTA_4);
GO

-- 2. Index (EDG_DIR, DTA_HASH)
--    La cle primaire (LNA_UID, LIN_UID, EDG_DIR) est ajoutee automatiquement
--    a chaque ligne d'index : a hash egal, les lignes sont deja rangees par
--    LNA_UID, LIN_UID -> le TOP de la procedure n'a rien a trier.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_LINE_VIS_EDG_DIR_HASH'
      AND object_id = OBJECT_ID(N'dbo.LINE_VIS_EDG')
)
BEGIN
    -- Compression PAGE possible ?
    --   EngineEdition 3 = Enterprise / Developer : toujours ;
    --   autres editions (Express, Standard...) : depuis 2016 SP1
    --   (version 13.0.4001) ou version majeure >= 14 (2017+).
    DECLARE @version VARCHAR(30)  = CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(30));
    DECLARE @majeure INT          = CAST(PARSENAME(@version, 4) AS INT);
    DECLARE @build   INT          = CAST(PARSENAME(@version, 2) AS INT);
    DECLARE @compression VARCHAR(10) =
        CASE WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) = 3 THEN 'PAGE'
             WHEN @majeure >= 14                                   THEN 'PAGE'
             WHEN @majeure = 13 AND @build >= 4001                 THEN 'PAGE'
             ELSE 'NONE' END;

    PRINT 'Creation de IX_LINE_VIS_EDG_DIR_HASH (compression ' + @compression + ')...';

    -- SQL dynamique : la clause WITH (DATA_COMPRESSION = ...) n'accepte pas
    -- de variable.
    DECLARE @sql NVARCHAR(500) =
        N'CREATE NONCLUSTERED INDEX IX_LINE_VIS_EDG_DIR_HASH
              ON dbo.LINE_VIS_EDG (EDG_DIR, DTA_HASH)
              WITH (DATA_COMPRESSION = ' + @compression + N', SORT_IN_TEMPDB = ON);';
    EXEC sys.sp_executesql @sql;
END
GO
