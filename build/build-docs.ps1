# DocForge - build-docs.ps1
# Generates docs/out/index.html from docs/source/docs.xlsx (sheet: Content)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$SourceXlsx = Join-Path $RepoRoot 'docs\source\docs.xlsx'
$OutDir     = Join-Path $RepoRoot 'docs\out'
$OutFile    = Join-Path $OutDir   'index.html'

function HtmlEncode([string]$s) {
  if ($null -eq $s) { return '' }
  return [System.Net.WebUtility]::HtmlEncode($s)
}

function ToBool($v) {
  if ($null -eq $v) { return $false }
  $t = ($v.ToString().Trim().ToLowerInvariant())
  return @('1','true','yes','y','ja').Contains($t)
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

# --- HTML template (simple, readable) ---
$css = @"
body { font-family: Segoe UI, Arial, sans-serif; margin: 40px; max-width: 980px; line-height: 1.5; }
h1 { margin-bottom: 0.2em; }
.meta { color: #666; margin-top: 0; }
h2 { margin-top: 2em; border-bottom: 1px solid #ddd; padding-bottom: 0.2em; }
h3 { margin-top: 1.2em; }
details { margin-top: 1em; padding: 0.6em 0.8em; border: 1px solid #ddd; border-radius: 8px; background: #fafafa; }
summary { cursor: pointer; font-weight: 600; }
pre { padding: 12px; border-radius: 8px; overflow-x: auto; background: #f4f4f4; border: 1px solid #e5e5e5; }
code { font-family: Consolas, 'Cascadia Mono', monospace; font-size: 0.95em; }
.note { padding: 10px 12px; border-left: 4px solid #999; background: #f7f7f7; border-radius: 6px; }
img { max-width: 100%; border: 1px solid #ddd; border-radius: 8px; }
hr { border: none; border-top: 1px solid #eee; margin: 24px 0; }
"@

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html><head><meta charset="utf-8" />')
[void]$sb.AppendLine('<link rel="stylesheet" href="../assets/prism.css" />')
[void]$sb.AppendLine('<link rel="stylesheet" href="../assets/docforge.css" />')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1" />')
[void]$sb.AppendLine('<title>DocForge</title>')
[void]$sb.AppendLine("<style>$css</style>")
[void]$sb.AppendLine('</head><body>')
[void]$sb.AppendLine('<h1>DocForge</h1>')
[void]$sb.AppendLine(('<p class="meta">Generated: {0}</p>' -f (Get-Date)))
[void]$sb.AppendLine('<hr />')

foreach ($ch in $chapters) {
  $chapterName = $ch.Name
  [void]$sb.AppendLine(("<h2>{0}</h2>" -f (HtmlEncode $chapterName)))

  $sections = $ch.Group | Group-Object Section
  foreach ($sec in ($sections | Sort-Object Name)) {
    $sectionName = $sec.Name
    $secItems    = $sec.Group | Sort-Object Order
    $collapsed   = ($secItems | Select-Object -First 1).Collapsed

    if ($collapsed) {
      [void]$sb.AppendLine('<details>')
      [void]$sb.AppendLine(("<summary>{0}</summary>" -f (HtmlEncode $sectionName)))
    } else {
      [void]$sb.AppendLine(("<h3>{0}</h3>" -f (HtmlEncode $sectionName)))
    }

    foreach ($it in $secItems) {
      switch ($it.Type) {
        'text' {
          $p = (HtmlEncode $it.Body) -replace "(\r\n|\n)", "<br/>"
          [void]$sb.AppendLine("<p>$p</p>")
        }
        'note' {
          $p = (HtmlEncode $it.Body) -replace "(\r\n|\n)", "<br/>"
          [void]$sb.AppendLine("<div class=""note"">$p</div>")
        }
        'code' {
          $lang = if ($it.Lang) { $it.Lang } else { 'text' }
          $code = HtmlEncode $it.Body
          [void]$sb.AppendLine(("<pre class='line-numbers'><code class='language-{0}'>{1}</code></pre>" -f $lang, $code))
        }
        'image' {
          # Body should be a relative path from docs/out, e.g. "../images/foo.png" or "images/foo.png"
          $src = HtmlEncode $it.Body.Trim()
          [void]$sb.AppendLine(("<p><img src=""{0}"" alt=""{1}"" /></p>" -f $src, (HtmlEncode $sectionName)))
        }
        default {
          $p = (HtmlEncode $it.Body) -replace "(\r\n|\n)", "<br/>"
          [void]$sb.AppendLine("<p>$p</p>")
        }
      }
    }

    if ($collapsed) {
      [void]$sb.AppendLine('</details>')
    }
  }
}

[void]$sb.AppendLine('<script src="../assets/prism.js"></script>')
[void]$sb.AppendLine('</body></html>')

$sb.ToString() | Set-Content -Path $OutFile -Encoding UTF8
Write-Host "Generated: $OutFile" -ForegroundColor Green
