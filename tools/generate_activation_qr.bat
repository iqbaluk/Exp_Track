@echo off
setlocal
cd /d "%~dp0\.."
python tools\generate_activation_qr_ui.py
endlocal
