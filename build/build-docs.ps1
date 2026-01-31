# DocForge - build-docs.ps1
# Generates docs/out/index.html from docs/source/docs.xlsx (sheet: Content)

param(
  [string]$Workbook,
  [switch]$ListWorkbooks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$DefaultWorkbookName = 'docs.xlsx'
$OutDir     = Join-Path $RepoRoot 'docs\out'
$OutFile    = Join-Path $OutDir   'index.html'

$SourceDir = Join-Path $RepoRoot 'docs\source'

$workbooks = Get-ChildItem $SourceDir -Filter *.xlsx |
  Where-Object { $_.Name -notmatch '_dev' }

if ($ListWorkbooks) {
  $workbooks | ForEach-Object { Write-Host $_.Name }
  exit 0
}

# Selection
$selected = $null

if ($Workbook) {
  $selected = $workbooks | Where-Object { $_.Name -ieq $Workbook } | Select-Object -First 1
  if (-not $selected) {
    $available = ($workbooks | ForEach-Object Name) -join ', '
    throw "Workbook not found: $Workbook. Available: $available"
  }
} else {
  $selected = $workbooks |
    Where-Object { $_.Name -ieq $DefaultWorkbookName } |
    Select-Object -First 1

  if (-not $selected) {
    $available = ($workbooks | ForEach-Object Name) -join ', '
    throw "Default workbook '$DefaultWorkbookName' not found in $SourceDir. Available: $available"
  }
}

$SourceXlsx = $selected.FullName

Write-Host ("Using workbook: {0}" -f $selected.Name) -ForegroundColor DarkGray


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

# --- Preconditions ---
if (-not (Test-Path $SourceXlsx)) {
  throw "Source workbook not found: $SourceXlsx"
}

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
  Write-Host "Module 'ImportExcel' not found. Installing for CurrentUser..." -ForegroundColor Yellow
  Install-Module ImportExcel -Scope CurrentUser -Force
}

Import-Module ImportExcel

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

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
  throw "No usable rows (need Chapter, Section, Type)."
}

# Group: Chapter -> Section -> Items
$chapters = $items |
  Sort-Object Chapter, Section, Order |
  Group-Object Chapter

# --- Build TOC model + stable ids ---
$idCounts = @{} # slugKey -> count
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
    # include chapter name to avoid collisions across chapters
    $secId = NextId 'sec' ($ch.Name + '-' + $sec.Name)
    $collapsed = (($sec.Group | Sort-Object Order | Select-Object -First 1).Collapsed)

    $secs += [pscustomobject]@{
      Name      = $sec.Name
      Id        = $secId
      Collapsed = $collapsed
    }
  }

  $toc += [pscustomobject]@{
    Name     = $ch.Name
    Id       = $chId
    Sections = $secs
  }
}

# --- Minimal theme preload (prevents flash) ---
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
[void]$sb.AppendLine('<title>DocForge</title>')

# Assets (single-out: docs/out/index.html -> ../assets/...)
[void]$sb.AppendLine('<link rel="stylesheet" href="../assets/prism.css" />')
[void]$sb.AppendLine('<link rel="stylesheet" href="../assets/docforge.css" />')
[void]$sb.AppendLine($themeBootstrap)

[void]$sb.AppendLine('</head><body>')

# Header (mit Toggle-Button)
[void]$sb.AppendLine('<header class="df-header">')
[void]$sb.AppendLine('  <div class="df-header__inner">')
[void]$sb.AppendLine('    <div>')
[void]$sb.AppendLine('      <h1 class="df-title">DocForge</h1>')
[void]$sb.AppendLine(('      <p class="df-meta">Generated: {0}</p>' -f (Get-Date)))
[void]$sb.AppendLine('    </div>')
[void]$sb.AppendLine('    <button class="df-theme-toggle" id="themeToggle" type="button">Toggle theme</button>')
[void]$sb.AppendLine('  </div>')
[void]$sb.AppendLine('</header>')

# Layout: Sidebar + Content
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
          $src = HtmlEncode $it.Body.Trim()
          [void]$sb.AppendLine(("<p class=""df-p""><img class=""df-img"" src=""{0}"" alt=""{1}"" /></p>" -f $src, (HtmlEncode $sectionName)))
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

[void]$sb.AppendLine('</main>')   # df-content
[void]$sb.AppendLine('</div>')    # df-layout

# Scripts
[void]$sb.AppendLine('<script src="../assets/prism.js"></script>')
[void]$sb.AppendLine('<script src="../assets/docforge.js"></script>')
[void]$sb.AppendLine('</body></html>')

$sb.ToString() | Set-Content -Path $OutFile -Encoding UTF8
Write-Host "Generated: $OutFile" -ForegroundColor Green
