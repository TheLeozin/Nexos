#Requires -Version 5.1
<#
.SYNOPSIS
    Nexos Torre - Bootstrap (launcher do instalador visual)

    Uso em uma linha, sem admin:
        irm https://raw.githubusercontent.com/TheLeozin/Nexos/main/updater/bootstrap.ps1 | iex

    Baixa nexos-installer.ps1 e abre o instalador visual (WinForms) em modo STA.
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RAW          = 'https://raw.githubusercontent.com/TheLeozin/Nexos/main'
$INSTALLER_URL = "$RAW/updater/nexos-installer.ps1"
$TMP_SCRIPT   = "$env:TEMP\nexos-installer-$PID.ps1"

Write-Host ''
Write-Host '  Nexos Torre  |  Iniciando instalador...' -ForegroundColor Cyan
Write-Host ''

# Baixar o instalador visual
try {
    Write-Host '  Baixando instalador...' -ForegroundColor DarkGray
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'NexosBootstrap/3.0')
    $wc.Headers.Add('Cache-Control', 'no-cache')
    $wc.DownloadFile($INSTALLER_URL, $TMP_SCRIPT)
    $wc.Dispose()
    Write-Host '  OK - nexos-installer.ps1 baixado' -ForegroundColor Green
} catch {
    $wc.Dispose()
    Write-Host "  ERRO ao baixar instalador: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  Verifique a conexao com a internet e tente novamente.' -ForegroundColor Yellow
    exit 1
}

# Montar argumentos passando InstallPath e Force
$forceArg = if ($Force) { '-Force' } else { '' }
$psArgs   = "-sta -noprofile -executionpolicy bypass -file `"$TMP_SCRIPT`" -InstallPath `"$InstallPath`" $forceArg".Trim()

Write-Host '  Abrindo instalador visual...' -ForegroundColor DarkGray

# Abrir janela do instalador em STA (WinForms requer STA)
# -WindowStyle Hidden oculta o console do PS; o WinForms aparece normalmente
$proc = Start-Process powershell.exe -ArgumentList $psArgs -WindowStyle Hidden -Wait -PassThru

# Limpar arquivo temporario
try { Remove-Item $TMP_SCRIPT -Force -ErrorAction SilentlyContinue } catch {}

exit ($proc.ExitCode)