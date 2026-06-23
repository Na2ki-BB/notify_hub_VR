# Raspberry Pi Forwarder

Raspberry Pi上の既存Goシステムが更新するJSONファイルを監視し、Windows側のNotify Hub VRへHTTP POSTする常駐forwarderです。

## 必要なもの

- Go 1.23以上。`fsnotify v1.10.1` がGo 1.23以上を要求します。
- Windows側でNotify Hub VRが起動し、Raspberry Piから `notify_url` に接続できること。

## 入力JSON

特定ファイル1個を監視します。ファイルは他システムも参照するため、forwarderは移動も削除もしません。

```json
{
  "updated_at": "2024-01-01T12:34:56",
  "lines": ["行1", "行2", "行3", "行4"]
}
```

`updated_at` は秒単位でも問題ありません。重複判定にはファイルのmtime、size、内容hashを使います。

## 表示ルール

VR通知には次のように変換します。

```text
title = lines[0] + " / " + lines[1] + " / " + lines[3]
body  = lines[2]
```

`lines[2]` が空の場合だけ、空でない行をまとめて本文にします。

## 設定

実運用の `config.json` はGitに入れません。exampleをコピーして編集してください。

```bash
cp cmd/notify-forwarder/config.example.json cmd/notify-forwarder/config.json
```

設定例:

```json
{
  "input_path": "/home/pi/notify-source/current.json",
  "notify_url": "http://WINDOWS_PC_IP:17890/notify",
  "state_path": "/var/lib/notify-hub-vr-forwarder/state.json",
  "default_level": "info",
  "default_duration_ms": 5000,
  "debounce_ms": 120,
  "request_timeout_ms": 5000,
  "max_notification_age_ms": 30000,
  "retry_initial_interval_ms": 1000,
  "retry_max_interval_ms": 300000,
  "retry_unavailable_initial_interval_ms": 5000,
  "retry_unavailable_max_interval_ms": 30000,
  "retry_max_elapsed_ms": 1800000
}
```

主な項目:

- `input_path`: 既存Goシステムがatomicに上書きするJSONファイル。
- `notify_url`: Windows側Notify Hub VRの `/notify` URL。
- `state_path`: 最後に通知済みのイベントキーを保存するファイル。
- `debounce_ms`: ファイル更新イベント後、読み込む前に待つ時間。atomic rename直後の揺れを吸収します。
- `max_notification_age_ms`: ファイル更新時刻からこの時間を過ぎた通知は送らずに捨てます。初期値は30秒です。`0` 以下にすると無効化します。
- `retry_max_interval_ms`: ネットワークtimeoutなど通常失敗時の最大retry間隔。初期値は5分です。
- `retry_unavailable_initial_interval_ms`: Windows側が503を返したときの初回retry間隔。HMD未接続など一時的なOpenVR準備待ちを想定しています。
- `retry_unavailable_max_interval_ms`: Windows側が503を返したときの最大retry間隔。初期値は30秒です。
- `retry_max_elapsed_ms`: 送信失敗時に諦めるまでの最大時間。初期値は30分です。

## 実行

開発中はrepo直下で実行します。

```bash
go run ./cmd/notify-forwarder --config cmd/notify-forwarder/config.json
```

手動でbuildして実行する場合:

```bash
go build -o bin/notify-forwarder ./cmd/notify-forwarder
./bin/notify-forwarder --config cmd/notify-forwarder/config.json
```

## systemdで常駐化

Raspberry Piで常駐させる場合は、インストールスクリプトを使います。

```bash
./scripts/install-forwarder-systemd.sh
```

このスクリプトは次の場所へ配置します。

- binary: `/usr/local/bin/notify-hub-vr-forwarder`
- config: `/etc/notify-hub-vr-forwarder/config.json`
- state: `/var/lib/notify-hub-vr-forwarder/state.json`
- service: `/etc/systemd/system/notify-hub-vr-forwarder.service`

`cmd/notify-forwarder/config.json` が存在する場合、初回だけその内容を `/etc/notify-hub-vr-forwarder/config.json` にコピーします。すでに `/etc/notify-hub-vr-forwarder/config.json` が存在する場合は上書きしません。

初回はconfigを編集してください。

```bash
sudo nano /etc/notify-hub-vr-forwarder/config.json
```

最低限、次の3つを実環境に合わせます。`state_path` はserviceが書き込める `/var/lib/notify-hub-vr-forwarder/` 配下に置いてください。

```json
{
  "input_path": "/home/YOUR_USER/path/to/status-panel/hub/data/vrchat.json",
  "notify_url": "http://WINDOWS_PC_IP:17890/notify",
  "state_path": "/var/lib/notify-hub-vr-forwarder/state.json"
}
```

config編集後、起動してboot時にも自動起動するようにします。

```bash
sudo systemctl enable --now notify-hub-vr-forwarder
```

状態確認:

```bash
systemctl status notify-hub-vr-forwarder
```

ログ確認:

```bash
journalctl -u notify-hub-vr-forwarder -f
```

停止:

```bash
sudo systemctl stop notify-hub-vr-forwarder
```

再起動:

```bash
sudo systemctl restart notify-hub-vr-forwarder
```

forwarderを更新した場合は、repoを更新してからもう一度インストールスクリプトを実行し、serviceを再起動します。

```bash
git pull
./scripts/install-forwarder-systemd.sh
sudo systemctl restart notify-hub-vr-forwarder
```

## 挙動

- `fsnotify` で `input_path` の親ディレクトリを監視します。
- 対象ファイルのcreate/write/rename/chmodを検知したらJSONを読みます。
- 同じイベントキーは再通知しません。
- 送信失敗時は指数バックオフでリトライします。Windows側が503を返す場合は、HMD接続待ちとして短めの間隔でリトライします。
- ファイル更新から `max_notification_age_ms` を過ぎた通知は、古いリアルタイム通知として送らずに捨てます。
- リトライ中に新しいファイル更新が来た場合、古い通知をキャンセルして最新を優先します。
- JSONファイル本体は削除、移動、書き換えしません。

## 注意

単一ファイル上書き方式では、短時間に複数回更新されてforwarderが読む前に次の内容で上書きされた場合、途中の内容は通知できません。このプロジェクトでは最新通知を優先するため、この挙動で問題ない前提です。全イベントを必ず通知したい場合は、イベントごとに別ファイルを作るか、既存Goシステムからforwarderへ直接POSTする方式に変えてください。
