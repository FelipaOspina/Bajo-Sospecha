@echo off
REM Abre de 1 a 4 ventanas del juego, cada una con su propio perfil de prueba.
REM Uso: abrir_clientes.bat [cantidad] [codigo_de_sala]
REM   Sin codigo: cada ventana arranca en el menu principal.
REM   Con codigo (p. ej. abrir_clientes.bat 4 PRUEBA): entran directo a esa sala, listos.
REM Pon la ruta de tu Godot 4.3 en la linea siguiente.
set "GODOT=D:\Godot\Godot_v4.3-stable_win64.exe"
set N=%1
if "%N%"=="" set N=4
if not "%2"=="" set "ROOM=%2"
set "PROFILE_ID=prueba_jugador_1" & set "PNAME=Jugador 1"
start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 0,0
if %N% LSS 2 goto :eof
set "PROFILE_ID=prueba_jugador_2" & set "PNAME=Jugador 2"
start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 960,0
if %N% LSS 3 goto :eof
set "PROFILE_ID=prueba_jugador_3" & set "PNAME=Jugador 3"
start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 0,540
if %N% LSS 4 goto :eof
set "PROFILE_ID=prueba_jugador_4" & set "PNAME=Jugador 4"
start "" "%GODOT%" --path "%~dp0client" --resolution 960x540 --position 960,540
