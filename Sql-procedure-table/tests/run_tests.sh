#!/usr/bin/env bash
# =============================================================================
#  Lance le test unitaire de dbo.LINE_VIS_NodesListV2 dans une base jetable.
#
#  1. (re)cree la base de test
#  2. y deploie LINE_VIS_EDG.sql (table + index) et LINE_VIS_NodesListV2.sql
#     (les scripts "prod" ciblent RestitutionGrapheProd ; on redirige le nom
#      vers la base de test par simple substitution de chaine)
#  3. execute tests/test_LINE_VIS_NodesListV2.sql
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

echo "== (2) deploiement du schema + du cache d'agregats + de la procedure"
sed "s/${PROD_DB}/${TEST_DB}/g" "$SRC/LINE_VIS_EDG.sql"          > "$TMP/schema.sql"
sed "s/${PROD_DB}/${TEST_DB}/g" "$SRC/LINE_VIS_EDG_Stats.sql"    > "$TMP/stats.sql"
sed "s/${PROD_DB}/${TEST_DB}/g" "$SRC/LINE_VIS_NodesListV2.sql"  > "$TMP/proc.sql"
run_file "$TMP/schema.sql"
run_file "$TMP/stats.sql"
run_file "$TMP/proc.sql"

echo "== (3) execution des tests"
set +e
"$SQLCMD" -S "$SERVER" -E -C -b -I -i "$(win "$HERE/test_LINE_VIS_NodesListV2.sql")"
rc=$?
set -e

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
