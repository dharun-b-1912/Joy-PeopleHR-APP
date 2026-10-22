@echo off
echo ===================================================
echo   JOY PeopleHR Mobile - Google Play App Bundle Builder
echo   Version: 1.1.4+21 (Production AAB for Play Console)
echo ===================================================
echo.
cd /d "%~dp0"
set "PATH=%SystemRoot%\System32\WindowsPowerShell\v1.0;%SystemRoot%\System32;%PATH%"
echo [1/3] Fetching Flutter dependencies...
call flutter pub get
echo.
echo [2/3] Building Production Release App Bundle (.aab)...
call flutter build appbundle --release
echo.
echo [3/3] Copying App Bundle to root for Google Play Console upload...
if exist "build\app\outputs\bundle\release\app-release.aab" (
    copy /y "build\app\outputs\bundle\release\app-release.aab" "JOY_PeopleHR_v1.1.4_build21.aab"
    copy /y "build\app\outputs\bundle\release\app-release.aab" "..\JOY_PeopleHR_v1.1.4_build21.aab"
    echo.
    echo ===================================================
    echo   SUCCESS! Production App Bundle generated:
    echo   JOY_PeopleHR_v1.1.4_build21.aab
    echo ===================================================
) else (
    echo.
    echo [ERROR] Build failed. Please check Flutter build logs above.
)
pause
