<#
    GenshinUltraSlimmer Audio Language Stubber
    Multilingual language stubbing and locale-specific manifest handling: Rueben Gill.
    Adapted from dnullptr's GenshinSlimmer GUI and original project.
    See README.md and the upstream discussion at https://github.com/dnullptr/GenshinSlimmer/pull/22.
#>

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq "STA"
if (-not $isAdmin -or -not $isSta) {
    $scriptPath = $PSCommandPath
    $argumentList = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$scriptPath`""
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList
    exit
}

$emptyMd5 = "d41d8cd98f00b204e9800998ecf8427e"
$emptyHash = "ef46db3751d8e999"
$baseDir = $PSScriptRoot
$configPath = Join-Path $baseDir "path.ini"
$audioAssetsRelativePath = "GenshinImpact_Data\Persistent\AudioAssets"

function Test-GameRoot {
    param([string]$Path)
    return ($Path -and (Test-Path -LiteralPath (Join-Path $Path "GenshinImpact_Data\Persistent\AudioAssets")))
}

function Remove-FileLock {
    param([string]$Path)

    try {
        $file = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($null -eq $file) { return }
        if ($file.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $file.Attributes = $file.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
        }
        if ($file.IsReadOnly) {
            $file.IsReadOnly = $false
        }

        $acl = $file.GetAccessControl()
        $rules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
        $modified = $false
        foreach ($rule in $rules) {
            if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) {
                $acl.RemoveAccessRuleSpecific($rule)
                $modified = $true
            }
        }
        if ($modified) {
            $file.SetAccessControl($acl)
        }
    } catch {
        # The write attempt below reports the actionable access error, if this is insufficient.
    }
}

function Get-ManifestCandidates {
    param([string]$GameRoot)

    $persistentDir = Join-Path $GameRoot "GenshinImpact_Data\Persistent"
    if (-not (Test-Path -LiteralPath $persistentDir -PathType Container)) {
        throw "The game's Persistent folder was not found: $persistentDir"
    }

    return @(
        Get-ChildItem -LiteralPath $persistentDir -File -Recurse |
            Where-Object {
                ($_.Name -like "*versions*persist*" -or $_.Name -like "audio_versions*" -or $_.Name -like "*audio*versions*") -and
                $_.Name -notlike "*.bak"
            } |
            Select-Object -ExpandProperty FullName -Unique
    )
}

function Get-LanguageManifestKeys {
    param(
        [string]$GameRoot
    )

    $keys = @{}
    foreach ($manifestPath in (Get-ManifestCandidates -GameRoot $GameRoot)) {
        foreach ($line in (Get-Content -LiteralPath $manifestPath -Encoding utf8)) {
            if ($line -match '"remoteName":\s*"([^"]+)"') {
                $keys[(ConvertTo-ManifestKey $matches[1])] = $true
            }
        }
    }
    return $keys
}

function Get-LanguageFiles {
    param(
        [string]$GameRoot,
        [string]$Language
    )

    $languageDir = Join-Path (Join-Path $GameRoot $audioAssetsRelativePath) $Language
    if (-not (Test-Path -LiteralPath $languageDir -PathType Container)) {
        throw "The installed language folder was not found: $languageDir"
    }

    return @(Get-ChildItem -LiteralPath $languageDir -File | Where-Object { $_.Name -notlike "*.bak" })
}

function ConvertTo-ManifestKey {
    param([string]$RemoteName)
    return $RemoteName.Replace("\", "/").ToLowerInvariant()
}

function Sync-LanguageManifest {
    param(
        [string]$GameRoot,
        [string]$Language,
        [System.IO.FileInfo[]]$Files
    )

    $manifestPaths = @(Get-ManifestCandidates -GameRoot $GameRoot)
    if ($manifestPaths.Count -eq 0) {
        throw "No current persistent resource or audio manifests were found. Nothing was changed."
    }

    # Keep the locale in each manifest key so matching filenames in other packs are untouched.
    $stubbed = @{}
    foreach ($file in $Files) {
        if ($file.Length -eq 0) {
            $stubbed[(ConvertTo-ManifestKey "$Language/$($file.Name)")] = $true
        }
    }

    $patchedTotal = 0
    foreach ($manifestPath in $manifestPaths) {
        $lines = @(Get-Content -LiteralPath $manifestPath -Encoding utf8)
        $backupPath = "$manifestPath.bak"
        $isPristine = -not ($lines | Select-String -SimpleMatch $emptyMd5 -Quiet)
        if ($isPristine -or -not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $manifestPath -Destination $backupPath -Force
        }

        $output = [System.Collections.Generic.List[string]]::new($lines.Count)
        $patched = 0
        foreach ($line in $lines) {
            if ($line -match '"remoteName":\s*"([^"]+)"' -and
                $stubbed.ContainsKey((ConvertTo-ManifestKey $matches[1]))) {
                $updatedLine = $line -replace '"fileSize":\s*\d+', '"fileSize": 0' `
                                      -replace '"md5":\s*"[^"]+"', "`"md5`": `"$emptyMd5`""
                if ($updatedLine -match '"hash":') {
                    $updatedLine = $updatedLine -replace '"hash":\s*"[^"]+"', "`"hash`": `"$emptyHash`""
                }
                $output.Add($updatedLine)
                $patched++
            } else {
                $output.Add($line)
            }
        }

        Remove-FileLock -Path $manifestPath
        [System.IO.File]::WriteAllLines($manifestPath, $output, [System.Text.UTF8Encoding]::new($false))
        $patchedTotal += $patched
    }

    if ($patchedTotal -eq 0) {
        throw "No current manifest entries matched the stubbed $Language files."
    }
    return $patchedTotal
}

