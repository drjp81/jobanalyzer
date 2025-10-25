<#
.SYNOPSIS
    Enriches LinkedIn job data with AI-powered scoring and analysis using Ollama API.

.DESCRIPTION
    This script processes a CSV file containing job listings and scores each job against a candidate's resume using an Ollama-hosted LLM.
    It evaluates job fit based on configurable criteria including must-haves, nice-to-haves, exclusions, locale, language preferences, and seniority level.
    
    The script performs the following operations:
    - Validates and ensures required Ollama models are available (pulls if necessary)
    - Loads and caches the candidate's resume
    - Processes each job from the input CSV
    - Uses RAG (Retrieval-Augmented Generation) to match resume content with job requirements
    - Generates structured JSON output with scoring, reasoning, gaps analysis, and metadata extraction
    - Exports enriched results to a new CSV file with backup of existing output

.PARAMETER InCSV
    [Required] Path to the input CSV file containing job listings. Must include 'title' and 'Description' (or 'description') columns.

.PARAMETER DataDir
    Directory for data storage and caching. Defaults to environment variable DATA_DIR or "/DATA".

.PARAMETER OllamaBase
    Base URL for the Ollama API endpoint. Defaults to environment variable OLLAMA_BASE or "http://ollama:11434".

.PARAMETER ScorerModel
    The Ollama model to use for job scoring and analysis. Defaults to environment variable SCORER_MODEL or "qwen2.5:7b-instruct".

.PARAMETER EmbedModel
    The Ollama model to use for text embeddings (for semantic search). Defaults to environment variable EMBED_MODEL.

.PARAMETER ResumePath
    Path to the candidate's resume text file. Defaults to environment variable CANDIDATE_RESUME_PATH. Required for operation.

.PARAMETER CandidateName
    Name of the candidate being evaluated. Defaults to environment variable CANDIDATE_NAME.

.PARAMETER Retries
    Number of retry attempts for API calls. Defaults to environment variable RETRIES or 3.

.PARAMETER K
    Number of top resume snippets to retrieve for context (when using embeddings). Defaults to environment variable K_RESUME_SNIPPETS or 6.

.PARAMETER ChunkSize
    Size of text chunks when splitting resume. Defaults to environment variable RESUME_CHUNK_SIZE or 900.

.PARAMETER ChunkOverlap
    Overlap between consecutive chunks. Defaults to environment variable RESUME_CHUNK_OVERLAP or 150.

.NOTES
    File Name      : csvget_ollama.ps1
    Author         : Jean-Paul Lizotte
    Created        : 2025-10-24
    Version        : 0.0.1
    Prerequisite   : PowerShell 7+, Ollama API endpoint accessible, valid resume TEXT file
    
    Environment Variables (Optional):
    - DATA_DIR: Data directory path
    - OLLAMA_BASE: Ollama API base URL
    - SCORER_MODEL: LLM model for scoring
    - EMBED_MODEL: Embedding model for semantic search
    - CANDIDATE_RESUME_PATH: Path to resume file
    - CANDIDATE_NAME: Candidate's name
    - MUST_HAVES: Comma-separated required skills/attributes
    - NICE_TO_HAVES: Comma-separated preferred skills/attributes
    - EXCLUSIONS: Comma-separated deal-breakers
    - LOCALE: Comma-separated acceptable locations
    - LANG_PREF: Language preference (fr/en/either)
    - SENIORITY_TARGET: Target seniority level (junior/mid/senior/lead)
    - TIMEOUT_MINUTES: API timeout in minutes (default: 5)
    - TEMPERATURE: LLM temperature setting (default: 0.3)
    - CONTEXT_LENGTH: LLM context window size (default: 8192)
    - RETRIES: Number of retry attempts (default: 3)
    - K_RESUME_SNIPPETS: Number of resume snippets to retrieve (default: 6)
    - RESUME_CHUNK_SIZE: Resume chunk size (default: 900)
    - RESUME_CHUNK_OVERLAP: Resume chunk overlap (default: 150)

