-- Ajoute deux petites composantes ISOLEES a dbo.LINE_VIS_EDG, sans aucune
-- arete vers le gros graphe N* deja en place. De quoi tester le SCAN de
-- dotnet-new-scan/ : apres un re-scan, la table dbo.NODE_COMPONENT contient
-- 3 composantes, et la recherche N1 -> X1 repond "aucun chemin" sans BFS.
--
--   composante N* : ~100 000 noeuds (seed_sqlserver.py)
--   composante X  : cycle X1->X2->X3->X1, puis X3->X4->X5
--   composante Y  : chemin simple Y1->Y2->Y3
--
-- Idempotent : supprime d'abord les lignes X*/Y* puis les reinsere.
-- Convention identique au reste du projet : Direction = 'predecesseur'
-- signifie  Nodes -> NodesLie.
--
-- Lancer :
--   sqlcmd -S "localhost\SQLEXPRESS01" -d RestitutionGraphe -E -i scripts/seed_disconnected_test.sql
-- puis, dans l'appli : /Scan  ->  "Relancer le scan".

SET NOCOUNT ON;

DELETE FROM dbo.LINE_VIS_EDG
WHERE Nodes LIKE 'X%' OR NodesLie LIKE 'X%'
   OR Nodes LIKE 'Y%' OR NodesLie LIKE 'Y%';

INSERT INTO dbo.LINE_VIS_EDG (Nodes, Direction, NodesLie, Transformation) VALUES
    ('X1', 'predecesseur', 'X2', 'SELECT'),
    ('X2', 'predecesseur', 'X3', 'JOIN'),
    ('X3', 'predecesseur', 'X1', 'FILTER'),      -- referme le cycle X1->X2->X3->X1
    ('X3', 'predecesseur', 'X4', 'AGGREGATE'),
    ('X4', 'predecesseur', 'X5', 'CAST'),
    ('Y1', 'predecesseur', 'Y2', 'MERGE'),
    ('Y2', 'predecesseur', 'Y3', 'PIVOT');

SELECT 'lignes X*/Y* dans LINE_VIS_EDG' AS info,
       COUNT(*) AS n
FROM dbo.LINE_VIS_EDG
WHERE Nodes LIKE 'X%' OR Nodes LIKE 'Y%';
