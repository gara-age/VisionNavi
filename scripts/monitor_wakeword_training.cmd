@echo off
setlocal
title VisionNavi Wakeword Training Monitor

:loop
cls
echo ==========================================
echo VisionNavi Wakeword Training Monitor
echo ==========================================
echo.
echo [Time]
powershell -NoLogo -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"
echo.
echo [Drive Free Space]
powershell -NoLogo -NoProfile -Command "Get-PSDrive C,D | Select-Object Name,@{Name='FreeGB';Expression={[math]::Round($_.Free/1GB,2)}},@{Name='UsedGB';Expression={[math]::Round($_.Used/1GB,2)}} | Format-Table -AutoSize"
echo.
echo [Wakeword Processes]
powershell -NoLogo -NoProfile -Command "$rows = Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('python.exe','powershell.exe') -and ($_.CommandLine -like '*ko_hey_nabi.yaml*' -or $_.CommandLine -like '*ja_nee_navi.yaml*' -or $_.CommandLine -like '*ja_navisan.yaml*' -or $_.CommandLine -like '*start_wakeword_training_remaining_prod.ps1*') } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine; if ($rows) { $rows | Format-List } else { 'No matching wakeword training process.' }"
echo.
echo [Output Clip Counts]
powershell -NoLogo -NoProfile -Command "$paths = @('D:\VisionNaviWakeword\output\ko_hey_nabi\positive_train','D:\VisionNaviWakeword\output\ja_nee_navi\positive_train','D:\VisionNaviWakeword\output\ja_navisan\positive_train'); $rows = foreach ($p in $paths) { if (Test-Path $p) { [PSCustomObject]@{ Path = $p; Count = (Get-ChildItem $p -File -ErrorAction SilentlyContinue | Measure-Object).Count } } else { [PSCustomObject]@{ Path = $p; Count = 'missing' } } }; $rows | Format-Table -AutoSize"
echo.
echo [Training Log Tail]
powershell -NoLogo -NoProfile -Command "if (Test-Path 'D:\VisionNaviWakeword\logs\wakeword_training_prod_remaining.log') { Get-Content -Tail 40 'D:\VisionNaviWakeword\logs\wakeword_training_prod_remaining.log' } else { 'log_missing' }"
echo.
echo [Training Error Log Tail]
powershell -NoLogo -NoProfile -Command "if (Test-Path 'D:\VisionNaviWakeword\logs\wakeword_training_prod_remaining.error.log') { Get-Content -Tail 40 'D:\VisionNaviWakeword\logs\wakeword_training_prod_remaining.error.log' } else { 'err_log_missing' }"
echo.
echo Refreshing in 10 seconds. Press Ctrl+C to exit.
timeout /t 10 /nobreak >nul
goto loop
