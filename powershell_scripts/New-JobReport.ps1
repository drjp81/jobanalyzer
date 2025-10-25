<#
.SYNOPSIS
    Generates an HTML job report from a CSV file containing job listings with company information, descriptions, and evaluation metrics.

.DESCRIPTION
    This script processes a CSV file with job listings and generates a comprehensive HTML report featuring:
    - Executive summary with statistics (total jobs, average score, top companies, language distribution)
    - Paginated job cards with company logos, job details, and evaluation metrics
    - Print-friendly formatting with page breaks
    - Interactive navigation controls for browsing job listings
    - Markdown-to-HTML conversion for job descriptions
    - Automatic fallback to SVG logos with company initials when logo images are unavailable
    
    The script expects a CSV with the following default columns (case-insensitive):
    company, company_logo, title, job_url, description, score, why, gaps, seniority, lang, location
    
    Column names can be customized using the -ColumnMap parameter.

.PARAMETER CsvPath
    Mandatory. The path to the input CSV file containing job listings.

.PARAMETER OutputHtmlPath
    Mandatory. The path where the generated HTML report will be saved.

.PARAMETER PageSize
    Optional. The number of job cards to display per page in the report. Default is 10.

.PARAMETER DefaultLogoPath
    Optional. The default logo image path to use when a job listing doesn't specify a company logo.

.PARAMETER ColumnMap
    Optional. A hashtable to map custom CSV column names to the expected field names.
    Example: @{ company = 'CompanyName'; title = 'JobTitle'; score = 'MatchScore' }
    
    Supported mapping keys:
    - company: Company name
    - company_logo: Path or URL to company logo
    - title: Job title
    - job_url: URL to the job posting
    - description: Job description (supports Markdown)
    - score: Numerical match/relevance score
    - why: Reason for match/recommendation
    - gaps: Identified skill or experience gaps
    - seniority: Job seniority level
    - lang: Programming language or primary language requirement
    - location: Job location

.EXAMPLE
    .\New-JobReport.ps1 -CsvPath "jobs.csv" -OutputHtmlPath "report.html"
    
    Generates a job report from jobs.csv and saves it to report.html with default settings.

.EXAMPLE
    .\New-JobReport.ps1 -CsvPath "jobs.csv" -OutputHtmlPath "report.html" -PageSize 20
    
    Generates a job report with 20 jobs displayed per page.

.EXAMPLE
    .\New-JobReport.ps1 -CsvPath "jobs.csv" -OutputHtmlPath "report.html" -DefaultLogoPath "default-logo.png"
    
    Generates a job report using default-logo.png when job listings don't have a company logo.

.EXAMPLE
    $mapping = @{ company = 'CompanyName'; title = 'Position'; score = 'MatchScore' }
    .\New-JobReport.ps1 -CsvPath "jobs.csv" -OutputHtmlPath "report.html" -ColumnMap $mapping
    
    Generates a job report with custom column mapping for a CSV with different header names.

.NOTES
    File Name      : New-JobReport.ps1
    Author         : Jean-Paul Lizotte
    Created        : 2024-10-24
    Version        : 0.0.1
    Prerequisite   : PowerShell 5.1 or higher, CSV file with job listing data
    
    The script includes helper functions for:
    - HTML escaping and sanitization
    - Markdown-to-HTML conversion (headings, bold, italic, links, lists, code blocks)
    - Dynamic SVG logo generation with company initials
    - Image embedding as base64 data URIs
    
    The generated report is responsive and includes both screen and print stylesheets.

.INPUTS
    CSV file with job listing data

.OUTPUTS
    HTML file with formatted job report
#>

<#
The script below assumes a fixed CSV schema with these exact headers (case-insensitive):
company, company_logo, title, job_url, description, score, why, gaps, seniority, lang

It generates:
An Executive Summary section
Detailed paginated section: cards per job with company logo, company name, job title (linked to job URL), markdown > HTML description, and evaluation fields score, why, gaps, seniority, lang. (Prev/Next + jump-to).
Markdown > HTML for description.
Company logo (falls back to an inline SVG with initials if empty/broken).
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputHtmlPath,

    [int]$PageSize = 10,

    [string]$DefaultLogoPath = $null,

    [hashtable]$ColumnMap = @{}
)

# Script body starts here
# Validate CSV file exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}


Write-Host "Generating job report from: $CsvPath"
Write-Host "Output will be saved to: $OutputHtmlPath"


# -- Helpers --------------------------------------------------------------

function Get-FieldValue {
    param($row, $fieldName)
    if ($null -eq $row) { return "" }
    $prop = $row.psobject.Properties | Where-Object { $_.Name -ieq $fieldName } | Select-Object -First 1
    if ($prop) { return $prop.Value }
    return ""
}

