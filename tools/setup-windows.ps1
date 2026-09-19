# Mark Zero - put the game on the Windows laptop, and keep it up to date.
#
# Run it once to install. Run it again any time to get the newest version - it is also
# the "update" button.
#
#   irm https://raw.githubusercontent.com/JerzySukiennik/mark-zero-godot/main/tools/setup-windows.ps1 | iex
#
# Installs nothing system-wide and needs no administrator rights: the engine lands inside
# the game's own folder, so deleting that folder undoes everything this did.

$ErrorActionPreference = 'Stop'
$GodotVersion = '4.6.2-stable'
$Root   = Join-Path $HOME 'Mark Zero'
$Engine = Join-Path $Root 'engine'
$Repo   = Join-Path $Root 'mark-zero-godot'

function Say($m)  { Write-Host "  $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "MARK ZERO - setup" -ForegroundColor White
Write-Host ""

New-Item -ItemType Directory -Force -Path $Root, $Engine | Out-Null

# ---- 1. the engine ---------------------------------------------------------------------
$GodotExe = Get-ChildItem $Engine -Filter '*.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
if ($GodotExe) {
    Ok "Godot already installed"
} else {
    Say "Downloading Godot $GodotVersion (about 120 MB)..."
    $zip = Join-Path $env:TEMP "godot.zip"
    $url = "https://github.com/godotengine/godot/releases/download/$GodotVersion/Godot_v${GodotVersion}_win64.exe.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $Engine -Force
    Remove-Item $zip -Force
    # Take whatever .exe actually landed rather than trusting the name - it has changed
    # between releases before.
    $GodotExe = Get-ChildItem $Engine -Filter '*.exe' | Select-Object -First 1 -ExpandProperty FullName
    if (-not $GodotExe) { throw "Godot did not unpack into $Engine" }
    Ok "Godot installed"
}

# ---- 2. the game -----------------------------------------------------------------------
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if (Test-Path (Join-Path $Repo '.git')) {
    Say "Updating the game..."
    Push-Location $Repo
    & git pull --ff-only 2>&1 | Out-Null
    Pop-Location
    Ok "Game up to date"
} elseif ($hasGit) {
    Say "Downloading the game..."
    & git clone --depth 1 https://github.com/JerzySukiennik/mark-zero-godot.git $Repo 2>&1 | Out-Null
    Ok "Game downloaded"
} else {
    # No git: take the zip GitHub serves for the branch. Updating later still works, it
    # just re-downloads rather than pulling.
    Warn "git is not installed - taking a snapshot instead"
    $zip = Join-Path $env:TEMP 'mark-zero.zip'
    Invoke-WebRequest -Uri 'https://github.com/JerzySukiennik/mark-zero-godot/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
    if (Test-Path $Repo) { Remove-Item $Repo -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $Root -Force
    Rename-Item (Join-Path $Root 'mark-zero-godot-main') 'mark-zero-godot'
    Remove-Item $zip -Force
    Ok "Game downloaded"
}

$Project = Join-Path $Repo 'game'
if (-not (Test-Path (Join-Path $Project 'project.godot'))) { throw "project.godot missing from $Project" }

# ---- 3. the first import ----------------------------------------------------------------
# The six suit models must be imported before they appear. Scene importers do NOT run under
# --headless: measured on the Mac, it reports no error at all and simply leaves the models
# marked invalid. So this opens the real editor briefly and lets it finish the job.
$imported = Join-Path $Project '.godot\imported'
$done = (Test-Path $imported) -and (Get-ChildItem $imported -Filter '*.scn' -ErrorAction SilentlyContinue)
if ($done) {
    Ok "Suits already imported"
} else {
    Say "Importing the suits - a window will open and close itself, give it a minute"
    & $GodotExe --editor --path $Project --quit-after 4000 2>&1 | Out-Null
    if ((Test-Path $imported) -and (Get-ChildItem $imported -Filter '*.scn' -ErrorAction SilentlyContinue)) {
        Ok "Suits imported"
    } else {
        Warn "They did not import on their own. Open the editor once by hand:"
        Warn "  & `"$GodotExe`" --editor --path `"$Project`""
    }
}

# ---- 4. something to double-click --------------------------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
$shell = New-Object -ComObject WScript.Shell
foreach ($s in @(
    @{ n = 'Mark Zero.lnk';        a = "--path `"$Project`"";           d = 'Play Mark Zero' },
    @{ n = 'Mark Zero (edit).lnk'; a = "--editor --path `"$Project`""; d = 'Open Mark Zero in Godot' }
)) {
    $lnk = $shell.CreateShortcut((Join-Path $desktop $s.n))
    $lnk.TargetPath = $GodotExe
    $lnk.Arguments = $s.a
    $lnk.WorkingDirectory = $Project
    $lnk.Description = $s.d
    $lnk.Save()
}
Ok "Two shortcuts on the desktop: play, and edit"

Write-Host ""
Write-Host "  Done. Plug the controller in and double-click 'Mark Zero'." -ForegroundColor White
Write-Host "  Controller only - there is no keyboard control." -ForegroundColor DarkGray
Write-Host "  Run this again any time to get the newest version." -ForegroundColor DarkGray
Write-Host ""
