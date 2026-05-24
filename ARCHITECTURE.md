# BUNDLE Architecture

This file explains how `BUNDLE.ps1` works internally. The README is intentionally short, so this document is the place for deeper technical notes.

## Purpose

BUNDLE turns a project folder into a single reviewable file. It is designed for AI-assisted code review, debugging, and project sharing.

The script does not compile or execute the target project. It reads files, analyzes text, and writes a bundle or report.

## Main Flow

`BUNDLE.ps1` runs in these stages:

1. Resolve the input project path and output path.
2. Discover files under `-ProjectRoot`.
3. Filter out ignored folders, generated files, binary files, large files, and unsafe environment files.
4. Read each included file as text.
5. Extract lightweight metadata:
   - language
   - imports
   - exports
   - simple complexity score
   - line counts
   - token estimate
   - possible secret findings
6. Redact detected secrets when `-Redact` is used.
7. Optionally build a simple dependency graph.
8. Write the selected output format.

## Inputs

Important parameters:

| Parameter | Role |
| --- | --- |
| `-ProjectRoot` | Root folder to scan. |
| `-OutputDir` | Folder where output is written. |
| `-OutputFile` | Optional custom output filename. |
| `-Format` | Output format: `md`, `txt`, `json`, or `html`. |
| `-Redact` | Replaces detected secret values with redaction markers. |
| `-DryRun` | Runs discovery and analysis without writing a bundle. |
| `-BuildDepGraph` | Builds a simple dependency graph from extracted imports. |
| `-GenerateHTML` | Creates an HTML report next to non-HTML output. |
| `-ExtraExtensions` | Adds file extensions to include. |
| `-ExtraExcludes` | Adds folder names to exclude. |

## File Discovery

The script includes common source and documentation file types, such as:

- PowerShell
- Python
- JavaScript and TypeScript
- HTML and CSS
- JSON, YAML, TOML, XML
- Markdown and text
- Java, C#, Go, Rust, PHP, Ruby, SQL, shell scripts

It excludes common folders and files that are usually not useful in an AI bundle:

- `.git`
- `node_modules`
- build output
- dependency caches
- virtual environments
- test reports
- binary/media/archive files
- lock files
- `.env` files

Template environment files such as `.env.example` and `.env.sample` are allowed.

## Analysis

BUNDLE uses lightweight text analysis. It is intentionally simple and dependency-free.

Current analysis includes:

- regex-based import extraction
- regex-based export extraction
- basic cyclomatic complexity estimate
- duplicate-line ratio
- estimated token count
- secret-pattern scanning
- basic risk score

The dependency analysis is not a full compiler, parser, or AST engine. It is useful for orientation, not for perfect static analysis.

## Secret Scanning

The script checks for common secret patterns, including examples such as:

- API keys
- GitHub tokens
- AWS access keys
- private key blocks
- database connection strings
- generic passwords and secrets

When `-Redact` is enabled, matched values are replaced in bundle content and in report metadata.

Secret scanning is best-effort. Users should manually review output before sharing.

## Outputs

Supported output formats:

| Format | Use |
| --- | --- |
| `md` | Best default for AI tools and human reading. |
| `txt` | Plain text bundle. |
| `json` | Structured output for tools. |
| `html` | Browser-readable report. |

For non-HTML formats, `-GenerateHTML` can also create an HTML report.

## Design Choices

- Single-file script: easy to download and run.
- No external dependencies: simpler setup.
- Conservative exclusions: reduces accidental noise and private-file exposure.
- Redaction option: safer sharing workflow.
- Markdown-first output: practical for AI tools.

## Known Limits

- Secret scanning can miss unusual formats.
- Secret scanning can produce false positives.
- Dependency extraction is regex-based.
- Output can still contain sensitive business logic or private source code.
- Large projects can create very large bundle files.

## Recommended Future Improvements

- Add automated tests for all output formats.
- Add CI parser checks for `BUNDLE.ps1`.
- Improve dependency extraction with language-specific parsers.
- Add clearer output summaries for large projects.
- Add a safer default output location outside the scanned project.