.EXAMPLE
    .\csvget_ollama.ps1 -InCSV "jobs.csv"
    
    Processes jobs from jobs.csv using default environment variables and outputs to jobs_with_responses_ollama.csv

.EXAMPLE
    .\csvget_ollama.ps1 -InCSV "jobs.csv" -ResumePath "resume.txt" -CandidateName "John Doe" -ScorerModel "llama3:8b"
    
    Processes jobs with specific resume, candidate name, and LLM model

.OUTPUTS
    CSV file: jobs_with_responses_ollama.csv containing original job data plus:
    - score: Integer 0-100 representing job fit
    - why: Concise explanation of the score
    - gaps: Array of missing requirements
    - lang: Detected job language (fr/en/mixed/none)
    - seniority: Detected seniority level
    - tags: Array of relevant technology/domain tags
    - locations: Array of job locations
#>


param(
    [Parameter(Position = 0, mandatory = $true)]
    [string]$InCSV ,
    [string]$DataDir = $env:DATA_DIR,
    [string]$OllamaBase = $env:OLLAMA_BASE,
    [string]$ScorerModel = $env:SCORER_MODEL,
    [string]$EmbedModel = $env:EMBED_MODEL,
    [string]$ResumePath = $env:CANDIDATE_RESUME_PATH,
    [string]$CandidateName = $env:CANDIDATE_NAME,
    [int]$Retries = [int]($env:RETRIES ? $env:RETRIES : 3),
    [int]$K = [int]($env:K_RESUME_SNIPPETS ? $env:K_RESUME_SNIPPETS : 6),
    [int]$ChunkSize = [int]($env:RESUME_CHUNK_SIZE ? $env:RESUME_CHUNK_SIZE : 900),
    [int]$ChunkOverlap = [int]($env:RESUME_CHUNK_OVERLAP ? $env:RESUME_CHUNK_OVERLAP : 150)
)

if (-not $DataDir) { $DataDir = "/DATA" }
if (-not $OllamaBase) { $OllamaBase = "http://ollama:11434" }
if (-not $ScorerModel) { $ScorerModel = "qwen2.5:7b-instruct" }
#if (-not $EmbedModel) { $EmbedModel = "nomic-embed-text" }  # widely supported

Write-Host "[ai enricher] OLLAMA_BASE  = $OllamaBase"
Write-Host "[ai enricher] SCORER_MODEL = $ScorerModel"
#Write-Host "[ai enricher] EMBED_MODEL  = $EmbedModel"
if ($CandidateName) { Write-Host "[ai enricher] CANDIDATE    = $CandidateName" }

# Scoring knobs (optional)
$Must = $env:MUST_HAVES
$Nice = $env:NICE_TO_HAVES
$Exclude = $env:EXCLUSIONS
$Locale = $env:LOCALE
$LangPref = $env:LANG_PREF
$Seniority = $env:SENIORITY_TARGET
$timeoutMinutes = [int]($env:TIMEOUT_MINUTES ? $env:TIMEOUT_MINUTES : 5)
$temperature = [double]($env:TEMPERATURE ? $env:TEMPERATURE : 0.3)
$contextLength = [int]($env:CONTEXT_LENGTH ? $env:CONTEXT_LENGTH : 8192)

function Invoke-OllamaApi {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")] [string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        $Body = $null
    )
    $uri = ($OllamaBase.TrimEnd('/') + '/' + $Path.TrimStart('/'))
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            if ($null -ne $Body) {
                $json = $Body | ConvertTo-Json -Depth 20
                $response = Invoke-RestMethod -Method $Method -Uri $uri -Body $json -ContentType "application/json" -TimeoutSec (($timeoutMinutes * 60) - 2)
                return $response
            }
            else {
                $response = Invoke-RestMethod -Method $Method -Uri $uri -TimeoutSec (($timeoutMinutes * 60) - 2)
                return $response
            }
        }
        catch {
            Write-Warning "HTTP $Method $uri failed (attempt $($i+1)): $_"
            Start-Sleep -Seconds (2 * ($i + 1))
            if ($i -eq ($Retries - 1)) { throw }
        }
    }
}


