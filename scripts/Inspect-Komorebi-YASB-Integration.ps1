param(
    [Parameter(Mandatory=$true)]
    [string]$YasbRoot,

    [Parameter(Mandatory=$true)]
    [string]$KomorebiRoot,

    [Parameter(Mandatory=$true)]
    [string]$WhkdRoot,

    [Parameter(Mandatory=$true)]
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"

$YasbRoot = [IO.Path]::GetFullPath($YasbRoot)
$KomorebiRoot = [IO.Path]::GetFullPath($KomorebiRoot)
$WhkdRoot = [IO.Path]::GetFullPath($WhkdRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

foreach ($p in @($YasbRoot,$KomorebiRoot,$WhkdRoot)) {
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        throw "Source folder not found: $p"
    }
}

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$report = Join-Path $OutputRoot "Komorebi-YASB-Integration-Inspection.txt"

$yasbOut = Join-Path $OutputRoot "RelevantSource\yasb"
$komorebiOut = Join-Path $OutputRoot "RelevantSource\komorebi"
$whkdOut = Join-Path $OutputRoot "RelevantSource\whkd"

New-Item -ItemType Directory -Path $yasbOut,$komorebiOut,$whkdOut -Force | Out-Null

$yasbRev = (git -C $YasbRoot rev-parse HEAD).Trim()
$komorebiRev = (git -C $KomorebiRoot rev-parse HEAD).Trim()
$whkdRev = (git -C $WhkdRoot rev-parse HEAD).Trim()

Set-Content -LiteralPath $report -Encoding UTF8 -Value @(
    "KOMOREBI + WHKD + YASB PORTABLE INTEGRATION INSPECTION",
    "",
    "YASB revision:     $yasbRev",
    "Komorebi revision: $komorebiRev",
    "whkd revision:     $whkdRev",
    "Generated:         $(Get-Date)",
    "",
    "SOURCE CODE ONLY.",
    "This workflow does NOT read your AppData, config files, hotkeys, registry, running processes,",
    "Komorebi socket, YASB logs, or any local installation.",
    ""
)

function Add-Section {
    param([string]$Title)

    Add-Content -LiteralPath $report -Encoding UTF8 -Value @(
        "",
        ("=" * 92),
        $Title,
        ("=" * 92)
    )
}

function Inspect-Tree {
    param(
        [string]$Root,
        [string]$Destination,
        [string]$Label,
        [string[]]$Extensions,
        [hashtable]$Groups
    )

    $files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $Extensions -contains $_.Extension.ToLowerInvariant()
        }
    )

    $candidateMap = @{}

    foreach ($group in $Groups.GetEnumerator()) {
        Add-Section "$Label — $($group.Key)"
        $found = $false

        foreach ($file in $files) {
            $lines = Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue
            if ($null -eq $lines) { continue }

            for ($i=0; $i -lt $lines.Count; $i++) {
                $line = [string]$lines[$i]
                $hit = $null

                foreach ($term in $group.Value) {
                    if ($line.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $hit = $term
                        break
                    }
                }

                if (-not $hit) { continue }

                $found = $true
                $candidateMap[$file.FullName] = $true

                $rel = $file.FullName.Substring($Root.Length).TrimStart('\')
                $from = [Math]::Max(0,$i-6)
                $to = [Math]::Min($lines.Count-1,$i+12)

                Add-Content -LiteralPath $report -Encoding UTF8 `
                    -Value ("--- {0} | match: {1} | line {2} ---" -f $rel,$hit,($i+1))

                for ($j=$from; $j -le $to; $j++) {
                    Add-Content -LiteralPath $report -Encoding UTF8 `
                        -Value ("{0,5}: {1}" -f ($j+1),$lines[$j])
                }

                Add-Content -LiteralPath $report -Encoding UTF8 -Value ""
            }
        }

        if (-not $found) {
            Add-Content -LiteralPath $report -Encoding UTF8 -Value "No matches found."
        }
    }

    foreach ($filePath in ($candidateMap.Keys | Sort-Object)) {
        $rel = $filePath.Substring($Root.Length).TrimStart('\')
        $dest = Join-Path $Destination $rel

        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $filePath -Destination $dest -Force
    }
}

$komorebiGroups = [ordered]@{
    "LOCALAPPDATA / DATA_DIR" = @(
        "DATA_DIR",
        "data_local_dir",
        "LOCALAPPDATA",
        "AppData",
        "komorebi.sock",
        "komorebi.hwnd.json",
        "icul"
    )

    "CONFIG HOME" = @(
        "KOMOREBI_CONFIG_HOME",
        "WHKD_CONFIG_HOME",
        "HOME_DIR",
        "WHKD_CONFIG_DIR",
        ".config"
    )

    "TEMP / LOG / STATE" = @(
        "temp_dir",
        "komorebi.state.json",
        "tracing",
        "log",
        "state.json",
        "restore"
    )

    "IPC / STATE QUERY / SUBSCRIBE" = @(
        "SocketMessage",
        "StateQuery",
        "subscribe",
        "Unsubscribe",
        "NamedPipe",
        "komorebi.sock",
        "TcpStream",
        "UnixStream"
    )

    "AUTOSTART / STARTUP" = @(
        "enable-autostart",
        "disable-autostart",
        "Startup",
        "startup",
        "CreateShortcut",
        ".lnk",
        "komorebic-no-console"
    )

    "LICENSE / RUNTIME FILES" = @(
        "license",
        "validation",
        "icul",
        "splash"
    )
}

