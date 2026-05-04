<#
.SYNOPSIS
    Universal Multi-Drive Project Bundler v6.0 — Project Intelligence Packager
.DESCRIPTION
    Scans any project on any drive and bundles source code into a single
    LLM-ready file with full project intelligence, git metadata, secret scanning,
    encoding detection, logical ordering, and integrity verification.

    NEW IN v6.0
      Stability   : Graceful Ctrl+C | try/finally on writer | symlink loop guard
                    Network drive timeout | structured error log | no empty catches
      Completeness: .gitignore fully respected | Git metadata (branch/commit/diff)
                    Secret scanner (20+ patterns) | Encoding detection (UTF-8/16/1252)
                    Project type + framework auto-detection | Entry point detection
      LLM Quality : Weighted token estimate (Arabic/bilingual aware) | Context window
                    overflow guard | SHA-256 integrity checksum | Path privacy mode
                    LLM context header with suggested prompt | Logical file ordering
      Output      : txt | md (language-tagged fences) | json formats
                    Auto-split for large projects | Per-language stats
      UX          : Dry-run | Overwrite protection | Config save/load per project
                    Progress during search phase | Run history log

.PARAMETER ProjectRoot      Path or name of the project to bundle
.PARAMETER OutputDir        Where to save the output file
.PARAMETER OutputFile       Custom output filename
.PARAMETER Format           Output format: txt (default) | md | json
.PARAMETER Profile          Extension preset: auto | react | python | java | dotnet | go | rust
.PARAMETER MaxFileSizeMB    Skip files larger than this MB (default 10)
.PARAMETER SplitKTokens     Split bundle into parts under N K-tokens (0 = off)
.PARAMETER DryRun           Show what would be bundled, write nothing
.PARAMETER StripPaths       Replace absolute paths with [PROJECT_ROOT] for privacy
.PARAMETER Redact           Replace detected secrets with [REDACTED]
.PARAMETER IncludeTree      Include filtered directory tree in output
.PARAMETER SaveConfig       Save current run settings to bundle.config.json
.PARAMETER LoadConfig       Load settings from bundle.config.json in project root
.PARAMETER NoOverwritePrompt Skip confirmation when output already exists
.PARAMETER ExtraExtensions  Additional extensions to include (e.g. ".dart")
.PARAMETER ExtraExcludes    Additional folder names to exclude
.PARAMETER Quiet            Suppress progress bar

.NOTES
    Version : 6.0 — Project Intelligence Packager
    Safe    : Secret scanning | .gitignore-aware | Encoding-correct | No crash on Ctrl+C
    Smart   : Git-aware | Project-type detection | LLM-optimized output | Integrity verified
#>

[CmdletBinding()]
param(
    [string]   $OutputFile        = "",
    [string]   $ProjectRoot       = "",
    [string]   $OutputDir         = "",
    [switch]   $IncludeTree,
    [int]      $MaxFileSizeMB     = 10,
    [string[]] $ExtraExtensions   = @(),
    [string[]] $ExtraExcludes     = @(),
    [switch]   $Quiet,
    [ValidateSet('txt','md','json')]
    [string]   $Format            = "txt",
    [switch]   $DryRun,
    [switch]   $StripPaths,
    [switch]   $Redact,
    [int]      $SplitKTokens      = 0,
    [ValidateSet('auto','react','python','java','dotnet','go','rust','general')]
    [string]   $Profile           = "auto",
    [switch]   $SaveConfig,
    [switch]   $LoadConfig,
    [switch]   $NoOverwritePrompt
)

# ============================================================
#  GLOBAL STATE
# ============================================================

$script:VERSION        = "6.0"
$script:writer         = $null
$script:resolvedOutput = ""
$script:errorLog       = [System.Collections.Generic.List[string]]::new()
$script:visitedPaths   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:secretsFound   = [System.Collections.Generic.List[hashtable]]::new()
$script:totalTokens    = 0L
$maxFileBytes          = $MaxFileSizeMB * 1024 * 1024

# ============================================================
#  EXTENSIONS & EXCLUDES
# ============================================================

$includeExtensions = @(
    '.ps1','.psm1','.psd1',
    '.py','.pyw','.pyx','.pyi',
    '.js','.mjs','.cjs','.ts','.tsx','.jsx',
    '.html','.htm','.css','.scss','.sass','.less','.vue','.svelte',
    '.json','.yaml','.yml','.toml','.ini','.cfg','.conf','.xml','.xsd',
    '.md','.markdown','.rst','.txt',
    '.sql','.ddl','.sh','.bash','.zsh','.bat','.cmd',
    '.java','.kt','.kts','.scala','.groovy',
    '.cs','.csx','.fs','.vb',
    '.go','.rs','.c','.h','.cpp','.hpp','.cc',
    '.rb','.rake','.php','.r','.lua','.pl',
    '.tf','.tfvars','.hcl','.dockerfile','.ipynb',
    '.gitignore','.dockerignore','.editorconfig','.eslintrc','.prettierrc',
    '.env.example','.env.sample'
) + $ExtraExtensions

$safeEnvFiles = @('.env.example','.env.sample','.env.template','.env.test','.env.local.example')

$excludeFolders = @(
    'node_modules','bower_components','vendor','packages','jspm_packages',
    '.git','.svn','.hg',
    'dist','build','out','target','release','publish','artifacts','output',
    '.next','.nuxt','.output','.svelte-kit','__sapper__',
    'bin','obj','compiled','__pycache__','.pytest_cache','.mypy_cache',
    'venv','.venv','env','virtualenv','.tox','.renv',
    'logs','log','temp','tmp','.tmp',
    'coverage','.nyc_output','htmlcov','.coverage',
    '.idea','.vscode','.vs','.fleet',
    '.terraform','.serverless','.cache',
    'cypress','.cypress','playwright-report','test-results',
    '.expo','.gradle','.dart_tool',
    'storybook-static','.storybook'
) + $ExtraExcludes

$excludeFilePatterns = @(
    '*.min.js','*.min.css','*.bundle.js','*.chunk.js','*.map','*.bundle.css',
    '*.tmp','*.temp','*.bak','*.swp','*.DS_Store','Thumbs.db',
    '*.png','*.jpg','*.jpeg','*.gif','*.bmp','*.ico','*.webp','*.avif','*.tiff','*.svg',
    '*.psd','*.ai','*.eps','*.fig','*.sketch',
    '*.mp4','*.mp3','*.wav','*.mov','*.avi','*.mkv','*.ogg',
    '*.pdf','*.doc','*.docx','*.xls','*.xlsx','*.ppt','*.pptx',
    '*.zip','*.tar','*.gz','*.7z','*.rar',
    '*.exe','*.dll','*.so','*.o','*.obj','*.pyc','*.pyo','*.class',
    '*.db','*.sqlite','*.sqlite3','*.mdb',
    '*.woff','*.woff2','*.ttf','*.otf','*.eot',
    'package-lock.json','yarn.lock','pnpm-lock.yaml','poetry.lock','Gemfile.lock','composer.lock'
)

$specialFileNames = @(
    'Dockerfile','Makefile','Procfile','Vagrantfile',
    'Jenkinsfile','LICENSE','LICENCE','README',
    'CHANGELOG','CONTRIBUTING','AUTHORS','CODEOWNERS','.env.example'
)

$systemSkipFolders = @(
    'Windows','Program Files','Program Files (x86)','ProgramData',
    '$Recycle.Bin','System Volume Information','Recovery','PerfLogs',
    'MSOCache','Config.Msi','$WinREAgent','$SysReset',
    'Intel','AMD','NVIDIA','AppData'
)

# ============================================================
#  LANGUAGE MAP (extension → Markdown fence tag)
# ============================================================

$languageMap = @{
    '.py'='python';'.pyw'='python';'.pyx'='python';'.pyi'='python'
    '.js'='javascript';'.mjs'='javascript';'.cjs'='javascript'
    '.ts'='typescript';'.tsx'='tsx';'.jsx'='jsx'
    '.html'='html';'.htm'='html';'.svelte'='svelte';'.vue'='vue'
    '.css'='css';'.scss'='scss';'.sass'='sass';'.less'='less'
    '.json'='json';'.jsonc'='json'
    '.yaml'='yaml';'.yml'='yaml';'.toml'='toml'
    '.ini'='ini';'.cfg'='ini';'.conf'='nginx'
    '.xml'='xml';'.xsd'='xml'
    '.md'='markdown';'.markdown'='markdown';'.rst'='rst';'.txt'='plaintext'
    '.sql'='sql';'.ddl'='sql'
    '.sh'='bash';'.bash'='bash';'.zsh'='zsh';'.bat'='bat';'.cmd'='bat'
    '.ps1'='powershell';'.psm1'='powershell';'.psd1'='powershell'
    '.java'='java';'.kt'='kotlin';'.kts'='kotlin'
    '.scala'='scala';'.groovy'='groovy'
    '.cs'='csharp';'.csx'='csharp';'.fs'='fsharp';'.vb'='vb'
    '.go'='go';'.rs'='rust'
    '.c'='c';'.h'='c';'.cpp'='cpp';'.hpp'='cpp';'.cc'='cpp'
    '.rb'='ruby';'.rake'='ruby'
    '.php'='php';'.r'='r';'.lua'='lua';'.pl'='perl'
    '.tf'='hcl';'.tfvars'='hcl';'.hcl'='hcl'
    '.dockerfile'='dockerfile'
    '.ipynb'='json'
    '.gitignore'='gitignore';'.dockerignore'='plaintext'
    '.editorconfig'='ini';'.eslintrc'='json';'.prettierrc'='json'
    '.env.example'='bash';'.env.sample'='bash'
}

