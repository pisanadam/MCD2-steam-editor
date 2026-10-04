#Requires -Version 5.1
# JSON sayılarını Double'a çevirmeden karşılaştıran yerel doğrulama yardımcıları.

function Get-DFGameProcesses {
    # Match actual game executable names, not editors such as Dungeons-II-Forge.
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '(?i)^(?:Dungeons(?:2)?|MinecraftDungeons(?:II|2))(?:-Win(?:32|64)-(?:Shipping|Development|Test))?$'
    })
}

function Get-DFHash([byte[]]$Bytes) {
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($Sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $Sha.Dispose() }
}

function Convert-DFNumber([string]$Raw) {
    $Match = [regex]::Match($Raw, '^(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$')
    if (-not $Match.Success) { throw 'Geçersiz JSON sayısı.' }
    $Exponent = [long]0
    if ($Match.Groups[4].Success -and -not [long]::TryParse($Match.Groups[4].Value, [ref]$Exponent)) { return 'raw:' + $Raw }
    if ($Exponent -lt -100000 -or $Exponent -gt 100000) { return 'raw:' + $Raw }
    $Digits = ($Match.Groups[2].Value + $Match.Groups[3].Value).TrimStart('0')
    if ($Digits.Length -eq 0) { return '0e0' }
    $Scale = $Exponent - $Match.Groups[3].Value.Length
    while ($Digits.EndsWith('0')) { $Digits = $Digits.Substring(0, $Digits.Length - 1); $Scale++ }
    return $Match.Groups[1].Value + $Digits + 'e' + $Scale.ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Get-DFPathKey([string[]]$Path) {
    if ($Path.Count -eq 0) { return '' }
    return '/' + (($Path | ForEach-Object { $_.Replace('~', '~0').Replace('/', '~1') }) -join '/')
}

function Skip-DFSpace($State) {
    while ($State.At -lt $State.Text.Length -and $State.Text[$State.At] -match '[ \t\r\n]') { $State.At++ }
}

function Read-DFString($State) {
    $Start = $State.At
    if ($State.Text[$State.At] -ne '"') { throw 'JSON metin anahtarı bekleniyordu.' }
    $State.At++
    while ($State.At -lt $State.Text.Length) {
        $Character = $State.Text[$State.At]
        if ($Character -eq '\') { $State.At += 2; continue }
        $State.At++
        if ($Character -eq '"') {
            $Raw = $State.Text.Substring($Start, $State.At - $Start)
            $Value = ConvertFrom-Json -InputObject $Raw
            return [PSCustomObject]@{ Raw = $Raw; Value = $Value }
        }
    }
    throw 'JSON metni tamamlanmamış.'
}

function Read-DFNode($State, [string[]]$Path, [int]$Depth) {
    $State.Nodes++
    if ($Depth -gt 100 -or $State.Nodes -gt 200000) { throw 'Kayıt doğrulama için fazla karmaşık.' }
    Skip-DFSpace $State
    if ($State.At -ge $State.Text.Length) { throw 'JSON değeri eksik.' }
    $Character = $State.Text[$State.At]
    if ($Character -eq '{' -or $Character -eq '[') {
        $IsObject = $Character -eq '{'
        $End = ']'
        if ($IsObject) { $End = '}' }
        $State.At++
        Skip-DFSpace $State
        $Count = 0
        $Names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        if ($State.At -lt $State.Text.Length -and $State.Text[$State.At] -ne $End) {
            while ($true) {
                $Part = $Count.ToString([Globalization.CultureInfo]::InvariantCulture)
                if ($IsObject) {
                    $Part = (Read-DFString $State).Value
                    if (-not $Names.Add($Part)) { throw 'Yinelenen JSON anahtarları doğrulanamaz.' }
                    Skip-DFSpace $State
                    if ($State.Text[$State.At] -ne ':') { throw 'JSON iki nokta ayıracı eksik.' }
                    $State.At++
                }
                Read-DFNode $State @($Path + @($Part)) ($Depth + 1)
                $Count++
                Skip-DFSpace $State
                if ($State.At -ge $State.Text.Length) { throw 'JSON dizi veya nesnesi kapanmamış.' }
                if ($State.Text[$State.At] -eq $End) { break }
                if ($State.Text[$State.At] -ne ',') { throw 'JSON virgül ayıracı eksik.' }
                $State.At++
                Skip-DFSpace $State
            }
        }
        if ($State.At -ge $State.Text.Length -or $State.Text[$State.At] -ne $End) { throw 'JSON kapanış ayıracı eksik.' }
        $State.At++
        if (-not $IsObject) { $State.Arrays[(Get-DFPathKey $Path)] = $Count }
        return
    }
    $Kind = ''
    $Raw = ''
    $Canonical = ''
    if ($Character -eq '"') {
        $String = Read-DFString $State
        $Kind = 'string'
        $Raw = $String.Raw
        $Canonical = $String.Value
    } else {
        $Pattern = [regex]'\G(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)(?=$|[\s,\]}])'
        $Match = $Pattern.Match($State.Text, $State.At)
        if (-not $Match.Success) { throw 'Geçersiz JSON değeri.' }
        $Raw = $Match.Value
        $State.At += $Raw.Length
        $Kind = 'number'
        $Canonical = $Raw
        if ($Raw -eq 'true' -or $Raw -eq 'false') { $Kind = 'boolean' }
        elseif ($Raw -eq 'null') { $Kind = 'null' }
        else { $Canonical = Convert-DFNumber $Raw }
    }
    $Key = Get-DFPathKey $Path
    $State.Leaves[$Key] = [PSCustomObject]@{ Path = @($Path); Key = $Key; Kind = $Kind; Raw = $Raw; Canonical = $Canonical }
}

function Read-DFRecord([byte[]]$Bytes) {
    if ($Bytes.Length -le 0 -or $Bytes.Length -gt 20MB) { throw 'Kayıt boyutu 1 bayt ile 20 MB arasında olmalı.' }
    $Utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $State = [PSCustomObject]@{
        Text = $Utf8.GetString($Bytes).TrimStart([char]0xFEFF)
        At = 0
        Nodes = 0
        Leaves = (New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal))
        Arrays = (New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal))
        Hash = (Get-DFHash $Bytes)
    }
    Read-DFNode $State @() 0
    Skip-DFSpace $State
    if ($State.At -ne $State.Text.Length) { throw 'JSON dışında ek veri var.' }
    foreach ($Pair in @(
        @{ Path = '/SerializeMeta/HardFormat'; Value = 'FCharacterSaveV1' },
        @{ Path = '/CharacterSaveV1/MetaData/IsOnline'; Value = 'false' }
    )) {
        if (-not $State.Leaves.ContainsKey($Pair.Path) -or $State.Leaves[$Pair.Path].Canonical -cne $Pair.Value) { throw 'Tanınmış çevrimdışı FCharacterSaveV1 kaydı gerekli.' }
    }
    if (-not $State.Leaves.ContainsKey('/CharacterSaveV1/MetaData/CharacterId')) { throw 'CharacterId eksik.' }
    return $State
}

