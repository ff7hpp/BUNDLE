<#
.SYNOPSIS
    Universal Multi-Drive Project Bundler v5.0
.DESCRIPTION
    Automatically detects all drives, searches for projects by name,
    and bundles source code into a single LLM-ready file.
    Works on any Windows system regardless of disk setup.
.NOTES
    Version : 5.0 Universal
    Safe    : Never includes .env files
    Fast    : Smart search with priority paths and folder pruning
#>

[CmdletBinding()]
param(
    [string]   $OutputFile      = "",
    [string]   $ProjectRoot     = "",
    [string]   $OutputDir       = "",
    [switch]   $IncludeTree,
    [int]      $MaxFileSizeMB   = 10,
    [string[]] $ExtraExtensions = @(),
    [string[]] $ExtraExcludes   = @(),
    [switch]   $Quiet
)

# ============================================================
#  CONFIG
# ============================================================

$includeExtensions = @(
    '.ps1','.psm1','.psd1','.py','.pyw','.pyx','.pyi',
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

$safeEnvFiles = @('.env.example','.env.sample','.env.template')

$excludeFolders = @(
    'node_modules','bower_components','vendor','packages',
    '.git','.svn','.hg',
    'dist','build','out','target','release','publish',
    '.next','.nuxt','.output','.svelte-kit',
    'bin','obj','compiled','__pycache__','.pytest_cache','.mypy_cache',
    'venv','.venv','env','virtualenv','.tox',
    'logs','log','temp','tmp','.tmp',
    'coverage','.nyc_output','htmlcov',
    '.idea','.vscode','.vs','.fleet',
    '.terraform','.serverless','.cache','cypress'
) + $ExtraExcludes

$excludeFilePatterns = @(
    '*.min.js','*.min.css','*.bundle.js','*.chunk.js','*.map',
    '*.tmp','*.temp','*.bak','*.swp',
    '*.png','*.jpg','*.jpeg','*.gif','*.bmp','*.ico','*.webp',
    '*.psd','*.ai','*.eps','*.fig',
    '*.mp4','*.mp3','*.wav','*.mov','*.avi',
    '*.pdf','*.doc','*.docx','*.xls','*.xlsx','*.ppt','*.pptx',
    '*.zip','*.tar','*.gz','*.7z','*.rar',
    '*.exe','*.dll','*.so','*.o','*.obj','*.pyc',
    '*.db','*.sqlite','*.sqlite3',
    '*.woff','*.woff2','*.ttf','*.otf','*.eot',
    '*.lock','package-lock.json','yarn.lock','pnpm-lock.yaml','poetry.lock'
)

$specialFileNames = @(
    'Dockerfile','Makefile','Procfile','Vagrantfile',
    'Jenkinsfile','LICENSE','LICENCE','README'
)

# System folders to skip during drive-wide search
$systemSkipFolders = @(
    'Windows','Program Files','Program Files (x86)',
    'ProgramData','$Recycle.Bin','System Volume Information',
    'Recovery','PerfLogs','MSOCache','Config.Msi',
    '$WinREAgent','$SysReset','Intel','AMD','NVIDIA'
)

$maxFileBytes = $MaxFileSizeMB * 1024 * 1024

# ============================================================
#  UI HELPERS
# ============================================================

function Write-Banner {
    $W = 70
    $border  = "  ╔" + ("═" * $W) + "╗"
    $divider = "  ╠" + ("═" * $W) + "╣"
    $bottom  = "  ╚" + ("═" * $W) + "╝"
    $empty   = "  ║" + (" " * $W) + "║"

    Write-Host ""
    Write-Host $border -ForegroundColor DarkRed
    Write-Host $empty  -ForegroundColor DarkRed

    $artLines = @(
        @{ Text = "    ██████╗ ██╗   ██╗███╗   ██╗██████╗ ██╗     ███████╗    "; Color = "Red" },
        @{ Text = "    ██╔══██╗██║   ██║████╗  ██║██╔══██╗██║     ██╔════╝    "; Color = "Red" },
        @{ Text = "    ██████╔╝██║   ██║██╔██╗ ██║██║  ██║██║     █████╗      "; Color = "Red" },
        @{ Text = "    ██╔══██╗██║   ██║██║╚██╗██║██║  ██║██║     ██╔══╝      "; Color = "DarkRed" },
        @{ Text = "    ██████╔╝╚██████╔╝██║ ╚████║██████╔╝███████╗███████╗    "; Color = "DarkRed" },
        @{ Text = "    ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝    "; Color = "DarkRed" }
    )

    foreach ($line in $artLines) {
        $padRight = $W - $line.Text.Length
        Write-Host "  ║" -ForegroundColor DarkRed -NoNewline
        Write-Host $line.Text -ForegroundColor $line.Color -NoNewline
        Write-Host (" " * $padRight) -NoNewline
        Write-Host "║" -ForegroundColor DarkRed
    }

    Write-Host $empty   -ForegroundColor DarkRed
    Write-Host $divider -ForegroundColor DarkRed

    $footerText = "   Universal Multi-Drive Bundler " + ([char]0x00B7) + " v5.0 " + ([char]0x00B7) + " LLM-Ready Code Packager"
    $fpad = $W - $footerText.Length
    if ($fpad -lt 0) { $fpad = 0 }
    Write-Host "  ║" -ForegroundColor DarkRed -NoNewline
    Write-Host $footerText -ForegroundColor Gray -NoNewline
    Write-Host (" " * $fpad) -NoNewline
    Write-Host "║" -ForegroundColor DarkRed

    Write-Host $bottom -ForegroundColor DarkRed
    Write-Host ""
}

function Write-Status {
    param([string]$Tag,[string]$Message,[string]$TagColor="DarkGray",[string]$MsgColor="Gray")
    Write-Host "  " -NoNewline
    Write-Host $Tag.PadRight(8) -ForegroundColor $TagColor -NoNewline
    Write-Host " $Message" -ForegroundColor $MsgColor
}

function Write-Sep { Write-Host ("  " + "-" * 60) -ForegroundColor DarkGray }

# ============================================================
#  DRIVE DETECTION
# ============================================================

function Get-AvailableDrives {
    $drives = @()
    try {
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
            $root = $_.Root
            if ($root -and (Test-Path $root -ErrorAction SilentlyContinue)) {
                $drives += $root
            }
        }
    } catch {}
    if ($drives.Count -eq 0) { $drives = @("C:\") }
    return $drives | Sort-Object -Unique
}

# ============================================================
#  SMART PROJECT SEARCH
# ============================================================

function Get-PriorityPaths {
    param([string[]]$Drives)
    $paths = @()
    foreach ($drv in $Drives) {
        # User profile directories
        $usersDir = Join-Path $drv "Users"
        if (Test-Path $usersDir -ErrorAction SilentlyContinue) {
            Get-ChildItem -Path $usersDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $u = $_.FullName
                foreach ($sub in @("Desktop","Documents","Downloads","Projects","repos","dev","source","workspace","code","src","github")) {
                    $p = Join-Path $u $sub
                    if (Test-Path $p -ErrorAction SilentlyContinue) { $paths += $p }
                }
                # Also add the user folder itself at lower priority
                $paths += $u
            }
        }
        # Common dev root folders
        foreach ($sub in @("Projects","repos","dev","source","workspace","code","src","github","work")) {
            $p = Join-Path $drv $sub
            if (Test-Path $p -ErrorAction SilentlyContinue) { $paths += $p }
        }
    }
    return $paths | Sort-Object -Unique
}

function Search-ProjectByName {
    param([string]$Name, [string[]]$Drives)

    $exactMatches   = [System.Collections.Generic.List[string]]::new()
    $partialMatches = [System.Collections.Generic.List[string]]::new()
    $nameLower = $Name.ToLower()

    # Phase 1: Search priority paths (depth 4) — fast
    Write-Status "SEARCH" "Phase 1: Scanning priority locations..." "Red" "Gray"
    $priorityPaths = Get-PriorityPaths -Drives $Drives
    foreach ($base in $priorityPaths) {
        try {
            Get-ChildItem -Path $base -Directory -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object {
                $fn = $_.Name.ToLower()
                if ($fn -eq $nameLower) { $exactMatches.Add($_.FullName) }
                elseif ($fn -like "*$nameLower*") { $partialMatches.Add($_.FullName) }
            }
        } catch {}
    }

    if ($exactMatches.Count -gt 0) { return @{ Exact = $exactMatches; Partial = $partialMatches } }

    # Phase 2: Broader drive scan (depth 3) — skip system folders
    Write-Status "SEARCH" "Phase 2: Expanding to full drive scan..." "DarkRed" "Gray"
    foreach ($drv in $Drives) {
        try {
            Get-ChildItem -Path $drv -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($systemSkipFolders -contains $_.Name) { return }
                if ($_.Name.StartsWith('$')) { return }
                try {
                    Get-ChildItem -Path $_.FullName -Directory -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
                        $fn = $_.Name.ToLower()
                        if ($fn -eq $nameLower -and $exactMatches -notcontains $_.FullName) {
                            $exactMatches.Add($_.FullName)
                        }
                        elseif ($fn -like "*$nameLower*" -and $partialMatches -notcontains $_.FullName) {
                            $partialMatches.Add($_.FullName)
                        }
                    }
                } catch {}
            }
        } catch {}
    }

    return @{ Exact = $exactMatches; Partial = $partialMatches }
}

