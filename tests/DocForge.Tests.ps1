#requires -Modules Pester

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
$BuildScript = Join-Path $RepoRoot 'build\build-docs.ps1'
$OutRoot = Join-Path $RepoRoot 'docs\out'
$SourceDir = Join-Path $RepoRoot 'docs\source'
$PackagesDir = Join-Path $OutRoot 'packages'

function Invoke-Build($args)
{
  & $BuildScript @args
}

function Read-FileText([string]$path)
{
  return Get-Content -Path $path -Raw -Encoding UTF8
}

function Assert-Contains($text, $pattern, $because)
{
  $text | Should -Match $pattern -Because $because
}

Describe 'DocForge build-docs.ps1 (E2E)' {

  BeforeAll {
    if (-not (Test-Path $BuildScript)) { throw "Build script missing: $BuildScript" }
    if (-not (Test-Path $SourceDir))   { throw "Source dir missing: $SourceDir" }
  }

  BeforeEach {
    # Clean output to ensure tests are deterministic
    if (Test-Path $OutRoot) {
      Remove-Item $OutRoot -Recurse -Force
    }
  }

  It 'builds a specific workbook without errors' {
    Invoke-Build @('-Workbook', 'docs.xlsx')

    # adjust if your single-workbook output is elsewhere
    $html = Join-Path $OutRoot 'docs\index.html'
    Test-Path $html | Should -BeTrue -Because "Workbook output HTML should exist: $html"
  }

  It 'builds all workbooks and creates a root index' {
    Invoke-Build @('-All')

    $rootIndex = Join-Path $OutRoot 'index.html'
    Test-Path $rootIndex | Should -BeTrue -Because "Root index should exist for -All"
  }

  It 'copies shared assets to out/assets' {
    Invoke-Build @('-All')

    (Test-Path (Join-Path $OutRoot 'assets\prism.css'))    | Should -BeTrue
    (Test-Path (Join-Path $OutRoot 'assets\docforge.css')) | Should -BeTrue
    (Test-Path (Join-Path $OutRoot 'assets\prism.js'))     | Should -BeTrue
    (Test-Path (Join-Path $OutRoot 'assets\docforge.js'))  | Should -BeTrue
  }

  It 'root index references assets with correct relative paths' {
    Invoke-Build @('-All')

    $rootIndex = Join-Path $OutRoot 'index.html'
    $html = Read-FileText $rootIndex

    Assert-Contains $html 'href="assets/prism\.css"'    'Root index must reference assets/ (not ../assets)'
    Assert-Contains $html 'href="assets/docforge\.css"' 'Root index must reference assets/ (not ../assets)'
    Assert-Contains $html 'src="assets/prism\.js"'      'Root index must reference assets/ (not ../assets)'
    Assert-Contains $html 'src="assets/docforge\.js"'   'Root index must reference assets/ (not ../assets)'
  }

  It 'workbook index references assets with correct relative paths' {
    Invoke-Build @('-All')

    # find first workbook folder that contains index.html (excluding assets/images/packages)
    $workbookIndex = Get-ChildItem -Path $OutRoot -Directory |
      Where-Object { $_.Name -notin @('assets','images','packages') } |
      ForEach-Object { Join-Path $_.FullName 'index.html' } |
      Where-Object { Test-Path $_ } |
      Select-Object -First 1

    $workbookIndex | Should -Not -BeNullOrEmpty -Because "Expected at least one workbook index.html under out/<wb>/index.html"

    $html = Read-FileText $workbookIndex

    Assert-Contains $html 'href="\.\./assets/prism\.css"'    'Workbook index must reference ../assets/'
    Assert-Contains $html 'href="\.\./assets/docforge\.css"' 'Workbook index must reference ../assets/'
    Assert-Contains $html 'src="\.\./assets/prism\.js"'      'Workbook index must reference ../assets/'
    Assert-Contains $html 'src="\.\./assets/docforge\.js"'   'Workbook index must reference ../assets/'
  }

  It 'package mode creates zip files' {
    Invoke-Build @('-All', '-Package')

    Test-Path $PackagesDir | Should -BeTrue -Because "Packages dir should exist for -Package"
    (Get-ChildItem $PackagesDir -Filter *.zip -ErrorAction SilentlyContinue).Count |
      Should -BeGreaterThan 0 -Because "At least one zip should be produced"
  }

  It 'zip contains index.html and assets folder' {
    Invoke-Build @('-All', '-Package')

    $zip = Get-ChildItem $PackagesDir -Filter *.zip | Select-Object -First 1
    $zip | Should -Not -BeNullOrEmpty

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
    try {
      $entries = $z.Entries.FullName
      ($entries -contains 'index.html') | Should -BeTrue -Because "Zip must contain root index.html"
      ($entries | Where-Object { $_ -like 'assets/*' }).Count | Should -BeGreaterThan 0 -Because "Zip must include assets/"
    }
    finally {
      $z.Dispose()
    }
  }
}
