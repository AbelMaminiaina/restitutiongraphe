-- =============================================================================
--  Generation de donnees de test pour dbo.LINE_VIS_HEA
--  Base : RestitutionGrapheProd
--
--  Copie de Sql-procedure-table/LINE_VIS_HEA_data.sql. A lancer APRES
--  l'import bcp (LINE_VIS_EDG_bcp.cmd) : vide LINE_VIS_HEA puis cree une
--  ligne par LNA_UID distinct de LINE_VIS_EDG (valeurs derivees de LNA_UID,
--  donc deterministes).
-- =============================================================================

USE RestitutionGrapheProd;
GO

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
