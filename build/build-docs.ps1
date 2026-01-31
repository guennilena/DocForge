# DocForge - build-docs.ps1
# Multi-output build:
# - docs/source/*.xlsx (sheet: Content) -> docs/out/<workbook>/index.html
# - shared assets -> docs/out/assets/
# - shared images -> docs/out/images/   (from docs/source/images/)
# - optional landing page -> docs/out/index.html
# - optional packaging -> docs/out/packages/<workbook>.zip

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [string]$Workbook,       # Build a specific workbook, e.g. docs.xlsx
  [switch]$All,            # Build all publishable workbooks
  [switch]$ListWorkbooks,  # List publishable workbooks and exit
  [switch]$Package         # Create a zip package per built workbook
)

# ---- Defaults / Paths (config block) ----
$DefaultWorkbookName = 'docs.xlsx'

$RepoRoot        = Split-Path -Parent $PSScriptRoot
$SourceDir       = Join-Path $RepoRoot 'docs\source'
$SourceImagesDir = Join-Path $SourceDir 'images'

$OutRoot      = Join-Path $RepoRoot 'docs\out'
$OutAssetsDir = Join-Path $OutRoot 'assets'
$OutImagesDir = Join-Path $OutRoot 'images'
$OutPackages  = Join-Path $OutRoot 'packages'
$LandingFile  = Join-Path $OutRoot 'index.html'

# ---- Helpers ----
function HtmlEncode([string]$s) {
  if ($null -eq $s) { return '' }
  return [System.Net.WebUtility]::HtmlEncode($s)
}

function ToBool($v) {
  if ($null -eq $v) { return $false }
  $t = ($v.ToString().Trim().ToLowerInvariant())
  return @('1','true','yes','y','ja').Contains($t)
}

function Slugify([string]$s) {
  if ($null -eq $s) { return 'x' }
  $t = $s.Trim().ToLowerInvariant()
  $t = $t -replace 'ä','ae' -replace 'ö','oe' -replace 'ü','ue' -replace 'ß','ss'
  $t = ($t -replace '[^a-z0-9]+','-').Trim('-')
  if ([string]::IsNullOrWhiteSpace($t)) { $t = 'x' }
  return $t
}

function Ensure-Dir([string]$p) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function Get-PublishableWorkbooks {
  if (-not (Test-Path $SourceDir)) { throw "Source directory not found: $SourceDir" }

  $wbs = Get-ChildItem -Path $SourceDir -File -Filter '*.xlsx' |
    Where-Object { $_.Name -notlike '~$*' } |
    Where-Object { $_.Name -notmatch '_dev' } |
    Sort-Object Name

  return @($wbs)
}

function Copy-SharedAssets {
  # Copies docs/assets/* -> docs/out/assets/*
  $assetsSrc = Join-Path $RepoRoot 'docs\assets'
  if (-not (Test-Path $assetsSrc)) { throw "Assets directory not found: $assetsSrc" }

  Ensure-Dir $OutAssetsDir
  Copy-Item -Path (Join-Path $assetsSrc '*') -Destination $OutAssetsDir -Recurse -Force
}

function Copy-ImagesUsedByWorkbook($items) {
  # Copies referenced image files from docs/source/images -> docs/out/images (shared)
  $imageItems = $items | Where-Object { $_.Type -eq 'image' -and -not [string]::IsNullOrWhiteSpace($_.Body) }
  if (-not $imageItems -or $imageItems.Count -eq 0) { return }

  Ensure-Dir $OutImagesDir

  foreach ($it in $imageItems) {
    $name = $it.Body.ToString().Trim()

    # No subfolders expected: reject path separators to keep convention strict.
    if ($name -match '[\\/]' ) {
      throw "Invalid image name '$name'. Convention: Body must be a filename only (no subfolders)."
    }

    $src = Join-Path $SourceImagesDir $name
    if (-not (Test-Path $src)) {
      throw "Image not found: $src (referenced in workbook)."
    }

    $dst = Join-Path $OutImagesDir $name
    Copy-Item -Path $src -Destination $dst -Force
  }
}

