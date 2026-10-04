#Requires -Version 5.1
param(
    [string]$LocalDataRoot = $env:LOCALAPPDATA,
    [string[]]$SteamRootsOverride = @(),
    [string]$OutputBase = '',
    [switch]$NoExplorer,
    [switch]$SkipRegistry,
    [switch]$NonInteractive
)

# Windows PowerShell 5.1. Oyun dosyalarında yalnızca okuma yapar.
# Çıktı ve HTML yalnızca Masaüstündeki yeni klasöre yazılır.
$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($true)
$script:Notes = New-Object 'System.Collections.Generic.List[string]'
$script:Candidates = New-Object 'System.Collections.Generic.List[object]'
$script:SeenFiles = @{}
$script:SeenRoots = @{}
$script:SearchRoots = New-Object 'System.Collections.Generic.List[string]'
$script:ManifestRows = New-Object 'System.Collections.Generic.List[string]'
$script:CandidateLimit = 100
$script:ByteLimit = 20MB

function Add-Root([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $Full = [System.IO.Path]::GetFullPath($Path) } catch { return }
    if (-not $script:SeenRoots.ContainsKey($Full)) {
        $script:SeenRoots[$Full] = $true
        $script:SearchRoots.Add($Full)
    }
}

function Get-JsonProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $Property = $Object.PSObject.Properties[$Name]
    if ($null -ne $Property) { return $Property.Value }
    return $null
}

