@echo off
setlocal
title GenshinUltraSlimmer - Genshin Impact

rem GenshinUltraSlimmer launches dnullptr's original GUI and Rueben Gill's
rem multilingual audio stubber. Each tool updates from its own GitHub repository.

"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges for the slimmer tools...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "ROOT=%~dp0"
set "ORIGINAL=%ROOT%GenshinSlimmer_GUI.ps1"
set "AUDIO=%ROOT%GenshinUltraSlimmer_Audio.ps1"
set "ORIGINAL_DOWNLOAD=%ROOT%GenshinSlimmer_GUI.ps1.download"
set "AUDIO_DOWNLOAD=%ROOT%GenshinUltraSlimmer_Audio.ps1.download"
set "GAME_FINDER=%ROOT%GenshinUltraSlimmer_FindGame.ps1"
set "GAME_CONFIG=%ROOT%path.ini"
set "ORIGINAL_URL=https://raw.githubusercontent.com/dnullptr/GenshinSlimmer/main/GenshinSlimmer_GUI.ps1"
set "AUDIO_URL=https://raw.githubusercontent.com/Rue-G19/GenshinSlimmer/main/GenshinUltraSlimmer_Audio.ps1"

:startup_update
cls
echo.
echo  ============================================================
echo                 G E N S H I N   U L T R A   S L I M M E R
echo                   Starting up - checking for updates
echo  ============================================================
echo.
echo  [1/3] Looking for the Genshin Impact install...
if exist "%GAME_FINDER%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%GAME_FINDER%" -ConfigPath "%GAME_CONFIG%"
    if errorlevel 1 echo  Install not found automatically. You can select it in either tool.
) else (
    echo  Install scanner is missing. Select the game folder in either tool.
)
echo.
echo  [2/3] Checking dnullptr's original GUI...
call :update_dnull
echo.
echo  [3/3] Checking Rueben Gill's audio stubber...
call :update_audio
echo.
echo  Startup update check complete. Opening the menu...
timeout /t 2 /nobreak >nul

:choose_tool
cls
echo.
echo  ============================================================
echo                 G E N S H I N   U L T R A   S L I M M E R
echo                 Genshin Impact PC space tools
echo            Original project: github.com/dnullptr/GenshinSlimmer
echo  ============================================================
echo.
echo  1. Original GenshinSlimmer by dnullptr
echo     Original video and resource slimming tools.
echo.
echo  2. GenshinUltraSlimmer Audio language stubber by Rueben Gill
echo     Stub, sync, or restore installed voice-over language packs.
echo.
echo  3. Check for script updates again
echo     Refresh both tools from their respective GitHub repositories.
echo.
echo  4. Exit
echo.
if exist "%GAME_CONFIG%" echo  Game path saved in path.ini.
echo.
set /p "CHOICE=Select an option: "

if "%CHOICE%"=="1" (
    if not exist "%ORIGINAL%" (
        echo dnullptr's slimmer is unavailable until it can be downloaded.
        pause
        goto choose_tool
    )
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%ORIGINAL%"
    echo The slimmer has closed.
    goto choose_tool
)
if "%CHOICE%"=="2" (
    if not exist "%AUDIO%" (
        echo Language audio stubber not found: "%AUDIO%"
        pause
        goto choose_tool
    )
    powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%AUDIO%"
    echo The audio stubber has closed.
    goto choose_tool
)
rem Option 3 lets the user retry either update after the automatic startup check.
if "%CHOICE%"=="3" (
    call :update_dnull
    call :update_audio
    goto choose_tool
)
if "%CHOICE%"=="4" exit /b 0

echo Invalid choice.
pause
goto choose_tool

:update_dnull
rem Download to a temporary file and replace the cached original only after basic checks pass.
echo Checking for dnullptr's latest GenshinSlimmer...
curl.exe --fail --location --silent --show-error --output "%ORIGINAL_DOWNLOAD%" "%ORIGINAL_URL%"
if errorlevel 1 goto dnull_update_failed
if not exist "%ORIGINAL_DOWNLOAD%" goto dnull_update_failed
for %%F in ("%ORIGINAL_DOWNLOAD%") do if %%~zF EQU 0 goto dnull_update_failed
findstr /i /c:"GenshinSlimmer" "%ORIGINAL_DOWNLOAD%" >nul
if errorlevel 1 goto dnull_update_failed
move /y "%ORIGINAL_DOWNLOAD%" "%ORIGINAL%" >nul
if errorlevel 1 goto dnull_update_failed
echo Updated dnullptr's slimmer from GitHub.
exit /b 0

:dnull_update_failed
if exist "%ORIGINAL_DOWNLOAD%" del /q "%ORIGINAL_DOWNLOAD%"
if exist "%ORIGINAL%" (
    echo Update failed; the cached dnullptr script is still available.
    exit /b 0
)
echo Update failed and no local dnullptr script exists.
exit /b 1

:update_audio
rem Download the language stubber from this fork, falling back to the packaged copy if needed.
echo Checking for GenshinUltraSlimmer Audio updates...
curl.exe --fail --location --silent --show-error --output "%AUDIO_DOWNLOAD%" "%AUDIO_URL%"
if errorlevel 1 goto audio_update_failed
if not exist "%AUDIO_DOWNLOAD%" goto audio_update_failed
for %%F in ("%AUDIO_DOWNLOAD%") do if %%~zF EQU 0 goto audio_update_failed
findstr /i /c:"GenshinUltraSlimmer Audio Language Stubber" "%AUDIO_DOWNLOAD%" >nul
if errorlevel 1 goto audio_update_failed
move /y "%AUDIO_DOWNLOAD%" "%AUDIO%" >nul
if errorlevel 1 goto audio_update_failed
echo Updated GenshinUltraSlimmer Audio from Rue-G19/GenshinSlimmer.
exit /b 0

:audio_update_failed
if exist "%AUDIO_DOWNLOAD%" del /q "%AUDIO_DOWNLOAD%"
if exist "%AUDIO%" (
    echo Audio update failed; the packaged GenshinUltraSlimmer Audio script is still available.
    exit /b 0
)
echo Audio update failed and no packaged GenshinUltraSlimmer Audio script exists.
exit /b 1
