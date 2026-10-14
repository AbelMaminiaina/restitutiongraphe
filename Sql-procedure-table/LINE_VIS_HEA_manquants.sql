-- =============================================================================
--  Ajout des en-tetes manquants dans dbo.LINE_VIS_HEA
--  Base : RestitutionGrapheProd
--
--  Pourquoi : LINE_VIS_HEA_data.sql cree une ligne par LNA_UID present dans
--  LINE_VIS_EDG AU MOMENT ou on le lance. Si LINE_VIS_EDG est rechargee
--  ensuite (ex. import bcp de Sql-bcp-staging/LINE_VIS_EDG_8M.data, genere
--  avec 240 000 LNA_UID au lieu de 210 000), les nouveaux LNA_UID n'ont pas
--  d'en-tete et leurs lignes sont IGNOREES par toutes les procedures de
--  lineage (controle SANS_ENTETE de LINE_VIS_ControleQualite).
--
--  Ce script ajoute SEULEMENT les en-tetes manquants :
--    - les en-tetes existants ne sont pas modifies (contrairement a
--      LINE_VIS_HEA_data.sql, qui vide la table et recalcule toutes les
--      dates LNA_TSP / DLY_PGM_TSP) ;
--    - memes formules que LINE_VIS_HEA_data.sql (valeurs derivees de
--      LNA_UID) ;
--    - rejouable : relance sans rien a ajouter -> 0 ligne inseree.
--
--  Duree : une lecture de LINE_VIS_EDG (~10-30 s sur 7,2 M lignes).
--  Journal : une ligne par en-tete ajoute (30 000 lignes -> quelques Mo).
-- =============================================================================

USE RestitutionGrapheProd;
GO

SET NOCOUNT ON;

DECLARE @avant INT = (SELECT COUNT(*) FROM dbo.LINE_VIS_HEA);

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
FROM (SELECT DISTINCT LNA_UID FROM dbo.LINE_VIS_EDG WITH (NOLOCK)) AS d
WHERE NOT EXISTS (SELECT 1 FROM dbo.LINE_VIS_HEA h WHERE h.LNA_UID = d.LNA_UID);

DECLARE @ajoutes INT = @@ROWCOUNT;

PRINT 'LINE_VIS_HEA : ' + CAST(@avant AS VARCHAR) + ' en-tete(s) avant, '
    + CAST(@ajoutes AS VARCHAR) + ' ajoute(s), '
    + CAST(@avant + @ajoutes AS VARCHAR) + ' maintenant.';
GO
