---
title: "BLE個体識別の技術調査 + エピソード記憶の容量設計"
slug: ble-kotaishikibetsu-no-gijutsu-chousa-episoodo-kioku-no-youryou-sekkei
date: 2026-03-02
order: 19
tags: []
---


## BLE個体識別: 選択肢と制約

### 案1: iPhoneをiBeacon送信機にする
- CoreLocationでiBeacon広告を出せる（Apple公式API）
- **致命的制約: バックグラウンドでは広告フォーマットが壊れる**
  - iOSはバックグラウンドに入ると独自フォーマットに切り替える
  - UUID/Major/Minorが正しく読めなくなる
  - アプリをフォアグラウンドに保つ必要がある → 非現実的
- 判定: **不採用**

### 案2: 専用BLEビーコン（小型デバイス）
- キーホルダー型iBeaconビーコン（1000-2000円/個）
- 電池で数ヶ月〜1年持つ
- 常に一定のUUID/Major/Minorを広告し続ける
- Pi側: bleak (Python) でスキャン → iBeacon広告をパース → 個体識別
- **利点:** 確実。バックグラウンド問題なし。Pi内蔵BTで受信可能
- **欠点:** 追加ハードウェアの購入が必要。身につけ忘れると検知できない
- 判定: **最も現実的。まず2個購入して実験**

### 案3: iPhoneのBLE広告をIRKで追跡
- iPhoneは常にBLE広告を出している（ランダムMACアドレス）
- IRK（Identity Resolving Key）を使えばランダムMACから端末を特定可能
- ESPresense（ESP32用）がこの手法を実装済み
- **問題:** IRKの取得にはペアリングが必要。Piでの実装は非自明
  - bleakにはIRK解決の組み込みサポートがない
  - bluezのD-Bus APIを叩く必要がある
  - ESP32 + ESPresenseに任せてPiはMQTTで結果を受ける手もある
- 判定: **技術的に面白いが複雑。Phase Cの後半で検討**

### 案4: Wi-Fi接続ベースの在室検知
- 同じLANにいるデバイスのMACアドレスで判定
- `arp -a` やDHCPリースで確認
- **問題:** iPhoneはMACランダム化する（iOS 14以降）。同じSSIDでも接続ごとに変わりうる
- 判定: **信頼性低い。補助手段にとどめる**

### 推奨構成
```
Phase C初期: 専用BLEビーコン × 2（ねおの用、むしはかせ用）
  ↓
Pi内蔵BT + bleak でスキャン（1-3秒間隔）
  ↓
iBeacon UUID/Major/Minor → 個体ID マッピング
  ↓
PerceptionモジュールにBLE検知結果を供給
```

### bleak実装メモ

Koen Vervloesemのibeaconスキャン例が参考になる:
```python
from bleak import BleakScanner
from construct import Array, Byte, Const, Int8sl, Int16ub, Struct

ibeacon_format = Struct(
    "type_length" / Const(b"\x02\x15"),
    "uuid" / Array(16, Byte),
    "major" / Int16ub,
    "minor" / Int16ub,
    "power" / Int8sl,
)

def detection_callback(device, advertisement_data):
    apple_data = advertisement_data.manufacturer_data.get(0x004C)  # Apple company ID
    if apple_data:
        try:
            ibeacon = ibeacon_format.parse(apple_data)
            # ibeacon.major, ibeacon.minor で個体識別
        except:
            pass

scanner = BleakScanner(detection_callback=detection_callback)
```

依存: `bleak`, `construct`
Pi 5内蔵BT: bluez経由で動くはず（要検証）

---

## エピソード記憶の容量設計

### Episode構造体のサイズ見積もり

018で定義したEpisode:
```python
Episode:
    timestamp: float          # 8 bytes
    duration: float           # 8 bytes
    trigger: str              # ~32 bytes (短い文字列)
    sensor_snapshots: []      # 可変。1秒1サンプル × 30秒 × 3センサー = 720 bytes
    position_trace: Vec2[]    # 可変。1秒1サンプル × 30秒 × 2 = 480 bytes
    novelty_peak: float       # 8 bytes
    who_present: str[]        # ~64 bytes (ID × 数人)
    valence: float            # 8 bytes
    strength: float           # 8 bytes
    recall_count: int         # 4 bytes
    context_vector: float[]   # 想起用。次元数次第。32次元 = 256 bytes
```

**1エピソード ≈ 1.5 KB（sensor_snapshotsとposition_traceの長さ次第）**

### Pi 5のRAM制約
- Pi 5: 4GB or 8GB RAM
- ぼくらのPi: 8GB
- OS + Python + 他プロセス ≈ 1-2 GB使用
- ローバープロセスに割り当て可能: 最低2GB
- **メモリはボトルネックにならない**

### 容量の上限は「意味」で決める
- 技術制約ではなく、想起の質で決める
- 1000エピソード × 1.5KB = 1.5MB — メモリ的には余裕
- しかし1000個から類似検索するコストは？
  - cosine similarity × 1000 = 1000回の内積計算
  - 32次元ベクトル × 1000 = 1ステップあたり ~0.1ms — 無視できる
- **上限500エピソード**を提案。十分な経験蓄積 + 検索コスト無視可能

### 記憶の圧縮・忘却
- strength < 0.01 のエピソードを削除（自然忘却）
- 上限到達時: 最もstrengthが低いエピソードを削除
- **圧縮は不要**。削除で十分。忘れることも個性

### 永続化
- JSONファイルに定期保存（30秒ごと or エピソード追加時）
- SDカードに書くので書き込み頻度に注意（寿命）
- `/tmp/` にRAMディスクで置いて、5分ごとにSDに同期する案もある

## context_vectorの生成方法

想起で使うcontext_vectorをどう作るか。LLM embeddingは重すぎる。

### 案: 手作り特徴ベクトル
```python
def make_context_vector(episode):
    return [
        episode.novelty_peak,           # 驚きの大きさ
        episode.valence,                # 正負
        episode.duration,               # 長さ
        len(episode.who_present),       # 人数
        hour_of_day(episode.timestamp), # 時間帯（正規化）
        mean(episode.sensor_snapshots), # 平均距離
        std(episode.sensor_snapshots),  # 距離の変動
        # ... 必要に応じて追加
    ]
```

8-16次元で十分。これならcosine similarityも軽い。
LLMの意味理解はないが、ローバーの「意味」はセンサー値と感情値の組み合わせで十分表現できる。

## 開いた問い

1. **BLEビーコンの具体的製品** — iBeacon対応で安価なもの。秋月？Amazon？
2. **RSSI（電波強度）の活用** — ビーコンのRSSIで大まかな距離推定ができる。「近くにいる」vs「部屋の隅にいる」
3. **context_vectorの次元数** — 少なすぎると想起が粗く、多すぎると過学習。8-16次元で始めて調整
4. **反芻時のcontext** — 人がいないときの想起で何をcontextにするか。時間帯？直前のセンサー値？ランダム？