function Get-Models {
    $tags = Invoke-OllamaApi -Method GET -Path "api/tags"
    $models = @()
    if ($tags -and $tags.models) {
        foreach ($m in $tags.models) { $models += $m.name }
    }
    return $models
}


function Pull-Model {
    param([string]$Model)
    Write-Host "[ai enricher] Pulling model '$Model'..."
   $status= Invoke-OllamaApi -Method POST -Path "api/pull" -Body @{ model = $Model; stream = $false }
   if ($status -and $status.status -eq "success") {
       Write-Host "[ai enricher] Model '$Model' pulled successfully."
   }
   else {
       throw "Failed to pull model '$Model'."
   }
}

function Ensure-Model {
   
    param([string]$Model,
    [string[]]$availableModels)
    $available = $availableModels
    if ($available -notcontains $Model) {
        Pull-Model -Model $Model
    }
    else {
        Write-Host "[ai enricher] Model '$Model' is already available."
    }
}

function Read-ResumeText {
    param([string]$Path)
    if (-not $Path) { return $null }
    if (-not (Test-Path $Path)) { throw "Resume path not found: $Path" }
    return Get-Content -Raw -Encoding UTF8 -Path $Path
}

function Chunk-Text {
    param([string]$Text, [int]$Size, [int]$Overlap)
    if (-not $Text) { return @() }
    $chunks = @()
    $i = 0
    while ($i -lt $Text.Length) {
        $end = [Math]::Min($Text.Length, $i + $Size)
        $chunks += $Text.Substring($i, $end - $i)
        $i = $i + $Size - $Overlap
        if ($i -lt 0) { $i = 0 }
    }
    return $chunks
}

function Embed-Texts {
    param([string[]]$Texts)
    if (-not $Texts -or $Texts.Count -eq 0) { return @() }
    $resp = Invoke-OllamaApi -Method POST -Path "api/embed" -Body @{ model = $EmbedModel; input = $Texts }
    # Expected shape: { "embeddings": [[...], [...]] } OR { "data":[{embedding:[...]}] }
    $vecs = @()
    if ($resp.embeddings) {
        foreach ($v in $resp.embeddings) { $vecs += , $v }
    }
    elseif ($resp.data) {
        foreach ($it in $resp.data) { $vecs += , $it.embedding }
    }
    else {
        Write-Warning "Unexpected embeddings response shape: $($resp )"
        throw "Unexpected embeddings response shape: $($resp | ConvertTo-Json -Compress)"
    }
    return $vecs
}

function Cosine-Sim {
    param($a, $b)
    if (-not $a -or -not $b) { return 0.0 }
    $dot = 0.0; $na = 0.0; $nb = 0.0
    for ($i = 0; $i -lt [Math]::Min($a.Count, $b.Count); $i++) {
        $dot += ($a[$i] * $b[$i])
        $na += ($a[$i] * $a[$i])
        $nb += ($b[$i] * $b[$i])
    }
    if ($na -eq 0 -or $nb -eq 0) { return 0.0 }
    return $dot / ([Math]::Sqrt($na) * [Math]::Sqrt($nb))
}

function TopK-Resume-Snippets {
  param([string]$Query, [int]$K)

  if (-not $ResumeChunks -or $ResumeChunks.Count -eq 0) { return @() }

  # One embedding call per job
  $qvec = (Embed-Texts -Texts @($Query))[0]

  # Cosine sim against precomputed resume vectors
  $pairs = @()
  for ($i=0; $i -lt $ResumeChunks.Count; $i++) {
    $sim = Cosine-Sim -a $qvec -b $ResumeVecs[$i]
    $pairs += [PSCustomObject]@{ idx=$i; sim=$sim }
  }
  $top = $pairs | Sort-Object -Property sim -Descending | Select-Object -First $K
  return $top | ForEach-Object { $ResumeChunks[$_.idx] }
}


