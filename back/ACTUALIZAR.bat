@echo off
rem Copia la carpeta back al servidor y ejecuta este archivo.
rem Requiere que back\.env contenga valores reales de produccion.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0actualizar.ps1" %*
pause