# Windows Setup

この手順は、Windows 11のゲーミングPCでNotify Hub VRを起動し、SteamVR/OpenVR probeまで確認するためのものです。

## 必要なもの

- Windows 11 PC
- Steam
- SteamVR
- .NET 8 SDK
- Git for Windows
- このリポジトリの最新コード

Visual Studioは不要です。PowerShellと.NET SDKだけで確認できます。

## 1. SteamVRを入れる

SteamからSteamVRをインストールします。

- https://store.steampowered.com/app/250820/SteamVR/

その後、普段通りに以下を確認します。

1. Quest 3SでVirtual Desktopを起動する。
2. Windows PC側でSteamVRを起動する。
3. VRChatをSteamVR経由で起動する。
4. HMD内でSteamVR dashboardが開けることを確認する。

この確認が通れば、今回のアプリが狙っている実行経路と合っています。

## 2. .NET 8 SDKを入れる

このプロジェクトは `net8.0` を対象にしています。入れるのはRuntimeではなくSDKです。SDKにはビルドと実行に必要なものが含まれます。

PowerShellで確認します。

```powershell
dotnet --info
```

`dotnet` が見つからない場合は、次のどちらかで入れます。

### wingetで入れる

```powershell
winget install --id Microsoft.DotNet.SDK.8 --source winget
```

### 公式インストーラで入れる

.NET 8 SDKのWindows x64インストーラを入れます。

- https://dotnet.microsoft.com/en-us/download/dotnet/8.0

インストール後、新しいPowerShellを開いて確認します。

```powershell
dotnet --info
dotnet --list-sdks
```

`8.0.x` のSDKが表示されればOKです。

## 3. Gitを入れる

未導入ならGit for Windowsを入れます。

- https://git-scm.com/downloads/win

確認:

```powershell
git --version
```

## 4. リポジトリを取得する

GitHubにpush済みなら、Windows PCでcloneします。

```powershell
cd $HOME
git clone <REPOSITORY_URL> notify_hub_VR
cd notify_hub_VR
```

すでにclone済みなら:

```powershell
cd $HOME\notify_hub_VR
git pull
```

`<REPOSITORY_URL>` は実際のGitHub URLに置き換えてください。

## 5. まず通常モードで動かす

SteamVRに触る前に、HTTPサーバだけ確認します。

```powershell
cd src\NotifyHubVr
copy config.example.json config.json
dotnet run -- config.json
```

別のPowerShellで:

```powershell
curl.exe -X POST http://localhost:17890/notify `
  -H "Content-Type: application/json" `
  -d "{\"body\":\"hello from Windows\"}"
```

起動中の画面に `VR Notification Preview` が出ればOKです。

状態確認:

```powershell
curl.exe http://localhost:17890/state
```

## 6. Raspberry Piから送る

Windows PCのLAN IPを確認します。

```powershell
ipconfig
```

Raspberry Piから:

```bash
curl -X POST http://WINDOWS_PC_IP:17890/notify \
  -H 'Content-Type: application/json' \
  -d '{"body":"hello from raspberry pi"}'
```

Windows Defender Firewallが出たら、Private networkで許可してください。

## 7. OpenVR probeを動かす

ここからはWindows + SteamVRが必要です。

SteamVRを起動してから、PowerShellで:

```powershell
cd src\NotifyHubVr
copy config.openvr.example.json config.openvr.json
dotnet run -- config.openvr.json
```

別のPowerShellで:

```powershell
$json = @{ body = "日本語テスト`n2行目"; title = "Notify Hub"; level = "info" } | ConvertTo-Json
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod -Uri "http://localhost:17890/notify" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes
```

PowerShellでは日本語JSONを文字列のまま `-Body` に渡すと `?` に置換されることがあります。日本語を送るときはUTF-8 bytesで渡してください。

期待する結果:

- `OpenVR renderer accepted notification.`
- `SteamVR runtime installed: True`
- `HMD present: True` または `False`
- HMD内の視界右上付近に、通知テキスト入りのoverlayが見える

`HMD present: False` でも、SteamVR runtime初期化まで通っていれば一部確認はできています。ただしoverlay表示確認はHMD接続中に行います。

## 8. よくあるエラー

### dotnetが見つからない

.NET 8 SDKが入っていないか、インストール後のPowerShellを開き直していません。

```powershell
dotnet --info
```

で確認してください。

### 17890が使用中

すでにNotify Hub VRが起動しているか、別アプリが同じポートを使っています。

```powershell
netstat -ano | findstr :17890
```

必要なら `config.json` の `port` を別番号に変えます。

### Raspberry Piから接続できない

確認点:

- Windows PCとRaspberry Piが同じLANにいる。
- `WINDOWS_PC_IP` が正しい。
- Windows Defender FirewallでPrivate networkを許可している。
- `config.json` の `bind_address` が `0.0.0.0` になっている。

### openvr_api.dll was not found

SteamVR/OpenVRのDLLが見つかっていません。まずSteamVRをインストールして起動してください。

それでも失敗する場合は、SteamVR内の `openvr_api.dll` をアプリ実行ディレクトリにコピーする必要があります。典型的な場所:

```text
C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\openvr_api.dll
```

コピー先:

```text
src\NotifyHubVr\bin\Debug\net8.0\
```

## References

- .NET 8 download: https://dotnet.microsoft.com/en-us/download/dotnet/8.0
- SteamVR: https://store.steampowered.com/app/250820/SteamVR/
- OpenVR SDK: https://github.com/ValveSoftware/openvr
