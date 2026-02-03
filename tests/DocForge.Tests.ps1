#requires -Modules Pester
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'DocForge (E2E build smoke tests)' {

BeforeAll {
    # RepoRoot aus der Testdatei ableiten: tests\.. = RepoRoot
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

    $script:RepoRoot    = $repoRoot
    $script:BuildScript = Join-Path $script:RepoRoot 'build\build-docs.ps1'
    $script:OutRoot     = Join-Path $script:RepoRoot 'docs\out'
    $script:PackagesDir = Join-Path $script:OutRoot 'packages'

    function script:Invoke-Build([hashtable]$Params)
    {
      & $script:BuildScript @Params
    }

    function script:Read-Text([string]$Path)
    {
      Get-Content -Path $Path -Raw -Encoding UTF8
    }

    Write-Host "RepoRoot (BeforeAll):    $script:RepoRoot"
    Write-Host "BuildScript (BeforeAll): $script:BuildScript"

    if (-not (Test-Path $script:BuildScript))
    {
      throw "build-docs.ps1 not found at: $script:BuildScript"
    }
  }

  BeforeEach {
    if (Test-Path $script:OutRoot) {
      Remove-Item $script:OutRoot -Recurse -Force
    }
  }

  It 'runs -ListWorkbooks without error' {
    { Invoke-Build @{ ListWorkbooks = $true } } | Should -Not -Throw
  }

  It 'runs -All and produces landing page + assets' {
    { Invoke-Build @{ All = $true } } | Should -Not -Throw

    (Test-Path (Join-Path $script:OutRoot 'index.html')) | Should -BeTrue
    (Test-Path (Join-Path $script:OutRoot 'assets\prism.css')) | Should -BeTrue
    (Test-Path (Join-Path $script:OutRoot 'assets\docforge.css')) | Should -BeTrue
    (Test-Path (Join-Path $script:OutRoot 'assets\prism.js')) | Should -BeTrue
    (Test-Path (Join-Path $script:OutRoot 'assets\docforge.js')) | Should -BeTrue
  }

  It 'landing page references assets via ./assets (not ../assets)' {
    Invoke-Build @{ All = $true }

    $landing = Join-Path $script:OutRoot 'index.html'
    $html = Read-Text $landing

    $html | Should -Match 'href="\./assets/prism\.css"'
    $html | Should -Match 'href="\./assets/docforge\.css"'
    $html | Should -Match 'src="\./assets/docforge\.js"'
  }

  It 'each workbook index references shared assets via ../assets' {
    Invoke-Build @{ All = $true }

    $workbookDirs = Get-ChildItem -Path $script:OutRoot -Directory |
      Where-Object { $_.Name -notin @('assets','images','packages') }

    $workbookDirs.Count | Should -BeGreaterThan 0 -Because "expected at least one workbook output folder"

    foreach ($d in $workbookDirs) {
      $index = Join-Path $d.FullName 'index.html'
      Test-Path $index | Should -BeTrue -Because "workbook index.html should exist: $index"

      $html = Read-Text $index
      $html | Should -Match 'href="\.\./assets/prism\.css"'
      $html | Should -Match 'href="\.\./assets/docforge\.css"'
      $html | Should -Match 'src="\.\./assets/prism\.js"'
      $html | Should -Match 'src="\.\./assets/docforge\.js"'
    }
  }

  It '-All -Package creates at least one zip and zip contains assets' {
    Invoke-Build @{ All = $true ; Package = $true }

    Test-Path $script:PackagesDir | Should -BeTrue
    $zips = Get-ChildItem -Path $script:PackagesDir -Filter *.zip -ErrorAction SilentlyContinue
    $zips.Count | Should -BeGreaterThan 0

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = $zips | Select-Object -First 1
    $z = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
    try {
      $entries = $z.Entries | ForEach-Object FullName

      # package must contain assets folder
      ($entries | Where-Object { $_ -like "*/assets/*" }).Count | Should -BeGreaterThan 0

      # package must contain a workbook folder with index.html (supports ../assets layout)
      ($entries | Where-Object { $_ -match '.+/[^/]+/index\.html$' }).Count | Should -BeGreaterThan 0
    }
    finally {
      $z.Dispose()
    }
  }
}
