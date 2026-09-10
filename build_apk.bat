@echo off
echo ===================================================
echo   JOY PeopleHR Mobile - Production Release Builder
echo   Version: 1.0.2+7 (Live Office Production Test)
echo ===================================================
echo.
cd /d "%~dp0"
echo [1/3] Fetching Flutter dependencies...
call flutter pub get
echo.
echo [2/3] Building Release APK (Signed with Joy PeopleHR Keystore)...
call flutter build apk --release
echo.
echo [3/3] Copying APK to root for distribution...
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    copy /y "build\app\outputs\flutter-apk\app-release.apk" "JOY_PeopleHR_v1.0.2_build7.apk"
    echo.
    echo ===================================================
    echo   SUCCESS! Release APK generated:
    echo   JOY_PeopleHR_v1.0.2_build7.apk
    echo ===================================================
) else (
    echo.
    echo [ERROR] Build failed. Please check Flutter build logs above.
)
pause
