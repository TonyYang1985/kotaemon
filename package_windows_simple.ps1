# Kotaemon Windows Packaging Script
# Simple and reliable version
# Based on GitHub Actions auto-bump-and-release.yaml workflow

param(
    [string]$Version = "",
    [string]$OutputDir = ".\build",
    [switch]$SkipVersionPrompt
)

# Set console encoding for proper Unicode display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "=== Kotaemon Windows Packaging Script ===" -ForegroundColor Magenta
Write-Host "Working directory: $(Get-Location)" -ForegroundColor Gray
Write-Host ""

# Check if we're in the right directory
if (-not (Test-Path "app.py")) {
    Write-Host "ERROR: app.py not found. Please run this script from the kotaemon root directory." -ForegroundColor Red
    exit 1
}

# Define required files
$requiredFiles = @(
    "LICENSE.txt",
    "flowsettings.py", 
    "app.py",
    ".env.example",
    "pyproject.toml",
    "scripts",
    "libs\ktem",
    "libs\kotaemon"
)

# Check for required files
Write-Host "Checking required files..." -ForegroundColor Cyan
$missing = @()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $missing += $file
        Write-Host "  X $file (MISSING)" -ForegroundColor Red
    } else {
        Write-Host "  + $file" -ForegroundColor Green
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Missing required files. Cannot proceed." -ForegroundColor Red
    exit 1
}

# Get version
if ([string]::IsNullOrEmpty($Version)) {
    if (Test-Path "VERSION") {
        $currentVersion = Get-Content "VERSION" -Raw
        $currentVersion = $currentVersion.Trim()
        Write-Host "Current version: $currentVersion" -ForegroundColor Yellow
    }
    
    if (-not $SkipVersionPrompt) {
        $Version = Read-Host "Enter package version (e.g. v1.0.0)"
        if ([string]::IsNullOrEmpty($Version)) {
            if ($currentVersion) {
                $Version = $currentVersion
            } else {
                $Version = "v1.0.0"
            }
        }
    } else {
        if ($currentVersion) {
            $Version = $currentVersion
        } else {
            $Version = "v1.0.0"
        }
    }
}

Write-Host "Package version: $Version" -ForegroundColor Yellow
Write-Host ""

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Define package paths
$packageName = "kotaemon-app"
$packagePath = Join-Path $OutputDir $packageName

# Remove existing package if it exists
if (Test-Path $packagePath) {
    Write-Host "Removing existing package directory..." -ForegroundColor Yellow
    Remove-Item -Path $packagePath -Recurse -Force
}

# Create package directory
Write-Host "Creating package directory: $packagePath" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $packagePath -Force | Out-Null

# Write version file (without BOM to avoid Git issues)
Write-Host "Writing version: $Version" -ForegroundColor Cyan
# Use Out-File with ASCII encoding to avoid BOM
$Version | Out-File -FilePath (Join-Path $packagePath "VERSION") -Encoding ASCII -NoNewline

# Copy files
Write-Host "Copying files..." -ForegroundColor Cyan

# Copy LICENSE.txt
Copy-Item -Path "LICENSE.txt" -Destination $packagePath -Force
Write-Host "  + LICENSE.txt" -ForegroundColor Green

# Copy flowsettings.py
Copy-Item -Path "flowsettings.py" -Destination $packagePath -Force
Write-Host "  + flowsettings.py" -ForegroundColor Green

# Copy app.py
Copy-Item -Path "app.py" -Destination $packagePath -Force
Write-Host "  + app.py" -ForegroundColor Green

# Copy pyproject.toml
Copy-Item -Path "pyproject.toml" -Destination $packagePath -Force
Write-Host "  + pyproject.toml" -ForegroundColor Green

# Copy .env.example as .env
Copy-Item -Path ".env.example" -Destination (Join-Path $packagePath ".env") -Force
Write-Host "  + .env.example -> .env" -ForegroundColor Green

# Copy scripts directory
Copy-Item -Path "scripts" -Destination $packagePath -Recurse -Force
Write-Host "  + scripts/" -ForegroundColor Green

