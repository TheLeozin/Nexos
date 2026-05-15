#Requires -Version 5.1
<#
.SYNOPSIS
    Nexos Torre - Instalador Visual
    Janela WinForms com logo, steps, progresso e instrucoes finais.
    Executar sempre em modo STA:
        powershell.exe -sta -noprofile -executionpolicy bypass -file nexos-installer.ps1
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos",
    [switch]$Force
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- URLs ------------------------------------------------------------------
$RAW       = 'https://raw.githubusercontent.com/TheLeozin/Nexos/main'
$UPD_URL   = "$RAW/updater/nexos-updater.ps1"
$TASK_URL  = "$RAW/updater/install-task.ps1"
$LOGO_URL  = "$RAW/images/logo_nome.png"
$ICON_URL  = "$RAW/images/logo_circular.png"

# --- CAMINHOS --------------------------------------------------------------
$UPD_DIR   = Join-Path $InstallPath 'updater'
$EXT_DIR   = Join-Path $InstallPath 'extension'
$UPD_FILE  = Join-Path $UPD_DIR 'nexos-updater.ps1'
$TASK_FILE = Join-Path $UPD_DIR 'install-task.ps1'
$VER_LOCK  = Join-Path $InstallPath 'version.lock'

# --- PALETA ----------------------------------------------------------------
function rgb($r,$g,$b) { [System.Drawing.Color]::FromArgb($r,$g,$b) }

$C_HEADER  = rgb 22  45  95     # azul escuro do header
$C_HLINE   = rgb 30  60 120     # linha divisora no header
$C_WHITE   = [System.Drawing.Color]::White
$C_BG      = rgb 248 250 253    # fundo levemente off-white
$C_BLUE    = rgb 26  143 214    # azul acao
$C_GREEN   = rgb 34  168 110    # verde OK
$C_RED     = rgb 210  50  50    # vermelho erro
$C_ORANGE  = rgb 230 140   0    # laranja aviso
$C_GRAY    = rgb 210 218 230    # cinza pendente
$C_TEXT    = rgb  28  32  45    # texto principal
$C_SUB     = rgb 110 120 140    # subtexto
$C_LOGSUB  = rgb 140 150 165    # log text

# --- FORM PRINCIPAL --------------------------------------------------------
$F = New-Object System.Windows.Forms.Form
$F.Text            = 'Nexos Torre  |  Instalador'
$F.ClientSize      = New-Object System.Drawing.Size(560, 598)
$F.MinimumSize     = $F.Size
$F.MaximumSize     = $F.Size
$F.StartPosition   = 'CenterScreen'
$F.FormBorderStyle = 'FixedDialog'
$F.MaximizeBox     = $false
$F.BackColor       = $C_BG
$F.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

# --- HEADER ----------------------------------------------------------------
$HDR = New-Object System.Windows.Forms.Panel
$HDR.Dock      = 'Top'
$HDR.Height    = 116
$HDR.BackColor = $C_HEADER
$F.Controls.Add($HDR)

# Logo: caixa branca dentro do header escuro
$LOGO_CARD = New-Object System.Windows.Forms.Panel
$LOGO_CARD.Location  = New-Object System.Drawing.Point(18, 16)
$LOGO_CARD.Size      = New-Object System.Drawing.Size(126, 84)
$LOGO_CARD.BackColor = $C_WHITE
$HDR.Controls.Add($LOGO_CARD)

$PIC = New-Object System.Windows.Forms.PictureBox
$PIC.Dock      = 'Fill'
$PIC.SizeMode  = 'Zoom'
$PIC.BackColor = $C_WHITE
$LOGO_CARD.Controls.Add($PIC)

# Titulo
$LBL_TITLE = New-Object System.Windows.Forms.Label
$LBL_TITLE.Text      = 'Nexos Torre'
$LBL_TITLE.Location  = New-Object System.Drawing.Point(158, 18)
$LBL_TITLE.Size      = New-Object System.Drawing.Size(382, 40)
$LBL_TITLE.ForeColor = $C_WHITE
$LBL_TITLE.Font      = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
$HDR.Controls.Add($LBL_TITLE)

