#Requires -Version 5.1
<#
.SYNOPSIS
    Instala o Nexos Updater SEM privilégios de administrador.

.DESCRIPTION
    Cria uma tarefa agendada de nível de usuário (sem admin) que executa
    nexos-updater.ps1 a cada 5 minutos.
    Também registra em HKCU\Run para garantir execução no próximo login.

    NÃO requer privilégios de administrador.
    Usa schtasks.exe com launcher .bat para evitar problemas com aspas e espaços.

.PARAMETER InstallPath
    Raiz da instalação. Padrão: %LOCALAPPDATA%\Nexos (pasta do usuário, sem admin)

.EXAMPLE
    .\install-task.ps1
    .\install-task.ps1 -InstallPath "$env:USERPROFILE\Nexos"
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos"
)

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
$TASK_NAME      = 'NexosUpdater'
$UPDATER_SCRIPT = Join-Path $InstallPath 'updater\nexos-updater.ps1'
$LAUNCHER_BAT   = Join-Path $InstallPath 'updater\nexos-run.bat'
$LOGS_DIR       = Join-Path $InstallPath 'logs'
$INTERVAL_MIN   = 5

# ─────────────────────────────────────────────────────────────────────────────
# GARANTIR PASTAS
# ─────────────────────────────────────────────────────────────────────────────
foreach ($dir in @($InstallPath, (Split-Path $UPDATER_SCRIPT), $LOGS_DIR)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Pasta criada: $dir"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# COPIAR SCRIPT DO UPDATER (se executando do source)
# ─────────────────────────────────────────────────────────────────────────────
$sourceScript = Join-Path $PSScriptRoot 'nexos-updater.ps1'
if ((Test-Path $sourceScript) -and ((Get-Item $sourceScript).FullName -ne (Resolve-Path $UPDATER_SCRIPT -ErrorAction SilentlyContinue)?.Path)) {
    Copy-Item $sourceScript $UPDATER_SCRIPT -Force
    Write-Host "Script copiado: $UPDATER_SCRIPT"
} elseif (-not (Test-Path $UPDATER_SCRIPT)) {
    Write-Warning "nexos-updater.ps1 não encontrado em: $UPDATER_SCRIPT"
    Write-Warning "Copie o arquivo manualmente antes de executar a tarefa."
}

# ─────────────────────────────────────────────────────────────────────────────
# CRIAR LAUNCHER .BAT (evita problemas com aspas/espaços no schtasks.exe)
# ─────────────────────────────────────────────────────────────────────────────
$batContent = @"
@echo off
powershell.exe -NonInteractive -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0nexos-updater.ps1" -InstallPath "$InstallPath"
"@
Set-Content -Path $LAUNCHER_BAT -Value $batContent -Encoding ASCII
Write-Host "Launcher criado: $LAUNCHER_BAT"

# ─────────────────────────────────────────────────────────────────────────────
# REMOVER TAREFA ANTERIOR (se existir)
# ─────────────────────────────────────────────────────────────────────────────
$existingTask = & schtasks /query /tn $TASK_NAME 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removendo tarefa existente '$TASK_NAME'..."
    & schtasks /delete /tn $TASK_NAME /f 2>&1 | Out-Null
}

# ─────────────────────────────────────────────────────────────────────────────
# CRIAR TAREFA AGENDADA (schtasks.exe — sem admin, usuário atual)
# ─────────────────────────────────────────────────────────────────────────────
# /sc MINUTE /mo 5  → executa a cada 5 minutos
# /f                → sobrescreve se existir
# Sem /ru → usa o usuário atual (não pede senha)
& schtasks /create `
    /tn $TASK_NAME `
    /tr "`"$LAUNCHER_BAT`"" `
    /sc MINUTE /mo $INTERVAL_MIN `
    /f 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Warning "schtasks falhou (código $LASTEXITCODE). Tentando via Register-ScheduledTask..."

    # Fallback: Register-ScheduledTask (sem admin para tarefas do próprio usuário)
    try {
        $action   = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$LAUNCHER_BAT`""
        $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date)
        $trigger.Repetition.Interval = "PT${INTERVAL_MIN}M"
        $trigger.Repetition.Duration = 'P9999D'
        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
            -MultipleInstances IgnoreNew `
            -Hidden `
            -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal `
            -UserId $env:USERNAME `
            -LogonType Interactive `
            -RunLevel Limited

        Register-ScheduledTask `
            -TaskName $TASK_NAME `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Force | Out-Null

        Write-Host "✅ Tarefa criada via Register-ScheduledTask."
    } catch {
        Write-Warning "Register-ScheduledTask também falhou: $_"
        Write-Warning "A tarefa agendada não foi criada, mas HKCU\Run ainda será configurado."
    }
} else {
    Write-Host "✅ Tarefa '$TASK_NAME' registrada (a cada ${INTERVAL_MIN} min)."
}

# ─────────────────────────────────────────────────────────────────────────────
# HKCU\Run — executa no login do usuário (persistência adicional)
# ─────────────────────────────────────────────────────────────────────────────
$runKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
Set-ItemProperty -Path $runKey -Name $TASK_NAME -Value "`"$LAUNCHER_BAT`"" -Force
Write-Host "✅ HKCU\Run configurado (executa no próximo login)."

# ─────────────────────────────────────────────────────────────────────────────
# SUMÁRIO
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════"
Write-Host " Nexos Updater instalado com sucesso (sem admin)"
Write-Host "═══════════════════════════════════════════════════"
Write-Host "  Instalação : $InstallPath"
Write-Host "  Script     : $UPDATER_SCRIPT"
Write-Host "  Launcher   : $LAUNCHER_BAT"
Write-Host "  Logs       : $LOGS_DIR\updater.log"
Write-Host "  Intervalo  : a cada $INTERVAL_MIN minutos"
Write-Host ""
Write-Host "Para testar manualmente:"
Write-Host "  powershell -File `"$UPDATER_SCRIPT`" -DryRun"
Write-Host ""

# Executar agora se desejado
$response = Read-Host "Executar o updater agora? [S/n]"
if ($response -ne 'n' -and $response -ne 'N') {
    Write-Host "Iniciando updater em background..."
    Start-Process cmd.exe -ArgumentList "/c `"$LAUNCHER_BAT`"" -WindowStyle Hidden
    Write-Host "✅ Iniciado. Aguarde alguns segundos e verifique: $LOGS_DIR\updater.log"
}
