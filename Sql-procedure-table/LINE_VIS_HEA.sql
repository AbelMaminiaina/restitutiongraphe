-- =============================================================================
--  LINE_VIS_HEA : table d'en-tete (1 ligne par LNA_UID)
--  Cible : SQL Server - base dediee RestitutionGrapheProd
--
--  Code transcrit de la photo M1/2.jpeg (fichier LINE_VIS_HEA.sql).
--  Seul ajout : l'en-tete USE ci-dessous.
--  Le remplissage de test est dans LINE_VIS_HEA_data.sql.
-- =============================================================================

USE RestitutionGrapheProd;
GO

IF OBJECT_ID(N'[dbo].[LINE_VIS_HEA]') IS NULL
BEGIN
    CREATE TABLE dbo.LINE_VIS_HEA (
        LNA_UID     VARCHAR(200)    NOT NULL,
        RON_APP     VARCHAR(4),
        PCK_PGM_NME VARCHAR(500),
        EXE_PGM_NME VARCHAR(500),
        VRS_EXE_PGM VARCHAR(100),
        APP_ENV     VARCHAR(20),
        DLY_PGM_TSP DATETIME2,
        LNA_TSP     DATETIME2,
        PGM_TEC     VARCHAR(20),
        VRS_LNA_TOO VARCHAR(100),
        TUS_IND     INTEGER,
        CONSTRAINT PK_LINE_VIS_HEA PRIMARY KEY (LNA_UID)
    )
END
GO
