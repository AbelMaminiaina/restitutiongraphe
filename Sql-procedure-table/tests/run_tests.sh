#!/usr/bin/env bash
# =============================================================================
#  Lance les tests unitaires des procedures LINE_VIS_* dans une base jetable.
#
#  1. (re)cree la base de test
#  2. y deploie les scripts "schema" + "procedures" (ils ciblent
#     RestitutionGrapheProd ; on redirige le nom vers la base de test par
#     simple substitution de chaine)
#  3. execute chaque fichier tests/test_*.sql
#  4. supprime la base de test (sauf si KEEP=1)
#
#  Usage :
#     ./run_tests.sh                 # instance par defaut localhost\SQLEXPRESS01
#     SERVER='localhost\SQLEXPRESS01' ./run_tests.sh
#     KEEP=1 ./run_tests.sh          # garde la base de test pour inspection
#
#  Code retour : 0 si tous les tests passent, != 0 sinon.
# =============================================================================
set -euo pipefail

SERVER="${SERVER:-localhost\\SQLEXPRESS01}"
PROD_DB="RestitutionGrapheProd"
TEST_DB="${TEST_DB:-RestitutionGrapheProd_Test}"

SQLCMD="/c/Program Files/Microsoft SQL Server/Client SDK/ODBC/170/Tools/Binn/sqlcmd"
[ -x "$SQLCMD" ] || SQLCMD="sqlcmd"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

win() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || echo "$1"; }
run_file() { "$SQLCMD" -S "$SERVER" -E -C -b -I -i "$(win "$1")"; }

# Scripts a deployer AVANT les tests, dans l'ordre (schema puis procedures).
DEPLOY=(
    "LINE_VIS_EDG.sql"
    "LINE_VIS_EDG_Stats.sql"
    "LINE_VIS_HEA.sql"
    "LINE_VIS_NodesListV2.sql"
    "LINE_VIS_GetNodesSuccessorsPredecessorsV2.sql"
)

echo "== Serveur      : $SERVER"
echo "== Base de test : $TEST_DB"

echo "== (1) (re)creation de la base de test"
"$SQLCMD" -S "$SERVER" -E -C -b -Q "
IF DB_ID('$TEST_DB') IS NOT NULL
BEGIN
    ALTER DATABASE [$TEST_DB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$TEST_DB];
END
CREATE DATABASE [$TEST_DB];"

echo "== (2) deploiement schema + procedures"
for f in "${DEPLOY[@]}"; do
    echo "   - $f"
    sed "s/${PROD_DB}/${TEST_DB}/g" "$SRC/$f" > "$TMP/$(basename "$f")"
    run_file "$TMP/$(basename "$f")"
done

echo "== (3) execution des tests"
rc=0
for t in "$HERE"/test_*.sql; do
    echo "   --- $(basename "$t") ---"
    set +e
    "$SQLCMD" -S "$SERVER" -E -C -b -I -i "$(win "$t")"
    trc=$?
    set -e
    [ "$trc" -ne 0 ] && rc="$trc"
done

if [ "${KEEP:-0}" != "1" ]; then
    echo "== (4) suppression de la base de test"
    "$SQLCMD" -S "$SERVER" -E -C -Q "
IF DB_ID('$TEST_DB') IS NOT NULL
BEGIN
    ALTER DATABASE [$TEST_DB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$TEST_DB];
END" >/dev/null
else
    echo "== (4) base de test conservee (KEEP=1) : $TEST_DB"
fi

echo
if [ "$rc" -eq 0 ]; then echo "OK  - tous les tests passent"; else echo "ECHEC - code $rc"; fi
exit "$rc"
