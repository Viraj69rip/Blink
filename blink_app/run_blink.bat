@echo off
set "PATH=C:\tools\PortableGit\cmd;C:\tools\flutter\bin;%PATH%"
cd /d "c:\all html project\BLINK\blink_app"
echo =======================================
echo     LAUNCHING BLINK COMPANION APP      
echo =======================================
echo.
echo Running pub get...
call flutter pub get
echo.
echo Starting BLINK on Windows...
call flutter run -d windows
pause
