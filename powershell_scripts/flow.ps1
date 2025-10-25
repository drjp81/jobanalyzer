<#
.SYNOPSIS
    Master orchestration script that manages the LinkedIn job scraping and analysis workflow.

.DESCRIPTION
    This script serves as the main entry point for the LinkedIn scraping pipeline. It:
    - Detects whether Ollama (local LLM) or AnythingLLM API is available
    - Validates all required environment variables
    - Runs the collector to gather job data
    - Processes job data using the available LLM service (preferring Ollama)
    - Generates an HTML report of analyzed jobs
    
    The script follows this workflow:
    1. Check environment configuration
    2. Probe for available LLM services (Ollama has priority)
    3. Run collector.py to scrape job listings
    4. Process jobs with either csvget_ollama.ps1 or csvget.ps1
    5. Generate final HTML report with New-JobReport.ps1

.PARAMETER None
    This script does not accept parameters. All configuration is via environment variables.

.ENVIRONMENT VARIABLES
    DATA_DIR                - Required. Directory for data storage (e.g., /DATA)
    OLLAMA_BASE            - Optional. Base URL for Ollama API (e.g., http://localhost:11434)
    ANLLM_API_BASE         - Optional. Base URL for AnythingLLM API
    ANLLM_API_KEY          - Required if using AnythingLLM. API authentication key
    ANLLM_API_WORKSPACE    - Required if using AnythingLLM. Workspace identifier
    REPORT_PAGE_SIZE       - Optional. Number of jobs per page in report (default: 1)

.OUTPUTS
    - /DATA/flat_jobs_list.csv           - Collected job listings (from collector.py)
    - /DATA/jobs_with_responses.csv      - Processed jobs (AnythingLLM path)
    - /DATA/jobs_with_responses_ollama.csv - Processed jobs (Ollama path)
    - /DATA/jobs_report.html             - Final HTML report

.NOTES
    File Name   : flow.ps1
    Project     : LinkedIn Scraper
    Author      : Jean-Paul Lizotte
    Created     : 2025-10-24
    Version     : 0.0.1
    Requires    : PowerShell 7+, Python 3, collector.py, csvget.ps1, csvget_ollama.ps1, New-JobReport.ps1
    Exit Codes  : 0 = Success, 1 = Configuration/service error, other = propagated from child scripts

.EXAMPLE
    # Run with environment variables set
    .\flow.ps1

#>

Set-Location $PSScriptRoot

# --- Configuration -----------------------------------------------------------
$DataDir = $env:DATA_DIR            
$OllamaBase = $env:OLLAMA_BASE        
$AnllmBase = $env:ANLLM_API_BASE     
$AnllmApiKey = $env:ANLLM_API_KEY
$AnllmWorkspace = $env:ANLLM_API_WORKSPACE
$ReportPageSize = $env:REPORT_PAGE_SIZE    ; if (-not $ReportPageSize) { $ReportPageSize = 1 }


# test all variables, if they aren't set, exit with error
if (-not $DataDir) {
    Write-Host "[flow] ERROR: DATA_DIR environment variable is not set. Exiting."
    exit 1
}
if ((-not $OllamaBase) -and (-not $AnllmBase)) {
    Write-Host "[flow] ERROR: OLLAMA_BASE or ANLLM_API_BASE environment variable is not set. Exiting."
    exit 1
}

if ($AnllmBase -and (-not $AnllmApiKey)) {
    Write-Host "[flow] ERROR: ANLLM_API_KEY environment variable is not set. Exiting."
    exit 1
}
if ($AnllmBase -and (-not $AnllmWorkspace)) {
    Write-Host "[flow] ERROR: ANLLM_API_WORKSPACE environment variable is not set. Exiting."
    exit 1
}

function Test-HttpOk {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSec = 5,
        [hashtable]$Headers
    )
    try {
        $params = @{ Method = "GET"; Uri = $Url; TimeoutSec = $TimeoutSec; ErrorAction = "Stop" }
        if ($Headers) { $params.Headers = $Headers }
        $null = Invoke-RestMethod @params
        return $true
    } catch { return $false }
}


function Test-Ollama {
    param([string]$Base)
    $url = $Base.TrimEnd('/') + "/api/tags"
    return Test-HttpOk -Url $url -TimeoutSec 5
}


function Test-AnythingLLM {
    param([string]$Base, [string]$ApiKey, [string]$Workspace)
    if ([string]::IsNullOrWhiteSpace($ApiKey) -or [string]::IsNullOrWhiteSpace($Workspace)) { return $false }
    # Health endpoint (fast). If not available on your build, you can switch to a workspace GET.
    $url = $Base.TrimEnd('/') + "/api/health"
    $headers = @{ "Authorization" = "Bearer $ApiKey" }
    if (Test-HttpOk -Url $url -TimeoutSec 5 -Headers $headers) { return $true }
    # Fallback probe: try hitting the workspace page (leaves no side-effects)
    $wsUrl = $Base.TrimEnd('/') + "/api/v1/workspace/$Workspace"
    return Test-HttpOk -Url $wsUrl -TimeoutSec 5 -Headers $headers
}



# --- Probe targets (preference: Ollama) -------------------------------------
$hasOllama = Test-Ollama -Base $OllamaBase
$hasAnything = Test-AnythingLLM -Base $AnllmBase -ApiKey $AnllmApiKey -Workspace $AnllmWorkspace


#if neither is available stop the flow with a warning
if (-not $hasOllama -and -not $hasAnything) {
    Write-Host "[flow] ERROR: Neither Ollama nor AnythingLLM API is reachable. Exiting."
    exit 1
}   


#if ollama or anything is available start the collector
Write-Host "[flow] Starting the collector..."
& python3 ./collector.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "[flow] ERROR: Collector failed (exit $LASTEXITCODE). Exiting."
    exit $LASTEXITCODE
}

#if it exits normally, that means we have our file to analyze and if OLLAMA is available, we can start processing it

if ($hasOllama) {
    Write-Host "[flow] Ollama detected. Starting Ollama processing..."
    & ./csvget_ollama.ps1 -InCSV "$DataDir/flat_jobs_list.csv"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[flow] ERROR: Ollama processing did not complete successfully (exit $LASTEXITCODE)."
        if ($hasAnything) {
            Write-Host "[flow] Falling back to AnythingLLM..."
            & ./csvget.ps1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[flow] ERROR: AnythingLLM processing also failed (exit $LASTEXITCODE). Exiting."
                exit $LASTEXITCODE
            }
            & .\New-JobReport.ps1 -CsvPath "$DataDir/jobs_with_responses.csv" -OutputHtmlPath "$DataDir/jobs_report.html" -PageSize $ReportPageSize
            exit $LASTEXITCODE
        } else {
            exit $LASTEXITCODE
        }
    }

    # success path -> generate report
    & .\New-JobReport.ps1 -CsvPath "$DataDir/jobs_with_responses_ollama.csv" -OutputHtmlPath "$DataDir/jobs_report.html" -PageSize $ReportPageSize
    exit $LASTEXITCODE
}
elseif ($hasAnything) {
    Write-Host "[flow] AnythingLLM API detected. Starting AnythingLLM processing..."
    & ./csvget.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[flow] ERROR: AnythingLLM processing did not complete successfully (exit $LASTEXITCODE). Exiting."
        exit $LASTEXITCODE
    }
    & .\New-JobReport.ps1 -CsvPath "$DataDir/jobs_with_responses.csv" -OutputHtmlPath "$DataDir/jobs_report.html" -PageSize $ReportPageSize
    exit $LASTEXITCODE
}

