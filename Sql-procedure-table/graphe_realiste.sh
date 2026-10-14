#!/usr/bin/env bash
# =============================================================================
#  Cree (ou recree le contenu de) la base RestitutionGrapheRealiste et y
#  genere un graphe de lineage realiste (LINE_VIS_Graphe_Realiste_data.sql).
#
#  1. cree la base si elle n'existe pas (mode de recuperation SIMPLE)
#  2. y deploie tables, index et procedures LINE_VIS_* (les scripts visent
#     RestitutionGrapheProd : le nom est remplace a la volee, comme dans
#     tests/run_tests.sh)
#  3. lance le generateur (vide LINE_VIS_EDG et LINE_VIS_HEA puis les remplit)
#
#  Usage (depuis Sql-procedure-table/) :
#     ./graphe_realiste.sh
#     SERVER='.\SQLEXPRESS01' BASE=MaBase ./graphe_realiste.sh
#  Taille du graphe : section "Parametres" de LINE_VIS_Graphe_Realiste_data.sql.
#
#  Code retour : 0 si tout s'est bien passe.
# =============================================================================
set -euo pipefail

SERVER="${SERVER:-.\\SQLEXPRESS01}"
BASE="${BASE:-RestitutionGrapheRealiste}"
PROD_DB="RestitutionGrapheProd"

SQLCMD="/c/Program Files/Microsoft SQL Server/Client SDK/ODBC/170/Tools/Binn/sqlcmd"
[ -x "$SQLCMD" ] || SQLCMD="sqlcmd"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

win() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || echo "$1"; }
# sqlcmd lance depuis le dossier temporaire avec un nom relatif : certains
# chemins absolus de dossiers temporaires sont mal lus par sqlcmd.
run_file() { (cd "$TMP" && "$SQLCMD" -S "$SERVER" -E -C -b -I -i "$1"); }

# Scripts a deployer, dans l'ordre (memes que tests/run_tests.sh)
DEPLOY=(
    "LINE_VIS_EDG.sql"
    "LINE_VIS_EDG_IndexHash.sql"
    "LINE_VIS_EDG_Stats.sql"
    "LINE_VIS_HEA.sql"
    "LINE_VIS_NodesList.sql"
    "LINE_VIS_NodeById.sql"
    "LINE_VIS_GetNodesSuccessorsPredecessors.sql"
    "LINE_VIS_Lineage_Parcours.sql"
    "LINE_VIS_Lineage.sql"
    "LINE_VIS_Impact.sql"
    "LINE_VIS_Chemin.sql"
    "LINE_VIS_LineageTables.sql"
    "LINE_VIS_ControleQualite.sql"
    "LINE_VIS_Statistiques.sql"
)

echo "== Serveur : $SERVER"
echo "== Base    : $BASE"

echo "== (1) base (creee si absente, mode SIMPLE)"
"$SQLCMD" -S "$SERVER" -E -C -b -Q "
IF DB_ID('$BASE') IS NULL CREATE DATABASE [$BASE];
ALTER DATABASE [$BASE] SET RECOVERY SIMPLE;"

echo "== (2) deploiement tables + procedures"
for f in "${DEPLOY[@]}"; do
    echo "   - $f"
    sed "s/${PROD_DB}\b/${BASE}/g" "$HERE/$f" > "$TMP/$f"
    run_file "$f" > /dev/null
done

echo "== (3) generation du graphe"
sed "s/RestitutionGrapheRealiste\b/${BASE}/g" "$HERE/LINE_VIS_Graphe_Realiste_data.sql" > "$TMP/generateur.sql"
(cd "$TMP" && "$SQLCMD" -S "$SERVER" -E -C -b -I -W -i generateur.sql)

echo
echo "OK - graphe genere dans $BASE"