function Get-DFInventorySignature($Record) {
    $ArrayPath = '/CharacterSaveV1/Inventory/Entries'
    if (-not $Record.Arrays.ContainsKey($ArrayPath)) { return '' }
    $Parts = New-Object 'System.Collections.Generic.List[string]'
    for ($Index = 0; $Index -lt $Record.Arrays[$ArrayPath]; $Index++) {
        $Prefix = $ArrayPath + '/' + $Index + '/ItemData/'
        foreach ($Field in @('TypeTag', 'GeneratorData/GenesisRandomSeed', 'PickupTimestamp')) {
            $Key = $Prefix + $Field
            if ($Record.Leaves.ContainsKey($Key)) { $Parts.Add($Record.Leaves[$Key].Kind + ':' + $Record.Leaves[$Key].Canonical) }
            else { $Parts.Add('missing') }
        }
        $Parts.Add('|')
    }
    $Text = ConvertTo-Json -InputObject $Parts.ToArray() -Compress
    return Get-DFHash ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-DFAttributes($Record) {
    $Results = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $ArrayPath = '/CharacterSaveV1/Ability/Attributes'
    if (-not $Record.Arrays.ContainsKey($ArrayPath)) { return $Results }
    for ($Index = 0; $Index -lt $Record.Arrays[$ArrayPath]; $Index++) {
        $Prefix = $ArrayPath + '/' + $Index
        $NameKey = $Prefix + '/AttributeName'
        $ValueKey = $Prefix + '/CurrentValue'
        if (-not $Record.Leaves.ContainsKey($NameKey) -or -not $Record.Leaves.ContainsKey($ValueKey)) { continue }
        $Name = $Record.Leaves[$NameKey].Canonical
        if ($Results.ContainsKey($Name)) { $Results[$Name] = $null }
        else { $Results[$Name] = $Record.Leaves[$ValueKey] }
    }
    return $Results
}

function Get-DFInstalledBuilds {
    $Roots = @{}
    try {
        $SteamPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
        if (-not [string]::IsNullOrWhiteSpace($SteamPath)) { $Roots[$SteamPath] = $true }
    } catch { }
    $ProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($ProgramFilesX86)) { $Roots[(Join-Path $ProgramFilesX86 'Steam')] = $true }
    foreach ($Root in @($Roots.Keys)) {
        $LibraryFile = Join-Path $Root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $LibraryFile -PathType Leaf) {
            try {
                foreach ($Match in [regex]::Matches([IO.File]::ReadAllText($LibraryFile), '"path"\s+"((?:[^"\\]|\\.)*)"')) {
                    $Roots[$Match.Groups[1].Value.Replace('\\', '\')] = $true
                }
            } catch { }
        }
    }
    foreach ($Root in $Roots.Keys) {
        $Manifest = Join-Path $Root 'steamapps\appmanifest_1912410.acf'
        if (Test-Path -LiteralPath $Manifest -PathType Leaf) {
            try {
                $Build = [regex]::Match([IO.File]::ReadAllText($Manifest), '"buildid"\s+"([0-9]+)"').Groups[1].Value
                if (-not [string]::IsNullOrWhiteSpace($Build)) { Write-Output ([PSCustomObject]@{ AppId = 1912410; BuildId = $Build; ManifestPath = $Manifest }) }
            } catch { }
        }
    }
}

function New-DFContext([byte[]]$BeforeBytes, [byte[]]$EditedBytes, [string]$Target, [string]$Backup) {
    $Before = Read-DFRecord $BeforeBytes
    $Edited = Read-DFRecord $EditedBytes
    $BeforeAttributes = Get-DFAttributes $Before
    $EditedAttributes = Get-DFAttributes $Edited
    $Attributes = New-Object 'System.Collections.Generic.List[object]'
    $Changes = New-Object 'System.Collections.Generic.List[object]'
    $Unverified = New-Object 'System.Collections.Generic.List[string]'
    foreach ($Name in $EditedAttributes.Keys) {
        $Expected = $EditedAttributes[$Name]
        if ($null -eq $Expected -or -not $BeforeAttributes.ContainsKey($Name) -or $null -eq $BeforeAttributes[$Name]) { $Unverified.Add('Yeni veya yinelenen öznitelik: ' + $Name); continue }
        $Old = $BeforeAttributes[$Name]
        if ($Old.Kind -cne $Expected.Kind -or $Old.Canonical -cne $Expected.Canonical) {
            $Attributes.Add([PSCustomObject]@{ Name = $Name; Kind = $Expected.Kind; Raw = $Expected.Raw; Canonical = $Expected.Canonical })
        }
    }
    foreach ($Key in $Edited.Leaves.Keys) {
        if ($Key -like '/CharacterSaveV1/Ability/Attributes/*' -or $Key -eq '/CharacterSaveV1/MetaData/GameDataUpdated') { continue }
        $Expected = $Edited.Leaves[$Key]
        if (-not $Before.Leaves.ContainsKey($Key)) { $Unverified.Add('Eklenen alan: ' + $Key); continue }
        $Old = $Before.Leaves[$Key]
        if ($Old.Kind -cne $Expected.Kind -or $Old.Canonical -cne $Expected.Canonical) { $Changes.Add($Expected) }
    }
    foreach ($Key in $Before.Leaves.Keys) { if (-not $Edited.Leaves.ContainsKey($Key)) { $Unverified.Add('Silinen alan: ' + $Key) } }
    foreach ($Key in $Before.Arrays.Keys) {
        if (-not $Edited.Arrays.ContainsKey($Key) -or $Before.Arrays[$Key] -ne $Edited.Arrays[$Key]) { $Unverified.Add('Dizi uzunluğu değişti: ' + $Key) }
    }
    $Updated = $null
    $UpdatedKey = '/CharacterSaveV1/MetaData/GameDataUpdated'
    if ($Edited.Leaves.ContainsKey($UpdatedKey)) { $Updated = $Edited.Leaves[$UpdatedKey].Raw }
    return [PSCustomObject]@{
        Schema = 'dungeons-forge-game-verification-v1'
        AppId = 1912410
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        SourcePath = $Target
        BackupPath = $Backup
        CharacterId = $Edited.Leaves['/CharacterSaveV1/MetaData/CharacterId'].Canonical
        OriginalHash = $Before.Hash
        AppliedHash = $Edited.Hash
        AppliedGameDataUpdated = $Updated
        InventorySignature = (Get-DFInventorySignature $Edited)
        ExpectedAttributes = $Attributes.ToArray()
        ExpectedPaths = $Changes.ToArray()
        UnverifiedChanges = $Unverified.ToArray()
        InstalledSteamBuilds = @(Get-DFInstalledBuilds)
        Versions = @{
            SoftVersion = $Edited.Leaves['/SerializeMeta/SoftVersion'].Raw
            InternalVersion = $Edited.Leaves['/SerializeMeta/InternalVersion'].Raw
        }
    }
}