function Restore-LanguageFiles {
    param(
        [string]$GameRoot,
        [string]$Language,
        [System.IO.FileInfo[]]$Files
    )

    $stubbedFiles = @($Files | Where-Object { $_.Length -eq 0 })
    if ($stubbedFiles.Count -eq 0) {
        return 0
    }

    $streamingDir = Join-Path $GameRoot "GenshinImpact_Data\StreamingAssets"
    if (-not (Test-Path -LiteralPath $streamingDir -PathType Container)) {
        throw "The game's StreamingAssets folder was not found: $streamingDir"
    }

    $streamingManifests = @(
        Get-ChildItem -LiteralPath $streamingDir -File -Recurse |
            Where-Object {
                ($_.Name -like "*versions*streaming*" -or $_.Name -like "audio_versions*") -and
                $_.Name -notlike "*.bak"
            }
    )
    $streamingEntries = @{}
    foreach ($manifest in $streamingManifests) {
        foreach ($line in (Get-Content -LiteralPath $manifest.FullName -Encoding utf8)) {
            if ($line -match '"remoteName":\s*"([^"]+)"') {
                $key = ConvertTo-ManifestKey $matches[1]
                if (-not $streamingEntries.ContainsKey($key)) {
                    $streamingEntries[$key] = $line
                }
            }
        }
    }

    $restoreEntries = @{}
    foreach ($file in $stubbedFiles) {
        $key = ConvertTo-ManifestKey "$Language/$($file.Name)"
        if ($streamingEntries.ContainsKey($key)) {
            $restoreEntries[$key] = $streamingEntries[$key]
        }
    }
    if ($restoreEntries.Count -eq 0) {
        throw "No matching current streaming-manifest entries were found for $Language. The zero-byte files were left untouched."
    }

    $manifestPaths = @(Get-ManifestCandidates -GameRoot $GameRoot)
    if ($manifestPaths.Count -eq 0) {
        throw "No current persistent resource or audio manifests were found. The zero-byte files were left untouched."
    }

    foreach ($manifestPath in $manifestPaths) {
        $lines = @(Get-Content -LiteralPath $manifestPath -Encoding utf8)
        $output = [System.Collections.Generic.List[string]]::new($lines.Count)
        foreach ($line in $lines) {
            if ($line -match '"remoteName":\s*"([^"]+)"' -and
                $restoreEntries.ContainsKey((ConvertTo-ManifestKey $matches[1]))) {
                $output.Add($restoreEntries[(ConvertTo-ManifestKey $matches[1])])
            } else {
                $output.Add($line)
            }
        }
        Remove-FileLock -Path $manifestPath
        [System.IO.File]::WriteAllLines($manifestPath, $output, [System.Text.UTF8Encoding]::new($false))
    }

    $removed = 0
    foreach ($file in $stubbedFiles) {
        $key = ConvertTo-ManifestKey "$Language/$($file.Name)"
        if ($restoreEntries.ContainsKey($key)) {
            Remove-FileLock -Path $file.FullName
            Remove-Item -LiteralPath $file.FullName -Force
            $removed++
        }
    }
    return $removed
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

function Read-ProtoVarint {
    param ([byte[]]$Buffer, [ref]$Pos)
    [uint64]$result = 0
    $shift = 0
    while ($Pos.Value -lt $Buffer.Length) {
        $b = $Buffer[$Pos.Value]
        $Pos.Value++
        $result = $result -bor ([uint64]($b -band 0x7F) -shl $shift)
        if (($b -band 0x80) -eq 0) { return $result }
        $shift += 7
    }
    return $result
}

function Parse-ProtoFields {
    param ([byte[]]$Buffer)
    $pos = 0
    $fields = @{}
    while ($pos -lt $Buffer.Length) {
        $tag = Read-ProtoVarint -Buffer $Buffer -Pos ([ref]$pos)
        $fieldNum = [int]($tag -shr 3)
        $wireType = [int]($tag -band 7)
        if ($wireType -eq 0) {
            $fields[$fieldNum] = Read-ProtoVarint -Buffer $Buffer -Pos ([ref]$pos)
        } elseif ($wireType -eq 2) {
            $len = [int](Read-ProtoVarint -Buffer $Buffer -Pos ([ref]$pos))
            if ($len -le 0 -or ($pos + $len) -gt $Buffer.Length) { break }
            $fields[$fieldNum] = $Buffer[$pos..($pos + $len - 1)]
            $pos += $len
        } elseif ($wireType -eq 5) {
            $pos += 4
        } elseif ($wireType -eq 1) {
            $pos += 8
        } else {
            break
        }
    }
    return $fields
}

function Get-LiveServerRevisions {
    param ([string]$GameRoot)
    $persistentDir = Join-Path $GameRoot "GenshinImpact_Data\Persistent"
    $channelFile   = Join-Path $persistentDir "ChannelName"
    $scriptRevFile = Join-Path $persistentDir "ScriptVersion"
    $configIniPath = Join-Path $GameRoot "config.ini"

    $channel = if (Test-Path $channelFile) { (Get-Content $channelFile -Raw).Trim() } else { "OSRELWin" }
    $scriptVer = if (Test-Path $scriptRevFile) { (Get-Content $scriptRevFile -Raw).Trim() } else { "" }
    if (-not $scriptVer -and (Test-Path $configIniPath)) {
        $iniMatch = Select-String -Path $configIniPath -Pattern '^\s*game_version\s*=\s*([0-9.]+)' | Select-Object -First 1
        if ($iniMatch) { $scriptVer = $iniMatch.Matches[0].Groups[1].Value.Trim() }
    }
    if (-not $scriptVer) { $scriptVer = "7.2.0" }

    $dispatchRsaXml = '<RSAKeyValue><Modulus>sJbFp3WcsiojjdQtVnTuvtawL2m4XxK93F6lCnFwcZqUP39txFGGlrogHMqreyawIUN7E5shtwGzigzjW8Ly5CryBJpXP3ehNTqJS7emb+9LlC19Oxa1eQuUQnatgcsd16DPH7kJ5JzN3vXnhvUyk4Qficdmm0uk7FRaNYFi7EJs4xyqFTrp3rDZ0dzBHumlIeK1om7FNt6Nyivgp+UybO7kl0NLFEeSlV4S+7ofitWQsO5xYqKAzSzz+KIRQcxJidGBlZ1JN/g5DPDpx/ztvOWYUlM7TYk6xN3focZpU0kBzAw/rn94yW9z8jpXfzk+MvWzVL/HAcPy4ySwkay0Nw==</Modulus><Exponent>AQAB</Exponent><P>19wQUISXtpnmCrEZfbyZ6IwOy8ZCVaVUtbTjVa8UyfNglzzJG3yzcXU3X35v5/HNCHaXbG2qcbQLThnHBA+obW3RDo+Q49V84Zh1fUNH0ONHHuC09kB//gHqzn/4nLf1aJ2O0NrMyrZNsZ0ZKUKQuVCqWjBOmTNUitcc8RpXZ8s=</P><Q>0W09POM/It7RoVGI+cfbbgSRmzFo9kzSp5lP7iZ81bnvUMabu2nv3OeGc3Pmdh1ZJFRw6iDM6VVbG0uz8g+f8+JT32XdqM7MJAmgfcYfTVBMiVnh330WNkeRrGWqQzB2f2Wr+0vJjU8CAAcOWDh0oNguJ1l1TSyKxqdL8FsA38U=</Q><DP>udt1AJ7psgOYmqQZ+rUlH6FYLAQsoWmVIk75XpE9KRUwmYdw8QXRy2LNpp9K4z7C9wKFJorWMsh+42Q2gzyoHHBtjEf4zPLIb8XBg3UmpKjMV73Kkiy/B4nHDr4I5YdO+iCPEy0RH4kQJFnLjEcQLT9TLgxh4G7d4B2PgdjYYTk=</DP><DQ>rdgiV2LETCvulBzcuYufqOn9/He9i4cl7p4jbathQQFBmSnkqGQ+Cn/eagQxsKaYEsJNoOxtbNu/7x6eVzeFLawYt38Vy0UuzFN5eC54WXNotTN5fk2VnKU4VYVnGrMmCobZhpbYzoZhQKiazby/g60wUtW9u7xXzqOdM/428Yk=</DQ><InverseQ>cGxDsdUW6B/B/nz9QgIhfnKrauCa8/SEVjzoHA6bdlLJNaw8Hlq2cW00ZcCGlXOXLCBBNl9Nn7rf00169TKFx2urNnEK52WKuOOPPDbDuEwAtuoarP8fx21TnF9d4E9ukmJ4ABx3oe8Y1ia/yoCCML3L4L6FbOpbu2vGi1L6zmo=</InverseQ><D>PMpalrBtVgQdoziUtvugKMA9fMT3PHt2MsO+Kx8sJ1+gg0952Sh7na3LWj4G1GlYHstdNj2kWJzUUsTnC/LLrPJ/yEfdmzKyo2FYXGGHgWcubH9QaiQCKv5qdormZhUnW9C3HOOVXUcBtCyRHKuSUqgcN1EWqIVc7CKJv3ugM1aEP5HF/IbDAmfKdllJd0tstKLP9AdA2v/5R+QpEFrG3QJ9TuY4tnGjLp80DEd0FwEk8cLKH5oO8RuLHudKdxJTwm7/jxgnwOuCVtmxcJigDlTPw0wO5oQyCg1YIVBWgRxGQRShofsGVZ3dRQVE+cNnUHgGaStWhETxrnzc6pLBqQ==</D></RSAKeyValue>'

    $knownSeeds = @{
        "7.2.0" = "018bc9560abc707f"
        "7.0.0" = "d9f572e5464f160f"
    }
    $seedList = [System.Collections.Generic.List[string]]::new()
    if ($knownSeeds.ContainsKey($scriptVer)) { $seedList.Add($knownSeeds[$scriptVer]) }
    $seedList.Add("018bc9560abc707f")

    if (-not $knownSeeds.ContainsKey($scriptVer)) {
        try {
            $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
            if ($pwshCmd) {
                $fetchCmd = '$m=Invoke-RestMethod "https://raw.githubusercontent.com/CollapseLauncher/CollapseLauncher-ReleaseRepo/main/metadata/v3/stable/config_master.json"; $rsa=[System.Security.Cryptography.RSA]::Create(); $rsa.FromXmlString([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Key))); $b=Invoke-WebRequest "https://raw.githubusercontent.com/CollapseLauncher/CollapseLauncher-ReleaseRepo/main/metadata/v3/stable/config_GIGlb.json" -UseBasicParsing; $dec=$rsa.Decrypt($b.Content[0..($m.BitSize-1)],[Security.Cryptography.RSAEncryptionPadding]::Pkcs1); $ms=[IO.MemoryStream]::new(); $ms.Write($dec,0,$dec.Length); $ms.Write($b.Content,$m.BitSize,$b.Content.Length-$m.BitSize); $ms.Position=0; $br=[IO.Compression.BrotliStream]::new($ms,[IO.Compression.CompressionMode]::Decompress); $sr=[IO.StreamReader]::new($br); if($sr.ReadToEnd() -match "\"ProtoDispatchKey\"\s*:\s*\"([^\"]+)\""){$matches[1]}'
                $dynSeed = (& $pwshCmd.Source -NoProfile -Command $fetchCmd 2>$null | Select-Object -Last 1).Trim()
                if ($dynSeed -match '^[0-9a-fA-F]{16}$' -and -not $seedList.Contains($dynSeed)) {
                    $seedList.Insert(0, $dynSeed)
                }
            }
        } catch {}
    }

    $hosts = if ($channel -like "CN*") { @("cngfdispatch", "cnqddispatch") } else { @("oseurodispatch", "osusadispatch", "osasiadispatch") }

    foreach ($seed in ($seedList | Select-Object -Unique)) {
        foreach ($h in $hosts) {
            try {
                $url = "https://$h.yuanshen.com/query_cur_region?version=${channel}${scriptVer}&lang=1&platform=3&binary=1&time=260&channel_id=1&sub_channel_id=1&account_type=1&dispatchSeed=$seed&key_id=5"
                $resp = Invoke-RestMethod -Uri $url -TimeoutSec 8 -ErrorAction Stop
                if (-not $resp -or -not $resp.content) { continue }
                $encBytes = [Convert]::FromBase64String($resp.content)
                if ($encBytes.Length -lt 256 -or ($encBytes.Length % 256) -ne 0) { continue }

                $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
                $rsa.FromXmlString($dispatchRsaXml)
                $ms = New-Object System.IO.MemoryStream
                for ($offset = 0; $offset -lt $encBytes.Length; $offset += 256) {
                    $chunk = $encBytes[$offset..($offset + 255)]
                    $dec = $rsa.Decrypt($chunk, $false)
                    $ms.Write($dec, 0, $dec.Length)
                }
                $protoBytes = $ms.ToArray()
                if ($protoBytes.Length -lt 64) { continue }

                $root = Parse-ProtoFields -Buffer $protoBytes
                if (-not $root.ContainsKey(3)) { continue }
                $props = Parse-ProtoFields -Buffer $root[3]
                if (-not $props.ContainsKey(22)) { continue }
                $resVerProps = Parse-ProtoFields -Buffer $props[22]

                $liveResRev  = $resVerProps[1]
                $liveDataRev = $props[14]
                $liveSilRev  = $props[18]
                if ($liveResRev -gt 0) {
                    return @{
                        Success         = $true
                        Source          = "Live Server ($h)"
                        Version         = "${channel}${scriptVer}"
                        ResRevision     = "$liveResRev"
                        SilenceRevision = "$liveSilRev"
                        DataRevision    = "$liveDataRev"
                    }
                }
            } catch {}
        }
    }

    $infoTxt = Join-Path $env:USERPROFILE "AppData\LocalLow\miHoYo\Genshin Impact\info.txt"
    if (Test-Path -LiteralPath $infoTxt) {
        try {
            $firstLine = (Get-Content -LiteralPath $infoTxt -TotalCount 1 -ErrorAction Stop)
            if ($firstLine -match '([A-Z]+Win[0-9.]+)_\d+_(\d+)_(\d+)_(\d+)_(\d+)') {
                return @{
                    Success         = $true
                    Source          = "Local Log (info.txt)"
                    Version         = $matches[1]
                    ResRevision     = $matches[2]
                    DataRevision    = $matches[3]
                    SilenceRevision = $matches[4]
                }
            }
        } catch {}
    }

    return @{ Success = $false }
}

function Sync-StubbedLanguageManifests {
    param([string]$GameRoot)

    $audioAssetsDir = Join-Path $GameRoot $audioAssetsRelativePath
    $languageDirectories = @(
        Get-ChildItem -LiteralPath $audioAssetsDir -Directory |
            Where-Object { $_.Name -ne "BeyondUGC" -and @(Get-ChildItem -LiteralPath $_.FullName -File).Count -gt 0 }
    )
    $totalSynced = 0
    foreach ($directory in $languageDirectories) {
        $files = @(Get-LanguageFiles -GameRoot $GameRoot -Language $directory.Name)
        if (@($files | Where-Object { $_.Length -eq 0 }).Count -gt 0) {
            $synced = Sync-LanguageManifest -GameRoot $GameRoot -Language $directory.Name -Files $files
            $totalSynced += $synced
        }
    }
    return $totalSynced
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GenshinUltraSlimmer Audio - Language Stubber"
        Width="1040" Height="700" MinWidth="900" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        Background="#0D1117" Foreground="#E6EDF3"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="CardBorder" TargetType="Border">
            <Setter Property="Background" Value="#161B22"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="14,10"/>
        </Style>
        <Style x:Key="BtnBase" TargetType="Button">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="BorderBrush" Value="#363B42"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="BorderBrush" Value="#58A6FF"/>
                                <Setter TargetName="bd" Property="Opacity" Value="0.92"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.75"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="18,14,18,14">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="105"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,18,0">
                <Border Background="#1F6FEB" Width="6" Height="34" CornerRadius="3" Margin="0,0,10,0"/>
                <StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="GenshinUltraSlimmer" FontSize="20" FontWeight="Bold" Foreground="#F0F6FC"/>
                        <Border Background="#8957E5" CornerRadius="4" Padding="6,1" Margin="8,0,0,0" VerticalAlignment="Center">
                            <TextBlock Text="AUDIO" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF"/>
                        </Border>
                    </StackPanel>
                    <TextBlock Text="Multilingual voice-over stubbing  |  By Rueben Gill" FontSize="11.5" Foreground="#8B949E"/>
                </StackPanel>
            </StackPanel>
            <Border Grid.Column="1" Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="6" Padding="8,4" VerticalAlignment="Center">
                <DockPanel>
                    <TextBlock Text="Game Path:" Foreground="#8B949E" VerticalAlignment="Center" Margin="2,0,8,0" FontSize="12"/>
                    <TextBox x:Name="TxtGamePath" Background="Transparent" BorderThickness="0" Foreground="#E6EDF3"
                             VerticalContentAlignment="Center" FontSize="12.5"/>
                </DockPanel>
            </Border>
            <Button x:Name="BtnBrowse" Grid.Column="2" Style="{StaticResource BtnBase}" Content="Browse..." Margin="8,0,0,0" VerticalAlignment="Center"/>
            <Button x:Name="BtnRescan" Grid.Column="3" Style="{StaticResource BtnBase}" Content="Rescan" Background="#1F6FEB" BorderBrush="#388BFD" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </Grid>

        <Grid Grid.Row="1" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="1.25*"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Style="{StaticResource CardBorder}">
                <StackPanel>
                    <TextBlock Text="ACTIVE LANGUAGE AUDIO" FontSize="10.5" FontWeight="Bold" Foreground="#8B949E"/>
                    <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                        <TextBlock x:Name="LblTotalActiveGB" Text="0 MB" FontSize="20" FontWeight="Bold" Foreground="#58A6FF"/>
                        <TextBlock x:Name="LblSelectedGB" Text=" (0 selected)" FontSize="12.5" Foreground="#3FB950" VerticalAlignment="Bottom" Margin="8,0,0,2"/>
                    </StackPanel>
                    <TextBlock x:Name="LblTotalFilesSummary" Text="0 active files / 0 stubbed (0KB)" FontSize="11.5" Foreground="#8B949E" Margin="0,2,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="2" Style="{StaticResource CardBorder}">
                <StackPanel>
                    <TextBlock Text="CURRENT MANIFEST STATUS" FontSize="10.5" FontWeight="Bold" Foreground="#8B949E"/>
                    <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                        <TextBlock x:Name="LblManifestSynced" Text="0 synced" FontSize="20" FontWeight="Bold" Foreground="#3FB950"/>
                    </StackPanel>
                    <TextBlock x:Name="LblLanguageCount" Text="0 installed languages" FontSize="11.5" Foreground="#8B949E" Margin="0,2,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Column="4" Style="{StaticResource CardBorder}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <TextBlock Text="IN-GAME REVISION MANAGER (R / S / D)" FontSize="10.5" FontWeight="Bold" Foreground="#8B949E"/>
                        <TextBlock x:Name="LblVersionString" Text="OSRELWin7.2.0_R..._S..._D..." FontSize="13.5" FontWeight="Bold" Foreground="#E3B341" Margin="0,4,0,2"/>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Res Rev (R):" FontSize="11.5" Foreground="#8B949E" VerticalAlignment="Center" Margin="0,0,6,0"/>
                            <TextBox x:Name="TxtResRevision" Width="82" Background="#0D1117" Foreground="#E6EDF3" BorderBrush="#30363D"
                                     BorderThickness="1" Padding="5,2" FontSize="12"/>
                            <Button x:Name="BtnSaveRevision" Style="{StaticResource BtnBase}" Content="Update R" Padding="7,2" FontSize="11.5" Margin="5,0,0,0"/>
                            <Button x:Name="BtnFetchRevision" Style="{StaticResource BtnBase}" Content="Auto-Fetch R" Background="#238636" BorderBrush="#2EA043" Padding="8,2" FontSize="11.5" Margin="5,0,0,0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,0,0,10">
            <DockPanel>
                <TextBlock Text="Select installed languages:" FontWeight="SemiBold" Foreground="#C9D1D9" VerticalAlignment="Center" Margin="0,0,10,0" FontSize="12"/>
                <Button x:Name="BtnSelectAll" Style="{StaticResource BtnBase}" Content="Select All" Background="#122D42" BorderBrush="#1F6FEB" Margin="0,0,6,0"/>
                <Button x:Name="BtnSelectNone" Style="{StaticResource BtnBase}" Content="Clear Selection" Margin="0,0,6,0"/>
                <TextBlock Text="Chinese and Korean are disabled until installed; BeyondUGC is not a language pack." FontSize="11.5" Foreground="#8B949E" VerticalAlignment="Center" Margin="8,0,0,0"/>
            </DockPanel>
        </Border>

        <Border Grid.Row="3" Background="#161B22" BorderBrush="#30363D" BorderThickness="1" CornerRadius="8" Padding="6">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="10,4,18,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="36"/>
                        <ColumnDefinition Width="240"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="90"/>
                        <ColumnDefinition Width="130"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Use" FontSize="11" FontWeight="Bold" Foreground="#8B949E"/>
                    <TextBlock Grid.Column="1" Text="Language / Locale" FontSize="11" FontWeight="Bold" Foreground="#8B949E"/>
                    <TextBlock Grid.Column="2" Text="Installed voice-over audio pack" FontSize="11" FontWeight="Bold" Foreground="#8B949E"/>
                    <TextBlock Grid.Column="3" Text="Files" FontSize="11" FontWeight="Bold" Foreground="#8B949E" HorizontalAlignment="Right"/>
                    <TextBlock Grid.Column="4" Text="Status / Size" FontSize="11" FontWeight="Bold" Foreground="#8B949E" HorizontalAlignment="Right"/>
                </Grid>
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                    <StackPanel x:Name="LanguageListPanel"/>
                </ScrollViewer>
            </Grid>
        </Border>

        <Grid Grid.Row="4" Margin="0,10,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.5*"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="1.15*"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="BtnStubSelected" Grid.Column="0" Style="{StaticResource BtnBase}"
                    Content="Stub Selected &amp; Sync Manifest" Background="#238636" BorderBrush="#2EA043" FontSize="13.5" Padding="14,9"/>
            <Button x:Name="BtnSyncManifest" Grid.Column="2" Style="{StaticResource BtnBase}"
                    Content="[M] Sync Manifests" Background="#1F6FEB" BorderBrush="#388BFD" Padding="10,9"/>
            <Button x:Name="BtnRestoreSelected" Grid.Column="4" Style="{StaticResource BtnBase}"
                    Content="Restore Selected..." Background="#4A3619" BorderBrush="#D29922" Padding="10,9"/>
        </Grid>

        <Border Grid.Row="5" Background="#090D11" BorderBrush="#30363D" BorderThickness="1" CornerRadius="6" Padding="8,6">
            <DockPanel>
                <TextBlock DockPanel.Dock="Top" Text="ACTIVITY LOG" FontSize="10" FontWeight="Bold" Foreground="#8B949E" Margin="0,0,0,3"/>
                <TextBox x:Name="TxtLog" Background="Transparent" Foreground="#C9D1D9" BorderThickness="0"
                         IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                         FontFamily="Consolas" FontSize="11.5"/>
            </DockPanel>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$TxtGamePath = $window.FindName("TxtGamePath")
$BtnBrowse = $window.FindName("BtnBrowse")
$BtnRescan = $window.FindName("BtnRescan")
$LblTotalActiveGB = $window.FindName("LblTotalActiveGB")
$LblSelectedGB = $window.FindName("LblSelectedGB")
$LblTotalFilesSummary = $window.FindName("LblTotalFilesSummary")
$LblManifestSynced = $window.FindName("LblManifestSynced")
$LblLanguageCount = $window.FindName("LblLanguageCount")
$LblVersionString = $window.FindName("LblVersionString")
$TxtResRevision = $window.FindName("TxtResRevision")
$BtnSaveRevision = $window.FindName("BtnSaveRevision")
$BtnFetchRevision = $window.FindName("BtnFetchRevision")
$BtnSelectAll = $window.FindName("BtnSelectAll")
$BtnSelectNone = $window.FindName("BtnSelectNone")
$LanguageListPanel = $window.FindName("LanguageListPanel")
$BtnStubSelected = $window.FindName("BtnStubSelected")
$BtnSyncManifest = $window.FindName("BtnSyncManifest")
$BtnRestoreSelected = $window.FindName("BtnRestoreSelected")
$TxtLog = $window.FindName("TxtLog")

$script:LanguageRows = @{}
$script:AvailableLanguages = @()
$script:BrushConverter = New-Object System.Windows.Media.BrushConverter

function Get-Brush([string]$Hex) {
    return $script:BrushConverter.ConvertFromString($Hex)
}

function Write-GuiLog([string]$Message) {
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $TxtLog.AppendText("[$timestamp] $Message`r`n")
    $TxtLog.ScrollToEnd()
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -le 0) { return "0 MB" }
    if ($Bytes -lt 1GB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N2} GB" -f ($Bytes / 1GB))
}

function Get-SelectedLanguageNames {
    $selected = @()
    foreach ($language in $script:AvailableLanguages) {
        if ($script:LanguageRows[$language].CheckBox.IsChecked) {
            $selected += $language
        }
    }
    return $selected
}

function Get-SelectedDistinctFiles {
    $files = @()
    foreach ($language in (Get-SelectedLanguageNames)) {
        $files += $script:LanguageRows[$language].Files
    }
    return $files
}

function Update-SelectedTotals {
    $selectedFiles = @(Get-SelectedDistinctFiles)
    $bytes = [long]0
    $activeCount = 0
    foreach ($file in $selectedFiles) {
        if ($file.Length -gt 0) {
            $bytes += $file.Length
            $activeCount++
        }
    }
    $LblSelectedGB.Text = " ($activeCount active, $(Format-Bytes $bytes))"
}

function Add-LanguageRow {
    param(
        [string]$Language,
        [System.IO.FileInfo[]]$Files,
        [bool]$IsSelected,
        [bool]$IsInstalled = $true
    )

    $totalBytes = [long]0
    $stubbedCount = 0
    foreach ($file in $Files) {
        $totalBytes += $file.Length
        if ($file.Length -eq 0) { $stubbedCount++ }
    }

    $rowBorder = New-Object System.Windows.Controls.Border
    $rowBorder.Background = Get-Brush "#12171E"
    $rowBorder.BorderBrush = Get-Brush "#21262D"
    $rowBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $rowBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $rowBorder.Margin = New-Object System.Windows.Thickness(4, 2, 4, 2)
    $rowBorder.Padding = New-Object System.Windows.Thickness(10, 7, 12, 7)

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @("36", "240", "*", "90", "130")) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -eq "*") {
            $column.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        } else {
            $column.Width = New-Object System.Windows.GridLength([double]$width)
        }
        $grid.ColumnDefinitions.Add($column)
    }

    $checkBox = New-Object System.Windows.Controls.CheckBox
    $checkBox.IsChecked = $IsSelected
    $checkBox.IsEnabled = $IsInstalled
    $checkBox.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($checkBox, 0)

    $nameLabel = New-Object System.Windows.Controls.TextBlock
    $nameLabel.Text = $Language
    $nameLabel.FontWeight = "SemiBold"
    $nameLabel.FontSize = 13
    $nameLabel.VerticalAlignment = "Center"
    $nameLabel.Foreground = Get-Brush $(if ($IsInstalled) { "#F0F6FC" } else { "#8B949E" })
    [System.Windows.Controls.Grid]::SetColumn($nameLabel, 1)

    $descriptionLabel = New-Object System.Windows.Controls.TextBlock
    $descriptionLabel.Text = if ($IsInstalled) { "Installed language audio files" } else { "Install this voice-over in-game, then rescan" }
    $descriptionLabel.FontSize = 11.5
    $descriptionLabel.VerticalAlignment = "Center"
    $descriptionLabel.Foreground = Get-Brush "#8B949E"
    [System.Windows.Controls.Grid]::SetColumn($descriptionLabel, 2)

    $countLabel = New-Object System.Windows.Controls.TextBlock
    $countLabel.Text = if ($IsInstalled) { "$($Files.Count) files" } else { "Not installed" }
    $countLabel.FontSize = 12
    $countLabel.VerticalAlignment = "Center"
    $countLabel.HorizontalAlignment = "Right"
    $countLabel.Foreground = Get-Brush "#C9D1D9"
    [System.Windows.Controls.Grid]::SetColumn($countLabel, 3)

    $badge = New-Object System.Windows.Controls.Border
    $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $badge.Padding = New-Object System.Windows.Thickness(8, 2, 8, 2)
    $badge.HorizontalAlignment = "Right"
    $badge.VerticalAlignment = "Center"
    $sizeLabel = New-Object System.Windows.Controls.TextBlock
    if (-not $IsInstalled) {
        $badge.Background = Get-Brush "#21262D"
        $sizeLabel.Text = "NOT INSTALLED"
        $sizeLabel.Foreground = Get-Brush "#8B949E"
    } elseif ($stubbedCount -eq $Files.Count) {
        $badge.Background = Get-Brush "#12261E"
        $sizeLabel.Text = "STUBBED (0 KB)"
        $sizeLabel.Foreground = Get-Brush "#3FB950"
    } elseif ($stubbedCount -gt 0) {
        $badge.Background = Get-Brush "#122338"
        $sizeLabel.Text = "$stubbedCount stubbed"
        $sizeLabel.Foreground = Get-Brush "#E3B341"
    } else {
        $badge.Background = Get-Brush "#122338"
        $sizeLabel.Text = Format-Bytes $totalBytes
        $sizeLabel.Foreground = Get-Brush "#58A6FF"
    }
    $sizeLabel.FontSize = 11.5
    $sizeLabel.FontWeight = "Bold"
    $badge.Child = $sizeLabel
    [System.Windows.Controls.Grid]::SetColumn($badge, 4)

    $grid.Children.Add($checkBox) | Out-Null
    $grid.Children.Add($nameLabel) | Out-Null
    $grid.Children.Add($descriptionLabel) | Out-Null
    $grid.Children.Add($countLabel) | Out-Null
    $grid.Children.Add($badge) | Out-Null
    $rowBorder.Child = $grid
    $LanguageListPanel.Children.Add($rowBorder) | Out-Null

    $checkBox.Add_Click({ Update-SelectedTotals })
    $script:LanguageRows[$Language] = @{
        CheckBox = $checkBox
        Files = $Files
    }
}