function Select-FromMatches {
    param($Exact, $Partial)
    $all = @()
    if ($Exact.Count -gt 0) { $all += $Exact }
    if ($Partial.Count -gt 0) { $all += $Partial }
    if ($all.Count -eq 0) { return $null }
    if ($all.Count -eq 1) {
        Write-Status "FOUND" $all[0] "Green" "White"
        $confirm = Read-Host "  Use this path? [Y/n]"
        if ($confirm -match '^n') { return $null }
        return $all[0]
    }

    Write-Host ""
    Write-Status "FOUND" "$($all.Count) matches:" "Green" "White"
    Write-Host ""
    $limit = [Math]::Min($all.Count, 15)
    for ($i = 0; $i -lt $limit; $i++) {
        $tag = if ($Exact -and $Exact -contains $all[$i]) { " [EXACT]" } else { "" }
        Write-Host "    [$($i+1)] $($all[$i])$tag" -ForegroundColor White
    }
    if ($all.Count -gt 15) { Write-Host "    ... and $($all.Count - 15) more" -ForegroundColor DarkGray }
    Write-Host ""
    $choice = Read-Host "  Select number (or 0 to cancel)"
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $limit) {
        return $all[$idx - 1]
    }
    return $null
}

# ============================================================
#  OUTPUT FOLDER SEARCH
# ============================================================