# Fix Windows install script to include optional dependencies for v0.11.0+
Write-Host "  + Patching run_windows.bat for v0.11.0+ dependencies" -ForegroundColor Yellow
$runWindowsPath = Join-Path $packagePath "scripts\run_windows.bat"
if (Test-Path $runWindowsPath) {
    $content = Get-Content $runWindowsPath -Raw
    # Replace the actual GitHub installation patterns with local installation
    # These are the actual patterns in the run_windows.bat file
    $searchPattern1 = 'python -m pip install git@gitee.com:yangxiangjiang/kotaemon.git@"%app_version%"#subdirectory=libs/kotaemon'
    $searchPattern2 = 'python -m pip install git@gitee.com:yangxiangjiang/kotaemon.git@"%app_version%"#subdirectory=libs/ktem'
    $searchPattern3 = 'python -m pip install --no-deps git@gitee.com:yangxiangjiang/kotaemon.git@"%app_version%"'
    
    # Replace with local installation commands
    $newContent = $content -replace [regex]::Escape($searchPattern1), 'ECHO Installing kotaemon from local libs/kotaemon...
        python -m pip install -e ".\libs\kotaemon"'
    $newContent = $newContent -replace [regex]::Escape($searchPattern2), 'ECHO Installing ktem from local libs/ktem...
        python -m pip install -e ".\libs\ktem"'
    $newContent = $newContent -replace [regex]::Escape($searchPattern3), 'ECHO Installing kotaemon app from local source...
        python -m pip install --no-deps -e "."'
    # Add conda environment setup fix - ensure condabin directory is created
    # This addresses the issue where conda installation doesn't create condabin directory
    $condabinSetup = @'

:: Fix conda condabin directory if missing
IF NOT EXIST "%conda_root%\condabin" (
    ECHO Creating missing condabin directory...
    mkdir "%conda_root%\condabin" 2>nul
)

:: Copy conda.bat to condabin if missing
IF NOT EXIST "%conda_root%\condabin\conda.bat" (
    ECHO Copying conda.bat to condabin directory...
    FOR /D %%d IN ("%conda_root%\pkgs\conda-*") DO (
        IF EXIST "%%d\condabin\conda.bat" (
            copy "%%d\condabin\conda.bat" "%conda_root%\condabin\" >nul 2>&1
            IF NOT ERRORLEVEL 1 GOTO :condabin_fixed
        )
    )
)
:condabin_fixed

'@
    # Insert the condabin fix right before the activate_environment function
    $insertPoint = $newContent.IndexOf(':activate_environment')
    if ($insertPoint -gt 0) {
        $beforeActivate = $newContent.Substring(0, $insertPoint)
        $afterActivate = $newContent.Substring($insertPoint)
        $newContent = $beforeActivate + $condabinSetup + $afterActivate
    }
    # Write the file with Out-File using ASCII encoding to avoid BOM issues with Windows batch files
    $newContent | Out-File -FilePath $runWindowsPath -Encoding ASCII -NoNewline
}

# Create libs directory structure and copy assets
$libsPath = Join-Path $packagePath "libs"
New-Item -ItemType Directory -Path $libsPath -Force | Out-Null
Copy-Item -Path "libs\ktem" -Destination $libsPath -Recurse -Force
Copy-Item -Path "libs\kotaemon" -Destination $libsPath -Recurse -Force
Write-Host "  + libs/ktem/" -ForegroundColor Green
Write-Host "  + libs/kotaemon/" -ForegroundColor Green

# Show package contents
Write-Host ""
Write-Host "Package contents:" -ForegroundColor Cyan
Get-ChildItem -Path $packagePath -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($packagePath.Length + 1)
    if ($_.PSIsContainer) {
        Write-Host "  [DIR]  $relativePath/" -ForegroundColor Blue
    } else {
        $size = if ($_.Length -gt 1MB) { 
            "{0:N1} MB" -f ($_.Length / 1MB) 
        } elseif ($_.Length -gt 1KB) { 
            "{0:N1} KB" -f ($_.Length / 1KB) 
        } else { 
            "$($_.Length) B" 
        }
        Write-Host "  [FILE] $relativePath ($size)" -ForegroundColor Gray
    }
}

# Create zip archive
$zipPath = Join-Path $OutputDir "$packageName.zip"
if (Test-Path $zipPath) {
    Write-Host ""
    Write-Host "Removing existing zip file..." -ForegroundColor Yellow
    Remove-Item -Path $zipPath -Force
}

Write-Host ""
Write-Host "Creating zip archive: $zipPath" -ForegroundColor Cyan
Compress-Archive -Path "$packagePath\*" -DestinationPath $zipPath -Force

# Get zip file size
$zipSize = Get-Item $zipPath | ForEach-Object { 
    if ($_.Length -gt 1MB) { 
        "{0:N1} MB" -f ($_.Length / 1MB) 
    } else { 
        "{0:N1} KB" -f ($_.Length / 1KB) 
    }
}

Write-Host "+ Zip archive created successfully" -ForegroundColor Green

# Final summary
Write-Host ""
Write-Host "=== Packaging Complete ===" -ForegroundColor Green
Write-Host "Package directory: $packagePath" -ForegroundColor Cyan
Write-Host "Zip archive: $zipPath ($zipSize)" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now distribute the kotaemon-app.zip file!" -ForegroundColor Green
