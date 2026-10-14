$ErrorActionPreference = "Stop"

$REPO = "https://github.com/koditra/bodhiScript.git"
$DIR = "$env:USERPROFILE\.bodhiscript"

Write-Host "Installing BodhiScript..."
Write-Host ""

function Find-Git {
    $paths = @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:ProgramFiles\Git\bin\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            return $path
        }
    }

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        return $gitCmd.Source
    }

    return $null
}

function Find-Python {
    $candidates = @()

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $candidates += $pythonCmd.Source
    }

    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $candidates += $pyCmd.Source
    }

    $searchRoots = @(
        "$env:LOCALAPPDATA\Programs\Python",
        "$env:ProgramFiles\Python",
        "${env:ProgramFiles(x86)}\Python",
        "$env:LOCALAPPDATA\Programs\Python\Launcher",
        "$env:SystemDrive\Python"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }

        try {
            $pythonExes = Get-ChildItem -Path $root -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue
            foreach ($pythonExe in $pythonExes) {
                $candidates += $pythonExe.FullName
            }
        }
        catch {
        }
    }

    $seen = @{}
    foreach ($path in $candidates) {
        if (-not $path) { continue }

        $normalized = $path.Trim()
        if ($seen.ContainsKey($normalized)) { continue }
        $seen[$normalized] = $true

        try {
            $output = & $path --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $output -match "^Python 3") {
                return $path
            }
        }
        catch {
        }
    }

    return $null
}

function Install-PythonWithWinget {
    $ids = @(
        "Python.Python.3.13",
        "Python.Python.3.12",
        "Python.Python.3.11",
        "Python.Python.3.10",
        "Python.Python.3"
    )

    foreach ($id in $ids) {
        Write-Host "Trying Python package: $id"

        winget install --id $id -e --source winget `
            --accept-source-agreements `
            --accept-package-agreements

        if ($LASTEXITCODE -eq 0) {
            return $true
        }

        Write-Host "Package not available: $id"
    }

    return $false
}

$GIT = Find-Git

if (-not $GIT) {
    Write-Host "Git not found."
    Write-Host "Installing Git..."

    winget install --id Git.Git -e --source winget `
        --accept-source-agreements `
        --accept-package-agreements

    $GIT = Find-Git
}

if (-not $GIT) {
    Write-Host "Git installation failed."
    exit 1
}

Write-Host "Using Git: $GIT"

$PYTHON = Find-Python

if (-not $PYTHON) {
    Write-Host "Python not found."
    Write-Host "Installing Python..."

    if (-not (Install-PythonWithWinget)) {
        Write-Host "Python installation failed."
        exit 1
    }

    $PYTHON = Find-Python
}

if (-not $PYTHON) {
    Write-Host ""
    Write-Host "Python could not be found after installation."
    Write-Host "Please restart PowerShell and run the installer again."
    exit 1
}

Write-Host "Using Python: $PYTHON"

Write-Host "Checking Python..."

& $PYTHON --version

if ($LASTEXITCODE -ne 0) {
    Write-Host "Python is not working."
    exit 1
}

Write-Host "Checking pip..."

& $PYTHON -m pip --version

if ($LASTEXITCODE -ne 0) {
    Write-Host "pip not found. Installing pip..."
    & $PYTHON -m ensurepip --upgrade
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install pip."
    exit 1
}

if (Test-Path $DIR) {
    Write-Host "Removing previous BodhiScript installation..."
    Remove-Item -Recurse -Force $DIR
}

Write-Host "Downloading BodhiScript..."

& $GIT clone -q $REPO $DIR

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to download BodhiScript."
    exit 1
}

Write-Host "Installing BodhiScript..."

& $PYTHON -m pip install -q -e $DIR

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install BodhiScript."
    exit 1
}

$ScriptsDirectories = @(& $PYTHON -c "import sysconfig; print(sysconfig.get_path('scripts')); print(sysconfig.get_path('scripts', scheme='nt_user'))")

if ($LASTEXITCODE -ne 0 -or $ScriptsDirectories.Count -lt 2) {
    Write-Host "Could not determine the Python Scripts directories."
    exit 1
}

$ScriptsDirectories = @($ScriptsDirectories | ForEach-Object { "$_".Trim() } | Select-Object -Unique)

foreach ($ScriptsDirectory in $ScriptsDirectories) {
    if (-not (Test-Path $ScriptsDirectory)) {
        continue
    }

    $env:Path = "$ScriptsDirectory;$env:Path"
}

$ExistingScriptsDirectories = @($ScriptsDirectories | Where-Object { Test-Path $_ })

if ($ExistingScriptsDirectories.Count -eq 0) {
    Write-Host "Python Scripts directories not found: $($ScriptsDirectories -join ', ')"
    exit 1
}

$BODHI = $null
$launcherNames = @(
    "bodhi.exe",
    "bodhi-script.exe",
    "bodhi-script.py",
    "bodhi-script-script.exe",
    "bodhi-script-script.py"
)

foreach ($ScriptsDirectory in $ExistingScriptsDirectories) {
    foreach ($name in $launcherNames) {
        $candidate = Join-Path $ScriptsDirectory $name
        if (Test-Path $candidate) {
            $BODHI = $candidate
            break
        }
    }

    if (-not $BODHI) {
        $matchingLaunchers = Get-ChildItem -Path $ScriptsDirectory -Filter "bodhi*.exe" -ErrorAction SilentlyContinue
        if ($matchingLaunchers) {
            $BODHI = $matchingLaunchers[0].FullName
        }
    }

    if ($BODHI) {
        break
    }
}

if (-not $BODHI) {
    Write-Host "bodhi launcher was not created."
    Write-Host "Checked Python Scripts directories: $($ExistingScriptsDirectories -join ', ')"
    Write-Host "Please check the Python install and try again."
    exit 1
}

Write-Host ""
Write-Host "BodhiScript installed!"
Write-Host ""
Write-Host "Run:"
Write-Host "  bodhi your_file.bodhi"
Write-Host ""
Write-Host "Location:"
Write-Host "  $BODHI"