function Refresh-GameScan {
    $gameRoot = $TxtGamePath.Text.Trim().Trim('"')
    if (-not (Test-GameRoot $gameRoot)) {
        $script:AvailableLanguages = @()
        $script:LanguageRows = @{}
        $LanguageListPanel.Children.Clear()
        $LblTotalActiveGB.Text = "0 MB"
        $LblSelectedGB.Text = " (0 active)"
        $LblTotalFilesSummary.Text = "0 active files / 0 stubbed (0KB)"
        $LblManifestSynced.Text = "Unavailable"
        $LblLanguageCount.Text = "0 installed languages"
        $LblVersionString.Text = "No game selected"
        $TxtResRevision.Text = ""
        Write-GuiLog "Game folder not found or AudioAssets is missing. Browse to the Genshin Impact game folder."
        return
    }

    try {
        Set-Content -LiteralPath $configPath -Value $gameRoot -Encoding utf8
    } catch {
        Write-GuiLog "Could not save path.ini: $_"
    }

    $selectedBeforeScan = @(Get-SelectedLanguageNames)
    $audioAssetsDir = Join-Path $gameRoot $audioAssetsRelativePath
    $languageDirectories = @(
        Get-ChildItem -LiteralPath $audioAssetsDir -Directory |
            Where-Object { $_.Name -ne "BeyondUGC" -and @(Get-ChildItem -LiteralPath $_.FullName -File).Count -gt 0 } |
            Sort-Object Name
    )

    $script:AvailableLanguages = @($languageDirectories | ForEach-Object { $_.Name })
    $script:LanguageRows = @{}
    $LanguageListPanel.Children.Clear()
    $activeBytes = [long]0
    $activeCount = 0
    $stubbedCount = 0

    foreach ($directory in $languageDirectories) {
        $files = @(Get-LanguageFiles -GameRoot $gameRoot -Language $directory.Name)
        foreach ($file in $files) {
            if ($file.Length -eq 0) {
                $stubbedCount++
            } else {
                $activeCount++
                $activeBytes += $file.Length
            }
        }
        Add-LanguageRow -Language $directory.Name -Files $files -IsSelected ($selectedBeforeScan -contains $directory.Name)
    }

    # Show these choices even when absent, but keep unavailable packs out of selectable languages.
    foreach ($language in @("Chinese", "Korean")) {
        if ($script:AvailableLanguages -notcontains $language) {
            Add-LanguageRow -Language $language -Files @() -IsSelected $false -IsInstalled $false
        }
    }

    $LblTotalActiveGB.Text = Format-Bytes $activeBytes
    $LblTotalFilesSummary.Text = "$activeCount active files / $stubbedCount stubbed (0KB)"
    $LblLanguageCount.Text = "$($languageDirectories.Count) installed languages"

    $manifestCount = 0
    try {
        foreach ($manifestPath in (Get-ManifestCandidates -GameRoot $gameRoot)) {
            $manifestCount += @(Get-Content -LiteralPath $manifestPath -Encoding utf8 | Select-String -SimpleMatch $emptyMd5).Count
        }
        $LblManifestSynced.Text = "$manifestCount synced"
    } catch {
        $LblManifestSynced.Text = "Unavailable"
        Write-GuiLog "Manifest scan failed: $_"
    }

    $persistentDir = Join-Path $gameRoot "GenshinImpact_Data\Persistent"
    $channel = if (Test-Path "$persistentDir\ChannelName") { (Get-Content "$persistentDir\ChannelName" -Raw).Trim() } else { "OSRELWin" }
    $scriptVersion = if (Test-Path "$persistentDir\ScriptVersion") { (Get-Content "$persistentDir\ScriptVersion" -Raw).Trim() } else { "?" }
    $resRevision = if (Test-Path "$persistentDir\res_revision") { (Get-Content "$persistentDir\res_revision" -Raw).Trim() } else { "?" }
    $silenceRevision = if (Test-Path "$persistentDir\silence_revision") { (Get-Content "$persistentDir\silence_revision" -Raw).Trim() } else { "?" }
    $dataRevision = if (Test-Path "$persistentDir\data_revision") { (Get-Content "$persistentDir\data_revision" -Raw).Trim() } else { "?" }
    $LblVersionString.Text = "${channel}${scriptVersion}_R${resRevision}_S${silenceRevision}_D${dataRevision}"
    $TxtResRevision.Text = $resRevision

    Update-SelectedTotals
    if ($languageDirectories.Count -eq 0) {
        Write-GuiLog "No installed language audio folders were found."
    } else {
        Write-GuiLog "Scanned '$gameRoot': $($languageDirectories.Count) installed language packs, $activeCount active files, $stubbedCount stubbed."
    }
}

