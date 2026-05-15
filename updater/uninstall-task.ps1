#Requires -Version 5.1
<#
.SYNOPSIS
    Remove o Nexos Updater SEM precisar de administrador.

.PARAMETER InstallPath
    Raiz da instalação. Padrão: %LOCALAPPDATA%\Nexos

.PARAMETER RemoveFiles
    Se passado, remove também updater\, logs\ e temp\.
    Os arquivos da extensão em extension\ e os backups NÃO são removidos.
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos",
    [switch]$RemoveFiles
)

$ErrorActionPreference = 'Continue'

$TASK_NAME = 'NexosUpdater'

# ─────────────────────────────────────────────────────────────────────────────
# REMOVER TAREFA AGENDADA
# ─────────────────────────────────────────────────────────────────────────────
$existingTask = & schtasks /query /tn $TASK_NAME 2>&1
if ($LASTEXITCODE -eq 0) {
    & schtasks /end /tn $TASK_NAME 2>&1 | Out-Null
    & schtasks /delete /tn $TASK_NAME /f 2>&1 | Out-Null
    Write-Host "Tarefa '$TASK_NAME' removida do Task Scheduler."
} else {
    # Tentar também via Register-ScheduledTask (pode ter sido criada por este método)
    $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
        Write-Host "Tarefa '$TASK_NAME' removida (Register-ScheduledTask)."
    } else {
        Write-Host "Tarefa '$TASK_NAME' não encontrada (já removida)."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REMOVER ENTRADA HKCU\Run
# ─────────────────────────────────────────────────────────────────────────────
$runKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
if (Get-ItemProperty -Path $runKey -Name $TASK_NAME -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKey -Name $TASK_NAME -Force
    Write-Host "Entrada '$TASK_NAME' removida de HKCU\Run."
}

# ─────────────────────────────────────────────────────────────────────────────
# REMOVER update.lock (evita bloqueio de processo órfão)
# ─────────────────────────────────────────────────────────────────────────────
$lockFile = Join-Path $InstallPath 'update.lock'
if (Test-Path $lockFile) {
    Remove-Item $lockFile -Force
    Write-Host "update.lock removido."
}

# ─────────────────────────────────────────────────────────────────────────────
# REMOVER ARQUIVOS (opcional)
# ─────────────────────────────────────────────────────────────────────────────
if ($RemoveFiles) {
    $dirsToRemove = @(
        (Join-Path $InstallPath 'updater'),
        (Join-Path $InstallPath 'logs'),
        (Join-Path $InstallPath 'temp')
    )
    foreach ($dir in $dirsToRemove) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Pasta removida: $dir"
        }
    }
    Write-Host ""
    Write-Host "Os arquivos da extensão (extension\) e backups (backup\) foram preservados."
}

Write-Host ""
Write-Host "Nexos Updater desinstalado."