function Search-OutputFolder {
    param([string]$Name, [string[]]$Drives)
    $matches = [System.Collections.Generic.List[string]]::new()
    $nameLower = $Name.ToLower()

    # Check if it's already a valid full path
    if (Test-Path $Name -ErrorAction SilentlyContinue) {
        return $Name
    }

    # Search priority paths
    $priorityPaths = Get-PriorityPaths -Drives $Drives
    foreach ($base in $priorityPaths) {
        try {
            # Check direct child
            $direct = Join-Path $base $Name
            if (Test-Path $direct -ErrorAction SilentlyContinue) { $matches.Add($direct) }
            # Search deeper
            Get-ChildItem -Path $base -Directory -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name.ToLower() -eq $nameLower -and $matches -notcontains $_.FullName) {
                    $matches.Add($_.FullName)
                }
            }
        } catch {}
    }

    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) {
        Write-Host ""
        Write-Status "FOUND" "$($matches.Count) matching output folders:" "Green" "White"
        $limit = [Math]::Min($matches.Count, 10)
        for ($i = 0; $i -lt $limit; $i++) {
            Write-Host "    [$($i+1)] $($matches[$i])" -ForegroundColor White
        }
        Write-Host ""
        $choice = Read-Host "  Select number"
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $limit) {
            return $matches[$idx - 1]
        }
    }
    return $null
}

# ============================================================
#  BINARY DETECTION (8KB stream)
# ============================================================

