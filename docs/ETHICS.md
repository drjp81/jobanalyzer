# Ethical, legal and operational guidance

This document describes considerations and recommended safeguards when using JobAnalyzer. It is not legal advice. Adapt the policies to match local laws and your organisation's requirements.

## Summary
Use this tool responsibly. JobAnalyzer scrapes job postings and processes candidate resumes with language models. That combination raises legal, privacy, security and fairness concerns. Follow the recommendations in this document before running JobAnalyzer on production data.

## 1) Scraping and site Terms of Service
- Verify that scraping any job board or website is permitted by that site's Terms of Service (ToS) and robots.txt.
- Prefer official APIs where available.
- Implement rate limits, exponential backoff on errors, randomized delays between requests, and a small concurrency level to avoid overloading target sites.
- Keep audit logs of where you scraped data from and when.

## 2) Candidate privacy and PII
- Resumes and other candidate artifacts often contain personal data (names, contact information, employment history, dates, addresses). Treat this information as PII/Personal Data.
- Minimize retention: only store fields you need and delete raw resumes when they are no longer necessary.
- Do not commit resumes, API keys, or any secrets into the repository.
- Consider encryption at rest for any stored PII.

## 3) Consent and lawful basis
- Process candidate data only where you have a lawful basis (consent, contractual necessity, or legitimate interest) under applicable law (e.g., GDPR, CCPA).
- Inform candidates how their data will be used and provide a way to request deletion (DSR).
- Keep simple, clear notices describing that automated scoring will be performed and whether outputs may be used in hiring decisions.

## 4) Security and secrets management
- Store API keys, tokens and credentials in secure secret stores or environment variables. Rotate keys regularly.
- Limit access to production data and logs to authorized personnel only.
- Use HTTPS for all network communication to providers and services.

## 5) Responsible AI and model limitations
- Model scores are heuristic and can be biased, inconsistent, or hallucinate. Treat model outputs as assistive signals, not final decisions.
- Ensure human-in-the-loop review for any decision that materially affects candidates (shortlisting, rejections, job offers).
- Record which model and provider were used (model name & version, workspace slug/prompt variables) for auditability.

## 6) Bias, fairness and non-discrimination
- Avoid including protected attributes (e.g., race, religion, sex, age) in automated decisions.
- Monitor model outputs for disparate impact across demographic groups and tune or stop usage if harmful patterns appear.
- Logging should avoid recording unnecessary PII used for fairness analysis; use anonymized identifiers where possible.

## 7) Logging, retention and auditing
- Log evaluation metadata (timestamp, model/provider, workspace slug, non-sensitive job identifier) for reproducibility and debugging.
- Keep logs and data only as long as necessary; document retention periods.
- Maintain an audit trail for runs that influence decisions.

## 8) Use restrictions and acceptable behavior
- Do not use this software for unsolicited bulk applications, spamming, or any activity that violates platforms' ToS or local law.
- Do not use the tool to perform covert or deceptive operations that would harm candidates, employers or the public.

## 9) Licensing and attributions
- This repository is proposed to be licensed under the MIT License (see LICENSE).
- Respect the licenses of all third-party components and models. Maintain a record of third-party license attributions.

## 10) How to adapt this guidance
- Treat this file as a baseline. Organisations should produce or adopt formal policies (data protection, retention, incident response) that match their legal obligations and operational risk.
- If you want, I can propose a deletion/DSR workflow, a short privacy notice to display to candidates, or example logging config lines.
