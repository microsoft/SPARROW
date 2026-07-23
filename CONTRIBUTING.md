# Contributing to SPARROW

Thank you for your interest in contributing to SPARROW. Contributions can
include bug fixes, documentation improvements, hardware compatibility updates,
and new capabilities for the SPARROW client.

## Before you start

- Search the [existing issues](https://github.com/microsoft/SPARROW/issues) to
  avoid duplicating work.
- For bugs, include the SPARROW version or commit, hardware, operating system,
  Docker version, logs with sensitive values removed, and reproducible steps.
- For substantial changes, open an issue before implementation so the approach
  and hardware impact can be discussed.
- Report security vulnerabilities according to [SECURITY.md](SECURITY.md), not
  through a public issue.

## Development setup

SPARROW targets Raspberry Pi 5 hardware and runs its services with Docker
Compose. Follow the setup and hardware guidance in [README.md](README.md) for a
complete deployment.

To prepare a contribution:

1. Fork the repository and clone your fork.
2. Create a branch from the latest `main`.
3. Make a focused change and update related documentation.
4. Validate the change using the checks below.
5. Open a pull request describing the problem, solution, and validation.

Do not commit access keys, passwords, private certificates, deployment data, or
real field recordings and images. Remove personal data, precise deployment
locations, device identifiers, and credentials from logs and examples.

## Validation

The repository does not currently include an automated test suite. Run the
checks that apply to your change and describe any hardware validation in the
pull request.

```bash
# Check Python syntax.
python3 -m compileall -q sparrow starlink

# Validate the Compose configuration.
docker-compose config

# Build the affected services on a supported Docker host.
docker-compose build sparrow starlink-tools

# Check for whitespace errors.
git diff --check
```

Changes involving cameras, audio devices, environmental sensors, XBee radios,
Starlink, power management, or Raspberry Pi GPIO should be tested on the
relevant hardware when possible. If hardware validation is not possible,
clearly identify what remains untested.

## Pull request checklist

- Keep the change focused and avoid unrelated cleanup.
- Explain user-visible behavior changes and compatibility considerations.
- Update the README or other documentation when setup, configuration, hardware,
  or operational behavior changes.
- Add notable changes to the next semantic version section in
  [CHANGELOG.md](CHANGELOG.md).
- Confirm that no secrets, credentials, personal data, or deployment data are
  included.
- Include validation commands and results in the pull request description.

## Contributor License Agreement

Most contributions require you to agree to a Contributor License Agreement
(CLA) declaring that you have the right to, and actually do, grant us the
rights to use your contribution. For details, visit
[Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will determine whether you need to
provide a CLA and will add the appropriate status check or comment. Follow the
bot's instructions. You only need to complete this process once across
repositories that use the Microsoft CLA.

## Code of Conduct

This project follows the
[Microsoft Open Source Code of Conduct](CODE_OF_CONDUCT.md). For questions or
concerns, see the contact information in that document.
