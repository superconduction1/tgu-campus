# 解压 Flutter SDK、生成 android/ 工程骨架、修好必改的三处配置，然后跑 flutter analyze。
# 只在本机验证用，跟应用源码无关。
#
# 用法（在 tgu_campus 目录）：
#   powershell -ExecutionPolicy Bypass -File tools\flutter-analyze.ps1
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$zip = Join-Path $root '.tools\flutter_sdk.zip'
$dest = Join-Path $root '.tools'
$flutter = Join-Path $dest 'flutter\bin\flutter.bat'

if (-not (Test-Path $flutter)) {
    if (-not (Test-Path $zip)) {
        throw "缺少 $zip ，先运行：node tools\fetch-flutter.mjs"
    }
    Write-Host '解压 Flutter SDK …'
    Expand-Archive -Path $zip -DestinationPath $dest -Force
}

# 这台机器的工作区之外基本不可写，把各种缓存都指到工作区里
$env:USERPROFILE = Join-Path $root '.home'
$env:HOME = $env:USERPROFILE
$env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
$env:PUB_CACHE = Join-Path $root '.pub-cache'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA, $env:PUB_CACHE | Out-Null

Push-Location $root
try {
    Write-Host '--- flutter --version（首次会下载 Dart SDK 与引擎产物，比较久）---'
    & $flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'flutter --version 失败' }

    if (-not (Test-Path (Join-Path $root 'android'))) {
        Write-Host '--- 生成 android/ 工程骨架 ---'
        & $flutter create . --platforms=android --org edu.tgu --project-name tgu_campus
    }

    # 三处必改：release 包的 INTERNET 权限、明文流量、minSdk 23
    $manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
    if (Test-Path $manifest) {
        $xml = [System.IO.File]::ReadAllText($manifest)
        if ($xml -notmatch 'android\.permission\.INTERNET') {
            $xml = $xml.Replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>' + "`r`n    " + '<application')
        }
        if ($xml -notmatch 'usesCleartextTraffic') {
            $xml = $xml.Replace('<application', '<application' + "`r`n        " + 'android:usesCleartextTraffic="true"')
        }
        [System.IO.File]::WriteAllText($manifest, $xml, (New-Object System.Text.UTF8Encoding $false))
        Write-Host 'AndroidManifest.xml 已补 INTERNET 与 usesCleartextTraffic'
    }

    foreach ($gradle in @('android\app\build.gradle', 'android\app\build.gradle.kts')) {
        $p = Join-Path $root $gradle
        if (-not (Test-Path $p)) { continue }
        $g = [System.IO.File]::ReadAllText($p)
        $g = [regex]::Replace($g, 'minSdk(Version)?\s*=?\s*\d+', 'minSdk 23')
        [System.IO.File]::WriteAllText($p, $g, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "$gradle 的 minSdk 已设为 23"
    }

    Write-Host '--- flutter pub get ---'
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    Write-Host '--- flutter analyze ---'
    & $flutter analyze
    Write-Host ("analyze 退出码 " + $LASTEXITCODE)
} finally {
    Pop-Location
}
