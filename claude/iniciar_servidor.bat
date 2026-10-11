@echo off
REM Arranca el servidor del juego con el caso de la startup.
cd /d "%~dp0server"
if not exist node_modules call npm install
call npm run build
set "SCENARIO=..\scenarios\caso_fraude_tech_startup.json"
call npm start
pause