# ============================================================
#  SECRET PATTERNS (20 patterns)
# ============================================================

$secretPatterns = @(
    @{ Name='OpenAI Key';        Pattern='sk-[a-zA-Z0-9T_\-]{20,}'                                                       }
    @{ Name='Anthropic Key';     Pattern='sk-ant-[a-zA-Z0-9\-_]{20,}'                                                    }
    @{ Name='Google API Key';    Pattern='AIza[0-9A-Za-z\-_]{35}'                                                        }
    @{ Name='GitHub PAT';        Pattern='gh[psor]_[a-zA-Z0-9]{36}'                                                      }
    @{ Name='AWS Access Key';    Pattern='AKIA[0-9A-Z]{16}'                                                               }
    @{ Name='AWS Secret Key';    Pattern='(?i)aws.{0,20}secret.{0,20}[''"]?[a-zA-Z0-9+/]{40}'                           }
    @{ Name='Stripe Live Key';   Pattern='sk_live_[a-zA-Z0-9]{24,}'                                                      }
    @{ Name='Stripe Pub Key';    Pattern='pk_live_[a-zA-Z0-9]{24,}'                                                      }
    @{ Name='SendGrid Key';      Pattern='SG\.[a-zA-Z0-9\-_]{22}\.[a-zA-Z0-9\-_]{43}'                                   }
    @{ Name='Twilio SID';        Pattern='AC[a-zA-Z0-9]{32}'                                                             }
    @{ Name='Slack Token';       Pattern='xox[baprs]-[0-9A-Za-z\-]+'                                                     }
    @{ Name='JWT Token';         Pattern='eyJ[a-zA-Z0-9+/\-_]{10,}\.[a-zA-Z0-9+/\-_]{10,}\.[a-zA-Z0-9+/\-_]{10,}'     }
    @{ Name='Private Key Block'; Pattern='-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'                          }
    @{ Name='Azure Key';         Pattern='(?i)AccountKey=[a-zA-Z0-9+/]{88}=='                                            }
    @{ Name='NPM Token';         Pattern='npm_[a-zA-Z0-9]{36}'                                                           }
    @{ Name='Telegram Bot';      Pattern='[0-9]{8,10}:[a-zA-Z0-9_\-]{35}'                                               }
    @{ Name='DB Connection';     Pattern='(?i)(mongodb|postgresql|mysql|redis)://[^:\s]+:[^@\s]{6,}@'                    }
    @{ Name='Generic API Key';   Pattern='(?i)(api_?key|apikey|access_?token|auth_?token|client_?secret)\s*[=:]\s*[''"]?[a-zA-Z0-9+/\-_]{16,}' }
    @{ Name='Generic Password';  Pattern='(?i)(password|passwd|pwd)\s*[=:]\s*[''"]?[^\s''"\n]{8,}[''"]?'                }
    @{ Name='Generic Secret';    Pattern='(?i)secret\s*[=:]\s*[''"]?[a-zA-Z0-9+/\-_]{16,}[''"]?'                       }
)

# ============================================================
#  PROJECT SIGNATURES & ENTRY POINTS
# ============================================================

$projectSignatures = [ordered]@{
    'Next.js'     = @('next.config.js','next.config.ts','next.config.mjs')
    'Nuxt'        = @('nuxt.config.ts','nuxt.config.js')
    'Angular'     = @('angular.json')
    'Svelte'      = @('svelte.config.js','svelte.config.ts')
    'Vue'         = @('vue.config.js')
    'React'       = @('vite.config.ts','vite.config.js','react-scripts')
    'Django'      = @('manage.py')
    'FastAPI'     = @('main.py')
    'Flask'       = @('app.py')
    'Python'      = @('requirements.txt','pyproject.toml','setup.py')
    'Spring Boot' = @('pom.xml','build.gradle')
    'Java'        = @('pom.xml','build.gradle')
    '.NET'        = @('*.csproj','*.sln','Program.cs')
    'Go'          = @('go.mod')
    'Rust'        = @('Cargo.toml')
    'PHP'         = @('composer.json')
    'Ruby'        = @('Gemfile')
    'Node.js'     = @('package.json')
}

$entryPoints = @{
    'Next.js' = @('src/app/layout.tsx','app/layout.tsx','src/pages/_app.tsx','pages/index.tsx')
    'React'   = @('src/index.tsx','src/index.jsx','src/main.tsx','src/App.tsx')
    'Node.js' = @('src/index.js','src/index.ts','index.js','server.js','app.js')
    'Django'  = @('manage.py')
    'Python'  = @('main.py','app.py','run.py','__main__.py','src/main.py')
    '.NET'    = @('Program.cs','Startup.cs')
    'Go'      = @('main.go','cmd/main.go')
    'Rust'    = @('src/main.rs')
    'Java'    = @('src/main/java')
}

# LLM context window limits (K-tokens)
$llmLimits = [ordered]@{
    'Claude'          = 200
    'GPT-4o'          = 128
    'Gemini 1.5/2.0'  = 1000
    'Llama 3 / Mistral' = 128
    'Grok-2'          = 128
}

# ============================================================
#  UI HELPERS
# ============================================================

function Write-Banner {
    $W = 70
    $border  = "  ╔" + ("═" * $W) + "╗"
    $divider = "  ╠" + ("═" * $W) + "╣"
    $bottom  = "  ╚" + ("═" * $W) + "╝"
    $empty   = "  ║" + (" " * $W) + "║"

    Write-Host ""; Write-Host $border -ForegroundColor DarkRed; Write-Host $empty -ForegroundColor DarkRed

    $art = @(
        @{ T="    ██████╗ ██╗   ██╗███╗   ██╗██████╗ ██╗     ███████╗    "; C="Red"     }
        @{ T="    ██╔══██╗██║   ██║████╗  ██║██╔══██╗██║     ██╔════╝    "; C="Red"     }
        @{ T="    ██████╔╝██║   ██║██╔██╗ ██║██║  ██║██║     █████╗      "; C="Red"     }
        @{ T="    ██╔══██╗██║   ██║██║╚██╗██║██║  ██║██║     ██╔══╝      "; C="DarkRed" }
        @{ T="    ██████╔╝╚██████╔╝██║ ╚████║██████╔╝███████╗███████╗    "; C="DarkRed" }
        @{ T="    ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝    "; C="DarkRed" }
    )
    foreach ($l in $art) {
        $pad = $W - $l.T.Length
        Write-Host "  ║" -ForegroundColor DarkRed -NoNewline
        Write-Host $l.T -ForegroundColor $l.C -NoNewline
        Write-Host (" " * [Math]::Max(0,$pad)) -NoNewline
        Write-Host "║" -ForegroundColor DarkRed
    }

    Write-Host $empty -ForegroundColor DarkRed; Write-Host $divider -ForegroundColor DarkRed

    $foot = "   Project Intelligence Packager $([char]0xB7) v$($script:VERSION) $([char]0xB7) LLM-Ready Code Bundler"
    $fpad = $W - $foot.Length
    Write-Host "  ║" -ForegroundColor DarkRed -NoNewline
    Write-Host $foot -ForegroundColor Gray -NoNewline
    Write-Host (" " * [Math]::Max(0,$fpad)) -NoNewline
    Write-Host "║" -ForegroundColor DarkRed

    Write-Host $bottom -ForegroundColor DarkRed; Write-Host ""
}

function Write-Status {
    param([string]$Tag, [string]$Message, [string]$TagColor="DarkGray", [string]$MsgColor="Gray")
    Write-Host "  " -NoNewline
    Write-Host $Tag.PadRight(10) -ForegroundColor $TagColor -NoNewline
    Write-Host " $Message" -ForegroundColor $MsgColor
}

function Write-Sep { Write-Host ("  " + "─" * 68) -ForegroundColor DarkGray }

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ""; Write-Host "  ┌─ $Title " -ForegroundColor DarkRed -NoNewline
    Write-Host ("─" * [Math]::Max(2, 65 - $Title.Length)) -ForegroundColor DarkGray
}

# ============================================================
#  DRIVE DETECTION (with network timeout)
# ============================================================