function HtmlEscape([string]$s) {
    if ($null -eq $s) { return "" }
    $s = [string]$s
    $s = $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;').Replace("'",'&#39;')
    return $s
}

function Simple-MarkdownToHtml {
    param([string]$md)

    if ($null -eq $md) { return "" }
    $html = [string]$md

    # Escape HTML first
    $html = HtmlEscape $html

    # Normalize line endings and collapse multiple blank lines
    $html = $html -replace "`r`n", "`n"
    $html = $html -replace "`r", "`n"
    $html = [regex]::Replace($html, "`n{3,}", "`n`n")  # Collapse 3+ newlines to 2

    # clean the funky double backslashes that appear in some CSV exports
    $html = $html.replace("\\", "")


    # Code fences ``` -> <pre><code>
    $html = [regex]::Replace($html, '(?ms)```(.*?)```', { "<pre><code>$($args[0].Groups[1].Value)</code></pre>" })

    # Inline code `code`
    $html = [regex]::Replace($html, '`([^`\r\n]+)`', "<code>`$1</code>")

    # Headings (#, ##, ###)
    $html = [regex]::Replace($html, "(?m)^(#{1,6})\s*(.+)$", { param($m) "<h$($m.Groups[1].Value.Length)>$($m.Groups[2].Value)</h$($m.Groups[1].Value.Length)>" })

    # Bold **text**
    $html = [regex]::Replace($html, "\*\*(.+?)\*\*", "<strong>`$1</strong>")

    # Italic *text*
    $html = [regex]::Replace($html, "(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)", "<em>`$1</em>")

    # Links [text](url)
    $html = [regex]::Replace($html, "\[([^\]]+)\]\(([^)]+)\)", "<a href='`$2' target='_blank' rel='noopener'>`$1</a>")

    # Unordered lists: lines starting with - or *
    $lines = $html -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $inList = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*[-\*]\s+(.*)') {
            if (-not $inList) { $out.Add("<ul>"); $inList = $true }
            $out.Add("<li>$($Matches[1])</li>")
        } else {
            if ($inList) { $out.Add("</ul>"); $inList = $false }
            if ($line -match '^\s*$') { 
                $out.Add("<br/>")
            } else { 
                $out.Add("<p>$line</p>")
            }
        }
    }
    if ($inList) { $out.Add("</ul>") }
    $html = [string]::Join("`n",$out)
    $html = $html -replace "(<br/>\s*){2,}", "<br/>"  # Collapse multiple <br/>
    #if a paragraph is empty, remove it
    $html = $html -replace "<p>\s*</p>", ""
    #if a paragraph is followed by a <br/>, remove the <br/>
    $html = $html -replace "<p>(.*?)</p>\s*<br/>", "<p>$1</p>"

    return $html
}

function Get-LogoHtml {
    param([string]$company, [string]$logoPath)
    #if the logopath is an URL, return an img tag with that URL
    if ($logoPath -and $logoPath.Trim().Length -gt 0 -and $logoPath.StartsWith("http")) {
        return "<img class='company-logo' src='$logoPath' alt='${company} logo' />"
    }

    # If logo path provided and exists, embed as data URI
    if ($logoPath -and $logoPath.Trim().Length -gt 0 -and (Test-Path $logoPath)) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $logoPath))
            $ext = [System.IO.Path]::GetExtension($logoPath).ToLowerInvariant().TrimStart('.')
            $mime = switch ($ext) {
                'png' { 'image/png' }
                'jpg' { 'image/jpeg' }
                'jpeg' { 'image/jpeg' }
                'gif' { 'image/gif' }
                'svg' { 'image/svg+xml' }
                default { 'application/octet-stream' }
            }
            $b64 = [System.Convert]::ToBase64String($bytes)
            return "<img class='company-logo' src='data:$mime;base64,$b64' alt='${company} logo' />"
        } catch {
            # fallthrough to SVG fallback
        }
    }

    # Inline SVG fallback with initials
    if (-not $company -or $company.Trim().Length -eq 0) { $company = "?" }
    $words = ($company -split '\s+') | Where-Object { $_ -ne "" }
    if ($words.Count -ge 2) {
        $initials = ($words[0][0] + $words[1][0]).ToUpper()
    } elseif ($company.Length -gt 0) {
        $initials = $company.Substring(0, [Math]::Min(2, $company.Length)).ToUpper()
    } else {
        $initials = "?"
    }

    # Choose a deterministic color from company name
    $hash = 0
    foreach ($ch in $company.ToCharArray()) { $hash = (($hash * 33) + [int]$ch) -band 0x7FFFFFFF }
    $colors = @("#6C5CE7","#00B894","#0984E3","#FD79A8","#FF7675","#55E6C1","#FAB1A0","#74B9FF")
    $color = $colors[$hash % $colors.Count]

    $svg = "<svg class='company-logo' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100' role='img' aria-label='${company}'>
  <rect width='100' height='100' fill='$color'/>
  <text x='50' y='55' font-size='42' font-family='Helvetica, Arial, sans-serif' fill='white' text-anchor='middle' dominant-baseline='middle'>$initials</text>
