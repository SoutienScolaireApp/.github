# Security policy

This policy covers every repository of the SoutienScolaireApp organization. The platform processes personal data of children and their parents, and the tracking repositories hold the records of the Parties. Vulnerabilities are handled privately until they are fixed.

## Reporting a vulnerability

Do **not** open a regular issue, pull request or discussion that describes an exploitable vulnerability.

Report it privately through one of these channels:

- **GitHub private vulnerability reporting** (preferred): open the [Report a vulnerability form](https://github.com/SoutienScolaireApp/.github/security/advisories/new) of the public `SoutienScolaireApp/.github` repository (its **Security** tab, then **Report a vulnerability**). You need a GitHub account. The report stays private: only you and the administrators and security managers of the organization can see it.
- **Email**: **<dev@monatelierweb.com>**, if you cannot or prefer not to use GitHub.

GitHub offers private vulnerability reporting on public repositories only, and each repository enables it separately. `.github` is the only public repository of the organization, so its form is the GitHub channel for every repository, the private ones included: name the affected repository in the report.

Include in the report:

- the repository and the affected component, version or commit;
- a description of the issue and its impact;
- the steps to reproduce, using synthetic data only;
- whether you believe it is being exploited.

Never include real personal data, credentials or tokens in the report. If you found a leaked secret, say where it is without copying it.

## What happens next

- Acknowledgement within 3 working days.
- An assessment of severity and a remediation plan within 10 working days.
- The fix is tracked in a ticket labelled `security` (and `privacy` when personal data is involved) that does not describe the exploit until the fix is deployed.
- A critical or high finding blocks merges and releases on the affected repository until it is fixed.
- If personal data may have been exposed, the GDPR breach procedure applies (assessment and, where required, notification to the supervisory authority within 72 hours).

## Supported versions

Only the latest state of `develop` and the version currently deployed in production receive security fixes.
