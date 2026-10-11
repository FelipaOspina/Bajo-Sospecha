@echo off
REM Abre 4 ventanas del cliente. Pon la ruta de tu Godot 4.3 en la linea siguiente.
set "GODOT=D:\Godot\Godot_v4.3-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Godot\Godot_v4.3-stable_win64.exe"
set N=%1
if "%N%"=="" set N=4
start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 0,0
if %N% GEQ 2 start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 960,0
if %N% GEQ 3 start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 0,540
if %N% GEQ 4 start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 960,540
