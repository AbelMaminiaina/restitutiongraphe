# Génère backlog-openpyxl.xlsx, un fichier de test écrit par une autre bibliothèque qu'Excel/kanban-excel.js.
# Il vérifie que l'import supporte :
#   - des titres de colonnes différents de ceux de l'export (« Nom du projet », « Tâche », « Status »…)
#   - de vraies cellules date, des nombres, des textes partagés, un texte enrichi (gras + normal)
#   - une ligne vide et une ligne sans titre (à ignorer)
#
# Utilisation (une seule fois, le fichier produit est versionné) :
#   pip install openpyxl
#   python tests/fixtures/creer-fixture-openpyxl.py
import datetime
import os

import openpyxl
from openpyxl.cell.rich_text import CellRichText, TextBlock
from openpyxl.cell.text import InlineFont

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Mon backlog"

# Colonnes dans un ordre différent de l'export, et sans colonne « Étiquette »
ws.append(["Tâche", "Nom du projet", "Status", "Date d'échéance", "Prio", "Commentaire"])
ws.append(["Créer la table LINE_VIS_EDG", "Graphe", "In progress", datetime.date(2026, 11, 3), 1, "ligne 1\nligne 2"])
ws.append(["Écrire les tests", "Graphe", "Done", datetime.datetime(2026, 9, 30, 14, 30), 3, 'avec "guillemets" & <chevrons>'])
ws.append([])                                    # ligne vide : ignorée
ws.append([None, "Graphe", "Done", None, None, "pas de titre : ignorée"])
ws.append([CellRichText([TextBlock(InlineFont(b=True), "Texte "), "enrichi"]), "Kanban", "todo", None, "high", None])

# Une 2e feuille : seule la 1re doit être lue
wb.create_sheet("Aide").append(["Cette feuille ne doit pas être importée"])

dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backlog-openpyxl.xlsx")
wb.save(dest)
print("Créé :", dest)