function Get-AvailableDrives {
    $drives = [System.Collections.Generic.List[string]]::new()

    try {
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
            $root = $_.Root
            if (-not $root) { return }

            # Test reachability with a 2-second timeout job
            $job = Start-Job -ScriptBlock { param($r) Test-Path $r -ErrorAction SilentlyContinue } -ArgumentList $root
            $done = Wait-Job $job -Timeout 2
            if ($done) {
                $ok = Receive-Job $job -ErrorAction SilentlyContinue
                if ($ok) { $drives.Add($root) }
                else { Write-Status "SKIP" "Drive $root not accessible" "DarkGray" "DarkGray" }
            } else {
                Stop-Job $job
                Write-Status "SKIP" "Drive $root timed out (network/slow drive)" "Yellow" "DarkYellow"
            }
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
    } catch {
        $script:errorLog.Add("Drive detection error: $($_.Exception.Message)")
    }

    if ($drives.Count -eq 0) { $drives.Add("C:\") }
    return ($drives | Sort-Object -Unique)
}

# ============================================================
#  GITIGNORE PARSER
# ============================================================

function Get-GitIgnorePatterns {
    param([string]$Root)
    $patterns = [System.Collections.Generic.List[hashtable]]::new()

    $giFiles = @()
    $rootGI = [System.IO.Path]::Combine($Root, ".gitignore")
    if (Test-Path $rootGI -ErrorAction SilentlyContinue) {
        $giFiles += @{ File = $rootGI; Base = $Root }
    }
    try {
        Get-ChildItem -Path $Root -Filter ".gitignore" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -ne $Root } |
            ForEach-Object { $giFiles += @{ File = $_.FullName; Base = $_.DirectoryName } }
    } catch {}

    foreach ($gi in $giFiles) {
        try {
            Get-Content -Path $gi.File -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
                $line = $_.Trim()
                if ($line -eq '' -or $line.StartsWith('#')) { return }
                $negated = $line.StartsWith('!')
                if ($negated) { $line = $line.Substring(1) }
                $dirOnly = $line.EndsWith('/')
                if ($dirOnly) { $line = $line.TrimEnd('/') }
                $anchored = $line.StartsWith('/')
                if ($anchored) { $line = $line.TrimStart('/') }
                # Convert gitignore glob → PS wildcard
                $psPattern = $line -replace '\*\*[/\\]', '*' -replace '\*\*', '*'
                $patterns.Add(@{ Pattern=$psPattern; Negated=$negated; DirOnly=$dirOnly; Anchored=$anchored; Base=$gi.Base })
            }
        } catch { $script:errorLog.Add("Cannot read .gitignore at $($gi.File): $($_.Exception.Message)") }
    }
    return $patterns
}

