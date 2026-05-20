@echo off
cd /d "%~dp0"

echo ==========================================
echo  I2C Timing Compare: v2 vs modified
echo ==========================================
echo.

echo [1/3] Compiling...
iverilog -g2012 -o timing_cmp.vvp -I ../../rtl/core ^
    timing_cmp_tb.v ^
    i2c_mod_core.v ^
    ../../rtl/perips/i2c_v2.v
if %errorlevel% neq 0 (
    echo *** Compile FAILED ***
    pause
    exit /b 1
)
echo   Compile OK.

echo.
echo [2/3] Running simulation...
vvp timing_cmp.vvp
if %errorlevel% neq 0 (
    echo *** Simulation FAILED ***
    pause
    exit /b 1
)
echo   Simulation OK.

echo.
echo [3/3] Opening GTKWave...
start gtkwave timing_cmp.vcd

echo.
echo Done! Compare: v2_scl/sda  vs  m_scl/sda