function Sync-SelectedLanguages {
    $selectedLanguages = @(Get-SelectedLanguageNames)
    if ($selectedLanguages.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Select at least one installed language.", "No Languages Selected", "OK", "Information") | Out-Null
        return
    }

    $gameRoot = $TxtGamePath.Text.Trim().Trim('"')
    $totalSynced = 0
    foreach ($language in $selectedLanguages) {
        try {
            $files = @(Get-LanguageFiles -GameRoot $gameRoot -Language $language)
            if (@($files | Where-Object { $_.Length -eq 0 }).Count -eq 0) {
                Write-GuiLog "$language has no stubbed files to synchronize."
                continue
            }
            $synced = Sync-LanguageManifest -GameRoot $gameRoot -Language $language -Files $files
            $totalSynced += $synced
            Write-GuiLog "${language}: synchronized $synced current manifest entries."
        } catch {
            Write-GuiLog "$language manifest sync failed: $_"
        }
    }
    Write-GuiLog "Manifest sync complete: $totalSynced entries synchronized."
    Refresh-GameScan
}

$initialPath = ""
if (Test-Path -LiteralPath $configPath) {
    $savedPath = Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue
    if ($savedPath) { $initialPath = $savedPath.Trim().Trim('"') }
}
if (-not (Test-GameRoot $initialPath)) {
    $defaultPath = "C:\Program Files\HoYoPlay\games\Genshin Impact game"
    if (Test-GameRoot $defaultPath) { $initialPath = $defaultPath }
}
$TxtGamePath.Text = $initialPath
if (-not $initialPath) {
    $LblVersionString.Text = "No game selected"
    $TxtResRevision.Text = ""
}

$BtnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select your 'Genshin Impact game' folder (containing GenshinImpact_Data)"
    if ($TxtGamePath.Text -and (Test-Path -LiteralPath $TxtGamePath.Text)) {
        $dialog.SelectedPath = $TxtGamePath.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TxtGamePath.Text = $dialog.SelectedPath
        try { Refresh-GameScan } catch { Write-GuiLog "Scan failed: $_" }
    }
})

$BtnRescan.Add_Click({
    try { Refresh-GameScan } catch { Write-GuiLog "Scan failed: $_" }
})

$BtnSelectAll.Add_Click({
    foreach ($language in $script:AvailableLanguages) {
        $script:LanguageRows[$language].CheckBox.IsChecked = $true
    }
    Update-SelectedTotals
})

$BtnSelectNone.Add_Click({
    foreach ($language in $script:AvailableLanguages) {
        $script:LanguageRows[$language].CheckBox.IsChecked = $false
    }
    Update-SelectedTotals
})

$BtnSaveRevision.Add_Click({
    $gameRoot = $TxtGamePath.Text.Trim().Trim('"')
    if (-not (Test-GameRoot $gameRoot)) {
        [System.Windows.MessageBox]::Show("Please select a valid Genshin Impact game directory first.", "Invalid Game Path", "OK", "Warning") | Out-Null
        return
    }

    $newR = $TxtResRevision.Text.Trim().TrimStart('R', 'r')
    if ($newR -notmatch '^\d+$') {
        [System.Windows.MessageBox]::Show("Resource revision must be numeric.", "Invalid Revision", "OK", "Warning") | Out-Null
        return
    }

    $persistentDir = Join-Path $gameRoot "GenshinImpact_Data\Persistent"
    try {
        $newR | Out-File -FilePath (Join-Path $persistentDir "res_revision") -Encoding ascii -Force -NoNewline
        $newR | Out-File -FilePath (Join-Path $persistentDir "res_revision_eternal") -Encoding ascii -Force -NoNewline
    } catch {
        Write-GuiLog "Failed to write resource revision: $_"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Revision Update Failed", "OK", "Error") | Out-Null
        return
    }

    try {
        $synced = Sync-StubbedLanguageManifests -GameRoot $gameRoot
        Write-GuiLog "Updated res_revision and res_revision_eternal to R$newR; synchronized $synced stubbed language manifest entries."
    } catch {
        Write-GuiLog "Updated revision to R$newR, but language manifest sync failed: $_"
        [System.Windows.MessageBox]::Show("Revision R$newR was saved, but manifest sync failed:`n$($_.Exception.Message)", "Manifest Sync Failed", "OK", "Error") | Out-Null
    }
    Refresh-GameScan
})