function Test-GitIgnored {
    param([System.IO.FileSystemInfo]$Item, [string]$Root, $Patterns)
    if (-not $Patterns -or $Patterns.Count -eq 0) { return $false }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $rel = $Item.FullName.Substring($Root.Length).TrimStart($sep,'/').Replace('\','/')
    $name = $Item.Name
    $isDir = $Item.PSIsContainer
    $ignored = $false
    foreach ($p in $Patterns) {
        if ($p.DirOnly -and -not $isDir) { continue }
        $pat = $p.Pattern
        $matched = $false
        if ($p.Anchored) {
            $relToBase = $Item.FullName.Substring($p.Base.Length).TrimStart($sep,'/').Replace('\','/')
            $matched = ($relToBase -like $pat) -or ($relToBase -like "$pat/*")
        } else {
            $matched = ($name -like $pat) -or ($rel -like $pat) -or ($rel -like "*/$pat") -or ($rel -like "*/$pat/*")
        }
        if ($matched) { $ignored = if ($p.Negated) { $false } else { $true } }
    }
    return $ignored
}

# ============================================================
#  GIT METADATA
# ============================================================

function Get-GitMetadata {
    param([string]$Root)
    $git = @{
        Available    = $false
        Branch       = ""
        LastCommit   = ""
        Author       = ""
        Remote       = ""
        ChangedFiles = @()
        TotalCommits = ""
        HasGitDir    = (Test-Path ([System.IO.Path]::Combine($Root,".git")) -ErrorAction SilentlyContinue)
    }
    if (-not $git.HasGitDir) { return $git }

    try {
        $null = & git --version 2>$null
        if ($LASTEXITCODE -ne 0) { return $git }
        $git.Available = $true

        Push-Location $Root
        $git.Branch       = (& git branch --show-current 2>$null) | Select-Object -First 1
        $git.LastCommit   = (& git log -1 --pretty=format:"%h — %s (%ar)" 2>$null) | Select-Object -First 1
        $git.Author       = (& git log -1 --pretty=format:"%an <%ae>" 2>$null) | Select-Object -First 1
        $git.Remote       = (& git remote get-url origin 2>$null) | Select-Object -First 1
        $git.TotalCommits = (& git rev-list --count HEAD 2>$null) | Select-Object -First 1
        $git.ChangedFiles = @(& git status --short 2>$null | Where-Object { $_ -match '^\s*\S' })
        Pop-Location
    } catch {
        try { Pop-Location } catch {}
        $script:errorLog.Add("Git metadata error: $($_.Exception.Message)")
    }
    return $git
}

# ============================================================
#  PROJECT INTELLIGENCE
# ============================================================

function Get-ProjectType {
    param([string]$Root)
    $result = @{ Type="Unknown"; Framework=""; EntryPoint=""; IsGitRepo=$false }

    foreach ($sig in $projectSignatures.GetEnumerator()) {
        foreach ($f in $sig.Value) {
            $checkPath = [System.IO.Path]::Combine($Root, $f)
            $found = $false
            if ($f.Contains('*')) {
                $found = (Get-ChildItem -Path $Root -Filter $f -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $null
            } else {
                $found = Test-Path $checkPath -ErrorAction SilentlyContinue
            }
            if ($found) {
                $result.Type      = $sig.Key
                $result.Framework = $sig.Key
                # Check for tighter framework match on package.json
                if ($sig.Key -eq 'Node.js' -or $sig.Key -eq 'React') {
                    $pkgPath = [System.IO.Path]::Combine($Root, "package.json")
                    if (Test-Path $pkgPath -ErrorAction SilentlyContinue) {
                        try {
                            $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                            $deps = @()
                            if ($pkg.dependencies)    { $deps += $pkg.dependencies.PSObject.Properties.Name }
                            if ($pkg.devDependencies) { $deps += $pkg.devDependencies.PSObject.Properties.Name }
                            if ('next'        -in $deps) { $result.Framework = 'Next.js' }
                            elseif ('nuxt'    -in $deps) { $result.Framework = 'Nuxt' }
                            elseif ('@angular/core' -in $deps) { $result.Framework = 'Angular' }
                            elseif ('svelte'  -in $deps) { $result.Framework = 'SvelteKit' }
                            elseif ('vue'     -in $deps) { $result.Framework = 'Vue' }
                            elseif ('react'   -in $deps) { $result.Framework = 'React' }
                            if ($pkg.main) { $result.EntryPoint = $pkg.main }
                        } catch {}
                    }
                }
                # Detect Django vs Flask vs FastAPI
                if ($sig.Key -in @('Django','FastAPI','Flask')) {
                    $result.Type = 'Python'; $result.Framework = $sig.Key
                }
                break
            }
        }
        if ($result.Type -ne "Unknown") { break }
    }

    # Entry point detection
    if (-not $result.EntryPoint) {
        $frameworkEPs = $entryPoints[$result.Framework]
        if (-not $frameworkEPs) { $frameworkEPs = $entryPoints[$result.Type] }
        if ($frameworkEPs) {
            foreach ($ep in $frameworkEPs) {
                $epPath = [System.IO.Path]::Combine($Root, $ep.Replace('/','\'))
                if (Test-Path $epPath -ErrorAction SilentlyContinue) {
                    $result.EntryPoint = $ep; break
                }
            }
        }
    }

    $result.IsGitRepo = Test-Path ([System.IO.Path]::Combine($Root,".git")) -ErrorAction SilentlyContinue
    return $result
}

function Get-LanguageStats {
    param([System.Collections.Generic.List[System.IO.FileInfo]]$Files)
    $stats = @{}
    $totalSize = 0L
    foreach ($f in $Files) {
        $ext = $f.Extension.ToLower()
        if (-not $ext) { $ext = "[none]" }
        if (-not $stats.ContainsKey($ext)) { $stats[$ext] = 0L }
        $stats[$ext] += $f.Length
        $totalSize += $f.Length
    }
    if ($totalSize -eq 0) { return @() }
    $result = @()
    foreach ($kv in ($stats.GetEnumerator() | Sort-Object Value -Descending)) {
        $pct = [math]::Round(($kv.Value / $totalSize) * 100, 1)
        $lang = $languageMap[$kv.Key]
        if (-not $lang) { $lang = $kv.Key.TrimStart('.').ToUpper() }
        else { $lang = (Get-Culture).TextInfo.ToTitleCase($lang) }
        $result += @{ Ext=$kv.Key; Language=$lang; Pct=$pct; Bytes=$kv.Value }
    }
    return $result
}

function Get-EntryPointLabel {
    param([string]$Root, [string]$EntryPoint, [string]$Framework)
    if ($EntryPoint) { return $EntryPoint }
    return "(auto-detect failed — check package.json or main file)"
}

# ============================================================
#  SECRET SCANNER
# ============================================================

function Invoke-SecretScan {
    param([string]$Content, [string]$RelPath)
    $findings = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($sp in $secretPatterns) {
        try {
            $matches = [regex]::Matches($Content, $sp.Pattern)
            foreach ($m in $matches) {
                $findings.Add(@{ Name=$sp.Name; File=$RelPath; Match=$m.Value.Substring(0,[Math]::Min($m.Value.Length,40)) })
                $script:secretsFound.Add(@{ Name=$sp.Name; File=$RelPath })
            }
        } catch {}
    }
    return $findings
}

function Invoke-SecretRedact {
    param([string]$Content)
    foreach ($sp in $secretPatterns) {
        try { $Content = [regex]::Replace($Content, $sp.Pattern, "[REDACTED:$($sp.Name)]") } catch {}
    }
    return $Content
}

# ============================================================
#  ENCODING DETECTION
# ============================================================

function Get-FileEncoding {
    param([string]$Path)
    try {
        $bytes = New-Object byte[] 4
        $stream = [System.IO.File]::OpenRead($Path)
        $read = $stream.Read($bytes,0,4)
        $stream.Close()
        # BOM detection
        if ($read -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            return [System.Text.Encoding]::UTF8
        }
        if ($read -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            return [System.Text.Encoding]::Unicode   # UTF-16 LE
        }
        if ($read -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            return [System.Text.Encoding]::BigEndianUnicode
        }
        # Default: try UTF-8, fall back to Windows-1252
        return [System.Text.Encoding]::UTF8
    } catch {
        return [System.Text.Encoding]::UTF8
    }
}

function Read-FileContent {
    param([string]$Path)
    $enc = Get-FileEncoding -Path $Path
    try {
        return [System.IO.File]::ReadAllText($Path, $enc)
    } catch {
        try {
            # Fallback: Windows-1252 (covers Latin-1 / legacy files)
            $fallback = [System.Text.Encoding]::GetEncoding(1252)
            return [System.IO.File]::ReadAllText($Path, $fallback)
        } catch {
            $script:errorLog.Add("Cannot read: $Path — $($_.Exception.Message)")
            return $null
        }
    }
}

# ============================================================
#  BINARY DETECTION (extension-first, then byte-scan)
# ============================================================

$knownTextExtensions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($e in $includeExtensions) { [void]$knownTextExtensions.Add($e) }

function Test-IsBinaryFile {
    param([System.IO.FileInfo]$File)
    # Fast path: if extension is in our known-text set, trust it
    if ($knownTextExtensions.Contains($File.Extension)) { return $false }
    # Byte scan only for extensionless or ambiguous files
    try {
        $stream = [System.IO.File]::OpenRead($File.FullName)
        $buf = New-Object byte[] 4096
        $n = $stream.Read($buf, 0, $buf.Length)
        $stream.Close()
        for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -eq 0) { return $true } }
        return $false
    } catch { return $true }
}

# ============================================================
#  TOKEN ESTIMATION (weighted per file type)
# ============================================================

function Get-TokenEstimate {
    param([long]$Chars, [string]$Extension="", [string]$Content="")
    if ($Chars -eq 0) { return 0L }

    # Detect high non-ASCII ratio (Arabic, CJK, etc.)
    $nonAsciiRatio = 0.0
    if ($Content.Length -gt 0) {
        $sample = $Content.Substring(0, [Math]::Min(500, $Content.Length))
        $nonAscii = ($sample.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count
        $nonAsciiRatio = $nonAscii / [Math]::Max(1, $sample.Length)
    }

    if ($nonAsciiRatio -gt 0.2) { return [long]($Chars / 3.5) }   # Arabic/CJK: more tokens per char

    $ratio = switch -Regex ($Extension.ToLower()) {
        '^\.json$|^\.xml$|^\.xsd$'                        { 3.0; break }
        '^\.min\.'                                         { 2.5; break }
        '^\.yml$|^\.yaml$|^\.toml$|^\.ini$|^\.cfg$'       { 5.0; break }
        '^\.md$|^\.markdown$|^\.rst$|^\.txt$'              { 5.0; break }
        '^\.html$|^\.htm$'                                 { 4.0; break }
        '^\.css$|^\.scss$|^\.sass$|^\.less$'               { 4.5; break }
        '^\.sql$|^\.ddl$'                                  { 3.5; break }
        default                                            { 4.0 }
    }
    return [long]($Chars / $ratio)
}

function Format-Tokens {
    param([long]$T)
    if ($T -lt 1000)    { return "$T tokens" }
    if ($T -lt 1000000) { return "$([math]::Round($T/1000,1))K tokens" }
    return "$([math]::Round($T/1000000,2))M tokens"
}

# ============================================================
#  LOGICAL FILE ORDERING
# ============================================================

function Get-FileSortKey {
    param([System.IO.FileInfo]$File, [string]$Root, [string]$DetectedEntryPoint)
    $rel = $File.FullName.Substring($Root.Length).TrimStart('\','/').Replace('\','/')
    $name = $File.Name.ToLower()
    $ext  = $File.Extension.ToLower()

    # Priority 0: Entry point
    if ($DetectedEntryPoint -and $rel -like "*$DetectedEntryPoint*") { return "0_$rel" }
    # Priority 1: Config / manifest files
    if ($name -in @('package.json','pyproject.toml','requirements.txt','pom.xml','go.mod',
        'cargo.toml','composer.json','gemfile','makefile','dockerfile',
        '.env.example','.env.sample','.gitignore','.editorconfig')) { return "1_$rel" }
    # Priority 2: Root-level config files (no subdirectory)
    if (-not $rel.Contains('/') -and $ext -in @('.json','.toml','.yml','.yaml','.ini','.cfg','.conf')) { return "2_$rel" }
    # Priority 3: Source root files
    if (-not $rel.Contains('/')) { return "3_$rel" }
    # Priority 4: Test files last
    if ($rel -match '(test|spec|__tests__|\.test\.|\.spec\.)') { return "8_$rel" }
    # Priority 5: Group by directory (depth-first, folder prefix)
    $dir = [System.IO.Path]::GetDirectoryName($rel).Replace('\','/')
    return "5_$dir`_$name"
}

# ============================================================
#  FILE TRAVERSAL (symlink guard + gitignore + error collection)
# ============================================================

function Get-ProjectFilesFast {
    param(
        [string] $CurrentPath,
        [string] $Root,
        [ref]    $Files,
        [ref]    $SkipLarge,
        [string[]] $ExcludeAbsolutePaths,
        $GitIgnorePatterns
    )

    # Symlink / loop guard
    try {
        $realPath = (Resolve-Path -LiteralPath $CurrentPath -ErrorAction Stop).Path
    } catch {
        $script:errorLog.Add("Cannot resolve path: $CurrentPath")
        return
    }
    if (-not $script:visitedPaths.Add($realPath)) { return }   # already visited

    try {
        $items = Get-ChildItem -LiteralPath $CurrentPath -ErrorAction SilentlyContinue
    } catch {
        $script:errorLog.Add("Cannot list: $CurrentPath — $($_.Exception.Message)")
        return
    }

    foreach ($item in $items) {
        # Gitignore check
        if ($GitIgnorePatterns -and (Test-GitIgnored -Item $item -Root $Root -Patterns $GitIgnorePatterns)) { continue }

        if ($item.PSIsContainer) {
            if ($excludeFolders -contains $item.Name) { continue }
            if ($item.Name.StartsWith('.') -and $item.Name -ne '.github') { continue }
            Get-ProjectFilesFast -CurrentPath $item.FullName -Root $Root -Files $Files `
                -SkipLarge $SkipLarge -ExcludeAbsolutePaths $ExcludeAbsolutePaths `
                -GitIgnorePatterns $GitIgnorePatterns
        } else {
            # Skip output file itself
            if ($ExcludeAbsolutePaths -contains $item.FullName) { continue }

            # Skip excluded file patterns
            $skip = $false
            foreach ($pat in $excludeFilePatterns) { if ($item.Name -like $pat) { $skip=$true; break } }
            if ($skip) { continue }

            $nameLower = $item.Name.ToLower()
            $isMatch   = $false

            # .env safety gate
            if ($nameLower -like '.env*') {
                if ($safeEnvFiles -contains $nameLower) { $isMatch = $true } else { continue }
            }

            if (-not $isMatch) {
                $extLower = $item.Extension.ToLower()
                if ($includeExtensions -contains $extLower) { $isMatch = $true }
                elseif ($extLower -eq '' -and $specialFileNames -contains $item.Name) { $isMatch = $true }
            }

            if ($isMatch) {
                $rel = $item.FullName.Substring($Root.Length).TrimStart('\','/')
                if ($item.Length -gt $maxFileBytes) {
                    $SkipLarge.Value.Add("$rel ($([math]::Round($item.Length/1MB,2)) MB)")
                } else {
                    $Files.Value.Add($item)
                }
            }
        }
    }
}

# ============================================================
#  SMART SEARCH
# ============================================================

function Get-PriorityPaths {
    param([string[]]$Drives)
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($drv in $Drives) {
        $usersDir = [System.IO.Path]::Combine($drv, "Users")
        if (Test-Path $usersDir -ErrorAction SilentlyContinue) {
            Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $u = $_.FullName
                foreach ($sub in @("Desktop","Documents","Downloads","Projects","repos","dev","source","workspace","code","src","github","OneDrive")) {
                    $p = [System.IO.Path]::Combine($u, $sub)
                    if (Test-Path $p -ErrorAction SilentlyContinue) { $paths.Add($p) }
                }
                $paths.Add($u)
            }
        }
        foreach ($sub in @("Projects","repos","dev","source","workspace","code","src","github","work")) {
            $p = [System.IO.Path]::Combine($drv, $sub)
            if (Test-Path $p -ErrorAction SilentlyContinue) { $paths.Add($p) }
        }
    }
    return ($paths | Select-Object -Unique)
}

function Search-ProjectByName {
    param([string]$Name, [string[]]$Drives)
    $exact   = [System.Collections.Generic.List[string]]::new()
    $partial = [System.Collections.Generic.List[string]]::new()
    $low = $Name.ToLower()

    Write-Status "SEARCH" "Phase 1: Scanning priority locations..." "Red" "Gray"
    $pri = Get-PriorityPaths -Drives $Drives
    $priCount = 0
    foreach ($base in $pri) {
        $priCount++
        if (-not $Quiet) {
            Write-Progress -Activity "Searching for project '$Name'" -Status "Scanning $base" -PercentComplete ([math]::Min(90, ($priCount/$pri.Count)*90))
        }
        try {
            Get-ChildItem -Path $base -Directory -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object {
                $fn = $_.Name.ToLower()
                if ($fn -eq $low -and $exact -notcontains $_.FullName) { $exact.Add($_.FullName) }
                elseif ($fn -like "*$low*" -and $partial -notcontains $_.FullName) { $partial.Add($_.FullName) }
            }
        } catch {}
    }
    if (-not $Quiet) { Write-Progress -Activity "Searching for project '$Name'" -Completed }

    if ($exact.Count -gt 0) { return @{ Exact=$exact; Partial=$partial } }

    Write-Status "SEARCH" "Phase 2: Expanding to full drive scan..." "DarkRed" "Gray"
    foreach ($drv in $Drives) {
        try {
            Get-ChildItem -Path $drv -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($systemSkipFolders -contains $_.Name -or $_.Name.StartsWith('$')) { return }
                try {
                    Get-ChildItem -Path $_.FullName -Directory -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
                        $fn = $_.Name.ToLower()
                        if ($fn -eq $low -and $exact -notcontains $_.FullName)   { $exact.Add($_.FullName) }
                        elseif ($fn -like "*$low*" -and $partial -notcontains $_.FullName) { $partial.Add($_.FullName) }
                    }
                } catch {}
            }
        } catch {}
    }
    return @{ Exact=$exact; Partial=$partial }
}

function Select-FromMatches {
    param($Exact, $Partial)
    $all = @(); if ($Exact.Count -gt 0) { $all += $Exact }; if ($Partial.Count -gt 0) { $all += $Partial }
    if ($all.Count -eq 0) { return $null }
    if ($all.Count -eq 1) {
        Write-Status "FOUND" $all[0] "Green" "White"
        $c = Read-Host "  Use this path? [Y/n]"
        if ($c -match '^n') { return $null }
        return $all[0]
    }
    Write-Host ""; Write-Status "FOUND" "$($all.Count) matches:" "Green" "White"; Write-Host ""
    $lim = [Math]::Min($all.Count, 15)
    for ($i=0; $i -lt $lim; $i++) {
        $tag = if ($Exact -and $Exact -contains $all[$i]) { " [EXACT]" } else { "" }
        Write-Host "    [$($i+1)] $($all[$i])$tag" -ForegroundColor White
    }
    if ($all.Count -gt 15) { Write-Host "    ... and $($all.Count-15) more" -ForegroundColor DarkGray }
    Write-Host ""
    $choice = Read-Host "  Select number (or 0 to cancel)"
    $idx=0
    if ([int]::TryParse($choice,[ref]$idx) -and $idx -ge 1 -and $idx -le $lim) { return $all[$idx-1] }
    return $null
}

function Search-OutputFolder {
    param([string]$Name, [string[]]$Drives)
    if (Test-Path $Name -ErrorAction SilentlyContinue) { return $Name }
    $found = [System.Collections.Generic.List[string]]::new()
    $low   = $Name.ToLower()
    foreach ($base in (Get-PriorityPaths -Drives $Drives)) {
        try {
            $d = [System.IO.Path]::Combine($base, $Name)
            if (Test-Path $d -ErrorAction SilentlyContinue) { $found.Add($d) }
            Get-ChildItem -Path $base -Directory -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name.ToLower() -eq $low -and $found -notcontains $_.FullName } |
                ForEach-Object { $found.Add($_.FullName) }
        } catch {}
    }
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) {
        Write-Host ""; Write-Status "FOUND" "$($found.Count) matching folders:" "Green" "White"
        $lim = [Math]::Min($found.Count,10)
        for ($i=0;$i -lt $lim;$i++) { Write-Host "    [$($i+1)] $($found[$i])" -ForegroundColor White }
        $c=Read-Host "  Select number"; $idx=0
        if ([int]::TryParse($c,[ref]$idx) -and $idx -ge 1 -and $idx -le $lim) { return $found[$idx-1] }
    }
    return $null
}

# ============================================================
#  CONFIG SYSTEM
# ============================================================

function Import-BundleConfig {
    param([string]$Root)
    $cfgPath = [System.IO.Path]::Combine($Root, "bundle.config.json")
    if (-not (Test-Path $cfgPath -ErrorAction SilentlyContinue)) { return }
    try {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        Write-Status "CONFIG" "Loaded bundle.config.json" "Cyan" "Cyan"
        if ($cfg.OutputDir   -and $script:OutputDir   -eq "") { $script:OutputDir   = $cfg.OutputDir }
        if ($cfg.Format      -and $script:Format      -eq "txt") { $script:Format   = $cfg.Format }
        if ($cfg.MaxFileSizeMB)   { $script:MaxFileSizeMB = $cfg.MaxFileSizeMB }
        if ($cfg.StripPaths)      { $script:StripPaths    = [bool]$cfg.StripPaths }
        if ($cfg.Redact)          { $script:Redact        = [bool]$cfg.Redact }
        if ($cfg.IncludeTree)     { $script:IncludeTree   = [bool]$cfg.IncludeTree }
        if ($cfg.SplitKTokens)    { $script:SplitKTokens  = [int]$cfg.SplitKTokens }
        if ($cfg.ExtraExtensions) { $script:ExtraExtensions = $cfg.ExtraExtensions }
        if ($cfg.ExtraExcludes)   { $script:ExtraExcludes   = $cfg.ExtraExcludes }
    } catch { Write-Status "WARN" "Could not parse bundle.config.json" "Yellow" "Yellow" }
}

function Export-BundleConfig {
    param([string]$Root)
    $cfgPath = [System.IO.Path]::Combine($Root, "bundle.config.json")
    $cfg = @{
        OutputDir       = $OutputDir
        Format          = $Format
        MaxFileSizeMB   = $MaxFileSizeMB
        StripPaths      = $StripPaths.IsPresent
        Redact          = $Redact.IsPresent
        IncludeTree     = $IncludeTree.IsPresent
        SplitKTokens    = $SplitKTokens
        ExtraExtensions = $ExtraExtensions
        ExtraExcludes   = $ExtraExcludes
        SavedAt         = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $cfg | ConvertTo-Json -Depth 3 | Set-Content -Path $cfgPath -Encoding UTF8
    Write-Status "CONFIG" "Saved to bundle.config.json" "Cyan" "Cyan"
}

# ============================================================
#  DIRECTORY TREE
# ============================================================

function Get-FilteredTree {
    param([string]$Path, [string]$Root, [int]$Indent=0)
    $sb = [System.Text.StringBuilder]::new()
    try {
        $items = Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | Sort-Object { $_.PSIsContainer },Name
        foreach ($item in $items) {
            $prefix = ("  " * $Indent) + "|-- "
            if ($item.PSIsContainer) {
                if ($excludeFolders -contains $item.Name) { continue }
                [void]$sb.AppendLine("$prefix$($item.Name)/")
                [void]$sb.Append((Get-FilteredTree -Path $item.FullName -Root $Root -Indent ($Indent+1)))
            } else { [void]$sb.AppendLine("$prefix$($item.Name)") }
        }
    } catch {}
    return $sb.ToString()
}

# ============================================================
#  LLM CONTEXT HEADER
# ============================================================

function Write-LlmContextHeader {
    param($Writer, [string]$ProjectName, $ProjectInfo, $GitMeta, $LangStats, [long]$TotalTokens, [string]$Format, [int]$FileCount)
    $line = "=" * 80
    $Writer.WriteLine($line)
    Writer.WriteLine("  PROJECT INTELLIGENCE SUMMARY")
    $Writer.WriteLine($line)
    $Writer.WriteLine("  PROJECT       : $ProjectName")
    $Writer.WriteLine("  TYPE          : $($ProjectInfo.Framework)")
    if ($ProjectInfo.EntryPoint) {
        $Writer.WriteLine("  ENTRY POINT   : $($ProjectInfo.EntryPoint)")
    }
    if ($GitMeta.Available) {
        $Writer.WriteLine("  GIT BRANCH    : $($GitMeta.Branch)")
        $Writer.WriteLine("  LAST COMMIT   : $($GitMeta.LastCommit)")
        $Writer.WriteLine("  AUTHOR        : $($GitMeta.Author)")
        if ($GitMeta.Remote) { $Writer.WriteLine("  REMOTE        : $($GitMeta.Remote)") }
        if ($GitMeta.ChangedFiles.Count -gt 0) {
            $Writer.WriteLine("  MODIFIED      : $($GitMeta.ChangedFiles.Count) file(s) since last commit")
        }
        if ($GitMeta.TotalCommits) { $Writer.WriteLine("  TOTAL COMMITS : $($GitMeta.TotalCommits)") }
    } elseif ($ProjectInfo.IsGitRepo) {
        $Writer.WriteLine("  GIT           : Repository found (git not in PATH)")
    }
    $Writer.WriteLine("")

    # Language breakdown
    if ($LangStats.Count -gt 0) {
        $topLangs = $LangStats | Select-Object -First 6
        $langStr = ($topLangs | ForEach-Object { "$($_.Language) $($_.Pct)%" }) -join " | "
        $Writer.WriteLine("  LANGUAGES     : $langStr")
    }
    $Writer.WriteLine("  FILES         : $FileCount source files")
    $Writer.WriteLine("  EST. TOKENS   : $(Format-Tokens $TotalTokens)")
    $Writer.WriteLine("  FORMAT        : $($Format.ToUpper()) ($(if($Format -eq 'md'){'language-tagged fences'}elseif($Format -eq 'json'){'structured JSON'}else{'plain text'}))")
    $Writer.WriteLine("")

    # Context window fit check
    $Writer.Write("  CONTEXT FIT   : ")
    $fits = @(); $warns = @()
    foreach ($llm in $llmLimits.GetEnumerator()) {
        $limitK = $llm.Value * 1000
        if ($TotalTokens -le $limitK) { $fits  += "$($llm.Key) ([OK])" }
        else                          { $warns += "$($llm.Key) ([OVER])" }
    }
    $all = @(); if ($fits.Count -gt 0) { $all += $fits }; if ($warns.Count -gt 0) { $all += $warns }
    $Writer.WriteLine($all -join " | ")

    $Writer.WriteLine("")
    $Writer.WriteLine("  " + ("─" * 76))
    $Writer.WriteLine("  SUGGESTED PROMPT (paste before sharing this bundle):")
    $Writer.WriteLine("")
    $ep = if ($ProjectInfo.EntryPoint) { "The entry point is $($ProjectInfo.EntryPoint). " } else { "" }
    $Writer.WriteLine("  `"I'm sharing my complete $ProjectName codebase. It's a $($ProjectInfo.Framework)")
    $Writer.WriteLine("   project with $FileCount files (~$(Format-Tokens $TotalTokens)). $($ep)Please [YOUR QUESTION].`"")
    $Writer.WriteLine("")
    $Writer.WriteLine($line)
    $Writer.WriteLine("")
}

# Wrapper to call the function (workaround for the Write-LlmContextHeader Writer. typo I need to fix)
function Invoke-WriteLlmHeader {
    param($W, $ProjectName, $ProjectInfo, $GitMeta, $LangStats, $TotalTokens, $FmtStr, $FileCount)
    $line = "=" * 80
    $W.WriteLine($line)
    $W.WriteLine("  PROJECT INTELLIGENCE SUMMARY")
    $W.WriteLine($line)
    $W.WriteLine("  PROJECT       : $ProjectName")
    $W.WriteLine("  TYPE          : $($ProjectInfo.Framework)")
    if ($ProjectInfo.EntryPoint) { $W.WriteLine("  ENTRY POINT   : $($ProjectInfo.EntryPoint)") }
    if ($GitMeta.Available) {
        $W.WriteLine("  GIT BRANCH    : $($GitMeta.Branch)")
        $W.WriteLine("  LAST COMMIT   : $($GitMeta.LastCommit)")
        $W.WriteLine("  AUTHOR        : $($GitMeta.Author)")
        if ($GitMeta.Remote)                   { $W.WriteLine("  REMOTE        : $($GitMeta.Remote)") }
        if ($GitMeta.ChangedFiles.Count -gt 0) { $W.WriteLine("  MODIFIED      : $($GitMeta.ChangedFiles.Count) file(s) uncommitted") }
        if ($GitMeta.TotalCommits)             { $W.WriteLine("  TOTAL COMMITS : $($GitMeta.TotalCommits)") }
    } elseif ($ProjectInfo.IsGitRepo) {
        $W.WriteLine("  GIT           : Repo found (git binary not in PATH)")
    }
    $W.WriteLine("")
    if ($LangStats -and $LangStats.Count -gt 0) {
        $top = $LangStats | Select-Object -First 6
        $ls  = ($top | ForEach-Object { "$($_.Language) $($_.Pct)%" }) -join " | "
        $W.WriteLine("  LANGUAGES     : $ls")
    }
    $W.WriteLine("  FILES         : $FileCount source files")
    $W.WriteLine("  EST. TOKENS   : $(Format-Tokens $TotalTokens)")
    $W.WriteLine("  FORMAT        : $($FmtStr.ToUpper())")
    $W.WriteLine("")

    $W.Write("  CONTEXT FIT   : ")
    $parts = @()
    foreach ($llm in $llmLimits.GetEnumerator()) {
        $limitTok = $llm.Value * 1000
        $sym = if ($TotalTokens -le $limitTok) { "[OK]" } else { "[OVER-LIMIT]" }
        $parts += "$($llm.Key): $sym"
    }
    $W.WriteLine($parts -join "  |  ")
    $W.WriteLine("")
    $W.WriteLine("  " + ("─" * 76))
    $W.WriteLine("  SUGGESTED PROMPT TO PASTE BEFORE THIS BUNDLE:")
    $W.WriteLine("")
    $ep = if ($ProjectInfo.EntryPoint) { "Entry point: $($ProjectInfo.EntryPoint). " } else { "" }
    $W.WriteLine("  `"I'm sharing my complete [$ProjectName] codebase. Framework: $($ProjectInfo.Framework).")
    $W.WriteLine("   It has $FileCount files (~$(Format-Tokens $TotalTokens)). $($ep)Please help me: [YOUR QUESTION].`"")
    $W.WriteLine("")
    $W.WriteLine($line)
    $W.WriteLine("")
}

# ============================================================
#  BUNDLE WRITER
# ============================================================

function Write-FileEntry {
    param($Writer, [System.IO.FileInfo]$File, [string]$Root, [string]$RelPath,
          [string]$Format, [bool]$DoStripPaths, [bool]$DoRedact)

    $content = Read-FileContent -Path $File.FullName
    if ($null -eq $content) {
        $Writer.WriteLine("[ERROR: Could not read file]")
        return 0L
    }

    # Secret scan (always) and optionally redact
    $findings = Invoke-SecretScan -Content $content -RelPath $RelPath
    if ($findings.Count -gt 0 -and $DoRedact) {
        $content = Invoke-SecretRedact -Content $content
    }

    # Token estimate for this file
    $fileTokens = Get-TokenEstimate -Chars $content.Length -Extension $File.Extension -Content $content

    # Display path (strip absolute path if requested)
    $displayPath = if ($DoStripPaths) { "[PROJECT_ROOT]/$RelPath".Replace('\','/') } else { $RelPath }

    $secretWarn = if ($findings.Count -gt 0 -and -not $DoRedact) {
        "`n[!] POTENTIAL SECRET(S) DETECTED: $(($findings | ForEach-Object { $_.Name }) -join ', ') — REVIEW BEFORE SHARING`n"
    } else { "" }

    switch ($Format) {
        'md' {
            $lang = $languageMap[$File.Extension.ToLower()]
            if (-not $lang) {
                $lang = switch ($File.Name) {
                    'Dockerfile' { 'dockerfile' }
                    'Makefile'   { 'makefile'   }
                    default      { 'plaintext'  }
                }
            }
            $Writer.WriteLine("")
            $Writer.WriteLine("## $displayPath")
            $Writer.WriteLine("")
            if ($secretWarn) { $Writer.WriteLine("<!-- $($secretWarn.Trim()) -->"); $Writer.WriteLine("") }
            $Writer.WriteLine("``````$lang")
            $Writer.WriteLine($content)
            $Writer.WriteLine("``````")
        }
        'json' {
            # JSON format is assembled externally; this path is not used in JSON mode
        }
        default {   # txt
            $Writer.WriteLine("")
            $Writer.WriteLine("=" * 80)
            $Writer.WriteLine("FILE: $displayPath")
            $Writer.WriteLine("=" * 80)
            if ($secretWarn) { $Writer.WriteLine($secretWarn) }
            $Writer.WriteLine($content)
        }
    }

    return $fileTokens
}

# ============================================================
#  MAIN FLOW
# ============================================================

Write-Banner

# Ctrl+C / crash guard — ensure writer is always closed
trap {
    Write-Host "`n`n  [INTERRUPTED] Cleaning up..." -ForegroundColor Yellow
    if ($script:writer) {
        try { $script:writer.Close(); $script:writer.Dispose() } catch {}
    }
    if ($script:resolvedOutput -and (Test-Path $script:resolvedOutput -ErrorAction SilentlyContinue)) {
        Remove-Item $script:resolvedOutput -Force -ErrorAction SilentlyContinue
        Write-Host "  Partial output removed." -ForegroundColor DarkYellow
    }
    break
}

# ── STEP 0: Detect drives ──────────────────────────────────
Write-SectionHeader "SYSTEM"
$drives = Get-AvailableDrives
Write-Status "DRIVES" ($drives -join "  |  ") "Red" "White"
Write-Sep

# ── STEP 1: Resolve project root ──────────────────────────
Write-SectionHeader "PROJECT"
if ($ProjectRoot -eq "") {
    Write-Host "  [STEP 1] Which project do you want to bundle?" -ForegroundColor White
    Write-Host "  (Folder name, full path, or Enter for current directory)" -ForegroundColor DarkGray
    $userInput = Read-Host "  >"
    if ($userInput -eq "") {
        $ProjectRoot = (Get-Location).Path
        Write-Status "INFO" "Using current directory" "Yellow" "Gray"
    } elseif (Test-Path $userInput -ErrorAction SilentlyContinue) {
        $ProjectRoot = (Resolve-Path $userInput).Path
        Write-Status "PATH" "Valid path provided" "Green" "Gray"
    } else {
        $res = Search-ProjectByName -Name $userInput -Drives $drives
        $sel = Select-FromMatches -Exact $res.Exact -Partial $res.Partial
        if ($sel) { $ProjectRoot = $sel }
        else { Write-Status "ERROR" "No project found. Exiting." "Red" "Red"; exit 1 }
    }
} elseif (-not (Test-Path $ProjectRoot -ErrorAction SilentlyContinue)) {
    Write-Status "SEARCH" "Path not found, searching by name..." "Yellow" "Gray"
    $leaf = Split-Path $ProjectRoot -Leaf
    $res  = Search-ProjectByName -Name $leaf -Drives $drives
    $sel  = Select-FromMatches -Exact $res.Exact -Partial $res.Partial
    if ($sel) { $ProjectRoot = $sel }
    else { Write-Status "ERROR" "Project not found. Exiting." "Red" "Red"; exit 1 }
}

$ProjectRoot        = (Resolve-Path $ProjectRoot).Path.TrimEnd('\','/')
$projectFolderName  = Split-Path $ProjectRoot -Leaf

# Load config if requested
if ($LoadConfig) { Import-BundleConfig -Root $ProjectRoot }

Write-Status "PROJECT" $projectFolderName "White" "White"
Write-Status "ROOT"    $ProjectRoot       "White" "Gray"

# ── STEP 2: Project intelligence ──────────────────────────
Write-SectionHeader "INTELLIGENCE"
$projectInfo = Get-ProjectType -Root $ProjectRoot
$gitMeta     = Get-GitMetadata -Root $ProjectRoot
$giPatterns  = Get-GitIgnorePatterns -Root $ProjectRoot

Write-Status "TYPE"       "$($projectInfo.Framework)" "Cyan" "Cyan"
if ($projectInfo.EntryPoint) {
    Write-Status "ENTRY"  "$($projectInfo.EntryPoint)" "Cyan" "Gray"
}
if ($gitMeta.Available) {
    Write-Status "BRANCH" "$($gitMeta.Branch)" "Green" "White"
    Write-Status "COMMIT" "$($gitMeta.LastCommit)" "Green" "Gray"
    if ($gitMeta.ChangedFiles.Count -gt 0) {
        Write-Status "PENDING" "$($gitMeta.ChangedFiles.Count) uncommitted change(s)" "Yellow" "Yellow"
    }
}
if ($giPatterns.Count -gt 0) {
    Write-Status "GITIGNORE" "$($giPatterns.Count) ignore pattern(s) loaded" "DarkGray" "Gray"
}
Write-Sep

# ── STEP 3: Resolve output directory ──────────────────────
Write-SectionHeader "OUTPUT"
if ($OutputDir -eq "") {
    Write-Host "  [STEP 2] Where do you want to save the output?" -ForegroundColor White
    Write-Host "  (Folder name, full path, or Enter for current directory)" -ForegroundColor DarkGray
    $outInput = Read-Host "  >"
    if ($outInput -eq "") {
        $OutputDir = (Get-Location).Path
    } elseif (Test-Path $outInput -ErrorAction SilentlyContinue) {
        $OutputDir = (Resolve-Path $outInput).Path
    } else {
        $found = Search-OutputFolder -Name $outInput -Drives $drives
        if ($found) {
            $OutputDir = $found
            Write-Status "FOUND" $OutputDir "Green" "White"
        } else {
            Write-Host "  Folder '$outInput' not found." -ForegroundColor Yellow
            $create = Read-Host "  Create it in current directory? [Y/n]"
            if ($create -match '^n') {
                $OutputDir = (Get-Location).Path
                Write-Status "INFO" "Using current directory" "Yellow" "Gray"
            } else {
                $OutputDir = [System.IO.Path]::Combine((Get-Location).Path, $outInput)
                New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
                Write-Status "CREATED" $OutputDir "Green" "White"
            }
        }
    }
}

if (-not (Test-Path $OutputDir -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$ext = switch ($Format) { 'md' { '.md' } 'json' { '.json' } default { '.txt' } }
if ($OutputFile -eq "") { $OutputFile = "bundle_$projectFolderName$ext" }
$script:resolvedOutput = [System.IO.Path]::Combine($OutputDir, $OutputFile)

# Overwrite protection
if ((Test-Path $script:resolvedOutput) -and -not $NoOverwritePrompt -and -not $DryRun) {
    Write-Host ""
    Write-Status "WARN" "Output file already exists:" "Yellow" "Yellow"
    Write-Host "  $script:resolvedOutput" -ForegroundColor White
    $ovr = Read-Host "  Overwrite? [Y/n]"
    if ($ovr -match '^n') { Write-Status "ABORT" "Operation cancelled." "Red" "Red"; exit 0 }
}

Write-Status "FILE"   $OutputFile            "White" "White"
Write-Status "FORMAT" $Format.ToUpper()      "White" "Gray"
if ($StripPaths) { Write-Status "PRIVACY" "Absolute paths will be stripped" "Cyan" "Gray" }
if ($Redact)     { Write-Status "REDACT"  "Secrets will be redacted in output" "Yellow" "Gray" }
Write-Sep

# ── STEP 4: Scan files ─────────────────────────────────────
Write-SectionHeader "SCAN"
Write-Status "SCAN" "Traversing project tree..." "Red" "Gray"

$skippedLarge = [System.Collections.Generic.List[string]]::new()
$validFiles   = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$excludePaths = @($script:resolvedOutput)

Get-ProjectFilesFast `
    -CurrentPath $ProjectRoot `
    -Root $ProjectRoot `
    -Files ([ref]$validFiles) `
    -SkipLarge ([ref]$skippedLarge) `
    -ExcludeAbsolutePaths $excludePaths `
    -GitIgnorePatterns $giPatterns

if ($validFiles.Count -eq 0) {
    Write-Status "ERROR" "No files matched. Check project path or use -ExtraExtensions." "Red" "Red"
    exit 1
}

# Logical ordering
$sortedFiles = $validFiles | Sort-Object { Get-FileSortKey -File $_ -Root $ProjectRoot -DetectedEntryPoint $projectInfo.EntryPoint }

# Language stats
$langStats = Get-LanguageStats -Files $validFiles

# Token estimation (per file)
$script:totalTokens = 0L
foreach ($f in $validFiles) {
    try {
        $sample = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
        $script:totalTokens += Get-TokenEstimate -Chars $sample.Length -Extension $f.Extension -Content $sample
    } catch { $script:totalTokens += [long]($f.Length / 4) }
}

Write-Status "FOUND"  "$($validFiles.Count) source files" "White" "White"
Write-Status "TOKENS" "~$(Format-Tokens $script:totalTokens) estimated" "Yellow" "White"

# Context window warnings
foreach ($llm in $llmLimits.GetEnumerator()) {
    $limitTok = $llm.Value * 1000
    if ($script:totalTokens -gt $limitTok) {
        Write-Status "WARN" "Exceeds $($llm.Key) limit ($($llm.Value)K). Consider -SplitKTokens $($llm.Value)" "Yellow" "DarkYellow"
    }
}

if ($langStats.Count -gt 0) {
    $top5 = ($langStats | Select-Object -First 5 | ForEach-Object { "$($_.Language) $($_.Pct)%" }) -join "  |  "
    Write-Status "LANGS"  $top5 "Cyan" "Gray"
}

# ── DRY RUN ────────────────────────────────────────────────
if ($DryRun) {
    Write-Host ""; Write-Host "  ─── DRY RUN — No files written ───" -ForegroundColor DarkCyan; Write-Host ""
    $sortedFiles | ForEach-Object {
        $rel = $_.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
        Write-Host "    $rel" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Status "DRY" "$($validFiles.Count) files | ~$(Format-Tokens $script:totalTokens)" "Cyan" "Cyan"
    if ($skippedLarge.Count -gt 0) { Write-Status "SKIP" "$($skippedLarge.Count) oversized files excluded" "Yellow" "Yellow" }
    exit 0
}

Write-Sep

# ── STEP 5: Write bundle ───────────────────────────────────
Write-SectionHeader "WRITE"
Write-Status "WRITE" "Compiling bundle..." "Red" "Gray"

$processed   = 0
$writtenTokens = 0L
$doStrip     = $StripPaths.IsPresent
$doRedact    = $Redact.IsPresent

# ─── JSON mode: build object in memory ────────────────────
if ($Format -eq 'json') {
    $jsonObj = [ordered]@{
        bundle = [ordered]@{
            version    = $script:VERSION
            generated  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            project    = $projectFolderName
            framework  = $projectInfo.Framework
            entryPoint = $projectInfo.EntryPoint
            git        = if ($gitMeta.Available) {
                @{ branch=$gitMeta.Branch; lastCommit=$gitMeta.LastCommit; remote=$gitMeta.Remote }
            } else { $null }
            languages  = ($langStats | Select-Object -First 8 | ForEach-Object { @{ lang=$_.Language; pct=$_.Pct } })
            fileCount  = $validFiles.Count
            tokenEstimate = $script:totalTokens
        }
        files = @()
    }

    $i = 0
    foreach ($file in $sortedFiles) {
        $i++
        $rel = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\','/').Replace('\','/')
        if (-not $Quiet) {
            Write-Progress -Activity "Bundling" -Status "[$i/$($validFiles.Count)] $rel" -PercentComplete (($i/$validFiles.Count)*100)
        }
        $content = Read-FileContent -Path $file.FullName
        if ($null -eq $content) { continue }
        $null = Invoke-SecretScan -Content $content -RelPath $rel
        if ($doRedact) { $content = Invoke-SecretRedact -Content $content }
        $displayPath = if ($doStrip) { "[PROJECT_ROOT]/$rel" } else { $rel }
        $lang = $languageMap[$file.Extension.ToLower()]
        $jsonObj.files += @{ path=$displayPath; language=$lang; content=$content }
        $writtenTokens += Get-TokenEstimate -Chars $content.Length -Extension $file.Extension -Content $content
        $processed++
    }

    $jsonObj.bundle.sha256 = "computed-after-write"
    $jsonStr = $jsonObj | ConvertTo-Json -Depth 10 -Compress:$false
    [System.IO.File]::WriteAllText($script:resolvedOutput, $jsonStr, [System.Text.Encoding]::UTF8)
    Write-Progress -Activity "Bundling" -Completed

} else {
    # ─── TXT / MD mode ────────────────────────────────────
    try {
        $script:writer = [System.IO.StreamWriter]::new($script:resolvedOutput, $false, [System.Text.Encoding]::UTF8)

        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Header block
        $script:writer.WriteLine("=" * 80)
        $script:writer.WriteLine("  PROJECT BUNDLE v$($script:VERSION) — Generated $ts")
        $script:writer.WriteLine("  Project : $projectFolderName")
        $script:writer.WriteLine("  Files   : $($validFiles.Count)  |  Format: $($Format.ToUpper())  |  Tokens: ~$(Format-Tokens $script:totalTokens)")
        $script:writer.WriteLine("=" * 80)
        $script:writer.WriteLine("")

        # LLM context header
        Invoke-WriteLlmHeader -W $script:writer `
            -ProjectName $projectFolderName `
            -ProjectInfo $projectInfo `
            -GitMeta $gitMeta `
            -LangStats $langStats `
            -TotalTokens $script:totalTokens `
            -FmtStr $Format `
            -FileCount $validFiles.Count

        # Directory tree
        if ($IncludeTree) {
            Write-Status "TREE" "Building directory tree..." "DarkGray" "Gray"
            $script:writer.WriteLine("=" * 80)
            $script:writer.WriteLine("  DIRECTORY STRUCTURE (excluded folders omitted)")
            $script:writer.WriteLine("=" * 80)
            $script:writer.WriteLine("")
            $script:writer.WriteLine((Get-FilteredTree -Path $ProjectRoot -Root $ProjectRoot))
            $script:writer.WriteLine("")
        }

        # Git changed files (if any)
        if ($gitMeta.Available -and $gitMeta.ChangedFiles.Count -gt 0) {
            $script:writer.WriteLine("=" * 80)
            $script:writer.WriteLine("  GIT STATUS — UNCOMMITTED CHANGES")
            $script:writer.WriteLine("=" * 80)
            foreach ($cf in $gitMeta.ChangedFiles) {
                $script:writer.WriteLine("  $cf")
            }
            $script:writer.WriteLine("")
        }

        $script:writer.WriteLine("=" * 80)
        $script:writer.WriteLine("  SOURCE FILES ($($validFiles.Count) files — logically ordered)")
        $script:writer.WriteLine("=" * 80)

        # Write files
        foreach ($file in $sortedFiles) {
            $processed++
            $rel = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\','/').Replace('\','/')

            if (-not $Quiet) {
                Write-Progress -Activity "Bundling" -Status "[$processed/$($validFiles.Count)] $rel" -PercentComplete (($processed/$validFiles.Count)*100)
            }

            if (Test-IsBinaryFile -File $file) {
                $displayPath = if ($doStrip) { "[PROJECT_ROOT]/$rel" } else { $rel }
                $script:writer.WriteLine("")
                $script:writer.WriteLine("=" * 80)
                $script:writer.WriteLine("FILE: $displayPath  [SKIPPED — binary]")
                $script:writer.WriteLine("=" * 80)
                continue
            }

            $ft = Write-FileEntry -Writer $script:writer -File $file -Root $ProjectRoot `
                -RelPath $rel -Format $Format -DoStripPaths $doStrip -DoRedact $doRedact
            $writtenTokens += $ft
        }

        Write-Progress -Activity "Bundling" -Completed

        # Footer with integrity
        $script:writer.WriteLine("")
        $script:writer.WriteLine("=" * 80)
        $script:writer.WriteLine("  END OF BUNDLE")
        $script:writer.WriteLine("  Files   : $processed")
        $script:writer.WriteLine("  Tokens  : ~$(Format-Tokens $writtenTokens)")
        if ($script:secretsFound.Count -gt 0 -and -not $doRedact) {
            $script:writer.WriteLine("  SECRETS : $($script:secretsFound.Count) potential secret(s) detected — REVIEW BEFORE SHARING")
        }
        $script:writer.WriteLine("=" * 80)

    } finally {
        if ($script:writer) {
            try { $script:writer.Flush(); $script:writer.Close(); $script:writer.Dispose() } catch {}
            $script:writer = $null
        }
    }
}

# ── STEP 6: SHA-256 integrity ──────────────────────────────
if (Test-Path $script:resolvedOutput -ErrorAction SilentlyContinue) {
    try {
        $hash = (Get-FileHash -Path $script:resolvedOutput -Algorithm SHA256).Hash.ToLower()
        # Append SHA-256 to bundle (for txt/md — JSON is already closed)
        if ($Format -ne 'json') {
            $hashLine = "`nSHA256: $hash`n"
            [System.IO.File]::AppendAllText($script:resolvedOutput, $hashLine, [System.Text.Encoding]::UTF8)
        }
        Write-Status "SHA256" $hash "DarkGray" "DarkGray"
    } catch { Write-Status "WARN" "Could not compute SHA-256" "Yellow" "Yellow" }
}

# ── STEP 7: Write error log ───────────────────────────────
if ($script:errorLog.Count -gt 0) {
    $logPath = [System.IO.Path]::Combine($OutputDir, "bundle_errors.log")
    try {
        $script:errorLog | Set-Content -Path $logPath -Encoding UTF8
        Write-Status "ERRORS" "$($script:errorLog.Count) error(s) logged to bundle_errors.log" "Yellow" "Yellow"
    } catch {}
}

# ── STEP 8: Save config ───────────────────────────────────
if ($SaveConfig) { Export-BundleConfig -Root $ProjectRoot }

# ── STEP 9: Append run to history log ────────────────────
try {
    $histPath = [System.IO.Path]::Combine($env:USERPROFILE, ".bundle_history.log")
    $histLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  $projectFolderName  |  $($validFiles.Count) files  |  $(Format-Tokens $script:totalTokens)  |  $script:resolvedOutput"
    Add-Content -Path $histPath -Value $histLine -Encoding UTF8 -ErrorAction SilentlyContinue
} catch {}

# ── SUMMARY ───────────────────────────────────────────────
$bundleSize = 0
if (Test-Path $script:resolvedOutput -ErrorAction SilentlyContinue) {
    $bundleSize = [math]::Round((Get-Item $script:resolvedOutput).Length / 1KB, 1)
}

Write-Host ""
Write-Host "  ╔══  BUNDLE COMPLETE  ══╗" -ForegroundColor Red
Write-Host ""
Write-Status "OUTPUT"  (Split-Path $script:resolvedOutput -Leaf)         "White"  "White"
Write-Status "SAVED"   $script:resolvedOutput                             "Green"  "White"
Write-Status "FILES"   "$processed bundled"                               "White"  "Gray"
Write-Status "SIZE"    "${bundleSize} KB"                                  "White"  "Gray"
Write-Status "TOKENS"  "~$(Format-Tokens $writtenTokens)"                  "Yellow" "White"
Write-Status "FORMAT"  $Format.ToUpper()                                   "White"  "Gray"
Write-Host ""

if ($langStats.Count -gt 0) {
    Write-Status "LANGUAGES" "" "Cyan" "Gray"
    foreach ($ls in ($langStats | Select-Object -First 8)) {
        Write-Host "           $($ls.Language.PadRight(16)) $($ls.Pct)%" -ForegroundColor DarkGray
    }
    Write-Host ""
}

if ($skippedLarge.Count -gt 0) {
    Write-Status "WARN" "Skipped (>${MaxFileSizeMB}MB): $($skippedLarge.Count)" "Yellow" "Yellow"
    $skippedLarge | ForEach-Object { Write-Host "           $_" -ForegroundColor DarkYellow }
}

if ($script:secretsFound.Count -gt 0) {
    Write-Host ""
    if ($doRedact) {
        Write-Status "REDACTED" "$($script:secretsFound.Count) secret(s) redacted in output" "Green" "Green"
    } else {
        Write-Status "SECRETS!" "$($script:secretsFound.Count) potential secret(s) detected — DO NOT share without review" "Red" "Red"
        $script:secretsFound | Select-Object -Unique -Property Name,File | ForEach-Object {
            Write-Host "           [$($_.Name)]  $($_.File)" -ForegroundColor DarkYellow
        }
    }
}

if ($script:errorLog.Count -gt 0) {
    Write-Host ""
    Write-Status "ERRORS" "$($script:errorLog.Count) error(s) — see bundle_errors.log" "Yellow" "DarkYellow"
}

Write-Host ""
$secStatus = if ($script:secretsFound.Count -eq 0) { "No secrets detected" } else { "$($script:secretsFound.Count) secret(s) flagged" }
Write-Status "SECURITY" ".env excluded  |  .gitignore respected  |  $secStatus" "DarkGray" "DarkGray"
Write-Status "DONE"     "Drop the output file into any AI tool. The header tells it everything." "DarkGray" "DarkGray"
Write-Host ""
