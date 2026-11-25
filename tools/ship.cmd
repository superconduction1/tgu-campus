@echo off
rem One-shot: build APK locally, then install it into MuMu and launch it.
rem ASCII only: cmd reads .cmd as GBK, non-ASCII comments break parsing.
setlocal
set "ROOT=%~dp0.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
set "LOG=%ROOT%\.tools\ship.log"
set "APK=%ROOT%\build\app\outputs\flutter-apk\app-debug.apk"
set "ADB=D:\MuMuPlayer\nx_main\adb.exe"

echo ==== SHIP START %DATE% %TIME% ==== > "%LOG%"

echo [1/4] building... >> "%LOG%"
call "%ROOT%\b.cmd" >> "%LOG%" 2>&1
if not exist "%APK%" (
  echo SHIP_FAIL: no apk >> "%LOG%"
  echo SHIP_FAIL
  exit /b 1
)

echo [2/4] connecting emulator... >> "%LOG%"
"%ADB%" connect 127.0.0.1:16384 >> "%LOG%" 2>&1

echo [3/4] installing... >> "%LOG%"
"%ADB%" -s 127.0.0.1:16384 uninstall edu.tgu.tgu_campus >> "%LOG%" 2>&1
"%ADB%" -s 127.0.0.1:16384 install -r "%APK%" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo SHIP_FAIL: install failed >> "%LOG%"
  echo SHIP_FAIL
  exit /b 1
)

echo [4/4] launching... >> "%LOG%"
"%ADB%" -s 127.0.0.1:16384 shell monkey -p edu.tgu.tgu_campus -c android.intent.category.LAUNCHER 1 >> "%LOG%" 2>&1

echo SHIP_OK >> "%LOG%"
echo SHIP_OK
endlocal