</svg>"

    return $svg
}

# -- Prepare column mapping ------------------------------------------------
$defaults = @{
    company = 'company'
    company_logo = 'company_logo'
    title = 'title'
    job_url = 'job_url'
    description = 'description'
    score = 'score'
    why = 'why'
    gaps = 'gaps'
    seniority = 'seniority'
    lang = 'lang'
    location = 'location'  # Add location field
}

# Apply ColumnMap overrides (case-insensitive keys accepted)
foreach ($k in $defaults.Keys) {
    if ($ColumnMap.ContainsKey($k)) {
        $defaults[$k] = $ColumnMap[$k]
    } else {
        # allow user to specify case-insensitive keys e.g. "Company"
        $match = $ColumnMap.Keys | Where-Object { $_ -ieq $k } | Select-Object -First 1
        if ($match) { $defaults[$k] = $ColumnMap[$match] }
    }
}

# -- Load CSV rows ---------------------------------------------------------
$rows = Import-Csv -Path $CsvPath -ErrorAction Stop | Sort-Object -Property score -Descending
$total = $rows.Count

# -- Compute executive summary metrics -------------------------------------
# Average score (ignore non-numeric)
$scores = @()
foreach ($r in $rows) {
    $val = Get-FieldValue $r $defaults.score
    if ($val -ne $null -and $val -as [double]) { $scores += [double]$val }
}
$avgScore = if ($scores.Count -gt 0) { "{0:N2}" -f (($scores | Measure-Object -Sum).Sum / $scores.Count) } else { "N/A" }

# Top companies by count
$topCompanies = $rows | Group-Object -Property { Get-FieldValue $_ $defaults.company } |
    Where-Object { $_.Name -and $_.Name.Trim() -ne "" } |
    Sort-Object -Property Count -Descending |
    Select-Object -First 10

# Languages distribution
$langDist = $rows | Group-Object -Property { Get-FieldValue $_ $defaults.lang } | Sort-Object -Property Count -Descending

# -- Build HTML ------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder

