@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
msbuild DelphiColorPreview.dproj /t:Build /p:config=Debug /p:platform=Win32 /v:minimal /nologo
