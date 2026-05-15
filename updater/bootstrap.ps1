<#
.SYNOPSIS
    Instalador inicial da extensão Nexos Torre.
    Executa sem privilégios de administrador.

.DESCRIPTION
    Uso padrão (via PowerShell, sem admin):

        irm https://raw.githubusercontent.com/TheLeozin/Nexos/main/updater/bootstrap.ps1 | iex

    O que este script faz:
      1. Cria a estrutura de pastas em %LOCALAPPDATA%\Nexos\
      2. Baixa nexos-updater.ps1 e install-task.ps1 do GitHub
      3. Executa nexos-updater.ps1 para baixar e instalar a versão atual
      4. Registra a tarefa agendada NexosUpdater (a cada 5 min, sem admin)
      5. Exibe o caminho da extensão para carregar no Chrome

.PARAMETER InstallPath
    Pasta de instalação. Padrão: %LOCALAPPDATA%\Nexos

.PARAMETER Force
    Reinstala mesmo se já estiver instalado.
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$GITHUB_RAW   = 'https://raw.githubusercontent.com/TheLeozin/Nexos/main'
$UPDATER_URL  = "$GITHUB_RAW/updater/nexos-updater.ps1"
$TASK_URL     = "$GITHUB_RAW/updater/install-task.ps1"

$UPDATER_DIR  = Join-Path $InstallPath 'updater'
$EXT_DIR      = Join-Path $InstallPath 'extension'
$UPDATER_FILE = Join-Path $UPDATER_DIR 'nexos-updater.ps1'
$TASK_FILE    = Join-Path $UPDATER_DIR 'install-task.ps1'

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   NEXOS TORRE — INSTALAÇÃO AUTOMÁTICA                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# VERIFICAR SE JÁ ESTÁ INSTALADO
# ─────────────────────────────────────────────────────────────────────────────
$versionLock = Join-Path $InstallPath 'version.lock'
if ((Test-Path $EXT_DIR) -and (Test-Path $versionLock) -and -not $Force) {
    try {
        $lock = Get-Content $versionLock -Raw | ConvertFrom-Json
        Write-Host "ℹ️  Nexos já instalado — versão v$($lock.installed)" -ForegroundColor Yellow
        Write-Host "   Use -Force para reinstalar." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "📌 Extensão carregada de: $EXT_DIR" -ForegroundColor Green
        Write-Host ""
        exit 0
    } catch {}
}

# ─────────────────────────────────────────────────────────────────────────────
# CRIAR ESTRUTURA DE PASTAS
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "📁 Criando estrutura de pastas em: $InstallPath" -ForegroundColor White
foreach ($dir in @($InstallPath, $UPDATER_DIR, $EXT_DIR,
                   (Join-Path $InstallPath 'backup'),
                   (Join-Path $InstallPath 'logs'),
                   (Join-Path $InstallPath 'temp'))) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-Host "   ✅ Pastas criadas" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# BAIXAR SCRIPTS DO UPDATER
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "⬇️  Baixando scripts de atualização..." -ForegroundColor White

$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'NexosBootstrap/1.0')
$wc.Headers.Add('Cache-Control', 'no-cache')

try {
    $wc.DownloadFile($UPDATER_URL, $UPDATER_FILE)
    Write-Host "   ✅ nexos-updater.ps1 baixado" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Falha ao baixar nexos-updater.ps1: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Verifique sua conexão com a internet e tente novamente." -ForegroundColor Yellow
    exit 1
}

try {
    $wc.DownloadFile($TASK_URL, $TASK_FILE)
    Write-Host "   ✅ install-task.ps1 baixado" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  install-task.ps1 não baixado (não crítico): $($_.Exception.Message)" -ForegroundColor Yellow
}

$wc.Dispose()

# ─────────────────────────────────────────────────────────────────────────────
# EXECUTAR UPDATER PARA BAIXAR A VERSÃO ATUAL DA EXTENSÃO
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "📦 Baixando versão atual da extensão..." -ForegroundColor White

try {
    & $UPDATER_FILE -InstallPath $InstallPath -Force
    if ($LASTEXITCODE -ne 0) { throw "Updater retornou código $LASTEXITCODE" }
    Write-Host "   ✅ Extensão instalada com sucesso" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Falha ao instalar extensão: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Tente executar manualmente: $UPDATER_FILE" -ForegroundColor Yellow
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# REGISTRAR TAREFA AGENDADA (sem admin)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "⏰ Registrando tarefa de atualização automática..." -ForegroundColor White

if (Test-Path $TASK_FILE) {
    try {
        & $TASK_FILE -InstallPath $InstallPath
        Write-Host "   ✅ Tarefa 'NexosUpdater' criada (a cada 5 min, sem admin)" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️  Tarefa não pôde ser criada: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   As atualizações ainda funcionarão pelo background.js do Chrome." -ForegroundColor DarkGray
    }
} else {
    # Fallback: criar tarefa diretamente sem install-task.ps1
    try {
        $INTERVAL_MIN = 5
        $TASK_NAME    = 'NexosUpdater'
        $LAUNCHER_BAT = Join-Path $UPDATER_DIR 'nexos-run.bat'

        $batContent = "@echo off`r`npowershell.exe -NonInteractive -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$UPDATER_FILE`" -InstallPath `"$InstallPath`""
        Set-Content -Path $LAUNCHER_BAT -Value $batContent -Encoding ASCII

        # Remover tarefa anterior se existir
        & schtasks /delete /tn $TASK_NAME /f 2>&1 | Out-Null

        & schtasks /create /tn $TASK_NAME /tr "`"$LAUNCHER_BAT`"" /sc MINUTE /mo $INTERVAL_MIN /f 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ Tarefa 'NexosUpdater' criada (a cada 5 min)" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  Não foi possível criar tarefa agendada." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ⚠️  Tarefa não criada: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# LER VERSÃO INSTALADA
# ─────────────────────────────────────────────────────────────────────────────
$installedVersion = 'desconhecida'
try {
    $lock = Get-Content $versionLock -Raw | ConvertFrom-Json
    $installedVersion = $lock.installed
} catch {}

# ─────────────────────────────────────────────────────────────────────────────
# INSTRUÇÕES FINAIS
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   ✅ NEXOS TORRE v$installedVersion INSTALADO!$((' ' * [Math]::Max(0, 23 - $installedVersion.Length)))║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📌 Agora abra o Chrome/Edge e siga os passos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   1. Acesse:  chrome://extensions" -ForegroundColor White
Write-Host "   2. Ative o 'Modo do desenvolvedor' (canto superior direito)" -ForegroundColor White
Write-Host "   3. Clique em 'Carregar sem compactação'" -ForegroundColor White
Write-Host "   4. Selecione esta pasta:" -ForegroundColor White
Write-Host ""
Write-Host "      ► $EXT_DIR" -ForegroundColor Cyan
Write-Host ""
Write-Host "   ⚡ Esta é a ÚNICA vez que você precisa fazer isso." -ForegroundColor DarkGray
Write-Host "      Todas as atualizações futuras são automáticas." -ForegroundColor DarkGray
Write-Host ""

# Copiar caminho para área de transferência
try {
    $EXT_DIR | clip
    Write-Host "   📋 Caminho copiado para a área de transferência!" -ForegroundColor DarkGreen
} catch {}

Write-Host ""