# CSS + JS
$css = @"
body { font-family:'Segoe UI', Arial, sans-serif; margin:20px; color:#222; background:#f8f9fa }
.header { display:flex; justify-content:space-between; align-items:center; margin-bottom:20px; padding-bottom:12px; border-bottom:2px solid #dee2e6 }
.title { font-size:28px; font-weight:600; color:#1a1a1a }
.meta { color:#6c757d; font-size:14px }
.exec-summary { border:1px solid #dee2e6; padding:16px; border-radius:8px; margin-bottom:24px; background:#fff; box-shadow:0 1px 3px rgba(0,0,0,0.1) }
.exec-summary h3 { margin-top:0; color:#495057; font-size:20px }
.exec-summary ul { margin:8px 0; padding-left:24px }
.exec-summary li { margin:4px 0 }
.page-break { page-break-after: always; margin-top:20px }
.job-card { border:1px solid #e2e8f0; border-radius:8px; padding:14px; margin-bottom:14px; display:flex; gap:14px; background:#fff; box-shadow:0 1px 2px rgba(0,0,0,0.05); transition:box-shadow 0.2s }
.job-card:hover { box-shadow:0 4px 8px rgba(0,0,0,0.1) }
.company-logo { width:64px; height:64px; flex:0 0 64px; border-radius:8px; object-fit:cover; border:1px solid #e2e8f0 }
.job-body { flex:1; min-width:0 }
.job-title { font-size:18px; font-weight:600; margin:0 0 6px 0; color:#1a1a1a }
.job-title a { color:#0066cc; text-decoration:none }
.job-title a:hover { text-decoration:underline }
.job-company { color:#495057; margin:0 0 4px 0; font-weight:500 }
.job-location { color:#6c757d; margin:0 0 8px 0; font-size:14px; display:flex; align-items:center; gap:4px }
.job-location::before { content:'📍'; }
.job-desc { color:#333; margin-bottom:10px; line-height:1.5 }
.job-desc p { margin:6px 0 }
.job-desc code { background:#f1f3f5; padding:2px 6px; border-radius:3px; font-family:'Courier New', monospace; font-size:13px }
.job-desc pre { background:#f1f3f5; padding:10px; border-radius:4px; overflow-x:auto }
.job-desc pre code { background:transparent; padding:0 }
.job-desc ul { margin:8px 0; padding-left:24px }
.job-desc a { color:#0066cc }
.eval { display:flex; gap:12px; flex-wrap:wrap; color:#495057; font-size:13px; padding-top:8px; border-top:1px solid #e9ecef }
.eval span { background:#f8f9fa; padding:4px 8px; border-radius:4px }
.eval strong { color:#212529 }
.controls { display:flex; gap:10px; align-items:center; margin:16px 0; padding:12px; background:#fff; border-radius:6px; border:1px solid #dee2e6 }
.controls button { padding:8px 14px; border-radius:5px; border:1px solid #cbd5e1; background:#fff; cursor:pointer; font-weight:500; transition:all 0.2s }
.controls button:hover { background:#f1f5f9; border-color:#94a3b8 }
.controls button:active { background:#e2e8f0 }
.controls select { padding:7px 10px; border-radius:5px; border:1px solid #cbd5e1; background:#fff; cursor:pointer }
.controls label { font-weight:500; color:#495057 }
#pageInfo { color:#6c757d; font-size:14px; font-weight:500 }
@media print {
  body { background:#fff }
  .controls { display:none }
  .job-card { page-break-inside: avoid; box-shadow:none }
  .page-break { page-break-after:always }
}
"@

$js = @"
const pageSize = $PageSize;
let currentPage = 1;
function showPage(page) {
  const cards = Array.from(document.querySelectorAll('.job-card'));
  const total = cards.length;
  const pages = Math.max(1, Math.ceil(total / pageSize));
  if (page < 1) page = 1;
  if (page > pages) page = pages;
  currentPage = page;
  const start = (page - 1) * pageSize;
  const end = start + pageSize;
  cards.forEach((c, i) => { c.style.display = (i>=start && i<end) ? 'flex' : 'none'; });
  document.getElementById('pageInfo').textContent = 'Page ' + page + ' of ' + pages;
  document.getElementById('pageSelect').value = page;
}
function prevPage(){ showPage(currentPage - 1) }
function nextPage(){ showPage(currentPage + 1) }
function jumpPage(el){ showPage(parseInt(el.value) || 1) }
window.addEventListener('DOMContentLoaded', () => {
  const cards = document.querySelectorAll('.job-card');
  const pages = Math.max(1, Math.ceil(cards.length / pageSize));
  const sel = document.getElementById('pageSelect');
  for (let p=1;p<=pages;p++){ const opt=document.createElement('option'); opt.value=p; opt.textContent=p; sel.appendChild(opt) }
  showPage(1);
});
"@

# HTML head
$null = $sb.AppendLine("<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>")
$null = $sb.AppendLine("<title>Job Report - $total Jobs</title>")
$null = $sb.AppendLine("<style>$css</style>")
$null = $sb.AppendLine("</head><body>")
$null = $sb.AppendLine("<div class='header'><div class='title'>Job Report</div><div class='meta'>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') | Total: $total jobs</div></div>")

# Executive Summary #1
$null = $sb.AppendLine("<div class='exec-summary'>")
$null = $sb.AppendLine("<h3>Executive Summary</h3>")
$null = $sb.AppendLine("<p><strong>Total Jobs:</strong> $total &nbsp;|&nbsp; <strong>Average Score:</strong> $avgScore</p>")
if ($topCompanies.Count -gt 0) {
    $null = $sb.AppendLine("<p><strong>Top Companies:</strong></p><ul>")
    foreach ($c in $topCompanies) { 
        $name = HtmlEscape $c.Name
        $null = $sb.AppendLine("<li>$name — $($c.Count) job(s)</li>") 
    }
    $null = $sb.AppendLine("</ul>")
}
if ($langDist.Count -gt 0) {
    $null = $sb.AppendLine("<p><strong>Language Distribution:</strong></p><ul>")
    foreach ($ld in ($langDist | Select-Object -First 5)) {
        $langName = if ($ld.Name) { HtmlEscape $ld.Name } else { "Not specified" }
        $null = $sb.AppendLine("<li>$langName — $($ld.Count) job(s)</li>")
    }
    $null = $sb.AppendLine("</ul>")
}
$null = $sb.AppendLine("</div>")

# Page break for print
$null = $sb.AppendLine("<div class='page-break'></div>")

# Controls for pagination
$null = $sb.AppendLine("<div class='controls'>")
$null = $sb.AppendLine("<button onclick='prevPage()'>&#9664; Prev</button>")
$null = $sb.AppendLine("<button onclick='nextPage()'>Next &#9654;</button>")
$null = $sb.AppendLine("<label>Jump to page: <select id='pageSelect' onchange='jumpPage(this)'></select></label>")
$null = $sb.AppendLine("<span id='pageInfo'></span>")
$null = $sb.AppendLine("</div>")

# Detailed section: job cards
$null = $sb.AppendLine("<div id='jobs'>")

foreach ($r in $rows) {
    $company = Get-FieldValue $r $defaults.company
    $logo = Get-FieldValue $r $defaults.company_logo
    if (-not $logo -and $DefaultLogoPath) { $logo = $DefaultLogoPath }
    $title = Get-FieldValue $r $defaults.title
    $jobUrl = Get-FieldValue $r $defaults.job_url
    $location = Get-FieldValue $r $defaults.location  # Get location value
    $descMd = Get-FieldValue $r $defaults.description
    $descHtml = Simple-MarkdownToHtml $descMd
    $score = Get-FieldValue $r $defaults.score
    $why = Get-FieldValue $r $defaults.why
    $gaps = Get-FieldValue $r $defaults.gaps
    $seniority = Get-FieldValue $r $defaults.seniority
    $lang = Get-FieldValue $r $defaults.lang

    $compEsc = HtmlEscape $company
    $titleEsc = HtmlEscape $title
    $locationEsc = HtmlEscape $location  # Escape location
    $whyEsc = HtmlEscape $why
    $gapsEsc = HtmlEscape $gaps
    $senEsc = HtmlEscape $seniority
    $langEsc = HtmlEscape $lang
    $scoreEsc = HtmlEscape $score
    $logoHtml = Get-LogoHtml -company $company -logoPath $logo

    $null = $sb.AppendLine("<div class='job-card'>")
    $null = $sb.AppendLine($logoHtml)
    $null = $sb.AppendLine("<div class='job-body'>")
    $null = $sb.AppendLine("<div class='job-company'>$compEsc</div>")
    if ($jobUrl -and $jobUrl.Trim().Length -gt 0) {
        $jobUrlEsc = HtmlEscape $jobUrl
        $null = $sb.AppendLine("<div class='job-title'><a href='$jobUrlEsc' target='_blank' rel='noopener'>$titleEsc</a></div>")
    } else {
        $null = $sb.AppendLine("<div class='job-title'>$titleEsc</div>")
    }
    # Add location display
    if ($locationEsc -and $locationEsc.Trim().Length -gt 0) {
        $null = $sb.AppendLine("<div class='job-location'>$locationEsc</div>")
    }
    $null = $sb.AppendLine("<div class='job-desc'>$descHtml</div>")
    $null = $sb.AppendLine("<div class='eval'>")
    $null = $sb.AppendLine("<span>Score: <strong>$scoreEsc</strong></span>")
    $null = $sb.AppendLine("<span>Seniority: <strong>$senEsc</strong></span>")
    $null = $sb.AppendLine("<span>Language: <strong>$langEsc</strong></span>")
    $null = $sb.AppendLine("<span>Why: <strong>$whyEsc</strong></span>")
    $null = $sb.AppendLine("<span>Gaps: <strong>$gapsEsc</strong></span>")
    $null = $sb.AppendLine("</div>") # eval
    $null = $sb.AppendLine("</div>") # job-body
    $null = $sb.AppendLine("</div>") # job-card
}

$null = $sb.AppendLine("</div>") # jobs

# Footer & scripts
$null = $sb.AppendLine("<script>$js</script>")
$null = $sb.AppendLine("</body></html>")

#if the reportexists, make a dated copy before overwriting
if (Test-Path $OutputHtmlPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$OutputHtmlPath.bak_$timestamp"
    try {
        Copy-Item -Path $OutputHtmlPath -Destination $backupPath -ErrorAction Stop
        Write-Host "Existing report backed up to: $backupPath" -ForegroundColor Yellow
    } catch {
        Write-Warning "Failed to back up existing report: $_"
    }
}


# Write to file
try {
    $outDir = Split-Path -Parent $OutputHtmlPath
    if ($outDir -and -not (Test-Path $outDir)) { 
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null 
    }
    [System.IO.File]::WriteAllText($OutputHtmlPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
    Write-Host "✓ Report successfully generated: $OutputHtmlPath" -ForegroundColor Green
    Write-Host "  Total jobs: $total" -ForegroundColor Cyan
    Write-Host "  Average score: $avgScore" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to write output HTML: $_"
    exit 1
}