$LBL_SUB = New-Object System.Windows.Forms.Label
$LBL_SUB.Text      = 'Instalador Automatico  |  Torre de Controle GPA'
$LBL_SUB.Location  = New-Object System.Drawing.Point(160, 64)
$LBL_SUB.Size      = New-Object System.Drawing.Size(382, 22)
$LBL_SUB.ForeColor = rgb 155 190 235
$LBL_SUB.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$HDR.Controls.Add($LBL_SUB)

# Linha azul viva na base do header
$HDR_LINE = New-Object System.Windows.Forms.Panel
$HDR_LINE.Dock      = 'Bottom'
$HDR_LINE.Height    = 3
$HDR_LINE.BackColor = $C_BLUE
$HDR.Controls.Add($HDR_LINE)

# --- STEPS -----------------------------------------------------------------
$STEP_DEFS = @(
    @{ T = 'Preparando pastas';        S = 'Estrutura local em %LOCALAPPDATA%\Nexos' }
    @{ T = 'Baixando atualizador';     S = 'nexos-updater.ps1  |  install-task.ps1' }
    @{ T = 'Baixando extensao';        S = 'Versao mais recente do servidor Nexos' }
    @{ T = 'Instalando extensao';      S = 'Extraindo, validando e aplicando arquivos' }
    @{ T = 'Configurando auto-update'; S = 'Tarefa NexosUpdater  (executa a cada 5 min)' }
)

$SC = @()
$sy = 122

foreach ($i in 0..($STEP_DEFS.Count - 1)) {
    $sd = $STEP_DEFS[$i]

    $PN = New-Object System.Windows.Forms.Panel
    $PN.Location  = New-Object System.Drawing.Point(0, $sy)
    $PN.Size      = New-Object System.Drawing.Size(560, 50)
    $PN.BackColor = $C_BG
    $F.Controls.Add($PN)

    # Barra lateral colorida
    $BAR = New-Object System.Windows.Forms.Panel
    $BAR.Location  = New-Object System.Drawing.Point(0, 4)
    $BAR.Size      = New-Object System.Drawing.Size(4, 42)
    $BAR.BackColor = $C_GRAY
    $PN.Controls.Add($BAR)

    # Circulo indicador (numero)
    $IC = New-Object System.Windows.Forms.Label
    $IC.Location  = New-Object System.Drawing.Point(16, 11)
    $IC.Size      = New-Object System.Drawing.Size(28, 28)
    $IC.BackColor = $C_GRAY
    $IC.ForeColor = $C_WHITE
    $IC.Font      = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $IC.TextAlign = 'MiddleCenter'
    $IC.Text      = ($i + 1).ToString()
    $PN.Controls.Add($IC)

    # Titulo do step
    $LT = New-Object System.Windows.Forms.Label
    $LT.Location  = New-Object System.Drawing.Point(56, 7)
    $LT.Size      = New-Object System.Drawing.Size(488, 20)
    $LT.Text      = $sd.T
    $LT.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
    $LT.ForeColor = $C_SUB
    $PN.Controls.Add($LT)

    # Descricao
    $LS = New-Object System.Windows.Forms.Label
    $LS.Location  = New-Object System.Drawing.Point(56, 27)
    $LS.Size      = New-Object System.Drawing.Size(488, 16)
    $LS.Text      = $sd.S
    $LS.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $LS.ForeColor = rgb 168 175 192
    $PN.Controls.Add($LS)

    $SC += @{ P = $PN; Bar = $BAR; Ic = $IC; Lt = $LT; Ls = $LS }
    $sy += 50
}
# Fim dos steps: $sy = 122 + 5*50 = 372

# --- SEPARADOR -------------------------------------------------------------
$DIV = New-Object System.Windows.Forms.Panel
$DIV.Location  = New-Object System.Drawing.Point(20, 380)
$DIV.Size      = New-Object System.Drawing.Size(520, 1)
$DIV.BackColor = rgb 220 226 238
$F.Controls.Add($DIV)

# --- BARRA DE PROGRESSO ----------------------------------------------------
$PB = New-Object System.Windows.Forms.ProgressBar
$PB.Location = New-Object System.Drawing.Point(20, 390)
$PB.Size     = New-Object System.Drawing.Size(520, 10)
$PB.Minimum  = 0
$PB.Maximum  = 100
$PB.Value    = 0
$PB.Style    = 'Continuous'
$F.Controls.Add($PB)

