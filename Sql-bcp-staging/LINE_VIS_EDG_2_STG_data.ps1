# =============================================================================
#  Genere un fichier .data de test pour dbo.LINE_VIS_EDG_2_STG (import bcp)
#
#  Format du fichier (identique aux fichiers .data de prod, cf. commande bcp) :
#    - pas d'en-tete, 13 champs dans l'ordre des colonnes de la table :
#      LNA_UID, LIN_UID, DTA_1..DTA_4, EDG_DIR, EDG_1..EDG_4, TXN_DTA, PRX_TXN_DTA
#      (pas de DTA_HASH : c'est le trigger TR_BCP_Auto_Transfer qui la calcule
#       en recopiant les lignes dans LINE_VIS_EDG_2) ;
#    - separateur de champs  : 0x7F 0x7F 0x7F  (DEL DEL DEL)  -> bcp -t0x7F7F7F
#    - fin de ligne          : 0x07 0x08 0x0D 0x0A (BEL BS CR LF) -> bcp -r0x07080D0A
#    - encodage UTF-8 sans BOM                               -> bcp -C 65001
#    - valeur NULL = champ vide                               -> bcp -k
#
#  Valeurs : memes regles que LINE_VIS_EDG_data.sql (prefixes LNA_UID, LIN_UID
#  unique, EDG_DIR alterne O / I, champs NULL une ligne sur 2, 3, 4 ou 5...).
#  Les parties "aleatoires" viennent d'une graine fixe : deux executions avec
#  les memes parametres donnent exactement le meme fichier.
#
#  Lancement, dans un terminal PowerShell :
#    cd C:\Users\amami\GitHub\restitutiondonnees\Sql-bcp-staging
#    .\LINE_VIS_EDG_2_STG_data.ps1                         # 100 000 lignes
#    .\LINE_VIS_EDG_2_STG_data.ps1 -Lignes 3000000 -Fichier C:\Data\test.data
#  (si PowerShell refuse : powershell -ExecutionPolicy Bypass -File .\LINE_VIS_EDG_2_STG_data.ps1)
#
#  Import ensuite (meme commande que la prod) :
#    bcp dbo.LINE_VIS_EDG_2_STG in C:\Data\test.data -c -C 65001 -t0x7F7F7F
#        -r0x07080D0A -k -h "FIRE_TRIGGERS" -q -T -S <serveur> -d LINE_VIS_NI
# =============================================================================

param(
    # Nombre de lignes a generer
    [int]$Lignes = 100000,

    # Nombre de LNA_UID distincts (environ Lignes / NbLnaUid lignes par LNA_UID)
    [int]$NbLnaUid = 3000,

    # Fichier de sortie (par defaut : LINE_VIS_EDG_2_STG.data a cote du script)
    [string]$Fichier = (Join-Path $PSScriptRoot 'LINE_VIS_EDG_2_STG.data')
)

# Separateurs, fabriques a partir de leur code car ils sont invisibles
$sep = [string][char]0x7F * 3                                   # DEL DEL DEL
$fin = [string]([char]0x07) + [char]0x08 + [char]0x0D + [char]0x0A  # BEL BS CR LF

# Listes de valeurs (meme choix que LINE_VIS_EDG_data.sql)
$prefixesLna = 'ABN_HCL_VALINP', 'ABC_LIS_PCE', 'DEF_TRN_PROC', 'GHI_DAT_LOAD', 'JKL_MIG_TOOL'
$flux        = 'SPSS_LS2DC2', 'CCTS_CTRCAR_ADD_DWH', 'DAT_MIG_PROC', 'TRN_VAL_INP', 'WRK_FLOW'
$cibles      = 'LS2_REFDCP', 'ABC_LIS_PCE', 'DEF_TRN_PROC', 'GHI_DAT_LOAD'
$familles    = 'S_HIRRBT', 'C_INSCTR', 'T_MIG'

# Generateur pseudo-aleatoire a graine fixe -> fichier reproductible
$rnd = New-Object System.Random 42
function Hex8 { $rnd.Next().ToString('X8') }   # 8 caracteres hexa, comme LEFT(NEWID(), 8)

# Ecriture UTF-8 sans BOM (le BOM serait lu comme du texte dans le 1er champ)
$utf8 = New-Object System.Text.UTF8Encoding $false
$w = New-Object System.IO.StreamWriter($Fichier, $false, $utf8, 1MB)
$debut = Get-Date

try {
    for ($c = 1; $c -le $Lignes; $c++) {
        # LNA_UID : prefixe + numero sur 5 chiffres -> $NbLnaUid valeurs distinctes
        $lna = $prefixesLna[$c % 5] + '_' + ([math]::Floor(($c % $NbLnaUid) / 5)).ToString('00000')

        # LIN_UID : contient le compteur -> cle primaire (LNA_UID, LIN_UID, EDG_DIR) unique
        switch ($c % 4) {
            0 { $lin = "SPSW_HCL_ADD_DC2RG2_$c" }
            1 { $lin = "CCTW_CTRCAR_$c" }
            2 { $lin = "CCTX_CTRCAR_PPD_$c" }
            default { $lin = "DAT_MIG_$c" }
        }

        switch ($c % 3) {
            0 { $dta1 = 'FIADODSWRK' }
            1 { $dta1 = 'FIADODSOUT' }
            default { $dta1 = 'FIADODS' + ($c % 10) }
        }
        $dta2 = 'ZJ'
        $dta3 = '_' + (Hex8) + '.' + $flux[$c % 5] + '.' + $cibles[$c % 4]
        $dta4 = 'xDI_IBI' + $familles[$c % 3] + '_' + ($c % 1000) + '_WRK.' + ($c % 100) + '.ZJ'

        # EDG_DIR : O (sortant) ou I (entrant), alterne
        if ($c % 2 -eq 0) { $dir = 'O' } else { $dir = 'I' }

        # Champs EDG_* : vides (donc NULL avec bcp -k) une ligne sur 2, 3 ou 4
        $edg1 = $dta4
        if ($c % 2 -eq 0) { $edg2 = '' } else { $edg2 = 'EDG2_' + ($c % 100) }
        if ($c % 3 -eq 0) { $edg3 = '' } else { $edg3 = 'EDG3_' + (Hex8) }
        if ($c % 4 -eq 0) { $edg4 = '' } else { $edg4 = 'EDG4_' + ($c % 100) }

        # TXN_DTA (JSON) et PRX_TXN_DTA (XML) : vides une ligne sur 5
        if ($c % 5 -eq 0) {
            $txn = ''; $prx = ''
        } else {
            $txn = '{"status": "OK", "id": ' + $c + '}'
            $prx = '<data><value>' + $c + '</value></data>'
        }

        # Une ligne = 13 champs separes par DEL DEL DEL, terminee par BEL BS CR LF
        $w.Write(($lna, $lin, $dta1, $dta2, $dta3, $dta4, $dir,
                  $edg1, $edg2, $edg3, $edg4, $txn, $prx) -join $sep)
        $w.Write($fin)

        # Avancement toutes les 100 000 lignes
        if ($c % 100000 -eq 0) { Write-Host "$c lignes ecrites..." }
    }
}
finally {
    $w.Close()   # toujours fermer le fichier, meme en cas d'erreur
}

$duree = [math]::Round(((Get-Date) - $debut).TotalSeconds, 1)
$taille = [math]::Round((Get-Item $Fichier).Length / 1MB, 1)
Write-Host "$Lignes lignes ecrites dans $Fichier ($taille Mo, $duree s)" -ForegroundColor Green
