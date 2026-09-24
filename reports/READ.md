# USG Security Assessment Reports

This directory contains the Ubuntu Security Guide (USG) / OpenSCAP security assessment reports generated during the mail server hardening project.

The reports use the **CIS Ubuntu Linux 24.04 LTS Benchmark – Level 1 Server** profile to evaluate the Ubuntu server against a defined set of security configuration rules.

Multiple reports were retained to document the state of the system before deployment, before hardening, during remediation, and after the final hardening pass.

## Report Progression

| Report | Stage | Passed | Failed | Score |
|---|---|---:|---:|---:|
| `usg-baseline.html` | Initial Ubuntu baseline | 232 | 109 | 71.2% |
| `usg-pre-hardening.html` | Deployed mail server before hardening | 227 | 115 | 64.63% |
| `usg-framework-hardening.html` | First hardening pass | 232 | 110 | 64.92% |
| `usg-ssh-hardening.html` | SSH hardening pass | 247 | 96 | 65.65% |
| `usg-outliers-attempt.html` | Initial remediation of remaining/outlier rules | 247 | 96 | 65.65% |
| `usg-final.html` | Final verified configuration | 249 | 94 | 66.23% |

## What Each Report Represents

### `usg-baseline.html` — Initial Baseline

The baseline report represents the initial security posture of the Ubuntu Server before the complete mail-server environment was deployed.

It provides an early reference point for the project and recorded:

- **232 passed rules**
- **109 failed rules**
- **71.2% USG score**

Because the software and service footprint changed as Postfix, Dovecot, Apache, Roundcube, and related components were deployed, this report should not be treated as a direct one-to-one comparison with the final mail server.

### `usg-pre-hardening.html` — Pre-Hardening

This report represents the completed mail-server environment immediately before security hardening began.

At this point, the mail-server services had been deployed and tested, making this the primary starting point for measuring the hardening work.

The scan recorded:

- **227 passed rules**
- **115 failed rules**
- **64.63% USG score**

### `usg-framework-hardening.html` — Framework Hardening Pass

This report was generated after the first group of system-level hardening changes was applied.

The scan recorded:

- **232 passed rules**
- **110 failed rules**
- **64.92% USG score**

This reduced the number of failed rules from 115 to 110.

### `usg-ssh-hardening.html` — SSH Hardening Pass

This report was generated after applying additional SSH-focused security configuration changes.

The scan recorded:

- **247 passed rules**
- **96 failed rules**
- **65.65% USG score**

This stage produced a significant reduction in remaining failed rules.

### `usg-outliers-attempt.html` — Outlier Remediation Attempt

This scan represents an intermediate attempt to address additional remaining rules and configuration outliers.

The scan still recorded:

- **247 passed rules**
- **96 failed rules**
- **65.65% USG score**

The report was retained to document the iterative troubleshooting and validation process rather than only showing the successful result.

### `usg-final.html` — Final Assessment

This report represents the final verified state of the hardened mail server after the remaining successful remediation changes were applied.

The final scan recorded:

- **249 passed rules**
- **94 failed rules**
- **66.23% USG score**

Compared with the deployed **pre-hardening** state, the final configuration reduced the number of failed rules from **115 to 94**, for a total reduction of **21 failed rules**.

## Viewing the Reports

The USG/OpenSCAP reports are large standalone HTML files containing the complete benchmark results, rule descriptions, remediation guidance, references, and scoring information.

Because of their size, GitHub may not render the reports directly in the browser.

To view a report:

1. Download the desired `.html` file.
2. Open the downloaded file locally in a web browser such as Chrome, Firefox, or Edge.
3. Use the report's built-in rule navigation and search tools to review individual results.

No web server is required to view the downloaded reports.

## Public Report Sanitization

The reports included in this public repository are **sanitized copies** of the original assessment output.

Environment-specific or identifying information that was not necessary to demonstrate the security assessment and hardening process was removed or replaced before publication.

The security rule results, pass/fail status, benchmark information, scoring data, and remediation results were preserved so that the reports continue to accurately document the project's hardening process.

## Interpreting the Results

The USG score should be considered alongside the individual rule results rather than treated as the sole measurement of improvement.

The initial baseline was collected before the complete mail-server software stack was deployed. Installing and enabling additional services changes the system being evaluated and can affect which security rules are applicable and how the resulting assessment is scored.

For this reason, the most relevant comparison for the hardening phase is:

**Pre-Hardening: 115 failed rules → Final: 94 failed rules**

The intermediate reports are retained to show how the configuration was hardened and validated incrementally rather than presenting only the final assessment.