# --- STATUS ----------------------------------------------------------------
$STAT = New-Object System.Windows.Forms.Label
$STAT.Location  = New-Object System.Drawing.Point(20, 408)
$STAT.Size      = New-Object System.Drawing.Size(520, 18)
$STAT.Text      = 'Aguardando inicio...'
$STAT.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
$STAT.ForeColor = $C_SUB
$F.Controls.Add($STAT)

# --- LOG -------------------------------------------------------------------
$LOG = New-Object System.Windows.Forms.RichTextBox
$LOG.Location    = New-Object System.Drawing.Point(20, 432)
$LOG.Size        = New-Object System.Drawing.Size(520, 82)
$LOG.BackColor   = rgb 240 244 250
$LOG.ForeColor   = $C_LOGSUB
$LOG.Font        = New-Object System.Drawing.Font('Consolas', 7.5)
$LOG.ReadOnly    = $true
$LOG.ScrollBars  = 'Vertical'
$LOG.BorderStyle = 'None'
$F.Controls.Add($LOG)

# --- BOTAO FINAL -----------------------------------------------------------
$BTN = New-Object System.Windows.Forms.Button
$BTN.Location  = New-Object System.Drawing.Point(20, 526)
$BTN.Size      = New-Object System.Drawing.Size(520, 50)
$BTN.Text      = 'Instalando, aguarde...'
$BTN.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$BTN.BackColor = $C_GRAY
$BTN.ForeColor = $C_WHITE
$BTN.FlatStyle = 'Flat'
$BTN.FlatAppearance.BorderSize = 0
$BTN.Enabled   = $false
$F.Controls.Add($BTN)

# --- HELPERS DE UI ---------------------------------------------------------
function DoUI { [System.Windows.Forms.Application]::DoEvents() }

function Set-Step([int]$i, [string]$state, [string]$sub = '') {
    $c = $SC[$i]
    switch ($state) {
        'active' {
            $c.Bar.BackColor = $C_BLUE
            $c.Ic.BackColor  = $C_BLUE
            $c.Ic.Text       = '...'
            $c.Lt.ForeColor  = $C_TEXT
        }
        'done' {
            $c.Bar.BackColor = $C_GREEN
            $c.Ic.BackColor  = $C_GREEN
            $c.Ic.Text       = 'OK'
            $c.Lt.ForeColor  = $C_TEXT
        }
        'warn' {
            $c.Bar.BackColor = $C_ORANGE
            $c.Ic.BackColor  = $C_ORANGE
            $c.Ic.Text       = '!'
        }
        'error' {
            $c.Bar.BackColor = $C_RED
            $c.Ic.BackColor  = $C_RED
            $c.Ic.Text       = 'X'
            $c.Lt.ForeColor  = $C_RED
        }
    }
    if ($sub) { $c.Ls.Text = $sub }
    DoUI
}

function Add-Log([string]$msg) {
    $ts = Get-Date -Format 'HH:mm:ss'
    $LOG.AppendText("[$ts] $msg`n")
    try { $LOG.ScrollToCaret() } catch {}
    DoUI
}

function Set-Status([string]$msg, $col = $null) {
    $STAT.Text = $msg
    if ($col) { $STAT.ForeColor = $col } else { $STAT.ForeColor = $C_SUB }
    DoUI
}

function Set-Progress([int]$v) {
    $PB.Value = [Math]::Min(100, [Math]::Max(0, $v))
    DoUI
}

function Load-Logo {
    $localLogo = Join-Path $EXT_DIR 'images\logo_nome.png'
    try {
        if (Test-Path $localLogo) {
            $PIC.Image = [System.Drawing.Image]::FromFile($localLogo)
        } else {
            $tmp = "$env:TEMP\_nexos_logo_$PID.png"
            (New-Object System.Net.WebClient).DownloadFile($LOGO_URL, $tmp)
            $PIC.Image = [System.Drawing.Image]::FromFile($tmp)
        }
    } catch {}
    DoUI
}

# --- EXECUCAO DO UPDATER COM SAIDA EM TEMPO REAL ---------------------------
function Invoke-ProcessWithLog([string]$exe, [string]$args) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exe
    $psi.Arguments              = $args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)

    while (-not $proc.HasExited) {
        while ($proc.StandardOutput.Peek() -gt -1) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line -and $line.Trim()) { Add-Log $line }
        }
        DoUI
        Start-Sleep -Milliseconds 80
    }
    # drenar saida restante
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ($line -and $line.Trim()) { Add-Log $line }
    }
    return $proc.ExitCode
}

