@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
cd /d "%~dp0"
if not exist dcu mkdir dcu
dcc32 -B -NUdcu -E. ParserTests.dpr
if errorlevel 1 exit /b 1
.\ParserTests.exe
