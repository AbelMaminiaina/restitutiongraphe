@echo off
REM =============================================================================
REM  Import d'un fichier .data (sans en-tete, 13 colonnes) dans dbo.LINE_VIS_EDG
REM  Base : RestitutionGrapheProd - instance .\SQLEXPRESS01
REM
REM  Prerequis (une seule fois) : executer LINE_VIS_EDG_BCP_view.sql dans SSMS.
REM
REM  Usage :  LINE_VIS_EDG_bcp.cmd C:\chemin\vers\fichier.data
REM
REM  Le fichier n'a pas la 14e colonne DTA_HASH (colonne calculee) : on vise
REM  la vue LINE_VIS_EDG_BCP, qui n'expose que les 13 colonnes reelles ;
REM  les lignes vont dans dbo.LINE_VIS_EDG et DTA_HASH y est calculee.
REM
REM  Options bcp :
REM    -c  fichier texte (caracteres)
REM    -t  separateur de champs : 3 caracteres DEL (code 0x7F), affiches
REM        "DEL DEL DEL" dans Notepad++ -> ecrit en hexadecimal 0x7F7F7F
REM    -r  fin de ligne ; pour bcp, \n signifie CRLF (Windows)
REM    -q  QUOTED_IDENTIFIER ON (obligatoire a cause de l'index sur DTA_HASH)
REM    -T  authentification Windows
REM    -b  validation par lots de 100 000 lignes
REM    -h  TABLOCK : insertion minimalement journalisee si la table est vide
REM    -e  lignes rejetees ecrites dans un fichier d'erreurs (a cote du .data)
REM    -m  nombre d'erreurs tolerees avant arret
REM  Si le fichier est en UTF-8, ajouter : -C 65001
REM =============================================================================

if "%~1"=="" (
    echo Usage : %~nx0 fichier.data
    exit /b 1
)

bcp RestitutionGrapheProd.dbo.LINE_VIS_EDG_BCP in "%~1" ^
    -S .\SQLEXPRESS01 -T ^
    -c -t 0x7F7F7F -r \n ^
    -q ^
    -b 100000 ^
    -h "TABLOCK" ^
    -e "%~dpn1_erreurs.txt" ^
    -m 10
