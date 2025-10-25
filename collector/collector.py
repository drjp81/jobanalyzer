#!/usr/bin/env python3
"""
Job Collector
-------------
Scrapes job postings using the `jobspy` library and writes a CSV to /DATA (or DATA_DIR).
Configuration is controlled with environment variables or CLI flags.

Env Vars
- SITE_NAME: Comma-separated list of sources. Default: "indeed,linkedin,glassdoor"
- SEARCH_TERM: Query text. Default: "Azure devops"
- GOOGLE_SEARCH_TERM: Optional Google Jobs query. Default: mirrors SEARCH_TERM
- LOCATION: Geographic location string. Default: "Canada"
- RESULTS_WANTED: Max results to fetch. Default: 20
- HOURS_OLD: Max age in hours. Default: 24
- COUNTRY_INDEED: Country code for Indeed. Default: "canada"
- LINKEDIN_FETCH_DESCRIPTION: "true"/"false" to fetch long description. Default: "true"
- DATA_DIR: Output directory. Default: "/DATA"

Usage
$ python3 collector.py
$ SITE_NAME=linkedin SEARCH_TERM="platform engineer" python3 collector.py --results 100

flow:

scraper for multiple search terms, and writes aggregated results to a CSV file. It 
    performs the following steps and side effects:
        to environment variables. **Command-line arguments override environment variables.**
            - SEARCH_TERMS: "Azure,devops" (comma-separated list of search terms)
            - GOOGLE_SEARCH_TERM: defaults to current search_term if not provided
    - Builds a list of search terms from the SEARCH_TERMS CSV string and iterates through
        each term to collect job postings.
    - For each search term:
            - Prints progress message to stdout.
                pandas.DataFrame (or similar object).
            - Aggregates results from all search terms into a single DataFrame using pd.concat.
    - Writes the aggregated DataFrame to CSV using pandas.DataFrame.to_csv(..., 
        quoting=csv.QUOTE_NONNUMERIC, escapechar="\\", index=False, encoding='utf-8-sig').
    - Prints progress and summary messages to stdout, including per-term processing status
        and total job count.
            - 0 on success (CSV written with aggregated results from all search terms)
            - 2 if scrape_jobs raises an exception for any search term (scrape failure)
        scrape_jobs (called once per search term), and writing a single CSV file to disk
        containing all aggregated results.
    - The function loops through multiple search terms and aggregates all results before
        writing to a single output file.
"""
from __future__ import annotations
import csv
import os
import sys
import argparse
from typing import List
from jobspy import scrape_jobs

#print a friendly message on startup
print("[collector] Starting job collector...",flush=True)
def _env(key: str, default: str) -> str:
    val = os.getenv(key, default)
    return val

# if the output file already exists, inform the user and quit.
if os.path.exists(os.path.join(os.environ["DATA_DIR"], "flat_jobs_list.csv")):
    print(f"[collector] Output file already exists at {os.path.join(os.environ['DATA_DIR'], 'flat_jobs_list.csv')}. Please remove it before running again.",flush=True)
    print(f"[collector] Exiting normally...",flush=True)
    sys.exit(0)




def _env_bool(key: str, default: bool) -> bool:
    raw = os.getenv(key)
    if raw is None:
        return default
    return str(raw).strip().lower() in {"1", "true", "yes", "y"}

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Scrape jobs with jobspy and save CSV.")
    p.add_argument("--site", help="Comma-separated site list, e.g., indeed,linkedin,glassdoor")
    p.add_argument("--terms", help="Comma-separated search term list")
    p.add_argument("--google-term", help="Google Jobs search term override")
    p.add_argument("--location", help="Location filter")
    p.add_argument("--results", type=int, help="Max results to fetch")
    p.add_argument("--hours-old", type=int, help="Max age in hours")
    p.add_argument("--country-indeed", help="Indeed country")
    p.add_argument("--linkedin-fetch-description", action="store_true", help="Fetch LinkedIn descriptions")
    p.add_argument("--no-linkedin-fetch-description", action="store_true", help="Disable LinkedIn long descriptions")
    p.add_argument("--data-dir", help="Output directory")
    return p.parse_args()

