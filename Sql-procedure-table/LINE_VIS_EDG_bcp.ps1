# =============================================================================
#  Import bcp d'un fichier .data dans dbo.LINE_VIS_EDG (via la vue LINE_VIS_EDG_BCP)
#  Base : RestitutionGrapheProd - instance .\SQLEXPRESS01
#
#  Prerequis (une seule fois) : executer LINE_VIS_EDG_BCP_view.sql dans SSMS.
#
#  Fichier .data attendu :
#    - pas d'en-tete, 13 champs (sans DTA_HASH) ;
#    - separateur = 3 caracteres DEL (code 0x7F), affiches "DEL DEL DEL" dans Notepad++ ;
#    - fin de ligne Windows (CRLF).
#
#  Lancement, dans un terminal PowerShell :
#    cd C:\Users\amami\GitHub\restitutiondonnees\Sql-procedure-table
#    .\LINE_VIS_EDG_bcp.ps1 C:\chemin\vers\fichier.data
#  (si PowerShell refuse d'executer le script :
#    powershell -ExecutionPolicy Bypass -File .\LINE_VIS_EDG_bcp.ps1 C:\chemin\vers\fichier.data)
# =============================================================================

param(
    # Chemin du fichier .data a importer (premier argument du script)
    [Parameter(Mandatory = $true)]
    [string]$Fichier
)

# Separateur de champs : le caractere DEL (0x7F) repete 3 fois.
# Il est invisible, on le fabrique donc a partir de son code.
$sep = [string][char]0x7F * 3

# Fichier ou bcp ecrit les lignes rejetees : meme dossier et meme nom que
# le .data, suffixe _erreurs.txt
$erreurs = [IO.Path]::ChangeExtension($Fichier, $null).TrimEnd('.') + '_erreurs.txt'

# Appel de bcp. Chaque option :
#   in        : sens import (fichier -> base)
#   -S        : instance SQL Server
#   -T        : authentification Windows
#   -c        : fichier texte (caracteres)
#   -t        : separateur de champs (DEL DEL DEL)
#   -r "\n"   : fin de ligne ; pour bcp, "\n" signifie CRLF (Windows)
#   -q        : QUOTED_IDENTIFIER ON, obligatoire a cause de l'index sur DTA_HASH
#   -b        : validation par lots de 100 000 lignes
#   -h        : TABLOCK, insertion plus rapide (minimalement journalisee si table vide)
#   -e        : fichier des lignes rejetees
#   -m        : nombre d'erreurs tolerees avant arret
#  Si le fichier est en UTF-8 avec accents, ajouter : '-C', '65001'
& bcp 'RestitutionGrapheProd.dbo.LINE_VIS_EDG_BCP' in $Fichier `
    -S '.\SQLEXPRESS01' -T `
    -c -t $sep -r '\n' `
    -q `
    -b 100000 `
    -h 'TABLOCK' `
    -e $erreurs `
    -m 10

# Code retour de bcp : 0 = succes
if ($LASTEXITCODE -ne 0) {
    Write-Host "bcp a echoue (code $LASTEXITCODE). Voir $erreurs" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host 'Import termine.' -ForegroundColor Green
