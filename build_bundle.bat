@echo off
echo ===================================================
echo   JOY PeopleHR Mobile - Google Play App Bundle Builder
echo   Version: 1.1.6+24 (Production AAB for Play Console)
echo ===================================================
echo.
cd /d "%~dp0"
set "PATH=%SystemRoot%\System32\WindowsPowerShell\v1.0;%SystemRoot%\System32;%PATH%"
echo [1/4] Fetching Flutter dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] flutter pub get failed. Aborting.
    pause
    exit /b 1
)
echo.
echo [2/4] Running Flutter analyzer (quick check)...
call flutter analyze --no-fatal-infos
echo.
echo [3/4] Building Production Release App Bundle (.aab)...
call flutter build appbundle --release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] flutter build appbundle failed. Check logs above.
    pause
    exit /b 1
)
echo.
echo [4/4] Copying App Bundle to root for Google Play Console upload...
if exist "build\app\outputs\bundle\release\app-release.aab" (
    copy /y "build\app\outputs\bundle\release\app-release.aab" "JOY_PeopleHR_v1.1.6_build24.aab"
    echo.
    echo ===================================================
    echo   SUCCESS! Production App Bundle generated:
    echo   JOY_PeopleHR_v1.1.6_build24.aab
    echo.
    echo   Upload this file to Google Play Console.
    echo   See RELEASE_NOTES_v1.1.6.md for Play Store notes.
    echo ===================================================
) else (
    echo.
    echo [ERROR] Build artifact not found. Build may have failed.
)
pause
