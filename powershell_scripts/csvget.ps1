<#
.SYNOPSIS
  Evaluate job postings by calling an AnythingLLM workspace chat endpoint and appending the LLM's structured response to each job record.

.DESCRIPTION
  This script:
    - Changes the working directory to the provided data directory (defaults to /DATA or $env:DATA_DIR).
    - Backs up an existing jobs_with_responses.csv with a timestamped copy for traceability.
    - Loads job records from flat_jobs_list.csv (from the python collector task) and filters to those with a non-empty Description.
    - For each job, calls the configured AnythingLLM workspace chat API (via Invoke-AnythingLLMChat),
    attempts to parse JSON-like content found in the response, attaches parsed fields as properties
    to the job object (converting arrays and objects into strings), and always attaches the raw
    response as the llm_raw property.
    - Writes/overwrites jobs_with_responses.csv after processing each job so intermediate results are persisted.

.PARAMETER DataDir
  Path to the directory containing flat_jobs_list.csv and where jobs_with_responses.csv will be read/written.
  Default: value of environment variable DATA_DIR; if unset, defaults to "/DATA".

.NOTES
    File Name   : csvget.ps1
    Project     : LinkedIn Scraper
    Author      : Jean-Paul Lizotte
    Created     : 2025-10-24
    Version     : 0.0.1
    Requires    : PowerShell 7+, AnythingLLM API endpoint accessible, valid AnythingLLM API key and workspace
    Exit Codes  : 0 = Success, 1 = Configuration/service error, other = propagated from child scripts


.ENVIRONMENT
  The script expects the following environment variables to be set:
    - ANLLM_API_KEY        : Bearer API key for AnythingLLM (required).
    - ANLLM_API_WORKSPACE  : Workspace identifier for AnythingLLM (required).
    - ANLLM_API_BASE       : Base URL for the AnythingLLM service. Default: http://localhost:3001
    - CANDIDATE_NAME       : Name used in the prompt (required).
    - RETRIES              : Number of times to retry the API call on failure. Default: 3
    - TIMEOUT_MINUTES      : Timeout for API requests in minutes. Default: 5
    - DATA_DIR             : Alternate source for DataDir.

.REQUIREMENTS
  - PowerShell 6.0+ is recommended for the -TimeoutSec parameter on Invoke-RestMethod.
  - Network access to the AnythingLLM API base URL and workspace.
  - flat_jobs_list.csv must exist in DataDir and contain at least the fields referenced (e.g., id, title, Description).

FUNCTIONS
  Invoke-AnythingLLMChat (internal)
    Parameters:
      - Question       : Prompt text to send to the LLM (string).
      - JobTitle       : Title of the job (string).
      - JobDescription : Job description text (string).
    Behavior:
      - Truncates JobDescription to 4000 characters if longer.
      - Builds a JSON message payload containing question, job_title, job_description.
      - Calls POST $ANLLM_API_BASE/api/v1/workspace/$ANLLM_API_WORKSPACE/chat with Authorization header.
      - Uses a retry loop controlled by RETRIES; on error waits 10 seconds between attempts.
      - Honors TIMEOUT_MINUTES by converting to seconds and passing as -TimeoutSec on PS 6+.
      - Returns the parsed response object from Invoke-RestMethod on success, or the exception object on final failure.

OUTPUTS
  - jobs_with_responses.csv : CSV file of the original job records, **where there were descriptions**, with additional properties from the LLM response.
    For each job processed:
    - Any top-level fields returned by the LLM (if JSON-parsable) are added as CSV columns.
    - Arrays returned by the LLM are joined with "; " for CSV compatibility.
    - Nested objects returned by the LLM are converted to compact JSON strings.
    - llm_raw column is always added, containing the raw LLM response text (JSON-compressed).

ERRORS / FAILURES
  - The script will throw and stop if:
    - CANDIDATE_NAME is not set in the environment.
    - ANLLM_API_KEY or ANLLM_API_WORKSPACE are not set.
    - flat_jobs_list.csv is missing in DataDir.
  - API request failures are retried RETRIES times; on final failure the exception object is attached to the job processing step
    (and llm_raw will contain whatever textual response is present or a JSON representation).