$BtnFetchRevision.Add_Click({
    $gameRoot = $TxtGamePath.Text.Trim().Trim('"')
    if (-not (Test-GameRoot $gameRoot)) {
        [System.Windows.MessageBox]::Show("Please select a valid Genshin Impact game directory first.", "Invalid Game Path", "OK", "Warning") | Out-Null
        return
    }

    Write-GuiLog "Querying HoYoverse live dispatch server for latest revisions..."
    $live = Get-LiveServerRevisions -GameRoot $gameRoot
    if (-not $live.Success) {
        Write-GuiLog "Could not fetch live revision. Enter the R-number manually and click Update R."
        [System.Windows.MessageBox]::Show("Could not fetch the live revision. Check the connection or enter it manually.", "Auto-Fetch Failed", "OK", "Warning") | Out-Null
        return
    }

    $newR = $live.ResRevision
    $TxtResRevision.Text = $newR
    $persistentDir = Join-Path $gameRoot "GenshinImpact_Data\Persistent"
    try {
        $newR | Out-File -FilePath (Join-Path $persistentDir "res_revision") -Encoding ascii -Force -NoNewline
        $newR | Out-File -FilePath (Join-Path $persistentDir "res_revision_eternal") -Encoding ascii -Force -NoNewline
    } catch {
        Write-GuiLog "Failed to write fetched revision R${newR}: $_"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Revision Update Failed", "OK", "Error") | Out-Null
        return
    }

    try {
        $synced = Sync-StubbedLanguageManifests -GameRoot $gameRoot
        Write-GuiLog "Auto-fetched from $($live.Source): R$newR (S$($live.SilenceRevision) / D$($live.DataRevision)); synchronized $synced stubbed language manifest entries."
    } catch {
        Write-GuiLog "Fetched R$newR, but language manifest sync failed: $_"
        [System.Windows.MessageBox]::Show("Revision R$newR was saved, but manifest sync failed:`n$($_.Exception.Message)", "Manifest Sync Failed", "OK", "Error") | Out-Null
    }
    Refresh-GameScan
})

