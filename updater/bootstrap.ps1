#Requires -Version 5.1
<#
.SYNOPSIS
    Nexos - Bootstrap (launcher do instalador visual)

    Uso em uma linha, sem admin:
        irm https://raw.githubusercontent.com/TheLeozin/Nexos/main/updater/bootstrap.ps1 | iex

    Baixa nexos-installer.ps1 e abre o instalador visual (WinForms) em modo STA.
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-PowerShellExecutable {
    $candidates = @(
        (Get-Command powershell.exe -ErrorAction SilentlyContinue),
        (Get-Command pwsh.exe -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ }

    if ($candidates.Count -eq 0) {
        throw 'Nenhum executável do PowerShell foi encontrado (powershell.exe/pwsh.exe).'
    }

    return $candidates[0].Source
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $headers = @{
        'User-Agent'    = 'NexosBootstrap/3.1'
        'Cache-Control' = 'no-cache'
    }

    Invoke-WebRequest -Uri $Url -OutFile $Destination -Headers $headers -TimeoutSec 60
}

# Força TLS moderno em ambientes corporativos/restritos
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$RAW           = 'https://raw.githubusercontent.com/TheLeozin/Nexos/main'
$INSTALLER_URL = "$RAW/updater/nexos-installer.ps1"
$TMP_SCRIPT    = "$env:TEMP\nexos-installer-$PID.ps1"

Write-Host ''
Write-Host '  Nexos  |  Iniciando instalador...' -ForegroundColor Cyan
Write-Host ''

# Baixar o instalador visual
try {
    Write-Host '  Baixando instalador...' -ForegroundColor DarkGray
    Invoke-DownloadFile -Url $INSTALLER_URL -Destination $TMP_SCRIPT
    Write-Host '  OK - nexos-installer.ps1 baixado' -ForegroundColor Green
} catch {
    Write-Host "  ERRO ao baixar instalador: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  Verifique a conexao com a internet e tente novamente.' -ForegroundColor Yellow
    exit 1
}

# Montar argumentos passando InstallPath e Force
$forceArg = if ($Force) { '-Force' } else { '' }
$psArgs   = "-sta -noprofile -executionpolicy bypass -file `"$TMP_SCRIPT`" -InstallPath `"$InstallPath`" $forceArg".Trim()
$psExe    = Get-PowerShellExecutable

Write-Host '  Abrindo instalador visual...' -ForegroundColor DarkGray

# Abrir janela do instalador em STA (WinForms requer STA)
# -WindowStyle Hidden oculta o console do PS; o WinForms aparece normalmente
$proc = Start-Process $psExe -ArgumentList $psArgs -WindowStyle Hidden -Wait -PassThru

# Limpar arquivo temporario
try { Remove-Item $TMP_SCRIPT -Force -ErrorAction SilentlyContinue } catch {}

exit ($proc.ExitCode)