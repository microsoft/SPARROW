---
description: "How to build and deploy the SPARROW MkDocs documentation site locally and to GitHub Pages."
tags:
  - SPARROW
  - documentation
  - MkDocs
  - developer-guide
---

# Developer Guide — Building the Docs

This page explains how to build and preview the SPARROW documentation site locally.

## Prerequisites

Install the documentation dependencies (separate from the ML/hardware requirements):

```bash
pip install -r docs-requirements.txt
```

## Local Preview

Start the live-reload dev server:

```bash
mkdocs serve
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000) in your browser. The site rebuilds automatically when you save any file under `docs/` or `mkdocs.yml`.

## Build (Static)

To build the static site without serving it:

```bash
mkdocs build
```

Output goes to `site/` (gitignored — never commit this directory).

## Deploy to GitHub Pages

Deployment happens automatically via GitHub Actions on every push to `main` that touches `docs/**`, `mkdocs.yml`, or `docs-requirements.txt`. The workflow in `.github/workflows/deploy-docs.yml` builds the site and force-pushes to the `gh-pages` branch.

To deploy manually:

```bash
mkdocs gh-deploy --force
```

## Adding a New Page

1. Create `docs/<page-name>.md` with the required SEO front matter:

```yaml
---
description: "One-sentence description for search engines and the site description meta tag."
tags:
  - SPARROW
  - relevant-tag
---
```

2. Add the page to the `nav:` section of `mkdocs.yml`.
