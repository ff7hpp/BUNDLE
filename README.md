# BUNDLE

![BUNDLE logo](bundle_logo_v4.svg)

**BUNDLE packs a project into one AI-ready file.**

It is a PowerShell script for developers who want to send a clean snapshot of a codebase to an AI assistant, reviewer, or teammate without copying files one by one.

## What Is This Tool?

BUNDLE scans a project folder, collects useful source files, skips common private or generated files, and writes the result into one output file.

You can use the output file to:

- ask an AI tool to review a project
- share a small codebase snapshot
- prepare a project for debugging help
- check for obvious secrets before sharing code

## What It Creates

BUNDLE can create:

- Markdown bundle: `bundle.md`
- Text bundle: `bundle.txt`
- JSON bundle: `bundle.json`
- HTML report: `bundle.html`

The Markdown format is the easiest one to read and is usually the best choice for AI tools.

## Requirements

- PowerShell 7 or newer
- No package installation required

Check your PowerShell version:

```powershell
pwsh --version
```

## How To Use

Clone this repository:

```powershell
git clone https://github.com/ff7hpp/BUNDLE.git
cd BUNDLE
```

Run BUNDLE on a project folder:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\BUNDLE.ps1 -ProjectRoot "C:\path\to\your\project" -OutputDir "C:\path\to\output" -Format md -Redact
```

Simple example from inside the project you want to bundle:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\BUNDLE.ps1 -ProjectRoot . -OutputDir . -OutputFile bundle.md -Format md -Redact
```

## Useful Options

| Option | What it does |
| --- | --- |
| `-ProjectRoot` | Folder to scan. |
| `-OutputDir` | Folder where the bundle is saved. |
| `-OutputFile` | Custom output filename. |
| `-Format` | Output type: `md`, `txt`, `json`, or `html`. |
| `-Redact` | Redacts detected secret values in the output. |
| `-DryRun` | Tests the scan without writing a bundle. |
| `-BuildDepGraph` | Adds a simple dependency graph. |

## Safety Notes

BUNDLE helps reduce risk, but you should still review the generated file before sharing it.

Do not share bundles that contain:

- `.env` files
- API keys
- private keys
- passwords
- credentials or tokens
- personal data
- private project files you did not mean to include

Use `-Redact` when preparing a bundle for anyone else.

## Project Files

```text
BUNDLE/
├── BUNDLE.ps1
├── README.md
├── ARCHITECTURE.md
├── LICENSE
├── .gitignore
└── bundle_logo_v4.svg
```

For deeper technical details, read [`ARCHITECTURE.md`](ARCHITECTURE.md).

## License

MIT License. See [`LICENSE`](LICENSE).
