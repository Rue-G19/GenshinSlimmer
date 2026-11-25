param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

function Test-GenshinGameRoot {
    param([string]$Path)

    return (
        -not [string]::IsNullOrWhiteSpace($Path) -and
        (Test-Path -LiteralPath (Join-Path $Path "GenshinImpact.exe") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path "GenshinImpact_Data\Persistent") -PathType Container)
    )
}

function Save-GenshinGameRoot {
    param([string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $configDirectory = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $configDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $ConfigPath,
        $resolvedPath + [System.Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Found Genshin Impact at: $resolvedPath"
}

if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $savedPath = (Get-Content -LiteralPath $ConfigPath -Raw).Trim().Trim('"')
    if (Test-GenshinGameRoot $savedPath) {
        Write-Host "Using saved Genshin Impact location: $savedPath"
        exit 0
    }
}

$candidates = @(
    (Join-Path $env:ProgramFiles "HoYoPlay\games\Genshin Impact game"),
    (Join-Path ${env:ProgramFiles(x86)} "HoYoPlay\games\Genshin Impact game"),
    (Join-Path $env:LOCALAPPDATA "Programs\HoYoPlay\games\Genshin Impact game"),
    (Join-Path $env:ProgramFiles "Genshin Impact game"),
    (Join-Path ${env:ProgramFiles(x86)} "Genshin Impact game")
) | Where-Object { $_ -and $_ -notmatch '^\s*\\' } | Select-Object -Unique

foreach ($candidate in $candidates) {
    if (Test-GenshinGameRoot $candidate) {
        Save-GenshinGameRoot $candidate
        exit 0
    }
}

Write-Host "No saved or standard install found. Scanning fixed drives (up to 8 seconds per drive)..."
$skipDirectoryNames = @(
    '$Recycle.Bin',
    'System Volume Information',
    'Windows',
    'Recovery',
    'PerfLogs'
)
$maxDepth = 5
$maxSecondsPerDrive = 8

foreach ($drive in [System.IO.DriveInfo]::GetDrives() | Where-Object {
    $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady
}) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{
        Path = $drive.RootDirectory.FullName
        Depth = 0
    })

    while ($queue.Count -gt 0 -and $timer.Elapsed.TotalSeconds -lt $maxSecondsPerDrive) {
        $current = $queue.Dequeue()
        if (Test-GenshinGameRoot $current.Path) {
            Save-GenshinGameRoot $current.Path
            exit 0
        }
        if ($current.Depth -ge $maxDepth) {
            continue
        }

        try {
            foreach ($directory in [System.IO.Directory]::EnumerateDirectories($current.Path)) {
                if ($timer.Elapsed.TotalSeconds -ge $maxSecondsPerDrive) {
                    break
                }

                $name = [System.IO.Path]::GetFileName($directory.TrimEnd('\'))
                if ($skipDirectoryNames -contains $name) {
                    continue
                }

                try {
                    $attributes = [System.IO.File]::GetAttributes($directory)
                    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        continue
                    }
                    $queue.Enqueue([pscustomobject]@{
                        Path = $directory
                        Depth = $current.Depth + 1
                    })
                } catch {
                    continue
                }
            }
        } catch {
            continue
        }
    }

    $timer.Stop()
}

Write-Host "Could not locate the game automatically. Use Browse in either tool to select the game folder."
exit 1