# --- INSTALAR --------------------------------------------------------------
function Start-Install {

    # Verificar se ja esta instalado (e nao e forcado)
    if ((Test-Path $VER_LOCK) -and -not $Force) {
        try {
            $vl = Get-Content $VER_LOCK -Raw | ConvertFrom-Json
            if ($vl.installed -and $vl.installed -ne '0.0.0') {
                Show-AlreadyInstalled $vl.installed
                return
            }
        } catch {}
    }

    $ok = $true

    # -- STEP 0: Criar pastas ----------------------------------------------
    Set-Step 0 'active'
    Set-Status 'Criando estrutura de pastas...'
    Add-Log "Destino: $InstallPath"

    foreach ($d in @(
        $InstallPath,
        $UPD_DIR,
        $EXT_DIR,
        (Join-Path $InstallPath 'backup'),
        (Join-Path $InstallPath 'logs'),
        (Join-Path $InstallPath 'temp')
    )) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        Add-Log "  dir OK: $(Split-Path $d -Leaf)"
    }

    Set-Progress 10
    Set-Step 0 'done' 'Pastas criadas com sucesso'

    # -- STEP 1: Baixar scripts --------------------------------------------
    Set-Step 1 'active'
    Set-Status 'Baixando scripts do servidor Nexos...'

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'NexosInstaller/3.0')
        $wc.Headers.Add('Cache-Control', 'no-cache')

        Add-Log "Baixando nexos-updater.ps1..."
        $wc.DownloadFile($UPD_URL, $UPD_FILE)
        Add-Log "  OK  ($([math]::Round((Get-Item $UPD_FILE).Length/1KB,1)) KB)"

        Add-Log "Baixando install-task.ps1..."
        $wc.DownloadFile($TASK_URL, $TASK_FILE)
        Add-Log "  OK  ($([math]::Round((Get-Item $TASK_FILE).Length/1KB,1)) KB)"

        $wc.Dispose()
        Set-Progress 22
        Set-Step 1 'done' 'nexos-updater.ps1  |  install-task.ps1 prontos'
    } catch {
        try { $wc.Dispose() } catch {}
        Add-Log "ERRO: $($_.Exception.Message)"
        Set-Step 1 'error' 'Falha no download — verifique a conexao'
        Set-Status 'Nao foi possivel baixar os scripts. Verifique a internet.' $C_RED
        Show-Error
        return
    }

    # -- STEPS 2+3: Baixar e instalar extensao via updater -----------------
    Set-Step 2 'active'
    Set-Step 3 'active'
    Set-Status 'Baixando e instalando a extensao...'
    Set-Progress 28

    Add-Log 'Iniciando nexos-updater.ps1 -Force...'
    $updArgs = "-noprofile -executionpolicy bypass -command `"& '$UPD_FILE' -InstallPath '$InstallPath' -Force 2>&1`""
    $exitCode = Invoke-ProcessWithLog 'powershell.exe' $updArgs

    if ($exitCode -ne 0) {
        Add-Log "ERRO: updater encerrou com codigo $exitCode"
        Set-Step 2 'error' "Updater falhou (codigo $exitCode)"
        Set-Step 3 'error'
        Set-Status 'Falha ao instalar a extensao. Verifique o log.' $C_RED
        Show-Error
        return
    }

    Set-Progress 75
    Set-Step 2 'done' 'Download e hash SHA-256 verificados'
    Set-Step 3 'done' 'Arquivos instalados e validados'

    # -- STEP 4: Tarefa agendada -------------------------------------------
    Set-Step 4 'active'
    Set-Status 'Registrando tarefa de auto-atualizacao...'

    $taskArgs = "-noprofile -executionpolicy bypass -command `"& '$TASK_FILE' -InstallPath '$InstallPath' 2>&1`""
    $exitTask = Invoke-ProcessWithLog 'powershell.exe' $taskArgs

    if ($exitTask -ne 0) {
        Add-Log "AVISO: tarefa nao criada (codigo $exitTask) — updates pelo Chrome ainda funcionam"
        Set-Step 4 'warn' 'Tarefa nao criada  |  updates via background.js do Chrome'
    } else {
        Set-Step 4 'done' 'Tarefa NexosUpdater criada  (a cada 5 min, sem admin)'
    }

    Set-Progress 94

    # -- VERSAO INSTALADA -------------------------------------------------
    $ver = '?'
    try { $ver = (Get-Content $VER_LOCK -Raw | ConvertFrom-Json).installed } catch {}

    # Carregar logo da extensao instalada (alta qualidade)
    Load-Logo

    Set-Progress 100
    Set-Status "Instalacao concluida!   Nexos Torre v$ver esta pronto." $C_GREEN

    Add-Log ''
    Add-Log "============================================"
    Add-Log " PROXIMO PASSO: carregar no Chrome / Edge"
    Add-Log "============================================"
    Add-Log " 1. Clique no botao abaixo para abrir o Chrome"
    Add-Log " 2. Ative o 'Modo do desenvolvedor' (canto sup. dir.)"
    Add-Log " 3. Clique em 'Carregar sem compactacao'"
    Add-Log " 4. Selecione a pasta:"
    Add-Log "    $EXT_DIR"
    Add-Log " (o caminho sera copiado automaticamente)"
    Add-Log "============================================"

    # Copiar caminho imediatamente
    try { $EXT_DIR | clip } catch {}

    # Ativar botao
    $capturedDir = $EXT_DIR
    $capturedVer = $ver
    $BTN.Text      = "  Abrir chrome://extensions    |    Nexos Torre v$capturedVer instalado"
    $BTN.BackColor = $C_BLUE
    $BTN.Enabled   = $true

    $BTN.Add_Click({
        try { $capturedDir | clip } catch {}
        $launched = $false
        foreach ($cp in @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )) {
            if (Test-Path $cp) {
                $ext = if ($cp -like '*Edge*') { 'edge://extensions/' } else { 'chrome://extensions/' }
                Start-Process $cp "--new-window $ext"
                $launched = $true
                break
            }
        }
        if (-not $launched) {
            $msg = "Abra o Chrome ou Edge e acesse:`n  chrome://extensions`n`nDepois:`n 1. Ative o Modo do desenvolvedor`n 2. Carregar sem compactacao`n 3. Selecione a pasta:`n    $capturedDir`n`n(Caminho ja copiado para area de transferencia)"
            [System.Windows.Forms.MessageBox]::Show($msg, 'Nexos Torre - Passo Final', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    }.GetNewClosure())
}

