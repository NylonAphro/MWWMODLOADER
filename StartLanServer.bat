
@ECHO OFF

@ECHO ------------------------------------------------------
@ECHO Magicka: Wizard Wars [SERVER]
@ECHO STARTING....
@ECHO ------------------------------------------------------

SET name=

goto MENU

:MENU
@ECHO.
@ECHO Game Modes:
@ECHO.
@ECHO 	1. Duel
@ECHO 	2. Team Deathmatch
@ECHO 	3. Arena
@ECHO 	4. Wizard Warfare
@ECHO 	5. King of the Hill
@ECHO 	6. Soul Harvest
@ECHO 	7. Training
@ECHO 	8. Training Grounds
@ECHO.

choice /C 12345678E /M "Select desired game mode, E to exit"


if ERRORLEVEL ==9 GOTO EXIT
IF ERRORLEVEL ==8 GOTO TG
IF ERRORLEVEL ==7 GOTO TRAINING
If ERRORLEVEL ==6 GOTO SH
If ERRORLEVEL ==5 GOTO KOTH
If ERRORLEVEL ==4 GOTO WW
IF ERRORLEVEL ==3 GOTO ARENA
IF ERRORLEVEL ==2 GOTO DM
IF ERRORLEVEL ==1 GOTO DUEL


:DUEL
SET gamemode=duel
SET players=3

@ECHO.
@ECHO Available Maps:
@ECHO 	1. Ballongvisp
@ECHO 	2. Kakfat
@ECHO.

choice /C 12 /M "Select desired map: "

IF ERRORLEVEL 1 SET map=duel_ballongvisp
IF ERRORLEVEL 2 SET map=duel_kakfat


GOTO NAME

:DM
SET gamemode=melee
SET players=9

@ECHO.
@ECHO Avaialble Maps:
@ECHO 	1. Slaktmask
@ECHO 	2. Potatispress
@ECHO.

choice /C 12 /M "Select desired map: "

IF ERRORLEVEL 1 SET map=slaktmask
IF ERRORLEVEL 2 SET map=potatispress

GOTO NAME

:ARENA
SET gamemode=arena
SET map=duel_ballongvisp
SET players=3
GOTO NAME

:WW
SET gamemode=default
SET players=9

@ECHO.
@ECHO Avaialble Maps:
@ECHO 	1. Degbunke
@ECHO 	2. Perkulator
@ECHO 	3. Soppslev
@ECHO 	4. Slickepott
@ECHO.

choice /C 1234 /M "Select desired map: "

IF ERRORLEVEL 1 SET map=degbunke
IF ERRORLEVEL 2 SET map=perkulator
IF ERRORLEVEL 3 SET map=soppslev
IF ERRORLEVEL 4 SET map=slickepott
GOTO NAME

:KOTH
SET gamemode=kingofthehill
SET map=diskho
SET players=9
GOTO NAME

:SH
SET gamemode=confusion
SET players=9

@ECHO.
@ECHO Avaialble Maps:
@ECHO 	1. Varmluftsugn
@ECHO 	2. Bestick
@ECHO.

choice /C 12 /M "Select desired map: "

IF ERRORLEVEL 1 SET map=varmluftsugn
IF ERRORLEVEL 2 SET map=bestick

GOTO NAME

:TRAINING
SET gamemode=training
SET map=training
SET players=2
GOTO NAME

:TG
SET gamemode=training_grounds
SET map=training_grounds
SET players=2
GOTO NAME

:NAME
@ECHO.
IF DEFINED name GOTO LAUNCH
SET /P name="Please enter a server name in quotes (eg: "LAN Server"):"
IF NOT DEFINED name GOTO NAME
GOTO LAUNCH


:LAUNCH
@ECHO.
@ECHO Starting dedicated server [%name%]
@ECHO Launching %gamemode% [map:%map%]

SET base=-bundle-dir ./data_win32_bundled -window-title "Magicka:Wizard Wars" -ini settings_client -property-order server client -network-profile lan
SET server=-auto-start-server -server-name %name% -auto-run-game-mode-gameconfiguration %gamemode% -ignore-loadout-verification -no-anti-cheat -disable-chat -auto-run-level %map% -disable-persistence -dedicated-server -no-rendering -allow-spectators -max-players %players%

bitsquid_win32_dev.exe %base% %server%

pause


GOTO EXIT

:EXIT
@ECHO ------------------------------------------------------
@ECHO Shutting down....
@ECHO ------------------------------------------------------