SECURITY & PRIVACY NOTES
  - The API key is read from an environment variable and sent in an Authorization: Bearer header.
  - The script logs non-sensitive configuration details (API URL, workspace, candidate name, retry/timeout values).
    Be mindful of sensitive data in output and logs—CANDIDATE_NAME and LLM responses may contain PII.
  - Consider securing environment variables and limiting log verbosity in production.

USAGE EXAMPLES
  # Run using defaults (DATA_DIR or /DATA), with environment variables configured:
  # $env:ANLLM_API_KEY = "..."
  # $env:ANLLM_API_WORKSPACE = "workspace-id"
  # $env:CANDIDATE_NAME = "Jane Doe"
  # pwsh ./csvget.ps1

  # Specify an alternate data directory:
  # pwsh ./csvget.ps1 -DataDir "C:\data\jobs"

NOTES & IMPLEMENTATION DETAILS
  - The script attempts to parse resp.textResponse as JSON; if parsing fails, parsed fields are skipped but llm_raw is still recorded.
  - The script writes the cumulative CSV after each processed job so partial progress is persisted even if subsequent processing fails.
  - JobDescription truncation is performed to avoid excessively large payloads to the LLM endpoint.
  - The retry wait time is fixed at 10 seconds; exponential backoff is not implemented but can be added if desired.

#>
Param(
  [string]$DataDir = $env:DATA_DIR
)


Write-Host "[ai enricher] Starting job analysis script..."

# Defaults
if (-not $DataDir) { $DataDir = "/DATA" }
Set-Location $DataDir

Write-Host "[ai enricher] Using DataDir: $DataDir"

# Back up previous results for traceability
if (Test-Path -Path "jobs_with_responses.csv") {
  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  Copy-Item -Path "jobs_with_responses.csv" -Destination "jobs_with_responses_$timestamp.csv"
}

# AnythingLLM configuration - must be provided via env or .env
$ANLLM_API_KEY = $env:ANLLM_API_KEY
$ANLLM_API_WORKSPACE = $env:ANLLM_API_WORKSPACE
$ANLLM_API_BASE = $env:ANLLM_API_BASE     # eg http://anythingllm:3001
if (-not $ANLLM_API_BASE) { $ANLLM_API_BASE = "http://localhost:3001" }
$ANLLM_API_URL = "$ANLLM_API_BASE/api/v1/workspace/$ANLLM_API_WORKSPACE/chat"



# Timeouts and retries
$RETRIES = [int]($env:RETRIES ?? 3)
$TIMEOUT_MINUTES = [int]($env:TIMEOUT_MINUTES ?? 5)
$TIMEOUT_SECONDS = $TIMEOUT_MINUTES * 60

#output non sensitive configuration details for logging
Write-Host "[ai enricher] Using AnythingLLM API URL: $ANLLM_API_URL"
Write-Host "[ai enricher] Using TIMEOUT_MINUTES: $TIMEOUT_MINUTES"
Write-Host "[ai enricher] Using RETRIES: $RETRIES"
Write-Host "[ai enricher] Using CANDIDATE_NAME: $($env:CANDIDATE_NAME)"
Write-Host "[ai enricher] Using workspace: $ANLLM_API_WORKSPACE"
Write-Host "[ai enricher] Using full url: $ANLLM_API_URL"


# Validation
if (-not $ANLLM_API_KEY) { throw "ANLLM_API_KEY is required" }
if (-not $ANLLM_API_WORKSPACE) { throw "ANLLM_API_WORKSPACE is required" }
if (!($env:CANDIDATE_NAME)) { throw "CANDIDATE_NAME is required" }

$Headers = @{
  "accept"        = "application/json"
  "Authorization" = "Bearer $ANLLM_API_KEY"
  "Content-Type"  = "application/json"
}
# Basic message prompt

