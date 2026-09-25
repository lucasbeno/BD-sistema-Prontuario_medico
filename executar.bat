@echo off
chcp 65001 > nul
cd /d "%~dp0"
set "JAVAC="
for /f "delims=" %%i in ('where javac 2^>nul') do if not defined JAVAC set "JAVAC=%%i"
if not defined JAVAC (
    echo JDK nao encontrado. Instale o JDK 17 ou superior.
    pause
    exit /b 1
)
for %%i in ("%JAVAC%") do set "JDK_BIN=%%~dpi"
if exist out rmdir /s /q out
"%JDK_BIN%javac" -encoding UTF-8 -d out -cp "lib\*" src\prontuario\*.java src\prontuario\dao\*.java
if errorlevel 1 (
    echo.
    echo Erro ao compilar.
    pause
    exit /b 1
)
"%JDK_BIN%java" -Dfile.encoding=UTF-8 -cp "out;lib\*" prontuario.App %*
pause