# Get available models
$availableModels = Get-Models

# Prepare: ensure models
Ensure-Model -Model $ScorerModel -availableModels $availableModels
#Ensure-Model -Model $EmbedModel -availableModels $availableModels

# Load resume
$resumeText = $null
if ($ResumePath) { $resumeText = Read-ResumeText -Path $ResumePath }
# throw if no resume
if (-not $resumeText) { throw "No resume text available! Provide a valid CANDIDATE_RESUME_PATH." }

# Build a tiny on-disk cache so repeated runs don’t recompute
$cachePath = Join-Path $DataDir "resume_index.json"

function Get-FileHashHex([string]$path) {
  (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
}

$resumeHash = if ($ResumePath -and (Test-Path $ResumePath)) { Get-FileHashHex $ResumePath } else { "" }

$cached = $null
if (Test-Path $cachePath) {
  try { $cached = Get-Content -Raw -Encoding UTF8 $cachePath | ConvertFrom-Json } catch {}
}

$ResumeChunks = $null
$ResumeVecs   = $null

$needRebuild = $true
if ($cached -and $cached.resumeHash -eq $resumeHash -and $cached.chunkSize -eq $ChunkSize -and $cached.chunkOverlap -eq $ChunkOverlap -and $cached.embedModel -eq $EmbedModel) {
  $ResumeChunks = @($cached.chunks)
  $ResumeVecs   = @($cached.embeddings)
  if ($ResumeChunks.Count -gt 0 -and $ResumeVecs.Count -eq $ResumeChunks.Count) { $needRebuild = $false }
}

if ($needRebuild) {
  $ResumeChunks =  $resumeText -split "`r?`n" 
  #$ResumeVecs   = Embed-Texts -Texts $ResumeChunks
  @{
    resumeHash   = $resumeHash
    chunkSize    = $ChunkSize
    chunkOverlap = $ChunkOverlap
    embedModel   = $EmbedModel
    chunks       = $ResumeChunks
    embeddings   = $ResumeVecs
  } | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $cachePath
}


# Input CSV


$outCsv = Join-Path $DataDir "jobs_with_responses_ollama.csv"
if (-not (Test-Path $InCSV)) { throw "Missing $InCSV. Run the collector first." }
$jobs = Import-Csv -Path $InCSV | Where-Object { $_.title -and ($_.Description -or $_.description) }
if (-not $jobs -or $jobs.Count -eq 0) { throw "No rows in $InCSV." }

#Make a backup of an existing output file
if (Test-Path $outCsv) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = "$outCsv.bak_Ollama$timestamp"
    Copy-Item -Path $outCsv -Destination $backupPath
    Write-Host "[ai enricher] Backed up existing $outCsv to $backupPath"
}