function Write-LandingPage($builtWorkbooks) {
  # Minimal landing page linking to each workbook folder.
  Ensure-Dir $OutRoot

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<!DOCTYPE html>')
  [void]$sb.AppendLine('<html><head><meta charset="utf-8" />')
  [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1" />')
  [void]$sb.AppendLine('<title>DocForge - Index</title>')
  [void]$sb.AppendLine('<link rel="stylesheet" href="./assets/prism.css" />')
  [void]$sb.AppendLine('<link rel="stylesheet" href="./assets/docforge.css" />')
  [void]$sb.AppendLine(@"
<script>
(function(){
  try {
    var t = localStorage.getItem('docforge.theme');
    if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
    else {
      var d = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      document.documentElement.dataset.theme = d ? 'dark' : 'light';
    }
  } catch(e) {}
})();
</script>
"@)
  [void]$sb.AppendLine('</head><body>')

  [void]$sb.AppendLine('<header class="df-header"><div class="df-header__inner">')
  [void]$sb.AppendLine('<div>')
  [void]$sb.AppendLine('<h1 class="df-title">DocForge</h1>')
  [void]$sb.AppendLine(('<p class="df-meta">Generated: {0}</p>' -f (Get-Date)))
  [void]$sb.AppendLine('</div>')
  [void]$sb.AppendLine('<button class="df-theme-toggle" id="themeToggle" type="button">Toggle theme</button>')
  [void]$sb.AppendLine('</div></header>')

  [void]$sb.AppendLine('<div class="df-layout">')
  [void]$sb.AppendLine('<main class="df-content">')
  [void]$sb.AppendLine('<h2 class="df-h2">Workbooks</h2>')
  [void]$sb.AppendLine('<ul class="df-toc">')

  foreach ($wb in $builtWorkbooks) {
    $base = $wb.BaseName
    [void]$sb.AppendLine(('<li class="df-toc__ch"><a href="./{0}/">{1}</a></li>' -f (HtmlEncode $base), (HtmlEncode $wb.Name)))
  }

  [void]$sb.AppendLine('</ul>')
  [void]$sb.AppendLine('</main></div>')

  [void]$sb.AppendLine('<script src="./assets/docforge.js"></script>')
  [void]$sb.AppendLine('</body></html>')

  $sb.ToString() | Set-Content -Path $LandingFile -Encoding UTF8
  Write-Host "Generated landing: $LandingFile" -ForegroundColor Green
}

function Package-Workbook([System.IO.DirectoryInfo]$WorkbookOutDir, [System.IO.FileInfo]$WorkbookFile) {
  # Create a portable zip that contains:
  # <base>/
  #   index.html
  #   assets/
  #   images/
  Ensure-Dir $OutPackages

  $base = $WorkbookFile.BaseName
  $zipPath = Join-Path $OutPackages ("{0}.zip" -f $base)

  $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("docforge-pack-{0}-{1}" -f $base, ([Guid]::NewGuid().ToString('N')))
  Ensure-Dir $temp

  $root = Join-Path $temp $base
  Ensure-Dir $root

  # Copy workbook output
  Copy-Item -Path (Join-Path $WorkbookOutDir.FullName '*') -Destination $root -Recurse -Force

  # Copy shared assets + images into the package root
  if (Test-Path $OutAssetsDir) { Copy-Item -Path $OutAssetsDir -Destination $root -Recurse -Force }
  if (Test-Path $OutImagesDir) { Copy-Item -Path $OutImagesDir -Destination $root -Recurse -Force }

  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zipPath

  Remove-Item $temp -Recurse -Force

  Write-Host "Packaged: $zipPath" -ForegroundColor Green
}

# ---- Preconditions (ImportExcel) ----
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
  Write-Host "Module 'ImportExcel' not found. Installing for CurrentUser..." -ForegroundColor Yellow
  Install-Module ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

# ---- Workbook selection ----
$workbooks = Get-PublishableWorkbooks

if ($ListWorkbooks) {
  if ($workbooks.Count -eq 0) {
    Write-Host "No publishable workbooks found in: $SourceDir" -ForegroundColor Yellow
    Write-Host "Hint: workbooks containing '_dev' are ignored by convention." -ForegroundColor DarkGray
    exit 0
  }

  Write-Host "Publishable workbooks:" -ForegroundColor Cyan
  $workbooks | ForEach-Object { Write-Host (" - {0}" -f $_.Name) }
  exit 0
}

if ($workbooks.Count -eq 0) {
  throw "No publishable workbooks found in: $SourceDir"
}

$toBuild = @()

if ($All) {
  $toBuild = $workbooks
} elseif ($Workbook) {
  $sel = $workbooks | Where-Object { $_.Name -ieq $Workbook } | Select-Object -First 1
  if (-not $sel) {
    $available = ($workbooks | ForEach-Object Name) -join ', '
    throw "Workbook not found: $Workbook. Available: $available"
  }
  $toBuild = @($sel)
} else {
  $sel = $workbooks | Where-Object { $_.Name -ieq $DefaultWorkbookName } | Select-Object -First 1
  if (-not $sel) {
    $available = ($workbooks | ForEach-Object Name) -join ', '
    throw "Default workbook '$DefaultWorkbookName' not found in $SourceDir. Available: $available"
  }
  $toBuild = @($sel)
}

# Ensure output dirs
Ensure-Dir $OutRoot
Copy-SharedAssets

$built = @()

function Build-OneWorkbook([System.IO.FileInfo]$Xlsx) {
  Write-Host ("Using workbook: {0}" -f $Xlsx.Name) -ForegroundColor DarkGray

  $SourceXlsx = $Xlsx.FullName
  if (-not (Test-Path $SourceXlsx)) { throw "Source workbook not found: $SourceXlsx" }

  $wbOutDir = Join-Path $OutRoot $Xlsx.BaseName
  Ensure-Dir $wbOutDir
  $OutFile = Join-Path $wbOutDir 'index.html'

  # --- Load content ---
  $rows = Import-Excel -Path $SourceXlsx -WorksheetName 'Content'
  if (-not $rows -or $rows.Count -eq 0) {
    throw "No rows found in worksheet 'Content' in $SourceXlsx"
  }

  # Normalize + validate minimal fields
  $items = foreach ($r in $rows) {
    if ([string]::IsNullOrWhiteSpace($r.Chapter) -or
        [string]::IsNullOrWhiteSpace($r.Section) -or
        [string]::IsNullOrWhiteSpace($r.Type)) { continue }

    [pscustomobject]@{
      Chapter   = $r.Chapter.ToString().Trim()
      Section   = $r.Section.ToString().Trim()
      Order     = if ($r.Order) { [int]$r.Order } else { 0 }
      Type      = $r.Type.ToString().Trim().ToLowerInvariant()
      Lang      = if ($r.Lang) { $r.Lang.ToString().Trim().ToLowerInvariant() } else { '' }
      Body      = if ($r.Body) { $r.Body.ToString() } else { '' }
      Collapsed = ToBool $r.Collapsed
    }
  }

  if ($items.Count -eq 0) {
    throw "No usable rows (need Chapter, Section, Type) in $SourceXlsx."
  }

  # Copy referenced images (shared)
  Copy-ImagesUsedByWorkbook $items

  # Group: Chapter -> Section -> Items
  $chapters = $items | Sort-Object Chapter, Section, Order | Group-Object Chapter

  # --- Build TOC model + stable ids ---
  $idCounts = @{}
  function NextId([string]$prefix, [string]$name) {
    $slug = Slugify $name
    $key  = "$prefix-$slug"
    if (-not $idCounts.ContainsKey($key)) { $idCounts[$key] = 1; return $key }
    $idCounts[$key]++
    return "$key-$($idCounts[$key])"
  }

  $toc = @()
  foreach ($ch in $chapters) {
    $chId = NextId 'ch' $ch.Name
    $secGroups = $ch.Group | Group-Object Section
    $secs = @()
    foreach ($sec in ($secGroups | Sort-Object Name)) {
      $secId = NextId 'sec' ($ch.Name + '-' + $sec.Name)
      $collapsed = (($sec.Group | Sort-Object Order | Select-Object -First 1).Collapsed)
      $secs += [pscustomobject]@{ Name = $sec.Name; Id = $secId; Collapsed = $collapsed }
    }
    $toc += [pscustomobject]@{ Name = $ch.Name; Id = $chId; Sections = $secs }
  }

  # --- Theme preload (prevents flash) ---
  $themeBootstrap = @"
<script>
(function(){
  try {
    var t = localStorage.getItem('docforge.theme');
    if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
    else {
      var d = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      document.documentElement.dataset.theme = d ? 'dark' : 'light';
    }
  } catch(e) {}
})();
</script>
"@

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('<!DOCTYPE html>')
  [void]$sb.AppendLine('<html><head><meta charset="utf-8" />')
  [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1" />')
  [void]$sb.AppendLine(("<title>DocForge - {0}</title>" -f (HtmlEncode $Xlsx.BaseName)))

  # In workbook folder: link to shared assets in ../assets
  [void]$sb.AppendLine('<link rel="stylesheet" href="../assets/prism.css" />')
  [void]$sb.AppendLine('<link rel="stylesheet" href="../assets/docforge.css" />')
  [void]$sb.AppendLine($themeBootstrap)
  [void]$sb.AppendLine('</head><body>')

  # Header
  [void]$sb.AppendLine('<header class="df-header">')
  [void]$sb.AppendLine('  <div class="df-header__inner">')
  [void]$sb.AppendLine('    <div>')
  [void]$sb.AppendLine(('      <h1 class="df-title">DocForge <span style="font-weight:400; font-size:0.95rem; color:var(--muted);">({0})</span></h1>' -f (HtmlEncode $Xlsx.BaseName)))
  [void]$sb.AppendLine(('      <p class="df-meta">Generated: {0}</p>' -f (Get-Date)))
  [void]$sb.AppendLine('    </div>')
  [void]$sb.AppendLine('    <button class="df-theme-toggle" id="themeToggle" type="button">Toggle theme</button>')
  [void]$sb.AppendLine('  </div>')
  [void]$sb.AppendLine('</header>')

  # Layout
  [void]$sb.AppendLine('<div class="df-layout">')

  # Sidebar TOC
  [void]$sb.AppendLine('<aside class="df-sidebar">')
  [void]$sb.AppendLine('  <div class="df-toc-title">Contents</div>')
  [void]$sb.AppendLine('  <ul class="df-toc">')
  foreach ($ch in $toc) {
    [void]$sb.AppendLine(('    <li class="df-toc__ch"><a href="#{0}">{1}</a></li>' -f $ch.Id, (HtmlEncode $ch.Name)))
    foreach ($s in $ch.Sections) {
      [void]$sb.AppendLine(('    <li class="df-toc__sec"><a href="#{0}">{1}</a></li>' -f $s.Id, (HtmlEncode $s.Name)))
    }
  }
  [void]$sb.AppendLine('  </ul>')
  [void]$sb.AppendLine('</aside>')

  # Main content
  [void]$sb.AppendLine('<main class="df-content">')
  [void]$sb.AppendLine('<hr class="df-hr" />')

  foreach ($ch in $chapters) {
    $chapterName = $ch.Name
    $chEntry = $toc | Where-Object { $_.Name -eq $chapterName } | Select-Object -First 1
    $chId = $chEntry.Id

    [void]$sb.AppendLine(("<section id=""{0}"" class=""df-chapter"">" -f $chId))
    [void]$sb.AppendLine(("<h2 class=""df-h2"">{0}</h2>" -f (HtmlEncode $chapterName)))

    $sections = $ch.Group | Group-Object Section
    foreach ($sec in ($sections | Sort-Object Name)) {
      $sectionName = $sec.Name
      $secItems    = $sec.Group | Sort-Object Order
      $collapsed   = ($secItems | Select-Object -First 1).Collapsed

      $secEntry = ($chEntry.Sections | Where-Object { $_.Name -eq $sectionName } | Select-Object -First 1)
      $secId = $secEntry.Id

      if ($collapsed) {
        [void]$sb.AppendLine(("<details id=""{0}"" class=""df-details"">" -f $secId))
        [void]$sb.AppendLine(("<summary class=""df-summary"">{0}</summary>" -f (HtmlEncode $sectionName)))
      } else {
        [void]$sb.AppendLine(("<h3 id=""{0}"" class=""df-h3"">{1}</h3>" -f $secId, (HtmlEncode $sectionName)))
      }

      foreach ($it in $secItems) {
        switch ($it.Type) {
          'text' {
            $p = (HtmlEncode $it.Body) -replace "(\r\n|\n)", "<br/>"
            [void]$sb.AppendLine("<p class=""df-p"">$p</p>")
          }
          'note' {
            $p = (HtmlEncode $it.Body) -replace "(\r\n|\n)", "<br/>"
            [void]$sb.AppendLine("<div class=""df-note"">$p</div>")
          }
          'code' {
            $lang = if ($it.Lang) { $it.Lang } else { 'text' }
            $code = HtmlEncode $it.Body
            [void]$sb.AppendLine(("<pre class='line-numbers df-pre'><code class='language-{0}'>{1}</code></pre>" -f $lang, $code))
          }
          'image' {
            $name = HtmlEncode $it.Body.Trim()
            # Shared images: workbook index.html -> ../images/<filename>
            [void]$sb.AppendLine(("<p class=""df-p""><img class=""df-img"" src=""../images/{0}"" alt=""{1}"" /></p>" -f $name, (HtmlEncode $sectionName)))
          }
          default {
            $p = (HtmlEncode $it.Body) -replace "(\r\n|\n)", "<br/>"
            [void]$sb.AppendLine("<p class=""df-p"">$p</p>")
          }
        }
      }

      if ($collapsed) {
        [void]$sb.AppendLine('</details>')
      }
    }

    [void]$sb.AppendLine('</section>')
  }

  [void]$sb.AppendLine('</main>')
  [void]$sb.AppendLine('</div>') # df-layout

  # Scripts
  [void]$sb.AppendLine('<script src="../assets/prism.js"></script>')
  [void]$sb.AppendLine('<script src="../assets/docforge.js"></script>')
  [void]$sb.AppendLine('</body></html>')

  $sb.ToString() | Set-Content -Path $OutFile -Encoding UTF8
  Write-Host "Generated: $OutFile" -ForegroundColor Green

  return (Get-Item $wbOutDir)
}

# ---- Build ----
foreach ($wb in $toBuild) {
  $outDirInfo = Build-OneWorkbook $wb
  $built += $wb

  if ($Package) {
    Package-Workbook $outDirInfo $wb
  }
}

# Landing page makes sense when you have multiple outputs OR when -All
Write-LandingPage $built
