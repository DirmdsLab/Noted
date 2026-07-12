@echo off

:: ==========================================================
:: AUTO ELEVATE (jalankan ulang script sebagai Administrator)
:: ==========================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Elevating privileges... Mohon tunggu.
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: ==========================================================
:: MENU UTAMA
:: ==========================================================
:menu
cls
echo ==============================
echo      MENU SYNC WAKTU
echo ==============================
echo 1. net start w32time
echo 2. w32tm /resync
echo 3. quit
echo ==============================
set /p pilih="Pilih menu: "

if "%pilih%"=="1" goto netstart
if "%pilih%"=="2" goto resync
if "%pilih%"=="3" goto selesai

echo Pilihan tidak valid!
pause
goto menu


:netstart
net start w32time
pause
goto menu

:resync
w32tm /resync
pause
goto menu

:selesai
exit
