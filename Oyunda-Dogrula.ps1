#Requires -Version 5.1
param(
    [string]$ContextPath = '',
    [string]$LocalDataRoot = $env:LOCALAPPDATA,
    [switch]$NoUI,
    [switch]$SkipLaunch,
    [ValidateSet('yes', 'no', 'unknown')][string]$CharacterOpened = 'unknown'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Dogrulama-Ortak.ps1')
$Worker = $null
$StopPath = ''
$Utf8 = New-Object System.Text.UTF8Encoding($true)

function Test-DFNewGameWrite([string]$BeforeHash, [string]$BeforeUpdated, [string]$AfterHash, [string]$AfterUpdated) {
    if ([string]::IsNullOrWhiteSpace($BeforeHash) -or [string]::IsNullOrWhiteSpace($AfterHash) -or $BeforeHash -ceq $AfterHash) { return $false }
    $BeforeTime = [decimal]0
    $AfterTime = [decimal]0
    $Styles = [Globalization.NumberStyles]::Float
    $Culture = [Globalization.CultureInfo]::InvariantCulture
    $BeforeValid = [decimal]::TryParse($BeforeUpdated, $Styles, $Culture, [ref]$BeforeTime)
    $AfterValid = [decimal]::TryParse($AfterUpdated, $Styles, $Culture, [ref]$AfterTime)
    return $BeforeValid -and $AfterValid -and $AfterTime -gt $BeforeTime
}

try {
    Write-Host 'Minecraft Dungeons II - Oyunda kayıt doğrulama' -ForegroundColor Cyan
    Write-Host 'Oyuna yüklenmeden yalnızca dosya yazılmış olması başarı sayılmaz.'
    $VerificationRoot = Join-Path $LocalDataRoot 'DungeonsForge\Verification'
    if ([string]::IsNullOrWhiteSpace($ContextPath)) {
        $Contexts = @(Get-ChildItem -LiteralPath $VerificationRoot -Filter 'context-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
        if ($Contexts.Count -eq 0) { throw 'Doğrulama bilgisi bulunamadı. Önce Kaydi-Uygula.cmd ile düzenlenmiş dosyayı uygulayın.' }
        $ContextPath = $Contexts[0].FullName
        if ($Contexts.Count -gt 1 -and -not $NoUI) {
            Write-Host 'En son uygulanan karakterin kaydı doğrulanacak:'
            Write-Host $ContextPath
        }
    }
    $Context = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($ContextPath))
    if ($Context.Schema -cne 'dungeons-forge-game-verification-v1' -or $Context.AppId -ne 1912410) { throw 'Geçerli Minecraft Dungeons II doğrulama bağlamı gerekli.' }
    $SourcePath = [string]$Context.SourcePath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw 'Uygulanan karakter dosyası bulunamadı.' }
    $File = Get-Item -LiteralPath $SourcePath
    if (($File.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $File.Length -gt 20MB) { throw 'Normal, en fazla 20 MB karakter dosyası gerekli.' }
    $BeforeLaunch = Read-DFRecord ([IO.File]::ReadAllBytes($SourcePath))
    if ($BeforeLaunch.Leaves['/CharacterSaveV1/MetaData/CharacterId'].Canonical -cne $Context.CharacterId) { throw 'Karakter kimliği doğrulama bağlamıyla uyuşmuyor.' }
    if ((Get-DFGameProcesses).Count -gt 0) { throw 'Önce Minecraft Dungeons II oyununu tamamen kapatın; sonra bu yardımcıyla açın.' }

    $GameObserved = $false
    if (-not $SkipLaunch) {
        if ($NoUI) { throw 'Oyunu başlatan doğrulama akışı kullanıcı formunu gerektirir; -NoUI yalnızca -SkipLaunch test kipinde kullanılabilir.' }
        Add-Type -AssemblyName System.Windows.Forms
        $StopPath = Join-Path ([IO.Path]::GetDirectoryName($ContextPath)) ([guid]::NewGuid().ToString('N') + '.stop')
        $Worker = Start-Job -ArgumentList $StopPath, (Join-Path $PSScriptRoot 'Dogrulama-Ortak.ps1') -ScriptBlock {
            param($StopFile, $CommonPath)
            . $CommonPath
            $Observed = $false
            $Deadline = [DateTime]::UtcNow.AddHours(2)
            while (-not (Test-Path -LiteralPath $StopFile) -and [DateTime]::UtcNow -lt $Deadline) {
                $Running = @(Get-DFGameProcesses)
                if ($Running.Count -gt 0) { $Observed = $true }
                Start-Sleep -Milliseconds 750
            }
            return $Observed
        }
        Start-Process 'steam://rungameid/1912410'
        $Text = "Steam'de Minecraft Dungeons II açılıyor.`r`n`r`n1. Bu çevrimdışı karakteri yükleyin: " + $Context.CharacterId + "`r`n2. Değiştirdiğiniz zümrüt, güç veya büyü değerini kontrol edin.`r`n3. Ana menüye kaydederek çıkın ve oyunu tamamen kapatın.`r`n`r`nBu karakter hata vermeden açıldı ve yukarıdaki işlemleri tamamladınız mı?`r`nEvet: dosyada saklanan değerler karşılaştırılır. Hayır/İptal: oyunda doğrulanmış sayılmaz."
        $Answer = [Windows.Forms.MessageBox]::Show($Text, 'Karakteri oyunda açın ve kaydedin', [Windows.Forms.MessageBoxButtons]::YesNoCancel, [Windows.Forms.MessageBoxIcon]::Question)
        $CharacterOpened = 'unknown'
        if ($Answer -eq [Windows.Forms.DialogResult]::Yes) { $CharacterOpened = 'yes' }
        elseif ($Answer -eq [Windows.Forms.DialogResult]::No) { $CharacterOpened = 'no' }
        [IO.File]::WriteAllText($StopPath, 'stop')
        $GameObserved = [bool](Receive-Job -Job $Worker -Wait)
        Remove-Job -Job $Worker -Force
        $Worker = $null
        Remove-Item -LiteralPath $StopPath -ErrorAction SilentlyContinue
        $StopPath = ''
    }
    if ((Get-DFGameProcesses).Count -gt 0) { throw 'Oyun hâlâ açık. Ana menüye kaydedip tamamen kapatın, sonra doğrulamayı yeniden çalıştırın.' }
    $Current = Read-DFRecord ([IO.File]::ReadAllBytes($SourcePath))
    if ($Current.Leaves['/CharacterSaveV1/MetaData/CharacterId'].Canonical -cne $Context.CharacterId) { throw 'Oyun sonrası karakter kimliği değişmiş; bu dosya karşılaştırılamaz.' }
    foreach ($Name in @('SoftVersion', 'InternalVersion')) {
        $Key = '/SerializeMeta/' + $Name
        if (-not $Current.Leaves.ContainsKey($Key) -or $Current.Leaves[$Key].Canonical -cne (Convert-DFNumber ([string]$Context.Versions.$Name))) { throw 'Oyun sonrası kayıt biçimi sürümü değişmiş; yeniden düzenleyip doğrulayın.' }
    }
    $Reasons = New-Object 'System.Collections.Generic.List[string]'
    $Rows = New-Object 'System.Collections.Generic.List[object]'
    $Simulation = $SkipLaunch -or $NoUI
    $UpdatedKey = '/CharacterSaveV1/MetaData/GameDataUpdated'
    $CurrentUpdated = $null
    $BeforeLaunchUpdated = $null
    if ($Current.Leaves.ContainsKey($UpdatedKey)) { $CurrentUpdated = $Current.Leaves[$UpdatedKey].Raw }
    if ($BeforeLaunch.Leaves.ContainsKey($UpdatedKey)) { $BeforeLaunchUpdated = $BeforeLaunch.Leaves[$UpdatedKey].Raw }
    $AppliedAdvanced = Test-DFNewGameWrite $Context.AppliedHash $Context.AppliedGameDataUpdated $Current.Hash $CurrentUpdated
    $FreshAdvanced = Test-DFNewGameWrite $BeforeLaunch.Hash $BeforeLaunchUpdated $Current.Hash $CurrentUpdated
    $EngineAdvanced = $AppliedAdvanced
    if (-not $Simulation) { $EngineAdvanced = $AppliedAdvanced -and $FreshAdvanced }
    if (-not $EngineAdvanced) { $Reasons.Add('Bu doğrulama çalışmasında oyun tarafından yeni kayıt yazıldığı kanıtlanamadı: GameDataUpdated ilerlemeli ve dosya hash değeri değişmeli.') }
    if ($CharacterOpened -ne 'yes') { $Reasons.Add('Kullanıcı karakterin sorunsuz açıldığını onaylamadı.') }
    if (-not $GameObserved) { $Reasons.Add('Bu yardımcı çalışırken oyun süreci gözlemlenmedi.') }
    if ($Simulation) { $Reasons.Add('Test kipi: gerçek oyun doğrulaması sonucu verilmez.') }
    $Attributes = Get-DFAttributes $Current
    foreach ($Expected in @($Context.ExpectedAttributes)) {
        if ($null -eq $Expected) { continue }
        $Observed = $null
        if ($Attributes.ContainsKey([string]$Expected.Name)) { $Observed = $Attributes[[string]$Expected.Name] }
        $Match = $null -ne $Observed -and $Observed.Kind -ceq $Expected.Kind -and $Observed.Canonical -ceq $Expected.Canonical
        $Rows.Add([PSCustomObject]@{ Field = ('Attribute: ' + $Expected.Name); Expected = $Expected.Raw; Observed = $(if ($null -ne $Observed) { $Observed.Raw } else { $null }); Matches = $Match; Coverage = 'NamedAttribute' })
    }
    $InventorySame = (Get-DFInventorySignature $Current) -ceq $Context.InventorySignature
    foreach ($Expected in @($Context.ExpectedPaths)) {
        if ($null -eq $Expected) { continue }
        $Key = [string]$Expected.Key
        $Observed = $null
        $Comparable = $true
        if ($Key -like '/CharacterSaveV1/Inventory/Entries/*' -and -not $InventorySame) { $Comparable = $false }
        if ($Current.Leaves.ContainsKey($Key)) { $Observed = $Current.Leaves[$Key] }
        $Match = $Comparable -and $null -ne $Observed -and $Observed.Kind -ceq $Expected.Kind -and $Observed.Canonical -ceq $Expected.Canonical
        $Rows.Add([PSCustomObject]@{ Field = $Key; Expected = $Expected.Raw; Observed = $(if ($null -ne $Observed) { $Observed.Raw } else { $null }); Matches = $Match; Coverage = $(if ($Comparable) { 'ExistingPrimitivePath' } else { 'InventoryOrderOrIdentityChanged' }) })
    }
    foreach ($Reason in @($Context.UnverifiedChanges)) { if ($null -ne $Reason) { $Reasons.Add([string]$Reason) } }
    $Matched = @($Rows | Where-Object { $_.Matches }).Count
    $Unmatched = @($Rows | Where-Object { -not $_.Matches }).Count
    if ($Rows.Count -eq 0) { $Reasons.Add('Karşılaştırılacak mevcut sayısal veya metin alanı değişikliği yok.') }
    if ($Unmatched -gt 0) { $Reasons.Add('Bazı beklenen alanlar eşleşmedi veya envanter sırası/kimliği değişti; ayrıntılar raporda.') }
    $EvidenceComplete = $EngineAdvanced -and $CharacterOpened -eq 'yes' -and $GameObserved -and -not $Simulation
    $Status = 'not_verified'
    if ($EvidenceComplete -and $Matched -gt 0) {
        $Status = 'partially_verified'
        if ($Reasons.Count -eq 0) { $Status = 'verified_changed_fields' }
    }
    $Report = [PSCustomObject]@{
        Schema = 'dungeons-forge-game-verification-result-v1'
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        AppId = 1912410
        CharacterId = $Context.CharacterId
        SourcePath = $SourcePath
        ContextPath = $ContextPath
        AppliedSteamBuilds = @($Context.InstalledSteamBuilds)
        ReadBackSteamBuilds = @(Get-DFInstalledBuilds)
        Status = $Status
        Simulation = [bool]$Simulation
        CharacterOpenedAnswer = $CharacterOpened
        GameProcessObserved = $GameObserved
        EngineSaveAdvanced = [bool]$EngineAdvanced
        AppliedSaveAdvanced = [bool]$AppliedAdvanced
        FreshSaveAdvanced = [bool]$FreshAdvanced
        AppliedHash = $Context.AppliedHash
        BeforeLaunchHash = $BeforeLaunch.Hash
        ReadBackHash = $Current.Hash
        AppliedGameDataUpdated = $Context.AppliedGameDataUpdated
        BeforeLaunchGameDataUpdated = $BeforeLaunchUpdated
        ReadBackGameDataUpdated = $(if ($Current.Leaves.ContainsKey($UpdatedKey)) { $Current.Leaves[$UpdatedKey].Raw } else { $null })
        MatchedFields = $Matched
        UnconfirmedFields = $Unmatched
        Rows = $Rows.ToArray()
        Reasons = $Reasons.ToArray()
        Limit = 'Sonuç yalnızca rapordaki kaydedilen alanları ve kullanıcının karakter açılışı yanıtını kapsar. Görsel model, tüm eşya kombinasyonları ve gerçek savaş hasarı otomatik doğrulanmaz.'
    }
    $ReportPath = Join-Path ([IO.Path]::GetDirectoryName($ContextPath)) ('result-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json')
    [IO.File]::WriteAllText($ReportPath, (ConvertTo-Json -InputObject $Report -Depth 20), $Utf8)
    $Message = 'Oyunda doğrulanamadı.'
    if ($Status -eq 'verified_changed_fields') { $Message = ('Karakter açılışı ve değiştirilen {0} kayıt alanının korunması doğrulandı.' -f $Matched) }
    elseif ($Status -eq 'partially_verified') { $Message = ('Karakter açılışı ve {0} kayıt alanı doğrulandı; kalan alanlar doğrulanamadı.' -f $Matched) }
    $Message += "`r`nEşleşen alan: " + $Matched + "`r`nDoğrulanamayan alan: " + $Unmatched + "`r`nRapor: " + $ReportPath
    Write-Host $Message
    if (-not $NoUI) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($Message, 'Minecraft Dungeons II doğrulama sonucu', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)
    }
} catch {
    $Message = 'Oyunda doğrulanamadı: ' + $_.Exception.Message
    Write-Host $Message -ForegroundColor Yellow
    if (-not $NoUI) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show($Message, 'Doğrulama tamamlanamadı', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning)
        } catch { }
    }
    exit 1
} finally {
    if ($null -ne $Worker) { Stop-Job -Job $Worker -ErrorAction SilentlyContinue; Remove-Job -Job $Worker -Force -ErrorAction SilentlyContinue }
    if (-not [string]::IsNullOrWhiteSpace($StopPath)) { Remove-Item -LiteralPath $StopPath -ErrorAction SilentlyContinue }
}
