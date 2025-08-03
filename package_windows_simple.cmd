@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM Kotaemon Windows Packaging Script
REM Simple and reliable version - CMD/Batch implementation
REM Based on GitHub Actions auto-bump-and-release.yaml workflow

SET "VERSION=%~1"
SET "OUTPUT_DIR=.\build"
SET "SKIP_VERSION_PROMPT=%~2"

ECHO === Kotaemon Windows Packaging Script ===
ECHO Working directory: %CD%
ECHO.

REM Check if we're in the right directory
IF NOT EXIST "app.py" (
    ECHO ERROR: app.py not found. Please run this script from the kotaemon root directory.
    EXIT /B 1
)

REM Define and check required files
ECHO Checking required files...
SET "MISSING_FILES="
CALL :CHECK_FILE "LICENSE.txt"
CALL :CHECK_FILE "flowsettings.py"
CALL :CHECK_FILE "app.py"
CALL :CHECK_FILE ".env.example"
CALL :CHECK_FILE "pyproject.toml"
CALL :CHECK_FILE "scripts"
CALL :CHECK_FILE "libs\ktem\ktem\assets"

IF DEFINED MISSING_FILES (
    ECHO.
    ECHO ERROR: Missing required files. Cannot proceed.
    EXIT /B 1
)

REM Get version
IF "%VERSION%"=="" (
    IF EXIST "VERSION" (
        SET /P CURRENT_VERSION=<"VERSION"
        ECHO Current version: !CURRENT_VERSION!
    )
    
    IF NOT "%SKIP_VERSION_PROMPT%"=="--skip-prompt" (
        SET /P VERSION="Enter package version (e.g. v1.0.0): "
        IF "!VERSION!"=="" (
            IF DEFINED CURRENT_VERSION (
                SET "VERSION=!CURRENT_VERSION!"
            ) ELSE (
                SET "VERSION=v1.0.0"
            )
        )
    ) ELSE (
        IF DEFINED CURRENT_VERSION (
            SET "VERSION=!CURRENT_VERSION!"
        ) ELSE (
            SET "VERSION=v1.0.0"
        )
    )
)

ECHO Package version: %VERSION%
ECHO.

REM Create output directory
IF NOT EXIST "%OUTPUT_DIR%" (
    MKDIR "%OUTPUT_DIR%"
    ECHO Created output directory: %OUTPUT_DIR%
)

REM Define package paths
SET "PACKAGE_NAME=kotaemon-app"
SET "PACKAGE_PATH=%OUTPUT_DIR%\%PACKAGE_NAME%"

REM Remove existing package if it exists
IF EXIST "%PACKAGE_PATH%" (
    ECHO Removing existing package directory...
    REM Force remove with retry for locked files
    RMDIR /S /Q "%PACKAGE_PATH%" 2>NUL
    IF EXIST "%PACKAGE_PATH%" (
        ECHO Warning: Some files could not be removed. Trying to continue...
        TIMEOUT /T 2 /NOBREAK >NUL
        RMDIR /S /Q "%PACKAGE_PATH%" 2>NUL
    )
)

REM Create package directory
ECHO Creating package directory: %PACKAGE_PATH%
MKDIR "%PACKAGE_PATH%"

REM Write version file
ECHO Writing version: %VERSION%
ECHO %VERSION%> "%PACKAGE_PATH%\VERSION"

REM Copy files
ECHO Copying files...

COPY "LICENSE.txt" "%PACKAGE_PATH%\" >NUL
ECHO   + LICENSE.txt

COPY "flowsettings.py" "%PACKAGE_PATH%\" >NUL
ECHO   + flowsettings.py

COPY "app.py" "%PACKAGE_PATH%\" >NUL
ECHO   + app.py

COPY "pyproject.toml" "%PACKAGE_PATH%\" >NUL
ECHO   + pyproject.toml

COPY ".env.example" "%PACKAGE_PATH%\.env" >NUL
ECHO   + .env.example -^> .env

XCOPY "scripts" "%PACKAGE_PATH%\scripts\" /E /I /Q >NUL
ECHO   + scripts/

REM Fix Windows install script
ECHO   + Patching run_windows.bat for v0.11.0+ dependencies
SET "RUN_WINDOWS_PATH=%PACKAGE_PATH%\scripts\run_windows.bat"
IF EXIST "%RUN_WINDOWS_PATH%" (
    CALL :PATCH_RUN_WINDOWS "%RUN_WINDOWS_PATH%"
)

REM Create libs directory structure and copy assets
MKDIR "%PACKAGE_PATH%\libs\ktem\ktem" 2>NUL
XCOPY "libs\ktem\ktem\assets" "%PACKAGE_PATH%\libs\ktem\ktem\assets\" /E /I /Q >NUL
ECHO   + libs/ktem/ktem/assets/

REM Show package contents
ECHO.
ECHO Package contents:
FOR /R "%PACKAGE_PATH%" %%F IN (*) DO (
    SET "REL_PATH=%%F"
    SET "REL_PATH=!REL_PATH:%PACKAGE_PATH%\=!"
    CALL :GET_FILE_SIZE "%%F"
    ECHO   [FILE] !REL_PATH! (!FILE_SIZE!)
)

