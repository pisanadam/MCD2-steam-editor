#Requires -Version 5.1
param(
    [string]$EditedPath = '',
    [string]$SourcePath = '',
    [string]$ExpectedSourceHash = '',
    [string]$LocalDataRoot = $env:LOCALAPPDATA,
    [switch]$NoUI
)

# Yalnızca aynı CharacterId'ye ait çevrimdışı düz JSON kayıt uygulanır.
# Oyun dizinine yazmadan önce doğrulanmış .bak dosyası oluşturulur.
$ErrorActionPreference = 'Stop'
$script:MaxBytes = 20MB
$BackupPath = ''
$BackupVerified = $false
$TemporaryPath = ''
$TargetPath = ''
$Replaced = $false

function Assert-GameClosed {
    $Running = @(Get-DFGameProcesses)
    if ($Running.Count -gt 0) {
        $Names = @($Running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw ('Oyun açık: {0}. Minecraft Dungeons II oyununu tamamen kapatıp tekrar çalıştırın.' -f $Names)
    }
}

function Get-ByteHash([byte[]]$Bytes) {
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($Sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $Sha.Dispose() }
}

function Get-Property($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $Property = $Object.PSObject.Properties[$Name]
    if ($null -ne $Property) { return $Property.Value }
    return $null
}

function Read-OfflineCharacter([string]$Path) {
    $File = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($File.PSIsContainer -or ($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Normal bir kayıt dosyası seçilmeli; klasörler ve dosya bağlantıları kabul edilmez.'
    }
    if ($File.Length -le 0 -or $File.Length -gt $script:MaxBytes) { throw 'Kayıt boyutu 1 bayt ile 20 MB arasında olmalı.' }
    $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    if ($Bytes.Length -gt $script:MaxBytes) { throw 'Kayıt okunurken büyüdü; oyunu kapatıp yeniden deneyin.' }
    $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $Text = $StrictUtf8.GetString($Bytes).TrimStart([char]0xFEFF)
    try { $Document = $Text | ConvertFrom-Json } catch { throw 'Dosya geçerli düz UTF8 JSON değil. GVAS ve şifreli kayıtlar uygulanamaz.' }
    $SerializeMeta = Get-Property $Document 'SerializeMeta'
    $HardFormat = Get-Property $SerializeMeta 'HardFormat'
    if ($HardFormat -cne 'FCharacterSaveV1') { throw 'SerializeMeta.HardFormat alanı FCharacterSaveV1 olmalı.' }
    $Character = Get-Property $Document 'CharacterSaveV1'
    $Meta = Get-Property $Character 'MetaData'
    $IsOnline = Get-Property $Meta 'IsOnline'
    if ($IsOnline -isnot [bool] -or $IsOnline -ne $false) { throw 'Yalnızca IsOnline=false çevrimdışı karakter kayıtları uygulanabilir.' }
    $CharacterId = Get-Property $Meta 'CharacterId'
    $ParsedId = [guid]::Empty
    if ($CharacterId -isnot [string] -or -not [guid]::TryParse($CharacterId, [ref]$ParsedId) -or $ParsedId -eq [guid]::Empty) {
        throw 'MetaData.CharacterId alanında geçerli ve boş olmayan karakter kimliği bulunmalı.'
    }
    $Ability = Get-Property $Character 'Ability'
    $Inventory = Get-Property $Character 'Inventory'
    if ($null -eq $Ability -or $null -eq $Inventory -or $null -eq $Ability.PSObject.Properties['Attributes'] -or $null -eq $Inventory.PSObject.Properties['Entries']) {
        throw 'Karakterin Ability.Attributes ve Inventory.Entries alanları bulunamadı.'
    }
    if ($Ability.Attributes -isnot [System.Array] -or $Inventory.Entries -isnot [System.Array]) {
        throw 'Karakterin Attributes ve Entries alanları JSON dizisi olmalı.'
    }
    $Versions = @{}
    foreach ($Name in @('SoftVersion', 'InternalVersion')) {
        $Value = Get-Property $SerializeMeta $Name
        if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [System.Array] -or $Value -is [PSCustomObject]) {
            throw ('SerializeMeta.{0} sayısal sürüm alanı bulunamadı.' -f $Name)
        }
        $Number = [decimal]$Value
        if ($Number -lt 0 -or $Number -gt [int]::MaxValue -or [decimal]::Truncate($Number) -ne $Number) {
            throw ('SerializeMeta.{0} geçerli bir sürüm numarası olmalı.' -f $Name)
        }
        $Versions[$Name] = [int]$Number
    }
    return [PSCustomObject]@{
        Path = $File.FullName
        Bytes = $Bytes
        Hash = (Get-ByteHash $Bytes)
        CharacterId = $ParsedId.ToString('D')
        HardFormat = $HardFormat
        SoftVersion = $Versions.SoftVersion
        InternalVersion = $Versions.InternalVersion
        FormatHash = (Get-Property $SerializeMeta 'FormatHash')
        GameDataUpdated = (Get-Property $Meta 'GameDataUpdated')
    }
}

function Find-CharacterFiles([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $Queue = New-Object 'System.Collections.Generic.Queue[object]'
    $Queue.Enqueue([PSCustomObject]@{ Path = $Root; Depth = 0 })
    $Count = 0
    while ($Queue.Count -gt 0 -and $Count -lt 2000) {
        $Current = $Queue.Dequeue()
        $Count++
        foreach ($Entry in @(Get-ChildItem -LiteralPath $Current.Path -Force -ErrorAction SilentlyContinue)) {
            if (($Entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($Entry.PSIsContainer) {
                if ($Current.Depth -lt 6) { $Queue.Enqueue([PSCustomObject]@{ Path = $Entry.FullName; Depth = ($Current.Depth + 1) }) }
            } elseif ($Entry.Name -like 'Character*.sav' -and $Entry.Length -le $script:MaxBytes) {
                Write-Output $Entry.FullName
            }
        }
    }
    if ($Count -ge 2000) { throw 'Kayıt arama sınırına ulaşıldı; hedef güvenli biçimde seçilemedi.' }
}

function Assert-SameVersion($Original, $Edited) {
    if ($Original.CharacterId -cne $Edited.CharacterId) { throw 'Düzenlenmiş kayıt bu karaktere ait değil. CharacterId eşleşmiyor.' }
    foreach ($Name in @('HardFormat', 'SoftVersion', 'InternalVersion')) {
        if ($Original.$Name -cne $Edited.$Name) { throw ('Kayıt sürümü uyuşmuyor: {0}. Güncel kaydı tekrar açıp düzenleyin.' -f $Name) }
    }
    if ($null -ne $Original.GameDataUpdated -and $null -ne $Edited.GameDataUpdated -and $Original.GameDataUpdated -cne $Edited.GameDataUpdated) {
        throw 'Kayıt, kopyası alındıktan sonra oyunda güncellenmiş. Güncel kaydı yeniden açıp düzenleyin; eski ilerleme uygulanmadı.'
    }
    if (($null -ne $Original.FormatHash -or $null -ne $Edited.FormatHash) -and $Original.FormatHash -cne $Edited.FormatHash) {
        throw 'SerializeMeta.FormatHash uyuşmuyor; farklı kayıt biçimleri birleştirilemez.'
    }
}

function Assert-Unchanged([string]$Path, [string]$ExpectedHash) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $ExpectedHash) {
        throw ('Dosya işlem sırasında değişti: {0}. Oyun kapalıyken güncel kaydı yeniden düzenleyin.' -f [System.IO.Path]::GetFileName($Path))
    }
}

function Show-Result([string]$Text, [bool]$Success) {
    if ($Success) { Write-Host $Text -ForegroundColor Green } else { Write-Host $Text -ForegroundColor Red }
    if (-not $NoUI) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $Icon = [System.Windows.Forms.MessageBoxIcon]::Information
            if (-not $Success) { $Icon = [System.Windows.Forms.MessageBoxIcon]::Error }
            [void][System.Windows.Forms.MessageBox]::Show($Text, 'Minecraft Dungeons II', [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
        } catch { }
    }
}

try {
    Write-Host ''
    Write-Host 'Minecraft Dungeons II - Düzenlenmiş kaydı uygula' -ForegroundColor Cyan
    Write-Host 'Oyun kapalı olmalı. Seçtiğiniz çevrimdışı karakter kaydı, doğrulanmış yedek alındıktan sonra uygulanır.'
    Write-Host 'Dosyalar yalnızca bu bilgisayarda işlenir.'
    . (Join-Path $PSScriptRoot 'Dogrulama-Ortak.ps1')
    Assert-GameClosed

    if ([string]::IsNullOrWhiteSpace($EditedPath)) {
        if ($NoUI) { throw '-NoUI ile birlikte -EditedPath verilmelidir.' }
        Add-Type -AssemblyName System.Windows.Forms
        $Dialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $Dialog.Title = 'Düzenleyiciden indirilen -duzenlenmis.sav dosyasını seçin'
            $Dialog.Filter = 'Düzenlenmiş kayıt (*-duzenlenmis*.sav)|*-duzenlenmis*.sav|SAV kayıtları (*.sav)|*.sav'
            $Dialog.CheckFileExists = $true
            $Downloads = Join-Path $env:USERPROFILE 'Downloads'
            if (Test-Path -LiteralPath $Downloads -PathType Container) { $Dialog.InitialDirectory = $Downloads }
            if ($Dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Host 'Dosya seçilmedi. Oyun kaydı değiştirilmedi.'
                exit 0
            }
            $EditedPath = $Dialog.FileName
        } finally { $Dialog.Dispose() }
    }
    $Edited = Read-OfflineCharacter $EditedPath
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        if ([string]::IsNullOrWhiteSpace($LocalDataRoot)) { throw 'LOCALAPPDATA konumu bulunamadı.' }
        $SaveRoot = Join-Path $LocalDataRoot 'Dungeons2\Saved\SaveGames'
        $Matches = New-Object 'System.Collections.Generic.List[object]'
        foreach ($CandidatePath in @(Find-CharacterFiles $SaveRoot)) {
            try { $Candidate = Read-OfflineCharacter $CandidatePath } catch { continue }
            if ($Candidate.CharacterId -ceq $Edited.CharacterId) { $Matches.Add($Candidate) }
        }
        if ($Matches.Count -eq 0) { throw ('Aynı CharacterId kimliğine ait mevcut çevrimdışı kayıt bulunamadı. Aranan klasör: {0}' -f $SaveRoot) }
        if ($Matches.Count -ne 1) { throw 'Aynı kimliğe ait birden fazla kayıt bulundu. Hedef belirsiz olduğu için hiçbir kayıt değiştirilmedi.' }
        $Original = $Matches[0]
    } else {
        $Original = Read-OfflineCharacter $SourcePath
        if ([System.IO.Path]::GetFileName($Original.Path) -notlike 'Character*.sav') { throw 'Hedef dosya Character*.sav biçiminde olmalı.' }
    }
    $TargetPath = $Original.Path
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($TargetPath, $Edited.Path)) { throw 'Düzenlenmiş dosya hedefle aynı dosya olamaz. İndirilen ayrı kopyayı seçin.' }
    Assert-SameVersion $Original $Edited
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceHash) -and $Original.Hash -ine $ExpectedSourceHash) { throw 'Oyun kaydı değişti. Güncel kaydı yeniden açın; ilerlemeniz korunuyor.' }
    Assert-GameClosed
    Assert-Unchanged $TargetPath $Original.Hash
    Assert-Unchanged $Edited.Path $Edited.Hash

    $Suffix = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
    $BackupPath = $TargetPath + '.' + $Suffix + '.bak'
    $BackupStream = New-Object System.IO.FileStream($BackupPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $BackupStream.Write($Original.Bytes, 0, $Original.Bytes.Length)
        $BackupStream.Flush($true)
    } finally { $BackupStream.Dispose() }
    Assert-Unchanged $BackupPath $Original.Hash
    $BackupVerified = $true
    Assert-Unchanged $TargetPath $Original.Hash

    $VerificationContext = New-DFContext $Original.Bytes $Edited.Bytes $TargetPath $BackupPath
    $VerificationRoot = Join-Path $LocalDataRoot 'DungeonsForge\Verification'
    [void][IO.Directory]::CreateDirectory($VerificationRoot)
    $ContextPath = Join-Path $VerificationRoot ('context-' + $Edited.CharacterId + '-' + $Suffix + '.json')

    $TemporaryPath = $TargetPath + '.' + [guid]::NewGuid().ToString('N') + '.mcd2tmp'
    $TemporaryStream = New-Object System.IO.FileStream($TemporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $TemporaryStream.Write($Edited.Bytes, 0, $Edited.Bytes.Length)
        $TemporaryStream.Flush($true)
    } finally { $TemporaryStream.Dispose() }
    Assert-Unchanged $TemporaryPath $Edited.Hash
    Assert-GameClosed
    Assert-Unchanged $Edited.Path $Edited.Hash
    Assert-Unchanged $TargetPath $Original.Hash
    Assert-Unchanged $BackupPath $Original.Hash
    [System.IO.File]::Replace($TemporaryPath, $TargetPath, [NullString]::Value)
    $Replaced = $true
    $TemporaryPath = ''
    Assert-Unchanged $TargetPath $Edited.Hash
    $Written = Read-OfflineCharacter $TargetPath
    Assert-SameVersion $Original $Written
    [IO.File]::WriteAllText($ContextPath, (ConvertTo-Json -InputObject $VerificationContext -Depth 20), (New-Object Text.UTF8Encoding($true)))
    Show-Result ("Düzenlenmiş kayıt dosyaya uygulandı; henüz oyunda doğrulanmadı.`r`n`r`nKarakter: " + $Edited.CharacterId + "`r`nYedek: " + $BackupPath + "`r`n`r`nOyunda-Dogrula.cmd dosyasını çalıştırarak karakteri oyunda açıp kaydettikten sonra doğrulayın.") $true
} catch {
    $Reason = $_.Exception.Message
    if ($Replaced -and -not [string]::IsNullOrWhiteSpace($BackupPath)) {
        $RestoreTemp = ''
        try {
            Assert-GameClosed
            Assert-Unchanged $TargetPath $Edited.Hash
            Assert-Unchanged $BackupPath $Original.Hash
            $RestoreTemp = $TargetPath + '.' + [guid]::NewGuid().ToString('N') + '.restoretmp'
            [System.IO.File]::WriteAllBytes($RestoreTemp, [System.IO.File]::ReadAllBytes($BackupPath))
            Assert-Unchanged $RestoreTemp $Original.Hash
            [System.IO.File]::Replace($RestoreTemp, $TargetPath, [NullString]::Value)
            $RestoreTemp = ''
            Assert-Unchanged $TargetPath $Original.Hash
            $Reason += "`r`nÖnceki kayıt yedekten geri yüklendi."
        } catch {
            $Reason += "`r`nOtomatik geri yükleme tamamlanamadı. Oyunu kapatın; doğrulanmış yedek korunuyor: " + $BackupPath
        } finally {
            if (-not [string]::IsNullOrWhiteSpace($RestoreTemp) -and (Test-Path -LiteralPath $RestoreTemp)) { Remove-Item -LiteralPath $RestoreTemp -ErrorAction SilentlyContinue }
        }
    }
    if ($BackupVerified) { $Reason += "`r`nYedek konumu: " + $BackupPath }
    Show-Result ("Kayıt uygulanamadı.`r`n" + $Reason) $false
    exit 1
} finally {
    if (-not [string]::IsNullOrWhiteSpace($TemporaryPath) -and (Test-Path -LiteralPath $TemporaryPath)) { Remove-Item -LiteralPath $TemporaryPath -ErrorAction SilentlyContinue }
}