# Build the strict system prompt with your schema and knobs
function Make-System-Prompt {
    # Convert knob strings to JSON-ish lists when present
    function ToList($s) {
        if (-not $s) { return "[]" }
        $arr = @()
        foreach ($x in ($s -split ",")) {
            $v = $x.Trim()
            if ($v) { $arr += $v }
        }
        return "[" + ($arr | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join "," + "]"
    }
    $mustJson = ToList $Must
    $niceJson = ToList $Nice
    $excJson = ToList $Exclude
    $locJson = ToList $Locale
    $langPref = ($LangPref ? $LangPref : "either")
    $senior = ($Seniority ? $Seniority : "senior")

    @"
You are a strict job-fit scorer. Return ONLY valid JSON; no prose, no code fences.

CRITERIA:
must = $mustJson
nice = $niceJson
exclude = $excJson
locale = $locJson
lang_pref = "$langPref"
seniority_target = "$senior"

SCORING
- score ∈ [0,100]
- must hits = 60% weight (divide evenly)
- nice hits = 30% weight (divide evenly)
- risks = −10 each: excludes hits, wrong seniority, wrong locale, wrong language, contractor-only, relocation required
- clamp to [0,100]

EXTRACT (from title+description only)
- lang: "fr"|"en"|"mixed"
- seniority: "junior"|"mid"|"senior"|"lead"
- locations: list of places in the text (normalize city/region/country; include "Remote" if stated)

OUTPUT JSON SCHEMA (and nothing else):
{
  "score": int,
  "why": "≤100 words concise reason. Include resume matches or mismatches",
  "gaps": [string] short list of missing requirements for the job, According to the resume,
  "lang": "fr|en|mixed|none",
  "seniority": "junior|mid|senior|lead",
  "tags": up to 8 short tokens (e.g., ["azure","zerotrust","grc","k8s","iam","gov", "devops","secdevops"]),
  "locations": [string]
}
"@
}

$systemPrompt = Make-System-Prompt





# Main loop: for each job, retrieve top-K resume snippets and call /api/chat with format: json
$rowsOut = @()
#start a counter
$jobCounter = 0
foreach ($job in $jobs) {
    $jobCounter++
    Write-Host "[ai enricher] Processing job $jobCounter of $($jobs.Count)"
    #start a timer to calculate the duration of each job processing
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $title = $job.title
    $desc = ($job.Description ? $job.Description : ($job.description ? $job.description : ""))

    # Build retrieval query from job title + description
    $query = "$title`n`n$desc"
   #$resumeSnippets = TopK-Resume-Snippets -Query $query -K $K

    $jobJson = @{ job_title = $title; job_description = $desc } | ConvertTo-Json -Compress

    # Construct a user message that includes the minimal inputs and the retrieved resume context
    $query = "According to their resume, is the candidate $env:CANDIDATE_NAME, a good fit for this job?"
    
    $usercontent = @"
    RESUME_TEXT:
    $resumeText

    INPUT_JOB_JSON:
    $jobJson

    QUERY:
    $query
"@


    $messages = @(
        @{ role = "system"; content = $systemPrompt },
        @{ role = "user"; content = $usercontent }
    )

    # Latest Ollama: /api/chat with format:"json", stream:false, temperature:$temperature, num_ctx:$contextLength
    $body = @{
        model    = $ScorerModel
        messages = $messages
        format   = "json"
        stream   = $false
        keep_alive = [string]$timeoutMinutes +"m"
        options  = @{ temperature = $temperature; num_ctx = $contextLength }
    }
    Write-Host "[ai enricher] Processing job: $($job.id) - $title"
    $resp = Invoke-OllamaApi -Method POST -Path "api/chat" -Body $body

    # Expected shape: { message: { role: "assistant", content: "<JSON>" }, ... }
    if (-not $resp -or -not $resp.message -or -not $resp.message.content) {
        throw "Ollama /api/chat returned unexpected shape."
    }

    $jsonText = [string]$resp.message.content
    #for debugging: uncomment the next line to see raw output
    #Write-Host "[ai enricher] Raw response content: $jsonText"
    $parsed = $jsonText | ConvertFrom-Json -ErrorAction Stop

    # Merge parsed keys onto the job row
    $out = $job | Select-Object *
    foreach ($name in $parsed.PSObject.Properties.Name) {
        $val = $parsed.$name
        if (-not ($out | Get-Member -Name $name -ErrorAction SilentlyContinue)) {
            $out | Add-Member -NotePropertyName $name -NotePropertyValue $val
        }
        else {
            $out.$name = $val
        }
    }
    $rowsOut += $out
    $stopwatch.Stop()
    Write-Host ("[ai enricher] [{0}] score={1}" -f ($title -replace "\r?\n", " "), ($parsed.score -as [string]))
    Write-Host "[ai enricher] Elapsed time: $($stopwatch.Elapsed.TotalSeconds) seconds"
}

# Write output
$rowsOut | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
Write-Host "[ai enricher] Wrote $outCsv"