$PromptText = @"
"Based on the available data about $($env:CANDIDATE_NAME), can you evaluate their fitness for this job?".
"@
function Invoke-AnythingLLMChat {
  param(
    [Parameter(Mandatory = $true)][string]$Question,
    [Parameter(Mandatory = $true)][string]$JobTitle,
    [Parameter(Mandatory = $true)][string]$JobDescription
  )
  
  #if the job description is more than 4k characters, truncate it
  if ($JobDescription.Length -gt 4000) {
    $JobDescription = $JobDescription.Substring(0, 4000)
  }
  
  $Message = @{
    question        = $Question
    job_title       = $JobTitle
    job_description = $JobDescription
  }

  $Body = @{
    message = ($Message | ConvertTo-Json -Compress)
    reset   = $false
    mode    = "chat"
  } | ConvertTo-Json

 
  for ($i = 0; $i -lt $RETRIES; $i++) {
    try {
      # -TimeoutSec requires PowerShell 6.0 or later
      if ($PSVersionTable.PSVersion.Major -ge 6) {
        $resp = Invoke-RestMethod -Method Post -Uri $ANLLM_API_URL -Headers $Headers -Body $Body -TimeoutSec $TIMEOUT_SECONDS
      } else {
        Write-Warning "TimeoutSec is not supported in PowerShell versions below 6.0. Consider upgrading for timeout support."
        $resp = Invoke-RestMethod -Method Post -Uri $ANLLM_API_URL -Headers $Headers -Body $Body
      }
      return $resp
    }
    catch {
      start-sleep -Seconds 10
      Write-Host "[ai enricher] Attempt $($i + 1) failed: $($_.Exception.Message)"
      if ($i -eq ($RETRIES - 1)) { return $_ }
    }
  }
}

# Load jobs and evaluate those with non-empty descriptions
if (-not (Test-Path "flat_jobs_list.csv")) { throw "Missing flat_jobs_list.csv in $DataDir. Run collector first." }
$jobs = Import-Csv -Path "flat_jobs_list.csv" | Where-Object { $_.Description }

$new = @()
$counter = 0
foreach ($job in $jobs) {
  $counter++
  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  $resp = Invoke-AnythingLLMChat -Question $PromptText -JobTitle $job.title -JobDescription $job.Description

  # Expect JSON-like content; try to parse fields if present
  try {
    if ($resp.textResponse) {
      $parsed = $resp.textResponse | ConvertFrom-Json -ErrorAction Stop
    }
    else {
      $parsed = $null
    }
  }
  catch {
    $parsed = $null
  }

  if ($parsed -and $parsed.PSObject.Properties.Name.Count -gt 0) {
    foreach ($k in $parsed.PSObject.Properties.Name) {
      if (-not ($job | Get-Member -Name $k)) {
        #some fileds are arrays, so we need to convert them to string
        if ($parsed.$k -is [System.Array]) {
          $value = $parsed.$k -join "; "
          Add-Member -InputObject $job -MemberType NoteProperty -Name $k -Value $value
        }
        elseif ($parsed.$k -is [PSCustomObject]) {
          $value = $parsed.$k | ConvertTo-Json -Compress
          Add-Member -InputObject $job -MemberType NoteProperty -Name $k -Value $value
        }
        else {
          Add-Member -InputObject $job -MemberType NoteProperty -Name $k -Value $parsed.$k
        }
      }
      elseif ($job.$k -is [System.Array]) {
        $value = $parsed.$k -join "; "
        Add-Member -InputObject $job -MemberType NoteProperty -Name $k -Value $value
      }
      elseif ($job.$k -is [PSCustomObject]) {
        $value = $parsed.$k | ConvertTo-Json -Compress
        Add-Member -InputObject $job -MemberType NoteProperty -Name $k -Value $value
      }
      elseif (-not $job.$k) {
        Add-Member -InputObject $job -MemberType NoteProperty -Name $k -Value $parsed.$k
      }
      else {
        $job.$k = $parsed.$k
      }
    }
  } 
  # Fallback: always attach raw response text
  Add-Member -InputObject $job -NotePropertyName "llm_raw" -NotePropertyValue ($resp.textResponse | ConvertTo-Json -Compress)

  $timer.Stop()
  Write-Host ("Processed $counter of $($jobs.count) id={0} in {1:n2} seconds" -f $job.id, $timer.Elapsed.TotalSeconds)
  $new += $job
  #commit the new file each cycle
  $new | Export-Csv -Path "jobs_with_responses.csv" -NoTypeInformation -Encoding UTF8
}

Write-Host "[ai enricher] Wrote jobs_with_responses.csv"
