@echo off
:: ---- CEK ADMIN MODE ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Script tidak berjalan sebagai Administrator.
    echo     Mengalihkan ke mode Administrator...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:menu
cls
echo ===========================
echo      Kelola Password
echo ===========================
echo 1. Tambahkan password (temp1200)
echo 2. Hapus password
echo 3. Keluar
echo ===========================
set /p choice=Masukkan pilihan (1/2/3): 

if "%choice%"=="1" (
    net user LupaMinum temp1200
    echo.
    echo [+] Password "temp1200" berhasil ditambahkan untuk akun tutturuu.
    pause
    goto menu
)

if "%choice%"=="2" (
    net user LupaMinum ""
    echo.
    echo [+] Password berhasil dihapus untuk akun tutturuu.
    pause
    goto menu
)

if "%choice%"=="3" (
    exit
)

echo.
echo [!] Pilihan tidak valid.
pause
goto menu
