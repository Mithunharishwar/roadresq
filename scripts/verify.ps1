# Reproduce the CI checks locally: static analysis, backend tests, function syntax.
# Mirrors .github/workflows/ci.yml - run this before pushing.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host '==> flutter analyze'
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> backend tests'
Push-Location backend
$venvPython = Join-Path (Get-Location) '.venv\Scripts\python.exe'
if (Test-Path $venvPython) { & $venvPython -m pytest tests -q } else { python -m pytest tests -q }
$pytestExit = $LASTEXITCODE
Pop-Location
if ($pytestExit -ne 0) { exit $pytestExit }

Write-Host '==> cloud functions syntax'
Push-Location functions
$checkExit = 0
Get-ChildItem -Filter *.js | ForEach-Object {
    node --check $_.Name
    if ($LASTEXITCODE -ne 0) { $checkExit = $LASTEXITCODE }
}
Pop-Location
if ($checkExit -ne 0) { exit $checkExit }

Write-Host 'All checks passed.'
