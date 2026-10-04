// Génère Suivi-Projet/modele-backlog.xlsx : un fichier Excel d'exemple, prêt à remplir puis à importer
// dans le tableau (bouton « Importer Excel »).
//
// Utilisation (depuis le dossier Suivi-Projet) :   node outils/creer-modele-excel.js
//
// Le fichier est fabriqué avec writeXlsx, la même fonction que le bouton « Exporter Excel » :
// le modèle a donc exactement le format d'un export.
const fs = require("fs");
const path = require("path");
const { writeXlsx, tasksToRows } = require("../kanban-excel.js");

// Exemples de tâches (à remplacer par les tiennes dans Excel)
const exemples = [
  { project: "Restitution graphe", title: "Index sur CHECKSUM(DTA_1..4)", description: "Accélérer LINE_VIS_GetNodesSuccessorsPredecessors",
    priority: "haute", label: "SQL", due: "2026-10-15", column: "done" },
  { project: "Restitution graphe", title: "LINE_VIS_NodesList avec critère < 10 s", description: "Limiter aux 1000 premières lignes filtrées",
    priority: "haute", label: "SQL", due: "2026-10-20", column: "doing" },
  { project: "Restitution graphe", title: "Colonne txn_dta dans le graphe JS", description: "",
    priority: "moyenne", label: "front", due: "2026-10-31", column: "todo" },
  { project: "Restitution graphe", title: "Comparer BFS bi / Dijkstra / A*", description: "Refaire le benchmark avec des poids ≠ 1",
    priority: "basse", label: "C#", due: "", column: "backlog" },
  { project: "Suivi projet", title: "Importer le backlog Excel", description: "Remplir ce modèle puis cliquer sur « Importer Excel »",
    priority: "moyenne", label: "organisation", due: "2026-10-10", column: "todo" },
];

const bytes = writeXlsx(tasksToRows(exemples), { sheetName: "Backlog", widths: [22, 40, 50, 11, 16, 12, 12] });
const dest = path.join(__dirname, "..", "modele-backlog.xlsx");
fs.writeFileSync(dest, bytes);
console.log("Créé : " + dest + " (" + exemples.length + " tâches d'exemple)");