# --- JA INSTALADO ----------------------------------------------------------
function Show-AlreadyInstalled([string]$ver) {
    # Marcar todos os steps como done
    for ($i = 0; $i -lt $SC.Count; $i++) { Set-Step $i 'done' }
    Load-Logo
    Set-Progress 100
    Set-Status "Nexos Torre v$ver ja esta instalado e atualizado." $C_GREEN

    Add-Log "Instalacao detectada: v$ver"
    Add-Log "Caminho: $EXT_DIR"
    Add-Log "(caminho copiado para area de transferencia)"
    try { $EXT_DIR | clip } catch {}

    $capturedDir = $EXT_DIR
    $BTN.Text      = "  Abrir chrome://extensions    |    v$ver ja instalado"
    $BTN.BackColor = $C_GREEN
    $BTN.Enabled   = $true
    $BTN.Add_Click({
        try { $capturedDir | clip } catch {}
        foreach ($cp in @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )) {
            if (Test-Path $cp) {
                $ext = if ($cp -like '*Edge*') { 'edge://extensions/' } else { 'chrome://extensions/' }
                Start-Process $cp "--new-window $ext"
                break
            }
        }
    }.GetNewClosure())
}

# --- ERRO ------------------------------------------------------------------
function Show-Error {
    $BTN.Text      = '  Instalacao falhou  |  Ver log acima  |  Clique para fechar'
    $BTN.BackColor = $C_RED
    $BTN.Enabled   = $true
    $BTN.Add_Click({ $F.Close() })
    Set-Progress 0
}

# --- INIT ------------------------------------------------------------------
$F.Add_Shown({
    Load-Logo
    DoUI
    Start-Install
})

[void]$F.ShowDialog()
