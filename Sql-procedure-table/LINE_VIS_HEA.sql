-- =============================================================================
--  LINE_VIS_HEA : table d'en-tete (1 ligne par LNA_UID) + generateur
--  Cible : SQL Server - base dediee RestitutionGrapheProd
--
--  Schema transcrit de la capture IMG_5671. Le generateur (section 2) est
--  ajoute pour ce projet : il cree une ligne par LNA_UID distinct de
--  LINE_VIS_EDG (valeurs derivees de LNA_UID, donc deterministes).
--
--  Colonnes lues par la procedure LINE_VIS_GetNodesSuccessorsPredecessorsV2
--  via la jointure  INNER JOIN dbo.LINE_VIS_HEA h ON e.LNA_UID = h.LNA_UID :
--    RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
--    DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND
--
--  IMPORTANT : la cle primaire est (LNA_UID). C'est une relation 1:1 avec
--  LINE_VIS_EDG.LNA_UID -> la jointure ne multiplie JAMAIS les lignes de EDG.
--  La procedure optimisee s'appuie sur cette garantie (EXISTS pour le COUNT,
--  jointure apres pagination) : si un jour LINE_VIS_HEA devenait 1:N, il
--  faudrait revoir la procedure.
-- =============================================================================

USE RestitutionGrapheProd;
GO

-- 1. Creation de LINE_VIS_HEA si elle n'existe pas
IF OBJECT_ID(N'[dbo].[LINE_VIS_HEA]') IS NULL
BEGIN
    CREATE TABLE dbo.LINE_VIS_HEA (
        LNA_UID       VARCHAR(200)  NOT NULL,
        RON_APP       VARCHAR(4),
        PCK_PGM_NME   VARCHAR(500),
        EXE_PGM_NME   VARCHAR(500),
        VRS_EXE_PGM   VARCHAR(100),
        APP_ENV       VARCHAR(20),
        DLY_PGM_TSP   DATETIME2,
        LNA_TSP       DATETIME2,
        PGM_TEC       VARCHAR(20),
        VRS_LNA_TOO   VARCHAR(100),
        TUS_IND       INTEGER,
        CONSTRAINT PK_LINE_VIS_HEA PRIMARY KEY (LNA_UID)
    )
END
GO

-- 2. (Re)generation : une ligne par LNA_UID distinct present dans LINE_VIS_EDG
--    Les valeurs sont derivees de LNA_UID pour rester deterministes.
TRUNCATE TABLE dbo.LINE_VIS_HEA;

INSERT INTO dbo.LINE_VIS_HEA
    (LNA_UID, RON_APP, PCK_PGM_NME, EXE_PGM_NME, VRS_EXE_PGM, APP_ENV,
     DLY_PGM_TSP, LNA_TSP, PGM_TEC, VRS_LNA_TOO, TUS_IND)
SELECT
    d.LNA_UID,
    LEFT('R' + CAST(ABS(CHECKSUM(d.LNA_UID)) % 1000 AS VARCHAR(3)), 4)      AS RON_APP,
    'PCK_' + d.LNA_UID                                                      AS PCK_PGM_NME,
    'EXE_' + d.LNA_UID                                                      AS EXE_PGM_NME,
    'v' + CAST(ABS(CHECKSUM(d.LNA_UID)) % 20 AS VARCHAR(2)) + '.0'          AS VRS_EXE_PGM,
    CASE ABS(CHECKSUM(d.LNA_UID)) % 3 WHEN 0 THEN 'PROD'
                                     WHEN 1 THEN 'RECETTE'
                                     ELSE 'DEV' END                        AS APP_ENV,
    DATEADD(DAY, -(ABS(CHECKSUM(d.LNA_UID)) % 365), SYSDATETIME())          AS DLY_PGM_TSP,
    DATEADD(HOUR, -(ABS(CHECKSUM(d.LNA_UID)) % 48), SYSDATETIME())          AS LNA_TSP,
    LEFT('TEC_' + d.LNA_UID, 20)                                          AS PGM_TEC,
    'lna' + CAST(ABS(CHECKSUM(d.LNA_UID)) % 10 AS VARCHAR(2))              AS VRS_LNA_TOO,
    ABS(CHECKSUM(d.LNA_UID)) % 5                                           AS TUS_IND
FROM (SELECT DISTINCT LNA_UID FROM dbo.LINE_VIS_EDG) AS d;
GO

DECLARE @n INT = (SELECT COUNT(*) FROM dbo.LINE_VIS_HEA);
PRINT 'LINE_VIS_HEA : ' + CAST(@n AS VARCHAR) + ' ligne(s) (1 par LNA_UID distinct).';
GO