function Inspect-Candidate([System.IO.FileInfo]$File, [string]$Root) {
    if ($script:Candidates.Count -ge $script:CandidateLimit) { return }
    if ($script:SeenFiles.ContainsKey($File.FullName)) { return }
    $script:SeenFiles[$File.FullName] = $true
    if (($File.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return }
    if ($File.Extension.ToLowerInvariant() -notin @('.sav', '.dat', '.json')) { return }
    if ($File.Name -match '(?i)auth|token|entitlement|credential|settings|global|account|telemetry|session|manifest|steam_autocloud|cloudsync|^guid\.') { return }
    if ($File.Length -le 0 -or $File.Length -gt $script:ByteLimit) {
        $script:Notes.Add(('Boyut nedeniyle atlandı: {0} ({1} bayt)' -f $File.FullName, $File.Length))
        return
    }

    try {
        # Dogrulama icin ham kaydi okur; JSON'u yeniden yazmaz.
        $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
        $Text = [System.Text.Encoding]::UTF8.GetString($Bytes).TrimStart([char]0xFEFF)
        $HasMarker = $Text -match '"(?:FCharacterSaveV1|CharacterSaveV1)"'
        $NamedLikeHero = $File.BaseName -match '(?i)^(character|hero|player|savegame)(?:[0-9a-f_. -]|$)'
        if (-not $HasMarker -and -not $NamedLikeHero) { return }

        $Status = 'Tanınmayan kayıt adayı; oyuna uyumluluğu doğrulanmadı.'
        $Editable = $false
        $HeroName = $File.BaseName
        if ($HasMarker) {
            try {
                $Document = $Text | ConvertFrom-Json
                $Body = Get-JsonProperty $Document 'CharacterSaveV1'
                if ($null -eq $Body) { $Body = Get-JsonProperty $Document 'FCharacterSaveV1' }
                if ($null -eq $Body) { $Body = $Document }
                $Meta = Get-JsonProperty $Body 'MetaData'
                $Ability = Get-JsonProperty $Body 'Ability'
                $Inventory = Get-JsonProperty $Body 'Inventory'
                $IsOnline = Get-JsonProperty $Meta 'IsOnline'
                $SerializeMeta = Get-JsonProperty $Document 'SerializeMeta'
                $HardFormat = Get-JsonProperty $SerializeMeta 'HardFormat'
                $HasHeroFields = ($null -ne $Ability) -and ($null -ne $Inventory) -and ($null -ne $Ability.PSObject.Properties['Attributes']) -and ($null -ne $Inventory.PSObject.Properties['Entries'])
                if ($HasHeroFields -and $HardFormat -ceq 'FCharacterSaveV1' -and $IsOnline -is [bool] -and $IsOnline -eq $false) {
                    $Editable = $true
                    $Status = 'Tanınmış çevrimdışı CharacterSaveV1 JSON. Oyun içi yükleme bu bilgisayarda denenmeli.'
                } elseif ($HasHeroFields -and $IsOnline -eq $true) {
                    $Status = 'Çevrimiçi karakter: asıl veri oyun sunucusunda; düzenleyiciye açılmaz.'
                } else {
                    $Status = 'Karakter JSON adayı; çevrimdışı olması veya alanları doğrulanamadı.'
                }
                $SavedName = Get-JsonProperty $Meta 'Name'
                if ($SavedName -is [string] -and -not [string]::IsNullOrWhiteSpace($SavedName)) { $HeroName = $SavedName }
            } catch {
                $Status = 'Karakter işareti var, JSON ayrışamadı; yalnızca ham kopya alındı.'
            }
        } elseif ($Bytes.Length -ge 4 -and [System.Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -eq 'GVAS') {
            $Status = 'GVAS ikili kayıt adayı; bu düzenleyici bu biçimi yazmaz.'
        }
        $script:Candidates.Add([PSCustomObject]@{
            Source = $File.FullName
            FileName = $File.Name
            Root = $Root
            Length = $Bytes.Length
            Status = $Status
            Editable = $Editable
            HeroName = $HeroName
            CopyPath = ''
        })
    } catch {
        $script:Notes.Add(('Okunamadı: {0}: {1}' -f $File.FullName, $_.Exception.Message))
    }
}

function Search-Folder([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        $script:Notes.Add(('Klasör bulunamadı: {0}' -f $Root))
        return
    }
    # Yapilandirma/gunluk klasorlerine ve baglantilara girmez. Tum diski taramaz.
    $Queue = New-Object 'System.Collections.Generic.Queue[object]'
    $Queue.Enqueue([PSCustomObject]@{ Path = $Root; Depth = 0 })
    $FoldersVisited = 0
    while ($Queue.Count -gt 0 -and $FoldersVisited -lt 2000) {
        $Current = $Queue.Dequeue()
        $FoldersVisited++
        try { $Children = @(Get-ChildItem -LiteralPath $Current.Path -Force -ErrorAction Stop) } catch {
            $script:Notes.Add(('Klasör okunamadı: {0}' -f $Current.Path))
            continue
        }
        foreach ($Child in $Children) {
            if (($Child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($Child.PSIsContainer) {
                if ($Current.Depth -lt 6 -and $Child.Name -notmatch '(?i)^(config|logs|crashes|screenshots|auth|tokens|credentials|webcache|cache|temp)$') {
                    $Queue.Enqueue([PSCustomObject]@{ Path = $Child.FullName; Depth = ($Current.Depth + 1) })
                }
            } else {
                Inspect-Candidate $Child $Root
            }
        }
    }
    if ($FoldersVisited -ge 2000) { $script:Notes.Add(('Klasör arama sınırına ulaşıldı: {0}' -f $Root)) }
}

function Read-SteamLibraries([string[]]$InstallRoots) {
    $Libraries = @{}
    foreach ($SteamRoot in $InstallRoots) {
        if ([string]::IsNullOrWhiteSpace($SteamRoot)) { continue }
        $Libraries[$SteamRoot] = $true
        $Vdf = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $Vdf -PathType Leaf) {
            try {
                $Content = [System.IO.File]::ReadAllText($Vdf)
                foreach ($Match in [regex]::Matches($Content, '"path"\s+"((?:[^"\\]|\\.)*)"')) {
                    $Library = $Match.Groups[1].Value.Replace('\\', '\')
                    if (-not [string]::IsNullOrWhiteSpace($Library)) { $Libraries[$Library] = $true }
                }
            } catch { $script:Notes.Add(('Steam kütüphane listesi okunamadı: {0}' -f $Vdf)) }
        }
        $Userdata = Join-Path $SteamRoot 'userdata'
        if (Test-Path -LiteralPath $Userdata -PathType Container) {
            foreach ($Account in @(Get-ChildItem -LiteralPath $Userdata -Directory -ErrorAction SilentlyContinue)) {
                if ($Account.Name -match '^\d+$') { Add-Root (Join-Path $Account.FullName '1912410\remote') }
            }
        }
    }
    foreach ($Library in $Libraries.Keys) {
        $Manifest = Join-Path $Library 'steamapps\appmanifest_1912410.acf'
        if (Test-Path -LiteralPath $Manifest -PathType Leaf) {
            try {
                $Content = [System.IO.File]::ReadAllText($Manifest)
                $Build = [regex]::Match($Content, '"buildid"\s+"([0-9]+)"').Groups[1].Value
                if ([string]::IsNullOrEmpty($Build)) { $Build = 'bilinmiyor' }
                $script:ManifestRows.Add(('Steam AppID 1912410; buildid {0}; manifest {1}' -f $Build, $Manifest))
            } catch { $script:Notes.Add(('Steam oyun manifesti okunamadı: {0}' -f $Manifest)) }
        }
    }
}

try {
    Write-Host ''
    Write-Host 'Minecraft Dungeons II - Steam kayıt bulucu' -ForegroundColor Cyan
    Write-Host 'Orijinal kayıtlar değiştirilmez. Dosyalar internete yüklenmez.'
    Write-Host 'Önce oyunu tamamen kapatın. Yerel çevrimdışı karakter kaydı ve Steam sürüm bilgisi aranıyor...'

    if ([string]::IsNullOrWhiteSpace($LocalDataRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $LocalDataRoot = Join-Path $env:USERPROFILE 'AppData\Local' }
    }
    if (-not [string]::IsNullOrWhiteSpace($LocalDataRoot)) {
        Add-Root (Join-Path $LocalDataRoot 'Dungeons2\Saved\SaveGames')
        Add-Root (Join-Path $LocalDataRoot 'Dungeons2\Saved')
    }

    $SteamRoots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($Root in $SteamRootsOverride) { if (-not [string]::IsNullOrWhiteSpace($Root)) { $SteamRoots.Add($Root) } }
    if (-not $SkipRegistry) {
        foreach ($Spec in @(
            @{ Key = 'HKCU:\Software\Valve\Steam'; Value = 'SteamPath' },
            @{ Key = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Value = 'InstallPath' },
            @{ Key = 'HKLM:\SOFTWARE\Valve\Steam'; Value = 'InstallPath' }
        )) {
            try {
                $RegistryValue = (Get-ItemProperty -LiteralPath $Spec.Key -Name $Spec.Value -ErrorAction Stop).($Spec.Value)
                if ($RegistryValue -is [string] -and -not [string]::IsNullOrWhiteSpace($RegistryValue)) { $SteamRoots.Add($RegistryValue) }
            } catch { }
        }
        $ProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        if (-not [string]::IsNullOrWhiteSpace($ProgramFilesX86)) { $SteamRoots.Add((Join-Path $ProgramFilesX86 'Steam')) }
    }
    Read-SteamLibraries @($SteamRoots | Select-Object -Unique)
    foreach ($Root in $script:SearchRoots) { Search-Folder $Root }

    if ([string]::IsNullOrWhiteSpace($OutputBase)) { $OutputBase = [Environment]::GetFolderPath('Desktop') }
    if ([string]::IsNullOrWhiteSpace($OutputBase)) { $OutputBase = Join-Path $env:USERPROFILE 'Desktop' }
    [void][System.IO.Directory]::CreateDirectory($OutputBase)
    $FolderName = 'Dungeons-II-Kayit-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $Output = Join-Path $OutputBase $FolderName
    [void][System.IO.Directory]::CreateDirectory($Output)
    $Copies = Join-Path $Output 'Kayit-Kopyalari'
    [void][System.IO.Directory]::CreateDirectory($Copies)
    $Report = New-Object 'System.Collections.Generic.List[string]'
    $Report.Add('Minecraft Dungeons II Steam kayıt arama raporu')
    $Report.Add(('Tarih: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $Report.Add('Oyun kayıtları yalnızca okundu. Orijinaller değiştirilmedi. İnternet aktarımı yapılmadı.')
    $Report.Add('Arama konumları topluluk kaynaklarından alınmıştır; her build veya bilgisayarda aynı olmayabilir.')
    $Report.Add('Aday dosya bulunması tek başına oyun uyumluluğu anlamına gelmez.')
    $Report.Add('')
    if ($script:ManifestRows.Count -eq 0) { $Report.Add('Steam manifesti bulunamadı; oyun kurulu olmadığı sonucu çıkarılamaz.') }
    foreach ($Row in $script:ManifestRows) { $Report.Add($Row) }
    $Report.Add('')
    $Report.Add('Aranan klasörler:')
    foreach ($Root in $script:SearchRoots) { $Report.Add($Root) }
    $Report.Add('')
    $Report.Add(('Bulunan kayıt adayları: {0}' -f $script:Candidates.Count))
    $Number = 0
    foreach ($Candidate in $script:Candidates) {
        $Number++
        $CopyDir = Join-Path $Copies ('{0:D3}' -f $Number)
        [void][System.IO.Directory]::CreateDirectory($CopyDir)
        $Candidate.CopyPath = Join-Path $CopyDir $Candidate.FileName
        Copy-Item -LiteralPath $Candidate.Source -Destination $Candidate.CopyPath -ErrorAction Stop
        $HashBefore = (Get-FileHash -LiteralPath $Candidate.Source -Algorithm SHA256).Hash
        $HashAfter = (Get-FileHash -LiteralPath $Candidate.CopyPath -Algorithm SHA256).Hash
        if ($HashBefore -ne $HashAfter) { throw ('Kopya doğrulanamadı: {0}. Oyun kapalıyken tekrar deneyin.' -f $Candidate.FileName) }
        $Report.Add(('Dosya {0}: {1}' -f $Number, $Candidate.Source))
        $Report.Add(('Durum: {0}' -f $Candidate.Status))
        $Report.Add(('Boyut: {0} bayt; SHA256: {1}' -f $Candidate.Length, $HashAfter))
        $Report.Add(('Ham kopya: Kayit-Kopyalari\{0:D3}\{1}' -f $Number, $Candidate.FileName))
        $Report.Add('')
    }
    if ($script:Candidates.Count -ge $script:CandidateLimit) { $Report.Add('100 aday sınırına ulaşıldı; ek dosyalar kopyalanmadı.') }
    foreach ($Note in $script:Notes) { $Report.Add($Note) }
    $Report.Add('')
    $Report.Add('Kaynaklar:')
    $Report.Add('https://github.com/IshiakiZ/mcd2-save-editor/issues/4')
    $Report.Add('https://github.com/IshiakiZ/mcd2-save-editor/pull/1')
    $Report.Add('https://store.steampowered.com/app/1912410/Minecraft_Dungeons_II/')

    $Editable = @($script:Candidates | Where-Object { $_.Editable })
    $Selected = $null
    if ($Editable.Count -eq 1) {
        $Selected = $Editable[0]
    } elseif ($Editable.Count -gt 1) {
        Write-Host ''
        Write-Host 'Birden fazla çevrimdışı karakter bulundu:' -ForegroundColor Cyan
        for ($Index = 0; $Index -lt $Editable.Count; $Index++) {
            Write-Host ('{0}) {1} - {2}' -f ($Index + 1), $Editable[$Index].HeroName, $Editable[$Index].FileName)
        }
        if (-not $NonInteractive) {
            $Choice = Read-Host 'Düzenleyicide açılacak karakterin numarası (boş bırakırsanız hepsi kopyalanır)'
            $ChoiceNumber = 0
            if ([int]::TryParse($Choice, [ref]$ChoiceNumber) -and $ChoiceNumber -ge 1 -and $ChoiceNumber -le $Editable.Count) {
                $Selected = $Editable[$ChoiceNumber - 1]
            }
        }
    }

    $EditorPath = ''
    $TemplatePath = Join-Path $PSScriptRoot 'index.html'
    if ($null -ne $Selected -and (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        $Template = [System.IO.File]::ReadAllText($TemplatePath)
        $Marker = '<!--NATIVE_SAVE_BOOTSTRAP-->'
        if ($Template.Contains($Marker)) {
            $SaveBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Selected.CopyPath))
            $NameBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Selected.FileName))
            $Bootstrap = '<script>window.DUNGEONS_SAVE_B64="' + $SaveBase64 + '";window.DUNGEONS_SAVE_NAME_B64="' + $NameBase64 + '";</script>'
            $EditorPath = Join-Path $Output 'Duzenleyici.html'
            [System.IO.File]::WriteAllText($EditorPath, $Template.Replace($Marker, $Bootstrap), $script:Utf8)
            $Report.Add(('Duzenleyici.html içine açılan karakter: {0}' -f $Selected.FileName))
            $Report.Add('Düzenleyici kopyası yereldir. İndirilen düzenlenmiş .sav dosyası oyunda kontrol edilmeden uyumluluk garanti edilemez.')
        } else {
            $Report.Add('index.html içinde yerel kayıt başlatma alanı bulunamadı; ham kayıt kopyalarını düzenleyicide açabilirsiniz.')
        }
    }
    if ($script:Candidates.Count -eq 0) {
        $Report.Add('Kayıt bulunamadı. Oyunda çevrimdışı karakter oluşturup ana menüye kaydederek çıkın, oyunu kapatın ve tekrar çalıştırın.')
        $Report.Add('Çevrimiçi karakterin asıl kaydı oyun sunucusundadır; yerel envanter düzenlenemez.')
    }
    $ReportPath = Join-Path $Output 'Arama-Raporu.txt'
    [System.IO.File]::WriteAllLines($ReportPath, $Report.ToArray(), $script:Utf8)
    $ZipPath = $Output + '.zip'
    Compress-Archive -LiteralPath $Output -DestinationPath $ZipPath -CompressionLevel Optimal -Force

    Write-Host ''
    Write-Host ('{0} kayıt adayı kopyalandı; {1} çevrimdışı JSON tanındı.' -f $script:Candidates.Count, $Editable.Count) -ForegroundColor Green
    Write-Host ('Kopya ve rapor: {0}' -f $Output)
    Write-Host ('ZIP: {0}' -f $ZipPath)
    if (-not $NoExplorer) {
        Start-Process explorer.exe -ArgumentList ('"' + $Output + '"')
        if (-not [string]::IsNullOrWhiteSpace($EditorPath)) {
            Start-Process -FilePath $EditorPath
        } elseif ($script:Candidates.Count -eq 0) {
            Start-Process notepad.exe -ArgumentList ('"' + $ReportPath + '"')
        }
    }
    if ($script:Candidates.Count -eq 0) {
        Write-Host 'Oyunda çevrimdışı bir karakter oluşturun; ana menüye kaydedip çıkın ve tekrar çalıştırın.' -ForegroundColor Yellow
    } elseif ([string]::IsNullOrWhiteSpace($EditorPath)) {
        Write-Host 'Kayit-Kopyalari klasöründeki .sav dosyasını index.html içinde gerçek kayıt açarak seçebilirsiniz.'
    } else {
        Write-Host 'Karakterin kopyası Duzenleyici.html içinde açıldı. Değiştirilen kaydı ayrı .sav olarak indirebilirsiniz.'
    }
} catch {
    Write-Host ''
    Write-Host ('İşlem tamamlanamadı: {0}' -f $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Orijinal oyun kayıtlarına yazma yapılmadı. Oyunu kapatıp yeniden deneyin.'
    exit 1
}