$BtnStubSelected.Add_Click({
    $selectedLanguages = @(Get-SelectedLanguageNames)
    if ($selectedLanguages.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Select at least one installed language.", "No Languages Selected", "OK", "Information") | Out-Null
        return
    }

    $gameRoot = $TxtGamePath.Text.Trim().Trim('"')
    try {
        $manifestKeys = Get-LanguageManifestKeys -GameRoot $gameRoot
        $trackedByLanguage = @{}
        $trackedActive = @()
        $skippedCount = 0
        $existingStubs = 0
        $totalBytes = [long]0

        foreach ($language in $selectedLanguages) {
            $files = @(Get-LanguageFiles -GameRoot $gameRoot -Language $language)
            $existingStubs += @($files | Where-Object { $_.Length -eq 0 }).Count
            $tracked = @(
                $files | Where-Object {
                    $_.Length -gt 0 -and $manifestKeys.ContainsKey((ConvertTo-ManifestKey "$language/$($_.Name)"))
                }
            )
            $trackedByLanguage[$language] = $tracked
            $active = @($files | Where-Object { $_.Length -gt 0 })
            $trackedActive += $tracked
            $skippedCount += ($active.Count - $tracked.Count)
            foreach ($file in $tracked) { $totalBytes += $file.Length }
        }

        if ($skippedCount -gt 0) {
            Write-GuiLog "Skipping $skippedCount files without an exact current language manifest entry."
        }
        if ($trackedActive.Count -eq 0) {
            if ($existingStubs -gt 0) {
                Sync-SelectedLanguages
            } else {
                Write-GuiLog "No selected language files matched the current manifests; nothing was changed."
                [System.Windows.MessageBox]::Show("No selected language files matched current manifest entries.", "No Manifest Matches", "OK", "Warning") | Out-Null
            }
            return
        }

        $languageSummary = $selectedLanguages -join ", "
        $message = "Stub $($trackedActive.Count) files for $languageSummary ($(Format-Bytes $totalBytes)) to 0KB and synchronize the current manifests?`n`n" +
                   "The original audio must be downloaded again to restore it."
        $answer = [System.Windows.MessageBox]::Show(
            $message,
            "Confirm Language Audio Stubbing",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

        $stubbedCount = 0
        foreach ($language in $selectedLanguages) {
            foreach ($file in $trackedByLanguage[$language]) {
                try {
                    Remove-FileLock -Path $file.FullName
                    [System.IO.File]::WriteAllBytes($file.FullName, [byte[]]@())
                    $stubbedCount++
                } catch {
                    Write-GuiLog "Could not stub $($file.FullName): $_"
                }
            }
        }

        $syncedTotal = 0
        foreach ($language in $selectedLanguages) {
            try {
                $updatedFiles = @(Get-LanguageFiles -GameRoot $gameRoot -Language $language)
                if (@($updatedFiles | Where-Object { $_.Length -eq 0 }).Count -gt 0) {
                    $syncedTotal += Sync-LanguageManifest -GameRoot $gameRoot -Language $language -Files $updatedFiles
                }
            } catch {
                Write-GuiLog "$language manifest sync failed: $_"
            }
        }
        Write-GuiLog "Stubbed $stubbedCount files and synchronized $syncedTotal locale-specific manifest entries."
        Refresh-GameScan
    } catch {
        Write-GuiLog "Stubbing failed: $_"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Audio Stubber Error", "OK", "Error") | Out-Null
    }
})

$BtnSyncManifest.Add_Click({
    Sync-SelectedLanguages
})

$BtnRestoreSelected.Add_Click({
    $selectedLanguages = @(Get-SelectedLanguageNames)
    if ($selectedLanguages.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Select at least one installed language.", "No Languages Selected", "OK", "Information") | Out-Null
        return
    }

    $languageSummary = $selectedLanguages -join ", "
    $message = "Remove zero-byte stubs for $languageSummary, restore their current manifest entries, and let the game download the audio again?"
    $answer = [System.Windows.MessageBox]::Show(
        $message,
        "Confirm Language Audio Restore",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $gameRoot = $TxtGamePath.Text.Trim().Trim('"')
    foreach ($language in $selectedLanguages) {
        try {
            $files = @(Get-LanguageFiles -GameRoot $gameRoot -Language $language)
            $restored = Restore-LanguageFiles -GameRoot $gameRoot -Language $language -Files $files
            Write-GuiLog "${language}: removed $restored stubs and restored current manifest entries."
        } catch {
            Write-GuiLog "$language restore failed: $_"
        }
    }
    Refresh-GameScan
})

$window.Add_ContentRendered({
    Write-GuiLog "Language audio stubber ready."
    if ($TxtGamePath.Text) {
        try { Refresh-GameScan } catch { Write-GuiLog "Initial scan failed: $_" }
    }
})

[void]$window.ShowDialog()