REM Create zip archive using PowerShell (most reliable method)
SET "ZIP_PATH=%OUTPUT_DIR%\%PACKAGE_NAME%.zip"
IF EXIST "%ZIP_PATH%" (
    ECHO.
    ECHO Removing existing zip file...
    DEL "%ZIP_PATH%"
)

ECHO.
ECHO Creating zip archive: %ZIP_PATH%
PowerShell -Command "Compress-Archive -Path '%PACKAGE_PATH%\*' -DestinationPath '%ZIP_PATH%' -Force"

IF EXIST "%ZIP_PATH%" (
    CALL :GET_FILE_SIZE "%ZIP_PATH%"
    ECHO + Zip archive created successfully
    ECHO.
    ECHO === Packaging Complete ===
    ECHO Package directory: %PACKAGE_PATH%
    ECHO Zip archive: %ZIP_PATH% (!FILE_SIZE!)
    ECHO.
    ECHO You can now distribute the kotaemon-app.zip file!
) ELSE (
    ECHO ERROR: Failed to create zip archive
    EXIT /B 1
)

GOTO :EOF

:CHECK_FILE
IF NOT EXIST "%~1" (
    ECHO   X %~1 (MISSING)
    SET "MISSING_FILES=1"
) ELSE (
    ECHO   + %~1
)
GOTO :EOF

:GET_FILE_SIZE
SET "FILE_SIZE="
FOR %%A IN ("%~1") DO (
    SET /A SIZE_BYTES=%%~zA
    IF !SIZE_BYTES! GTR 1048576 (
        SET /A SIZE_MB=!SIZE_BYTES!/1048576
        SET "FILE_SIZE=!SIZE_MB! MB"
    ) ELSE IF !SIZE_BYTES! GTR 1024 (
        SET /A SIZE_KB=!SIZE_BYTES!/1024
        SET "FILE_SIZE=!SIZE_KB! KB"
    ) ELSE (
        SET "FILE_SIZE=!SIZE_BYTES! B"
    )
)
GOTO :EOF

:PATCH_RUN_WINDOWS
SET "TEMP_FILE=%TEMP%\run_windows_temp.bat"
SET "CONDA_FIX_ADDED="

REM Create conda environment fix
(
ECHO.
ECHO :: Fix conda condabin directory if missing
ECHO IF NOT EXIST "%%conda_root%%\condabin" ^(
ECHO     ECHO Creating missing condabin directory...
ECHO     mkdir "%%conda_root%%\condabin" 2^>nul
ECHO ^)
ECHO.
ECHO :: Copy conda.bat to condabin if missing
ECHO IF NOT EXIST "%%conda_root%%\condabin\conda.bat" ^(
ECHO     IF EXIST "%%conda_root%%\pkgs\conda-*\condabin\conda.bat" ^(
ECHO         ECHO Copying conda.bat to condabin directory...
ECHO         FOR /D %%%%d IN ^("%%conda_root%%\pkgs\conda-*"^) DO ^(
ECHO             IF EXIST "%%%%d\condabin\conda.bat" ^(
ECHO                 copy "%%%%d\condabin\conda.bat" "%%conda_root%%\condabin\" ^>nul 2^>^&1
ECHO                 GOTO :condabin_fixed
ECHO             ^)
ECHO         ^)
ECHO         :condabin_fixed
ECHO     ^)
ECHO ^)
ECHO.
) > "%TEMP%\conda_fix.txt"

REM Process the run_windows.bat file
(
FOR /F "usebackq delims=" %%L IN ("%~1") DO (
    SET "LINE=%%L"
    
    REM Replace GitHub URLs with local installation - Fixed patterns
    IF "!LINE!"=="        python -m pip install git@gitee.com:yangxiangjiang/kotaemon.git@\"%%app_version%%\"#subdirectory=libs/kotaemon" (
        ECHO         ECHO Installing kotaemon from local libs/kotaemon...
        ECHO         python -m pip install -e "%%CD%%\libs\kotaemon"
    ) ELSE IF "!LINE!"=="        python -m pip install git@gitee.com:yangxiangjiang/kotaemon.git@\"%%app_version%%\"#subdirectory=libs/ktem" (
        ECHO         ECHO Installing ktem from local libs/ktem...
        ECHO         python -m pip install -e "%%CD%%\libs\ktem"
    ) ELSE IF "!LINE!"=="        python -m pip install --no-deps git@gitee.com:yangxiangjiang/kotaemon.git@\"%%app_version%%\"" (
        ECHO         ECHO Installing kotaemon app from local source...
        ECHO         python -m pip install --no-deps -e .
    ) ELSE IF "!LINE!"==":activate_environment" AND NOT DEFINED CONDA_FIX_ADDED (
        REM Insert conda fix before activate_environment
        TYPE "%TEMP%\conda_fix.txt"
        ECHO !LINE!
        SET "CONDA_FIX_ADDED=1"
    ) ELSE (
        ECHO !LINE!
    )
)
) > "%TEMP_FILE%"

REM Replace original file
MOVE "%TEMP_FILE%" "%~1" >NUL
DEL "%TEMP%\conda_fix.txt" 2>NUL
ECHO     - Applied GitHub URL replacements and conda fixes
GOTO :EOF

:CHECK_FILE
IF EXIST "%~1" (
    ECHO   + %~1
) ELSE (
    ECHO   - %~1 (MISSING)
    SET "MISSING_FILES=1"
)
GOTO :EOF
