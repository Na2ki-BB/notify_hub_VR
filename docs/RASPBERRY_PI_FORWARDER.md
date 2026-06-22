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
  "retry_initial_interval_ms": 1000,
  "retry_max_interval_ms": 300000,
  "retry_max_elapsed_ms": 1800000
}
```

主な項目:

- `input_path`: 既存Goシステムがatomicに上書きするJSONファイル。
- `notify_url`: Windows側Notify Hub VRの `/notify` URL。
- `state_path`: 最後に通知済みのイベントキーを保存するファイル。
- `debounce_ms`: ファイル更新イベント後、読み込む前に待つ時間。atomic rename直後の揺れを吸収します。
- `retry_max_elapsed_ms`: 送信失敗時に諦めるまでの最大時間。初期値は30分です。

## 実行

開発中はrepo直下で実行します。

```bash
go run ./cmd/notify-forwarder --config cmd/notify-forwarder/config.json
```

Raspberry Piへ配置する場合はbuildできます。

```bash
go build -o bin/notify-forwarder ./cmd/notify-forwarder
./bin/notify-forwarder --config cmd/notify-forwarder/config.json
```

## 挙動

- `fsnotify` で `input_path` の親ディレクトリを監視します。
- 対象ファイルのcreate/write/rename/chmodを検知したらJSONを読みます。
- 同じイベントキーは再通知しません。
- 送信失敗時は指数バックオフでリトライします。
- リトライ中に新しいファイル更新が来た場合、古い通知をキャンセルして最新を優先します。
- JSONファイル本体は削除、移動、書き換えしません。

## 注意

単一ファイル上書き方式では、短時間に複数回更新されてforwarderが読む前に次の内容で上書きされた場合、途中の内容は通知できません。このプロジェクトでは最新通知を優先するため、この挙動で問題ない前提です。全イベントを必ず通知したい場合は、イベントごとに別ファイルを作るか、既存Goシステムからforwarderへ直接POSTする方式に変えてください。