$yasbGroups = [ordered]@{
    "KOMOREBI EVENT LISTENER" = @(
        "KomorebiEventListener",
        "Komorebi connected to named pipe",
        "Komorebi state query timed out",
        "Waiting for Komorebi",
        "Created named pipe"
    )

    "KOMOREBI COMMAND INVOCATION" = @(
        "komorebic",
        "subprocess",
        "Popen",
        "check_output",
        "run(",
        "which(",
        "shutil.which"
    )

    "KOMOREBI IPC / QUERY" = @(
        "subscribe",
        "state",
        "StateQuery",
        "named pipe",
        "pipe_name",
        "komorebi.sock",
        "LOCALAPPDATA",
        "KOMOREBI_DATA_HOME"
    )

    "KOMOREBI CONFIG / PROCESS ENVIRONMENT" = @(
        "KOMOREBI_CONFIG_HOME",
        "WHKD_CONFIG_HOME",
        "PATH",
        "os.environ",
        "env=",
        "start_command",
        "stop_command",
        "reload_command"
    )
}

$whkdGroups = [ordered]@{
    "CONFIG LOCATION" = @(
        "WHKD_CONFIG_HOME",
        "--config",
        ".config",
        "whkdrc",
        "home_dir"
    )

    "APPDATA / TEMP / PERSISTENCE" = @(
        "LOCALAPPDATA",
        "APPDATA",
        "data_local_dir",
        "temp_dir",
        "state",
        "cache",
        "registry"
    )

    "PROCESS / SHELL ENVIRONMENT" = @(
        "std::process",
        "Command::new",
        "env::var",
        "PATH",
        "pwsh",
        "powershell",
        "cmd"
    )
}

Inspect-Tree `
    -Root $KomorebiRoot `
    -Destination $komorebiOut `
    -Label "KOMOREBI" `
    -Extensions @(".rs",".toml",".md",".json") `
    -Groups $komorebiGroups

Inspect-Tree `
    -Root $YasbRoot `
    -Destination $yasbOut `
    -Label "YASB" `
    -Extensions @(".py",".yaml",".yml",".json",".toml",".md") `
    -Groups $yasbGroups

Inspect-Tree `
    -Root $WhkdRoot `
    -Destination $whkdOut `
    -Label "WHKD" `
    -Extensions @(".rs",".toml",".md") `
    -Groups $whkdGroups

$always = @(
    @{ Root=$KomorebiRoot; Dest=$komorebiOut; Rel="komorebi\src\lib.rs" },
    @{ Root=$KomorebiRoot; Dest=$komorebiOut; Rel="komorebi\src\main.rs" },
    @{ Root=$KomorebiRoot; Dest=$komorebiOut; Rel="komorebi-client\src\lib.rs" },
    @{ Root=$KomorebiRoot; Dest=$komorebiOut; Rel="komorebic\src\main.rs" },
    @{ Root=$KomorebiRoot; Dest=$komorebiOut; Rel="Cargo.toml" },
    @{ Root=$WhkdRoot; Dest=$whkdOut; Rel="src\main.rs" },
    @{ Root=$WhkdRoot; Dest=$whkdOut; Rel="Cargo.toml" }
)

foreach ($item in $always) {
    $src = Join-Path $item.Root $item.Rel

    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path $item.Dest $item.Rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }
}

Set-Content -LiteralPath (Join-Path $OutputRoot "REVISIONS.txt") -Encoding UTF8 -Value @(
    "YASB=$yasbRev",
    "KOMOREBI=$komorebiRev",
    "WHKD=$whkdRev"
)

Add-Section "NEXT STEP"

Add-Content -LiteralPath $report -Encoding UTF8 -Value @(
    "Upload the complete artifact to ChatGPT:",
    "  Komorebi-YASB-Integration-Inspection-<komorebi-commit>",
    "",
    "The final design will then be written against these exact revisions.",
    "",
    "Expected final architecture:",
    "  Komorebi-Portable-Builder -> source-level portable DATA_DIR / temp / config behavior",
    "  YASB-Portable-Builder      -> compatible Komorebi environment / PATH / IPC integration",
    "  whkd                       -> portable config beside Komorebi",
    "",
    "No source modifications were made by this inspection."
)

Write-Host ""
Write-Host "Komorebi + YASB integration inspection complete." -ForegroundColor Green
Write-Host "Output:"
Write-Host "  $OutputRoot"