function Test-IsBinaryFile([string]$Path) {
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $buf = New-Object byte[] 8192
        $n = $stream.Read($buf, 0, $buf.Length)
        $stream.Close()
        for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -eq 0) { return $true } }
        return $false
    } catch { return $true }
}

# ============================================================
#  FAST FILE TRAVERSAL (pruning)
# ============================================================

function Get-ProjectFilesFast {
    param([string]$CurrentPath, [string]$Root, [ref]$Files, [ref]$SkipLarge, [ref]$SkipBin)
    try {
        $items = Get-ChildItem -Path $CurrentPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                if ($excludeFolders -notcontains $item.Name) {
                    Get-ProjectFilesFast -CurrentPath $item.FullName -Root $Root -Files $Files -SkipLarge $SkipLarge -SkipBin $SkipBin
                }
            } else {
                if ($item.FullName -eq $script:resolvedOutput) { continue }
                $skip = $false
                foreach ($p in $excludeFilePatterns) { if ($item.Name -like $p) { $skip = $true; break } }
                if ($skip) { continue }

                $nameLower = $item.Name.ToLower()
                $isMatch = $false

                if ($nameLower -like '.env*') {
                    if ($safeEnvFiles -contains $nameLower) { $isMatch = $true } else { continue }
                }
                if (-not $isMatch) {
                    if ($includeExtensions -contains $item.Extension.ToLower()) { $isMatch = $true }
                    elseif ($item.Extension -eq '' -and $specialFileNames -contains $item.Name) { $isMatch = $true }
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
    } catch {}
}

# ============================================================
#  FILTERED DIRECTORY TREE
# ============================================================

function Get-FilteredTree {
    param([string]$RootPath, [string]$BaseRoot, [int]$Indent = 0)
    $sb = [System.Text.StringBuilder]::new()
    $items = Get-ChildItem -Path $RootPath -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($item in $items) {
        $prefix = ("  " * $Indent) + "|-- "
        if ($item.PSIsContainer) {
            if ($excludeFolders -contains $item.Name) { continue }
            [void]$sb.AppendLine("$prefix$($item.Name)/")
            [void]$sb.Append((Get-FilteredTree -RootPath $item.FullName -BaseRoot $BaseRoot -Indent ($Indent+1)))
        } else {
            [void]$sb.AppendLine("$prefix$($item.Name)")
        }
    }
    return $sb.ToString()
}

# ============================================================
#  TOKEN ESTIMATE
# ============================================================

function Get-TokenEstimate([long]$Chars) {
    $t = [math]::Round($Chars / 4)
    if ($t -lt 1000) { return "$t tokens" }
    if ($t -lt 1000000) { return "$([math]::Round($t/1000,1))K tokens" }
    return "$([math]::Round($t/1000000,2))M tokens"
}

# ============================================================
#  MAIN FLOW
# ============================================================

Write-Banner

# Step 1: Detect drives
$drives = Get-AvailableDrives
Write-Status "DRIVES" "Detected: $($drives -join ', ')" "Red" "White"
Write-Sep

# Step 2: Resolve ProjectRoot
if ($ProjectRoot -eq "") {
    Write-Host ""
    Write-Host "  [" -ForegroundColor DarkGray -NoNewline
    Write-Host "STEP 1" -ForegroundColor Red -NoNewline
    Write-Host "]" -ForegroundColor DarkGray -NoNewline
    Write-Host " Which project do you want to bundle?" -ForegroundColor White
    Write-Host "  (Enter a folder name, full path, or press Enter for current dir)" -ForegroundColor DarkGray
    $userInput = Read-Host "  >"

    if ($userInput -eq "") {
        Write-Status "INFO" "Using current directory." "Yellow" "Gray"
        $ProjectRoot = (Get-Location).Path
    }
    elseif (Test-Path $userInput -ErrorAction SilentlyContinue) {
        $ProjectRoot = (Resolve-Path $userInput).Path
        Write-Status "PATH" "Valid path provided." "Green" "Gray"
    }
    else {
        $results = Search-ProjectByName -Name $userInput -Drives $drives
        $selected = Select-FromMatches -Exact $results.Exact -Partial $results.Partial
        if ($selected) {
            $ProjectRoot = $selected
        } else {
            Write-Status "ERROR" "No project found. Exiting." "Red" "Red"
            exit 1
        }
    }
}
elseif (-not (Test-Path $ProjectRoot -ErrorAction SilentlyContinue)) {
    Write-Status "SEARCH" "Path not found, searching by name..." "Yellow" "Gray"
    $leaf = Split-Path $ProjectRoot -Leaf
    $results = Search-ProjectByName -Name $leaf -Drives $drives
    $selected = Select-FromMatches -Exact $results.Exact -Partial $results.Partial
    if ($selected) { $ProjectRoot = $selected }
    else { Write-Status "ERROR" "Project not found. Exiting." "Red" "Red"; exit 1 }
}

$ProjectRoot = (Resolve-Path $ProjectRoot).Path.TrimEnd('\','/')
$projectFolderName = Split-Path $ProjectRoot -Leaf

Write-Host ""
Write-Status "PROJECT" $projectFolderName "White" "White"
Write-Status "ROOT" $ProjectRoot "White" "Gray"
Write-Sep

# Step 3: Resolve OutputDir
if ($OutputDir -eq "") {
    Write-Host ""
    Write-Host "  [" -ForegroundColor DarkGray -NoNewline
    Write-Host "STEP 2" -ForegroundColor Red -NoNewline
    Write-Host "]" -ForegroundColor DarkGray -NoNewline
    Write-Host " Where do you want to save the output?" -ForegroundColor White
    Write-Host "  (Enter folder name, full path, or press Enter for current dir)" -ForegroundColor DarkGray
    $outInput = Read-Host "  >"

    if ($outInput -eq "") {
        $OutputDir = (Get-Location).Path
    }
    elseif (Test-Path $outInput -ErrorAction SilentlyContinue) {
        $OutputDir = (Resolve-Path $outInput).Path
    }
    else {
        $found = Search-OutputFolder -Name $outInput -Drives $drives
        if ($found) {
            $OutputDir = $found
            Write-Status "FOUND" $OutputDir "Green" "White"
        } else {
            Write-Host ""
            Write-Host "  Folder '$outInput' not found." -ForegroundColor Yellow
            $create = Read-Host "  Create it in current directory? [Y/n]"
            if ($create -match '^n') {
                $OutputDir = (Get-Location).Path
                Write-Status "INFO" "Using current directory." "Yellow" "Gray"
            } else {
                $OutputDir = Join-Path (Get-Location).Path $outInput
                New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
                Write-Status "CREATED" $OutputDir "Green" "White"
            }
        }
    }
}

if (-not (Test-Path $OutputDir -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if ($OutputFile -eq "") { $OutputFile = "bundle_$projectFolderName.txt" }
$script:resolvedOutput = Join-Path $OutputDir $OutputFile

Write-Host ""
Write-Status "OUTPUT" $script:resolvedOutput "White" "Gray"
Write-Sep

# Step 4: Scan files
Write-Host ""
Write-Status "SCAN" "Traversing project tree..." "Red" "Gray"

$skippedLarge  = [System.Collections.Generic.List[string]]::new()
$skippedBinary = [System.Collections.Generic.List[string]]::new()
$validFiles    = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

Get-ProjectFilesFast -CurrentPath $ProjectRoot -Root $ProjectRoot -Files ([ref]$validFiles) -SkipLarge ([ref]$skippedLarge) -SkipBin ([ref]$skippedBinary)
$validFiles = $validFiles | Sort-Object FullName
$fileCount = $validFiles.Count

Write-Status "FOUND" "$fileCount source files queued" "White" "White"

if ($fileCount -eq 0) {
    Write-Status "ERROR" "No files matched. Check project path or use -ExtraExtensions." "Red" "Red"
    exit 1
}

# Step 5: Write bundle
Write-Host ""
Write-Status "WRITE" "Compiling bundle..." "Red" "Gray"

if (Test-Path $script:resolvedOutput) { Remove-Item $script:resolvedOutput -Force }
$writer = [System.IO.StreamWriter]::new($script:resolvedOutput, $false, [System.Text.Encoding]::UTF8)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$writer.WriteLine("=" * 80)
$writer.WriteLine("  PROJECT BUNDLE - Generated by Universal Multi-Drive Bundler v5.0")
$writer.WriteLine("  Date       : $timestamp")
$writer.WriteLine("  Project    : $projectFolderName")
$writer.WriteLine("  Root       : $ProjectRoot")
$writer.WriteLine("  Files      : $fileCount")
$writer.WriteLine("  Drives     : $($drives -join ', ')")
$writer.WriteLine("=" * 80)
$writer.WriteLine("")

if ($IncludeTree) {
    Write-Status "TREE" "Building filtered directory tree..." "DarkGray" "Gray"
    $writer.WriteLine("=" * 80)
    $writer.WriteLine("  DIRECTORY STRUCTURE (excluded folders omitted)")
    $writer.WriteLine("=" * 80)
    $writer.WriteLine("")
    $writer.WriteLine((Get-FilteredTree -RootPath $ProjectRoot -BaseRoot $ProjectRoot))
    $writer.WriteLine("")
    $writer.WriteLine("=" * 80)
    $writer.WriteLine("  SOURCE CODE")
    $writer.WriteLine("=" * 80)
    $writer.WriteLine("")
}

$processed = 0
$totalChars = 0

foreach ($file in $validFiles) {
    $processed++
    $rel = $file.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')

    if (-not $Quiet) {
        Write-Progress -Activity "Bundling files" -Status "[$processed/$fileCount] $rel" -PercentComplete (($processed/$fileCount)*100)
    }

    $writer.WriteLine("")
    $writer.WriteLine("=" * 80)
    $writer.WriteLine("FILE: $rel")
    $writer.WriteLine("=" * 80)

    if (Test-IsBinaryFile $file.FullName) {
        $skippedBinary.Add($rel)
        $writer.WriteLine("[SKIPPED - binary content detected]")
    } else {
        try {
            $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $writer.WriteLine($content)
            $totalChars += $content.Length
        } catch {
            $writer.WriteLine("[ERROR reading file: $($_.Exception.Message)]")
        }
    }
}

$writer.WriteLine("")
$writer.WriteLine("=" * 80)
$writer.WriteLine("  END OF BUNDLE")
$writer.WriteLine("  Total files  : $processed")
$writer.WriteLine("  Token est.   : $(Get-TokenEstimate $totalChars)")
$writer.WriteLine("=" * 80)
$writer.Close()
$writer.Dispose()
Write-Progress -Activity "Bundling files" -Completed

# Step 6: Summary
$bundleSize = [math]::Round((Get-Item $script:resolvedOutput).Length / 1KB, 1)
$tokenEst = Get-TokenEstimate $totalChars

Write-Host ""
Write-Host "  ====  BUNDLE COMPLETE  ====" -ForegroundColor Red
Write-Host ""
Write-Status "OUTPUT" (Split-Path $script:resolvedOutput -Leaf) "White" "White"
Write-Status "FILES" "$processed bundled" "White" "Gray"
Write-Status "SIZE" "${bundleSize} KB" "White" "Gray"
Write-Status "TOKENS" $tokenEst "Yellow" "White"
Write-Status "SAVED" $script:resolvedOutput "Green" "White"
Write-Host ""

if ($skippedLarge.Count -gt 0) {
    Write-Status "WARN" "Skipped (>${MaxFileSizeMB}MB): $($skippedLarge.Count) files" "Yellow" "Yellow"
    $skippedLarge | ForEach-Object { Write-Host "           $_" -ForegroundColor DarkYellow }
}
if ($skippedBinary.Count -gt 0) {
    Write-Status "WARN" "Skipped (binary): $($skippedBinary.Count) files" "Yellow" "Yellow"
    $skippedBinary | ForEach-Object { Write-Host "           $_" -ForegroundColor DarkYellow }
}

Write-Host ""
Write-Status "DONE" ".env excluded | secrets protected" "DarkGray" "DarkGray"
Write-Host ""
