@echo off
setlocal

cd /d C:\Users\iqbal\Projects\receipt_scanner

echo [1/6] Checking for running Flutter/Dart processes...
powershell -NoProfile -Command "Get-Process | Where-Object { $_.ProcessName -match 'flutter|dart' } | Select-Object Id,ProcessName,CPU,StartTime"

set /p KILLPROCS=Kill these processes if found? (y/N): 
if /I "%KILLPROCS%"=="Y" (
  echo Stopping Flutter/Dart processes...
  powershell -NoProfile -Command "Get-Process | Where-Object { $_.ProcessName -match 'flutter|dart' } | Stop-Process -Force"
) else (
  echo Skipping process stop.
)

echo.
echo [2/6] Formatting target files...
call dart format lib\gemini_service.dart lib\pages\project_list_page.dart
if errorlevel 1 goto :fail

echo.
echo [3/6] Fast analyze gemini_service.dart (--no-pub)...
call flutter analyze --no-pub lib\gemini_service.dart
if errorlevel 1 goto :fail

echo.
echo [4/6] Fast analyze project_list_page.dart (--no-pub)...
call flutter analyze --no-pub lib\pages\project_list_page.dart
if errorlevel 1 goto :fail

echo.
set /p RUNPUB=Run flutter pub get and full analyze too? (y/N): 
if /I "%RUNPUB%"=="Y" (
  echo [5/6] Running flutter pub get...
  call flutter pub get
  if errorlevel 1 goto :fail

  echo [6/6] Full analyze on target files...
  call flutter analyze lib\gemini_service.dart
  if errorlevel 1 goto :fail
  call flutter analyze lib\pages\project_list_page.dart
  if errorlevel 1 goto :fail
) else (
  echo Skipping pub get and full analyze.
)

echo.
echo Done.
goto :eof

:fail
echo.
echo Command failed with exit code %errorlevel%.
exit /b %errorlevel%