def main() -> int:
    
    """
    Main entry point for the job collector.

    This function parses command-line arguments and environment variables, runs the job
    scraper, and writes results to a CSV file. It performs the following steps and side
    effects:

    - Reads configuration from command-line arguments (via parse_args()) with fallbacks
        to environment variables. **Command-line arguments override environment variables.
    - Environment variables used (and their defaults):
            - SITE_NAME: "indeed,linkedin,glassdoor"
            - SEARCH_TERM: "Azure devops"
            - GOOGLE_SEARCH_TERM: defaults to SEARCH_TERM if not provided
            - LOCATION: "Canada"
            - RESULTS_WANTED: "20"
            - HOURS_OLD: "24"
            - COUNTRY_INDEED: "canada"
            - LINKEDIN_FETCH_DESCRIPTION: True
            - DATA_DIR: "/DATA"
    - Builds a list of site names from the SITE_NAME CSV string.
    - Resolves linkedin_fetch_description by honoring explicit flags:
            - If both --linkedin-fetch-description and --no-linkedin-fetch-description are set,
                the function prefers disabling fetching and prints a warning to stderr.
            - Otherwise, the explicit flag takes precedence, then the LINKEDIN_FETCH_DESCRIPTION
                environment variable value.
    - Ensures the DATA_DIR exists (os.makedirs(..., exist_ok=True)) and writes output to
        DATA_DIR/flat_jobs_list.csv.
    - Calls scrape_jobs(...) with the resolved parameters. The expected return value is a
        pandas.DataFrame (or similar object) assigned to `jobs`.
    - Writes `jobs` to CSV using pandas.DataFrame.to_csv(..., quoting=csv.QUOTE_NONNUMERIC,
        escapechar="\\", index=False).

    Logging and exit codes:
    - Prints progress and summary messages to stdout.
    - Prints error messages to stderr.
    - Returns integer exit codes:
            - 0 on success (CSV written)
            - 2 if scrape_jobs raises an exception (scrape failure)
            - 3 if writing the CSV raises an exception (write failure)

    Notes:
    - The function has no parameters and relies entirely on parse_args() and environment
        variables for configuration.
    - Side effects include console output, directory creation, network/activity performed by
        scrape_jobs, and writing a CSV file to disk.
    """
    args = parse_args()

    site_csv = args.site or _env("SITE_NAME", "indeed,linkedin,glassdoor")
    site_name: List[str] = [s.strip() for s in site_csv.split(",") if s.strip()]

    #search_term = args.term or _env("SEARCH_TERM", "Azure devops")
    #we are going to convert search term to a search terms, plural as a comma seoarated string, to which we are going to make an arry then loop through each term to get more results
    search_term_csv = args.terms or _env("SEARCH_TERMS", "Azure,devops")
    search_terms: List[str] = [s.strip() for s in search_term_csv.split(",") if s.strip()]
    
    #initialize a new dataframe to append results to
    import pandas as pd
    jobcollected = pd.DataFrame()
    totaljobcount = 0
    for search_term in search_terms:
        print(f"[collector] Processing search term: '{search_term}'",flush=True)
        google_term = args.google_term or _env("GOOGLE_SEARCH_TERM", search_term)
        location = args.location or _env("LOCATION", "Canada")
        results_wanted = args.results or int(_env("RESULTS_WANTED", "20"))
        hours_old = args.hours_old or int(_env("HOURS_OLD", "24"))
        country_indeed = args.country_indeed or _env("COUNTRY_INDEED", "canada")
        if args.linkedin_fetch_description and args.no_linkedin_fetch_description:
            print("Both --linkedin-fetch-description and --no-linkedin-fetch-description set; prefer disable.", file=sys.stderr)
        linkedin_fetch_description = (
            False if args.no_linkedin_fetch_description else
            True if args.linkedin_fetch_description else
            _env_bool("LINKEDIN_FETCH_DESCRIPTION", True)
        )
        data_dir = args.data_dir or _env("DATA_DIR", "/DATA")
        os.makedirs(data_dir, exist_ok=True)
        out_csv = os.path.join(data_dir, "flat_jobs_list.csv")

        print(f"[collector] sites={site_name} term='{search_term}' location='{location}' results={results_wanted} hours_old={hours_old}")
        try:
            jobs = scrape_jobs(
                site_name=site_name,
                search_term=search_term,
                google_search_term=google_term,
                location=location,
                results_wanted=results_wanted,
                hours_old=hours_old,
                country_indeed=country_indeed,
                linkedin_fetch_description=linkedin_fetch_description,
            )
        except Exception as e:
            print(f"[collector] scrape failed: {e}", file=sys.stderr)
            return 2
        totaljobcount += len(jobs)
        jobcollected = pd.concat([jobcollected, jobs], ignore_index=True)


    print(f"[collector] Found {totaljobcount} jobs")
    try:
        jobcollected.to_csv(out_csv, quoting=csv.QUOTE_NONNUMERIC, escapechar="\\", index=False,encoding='utf-8-sig')
        print(f"[collector] wrote {out_csv}")
    except Exception as e:
        print(f"[collector] write failed: {e}", file=sys.stderr)
        return 3
        
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
