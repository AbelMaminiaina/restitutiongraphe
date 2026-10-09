@echo off
REM =============================================================================
REM  Import bcp d'un fichier .data dans dbo.LINE_VIS_EDG via LINE_VIS_EDG_2_STG
REM
REM  Usage :  LINE_VIS_EDG_bcp.cmd fichier.data [serveur] [base]
REM    serveur : par defaut .\SQLEXPRESS01
REM    base    : par defaut RestitutionGrapheProd
REM  Exemple :  LINE_VIS_EDG_bcp.cmd LINE_VIS_EDG_2_STG.data
REM
REM  Prerequis : LINE_VIS_EDG.sql puis LINE_VIS_EDG_2_STG.sql executes.
REM
REM  bcp vise la table d'arrivee LINE_VIS_EDG_2_STG (13 colonnes, comme le
REM  fichier) ; son trigger INSTEAD OF INSERT envoie les lignes dans
REM  LINE_VIS_EDG, ou DTA_HASH (14e colonne) est calculee par SQL Server.
REM
REM  Options bcp :
REM    -c              fichier texte
REM    -C 65001        encodage UTF-8
REM    -t0x7F7F7F      separateur de champs : DEL DEL DEL
REM    -r0x07080D0A    fin de ligne : BEL BS CR LF
REM    -k              champ vide = NULL (pas de valeur par defaut)
REM    -h FIRE_TRIGGERS  declenche le trigger de transfert (sans cette option,
REM                      bcp ne declenche aucun trigger et rien n'arrive dans
REM                      LINE_VIS_EDG)
REM    -q              QUOTED_IDENTIFIER ON (exige par l'index sur DTA_HASH)
REM    -T              authentification Windows
REM    -S / -d         serveur / base
REM =============================================================================

if "%~1"=="" (
    echo Usage : %~nx0 fichier.data [serveur] [base]
    exit /b 1
)

set "SERVEUR=%~2"
if "%SERVEUR%"=="" set "SERVEUR=.\SQLEXPRESS01"
set "BASE=%~3"
if "%BASE%"=="" set "BASE=RestitutionGrapheProd"

bcp dbo.LINE_VIS_EDG_2_STG in "%~1" -c -C 65001 -t0x7F7F7F -r0x07080D0A -k -h "FIRE_TRIGGERS" -q -T -S "%SERVEUR%" -d "%BASE%"
