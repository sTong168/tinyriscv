@echo off
cd /d "%~dp0"

echo ==========================================
echo  I2C Compare Simulation
echo  Ours (i2c.v) vs Modified (i2c_modified.v)
echo ==========================================
echo.

echo [1/3] Compiling...
iverilog -o i2c_compare.vvp -I ../../rtl/core ^
    i2c_compare_tb.v ^
    i2c_mod_core.v ^
    ../../rtl/perips/i2c.v
if %errorlevel% neq 0 (
    echo *** Compile FAILED ***
    pause
    exit /b 1
)
echo   Compile OK.

echo.
echo [2/3] Running simulation...
vvp i2c_compare.vvp
if %errorlevel% neq 0 (
    echo *** Simulation FAILED ***
    pause
    exit /b 1
)
echo   Simulation OK.

echo.
echo [3/3] Opening GTKWave...
start gtkwave i2c_compare.vcd

echo.
echo Done! Waveform opened in GTKWave.
echo Tip: drag our_scl/our_sda and mod_scl/mod_sda to the Signals pane.
