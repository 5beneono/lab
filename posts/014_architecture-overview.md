---
title: "ソフトウェアアーキテクチャ概観"
slug: sofutoueaaakitekucha-gaikan
date: 2026-03-01
order: 14
tags: []
---


## 目的

007-013で議論してきた要素を1枚の設計図にまとめる。ハードウェア（配線メモ参照）が動いたとき、ソフト側で何を実装すればいいか一望できる状態にする。

## システム構成

```
┌─────────────────────────────────────────────────┐
│                  Raspberry Pi                    │
│                                                  │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐    │
│  │ Sensors  │──▶│  Brain   │──▶│ Actuators│    │
│  │          │   │          │   │          │    │
│  │ HC-SR04  │   │ Memory   │   │ TB6612   │    │
│  │(距離×2-3)│   │ Novelty  │   │ Motor L  │    │
│  │          │   │ If-Then  │   │ Motor R  │    │
│  │          │   │ Conflict │   │          │    │
│  │          │   │ Decay    │   │ OLED     │    │
│  └──────────┘   │ Logger   │   │(Phase 2) │    │
│                  └──────────┘   └──────────┘    │
│                       │                          │
│                  ┌────▼─────┐                    │
│                  │ Log File │                    │
│                  │(SD card) │                    │
│                  └──────────┘                    │
└─────────────────────────────────────────────────┘
```

## Brainのモジュール構成

### 1. Perception — 知覚層
- センサー値の読み取り（距離、周期的にポーリング）
- 生値 → 正規化（0.0-1.0）
- 変化量の計算（前回との差分＝「何か動いた」検知）

### 2. Memory — 記憶層
- `SpatialMemory[]`: 位置＋センサー値＋強度＋タイムスタンプ
- 毎ステップ `strength *= DECAY_RATE`（指数減衰）
- strength < THRESHOLD で削除（メモリ解放）
- 容量上限: 50-100エントリ（Piのメモリ制約）
- 位置推定: オドメトリ（モーターのPWM値×時間から概算。精度は低いが十分）

### 3. Novelty — 新しさ計算
- `novelty(direction)` = 各方向のセンサー予測値と記憶の最小距離
- 全方向（前、左、右、後）のnoveltyスコアを算出
- noveltyが高い方向 → 引力（pull）

### 4. If-Then Rules — 偏りルール（3-5個）

```python
rules = [
    # Rule 1: 壁際の警戒
    {"if": dist_min < 0.15, "then": "safety_pull += 0.8 * backward"},
    
    # Rule 2: 開けた場所の好奇心
    {"if": dist_min > 0.5, "then": "novelty_pull *= 1.3"},
    
    # Rule 3: 急変への驚き（凍結）
    {"if": delta_dist > 0.3, "then": "freeze(0.5s)"},
    
    # Rule 4: 長時間停滞への退屈
    {"if": same_position_for > 10s, "then": "random_direction_pull += 0.5"},
    
    # Rule 5: 再訪の親近感（記憶にある場所への安心）
    {"if": memory_match > 0.8 AND strength > 0.5, "then": "safety_pull -= 0.2"},
]
```

ルールは擬似コード。実際にはif-elseの連鎖。重要なのは**ルール同士が独立に発火し、pullベクトルが加算される**こと。

### 5. Conflict Resolution — 葛藤解決

全ルールのpullベクトルを合算：
```
total_pull = novelty_pull + safety_pull + random_pull + ...
```

合算結果から行動を決定：
- `|total_pull| > MOVE_THRESHOLD` → 移動（方向と速度はベクトルから）
- `|total_pull| < FREEZE_THRESHOLD` → 凍結（pullが拮抗）
- 凍結が `MAX_FREEZE` を超えたら → 最大pullの方向へ突発的転換

**葛藤の検出：**
```
conflict_level = 1.0 - (|total_pull| / sum(|individual_pulls|))
```
- conflict_level ≈ 0 → 全pullが同じ方向。迷いなし
- conflict_level ≈ 1 → pullが完全に相殺。最大の迷い

conflict_levelが高いとき → 振動（モーター出力に微細な正弦波を加算）

### 6. Motor Output — モーター出力

差動駆動（左右独立モーター）：
- 直進: L = R = speed
- 左旋回: L = -speed, R = speed
- 右旋回: L = speed, R = -speed
- 振動: L, R に sin(t * freq) * amplitude を加算

PWM制御はTB6612FNG経由。GPIO12(PWMA), GPIO13(PWMB)。

### 7. Logger — ログ記録

毎ステップ記録：
```
timestamp | state | pulls[] | conflict_level | action | memory_refs[]
```

Phase 2ではこのログをOLEDにリアルタイム表示。

### 8. Phase Manager — フェーズ制御

- Phase 1: OLED OFF。Logger記録のみ
- Phase転換条件: 3回接近 OR 2分経過（009のハイブリッドトリガー）
- Phase 2: OLED ON。Loggerの出力をOLEDにストリーム
- 接近カウントはPerceptionが距離閾値で判定

## メインループ

```python
while True:
    # 1. 知覚
    sensors = read_sensors()
    position = update_odometry()
    
    # 2. 記憶更新
    memory.decay_all()
    memory.store(position, sensors)
    
    # 3. 新しさ計算
    novelty_scores = compute_novelty(sensors, memory)
    
    # 4. ルール評価（全ルール独立に発火）
    pulls = evaluate_rules(sensors, memory, novelty_scores)
    
    # 5. 葛藤解決
    action, conflict = resolve_conflict(pulls)
    
    # 6. 行動実行
    execute(action)
    
    # 7. ログ
    log(timestamp, state, pulls, conflict, action)
    
    # 8. フェーズ確認
    phase_manager.check_transition(sensors)
    
    sleep(TICK_INTERVAL)  # 50-100ms
```

## ハードウェアとの対応

配線メモ（`配線メモ_Devastator_TB6612__0228.md`）との接続：
- GPIO17(AIN1), GPIO27(AIN2), GPIO12(PWMA) → 左モーター（A系統が死んでいるので新TB6612待ち）
- GPIO22(BIN1), GPIO23(BIN2), GPIO13(PWMB) → 右モーター（B系統は正常）
- HC-SR04: GPIO未割当（前方、左、右に配置予定）
- OLED: I2C (SDA=GPIO2, SCL=GPIO3) が標準

## 実装言語の選択

**Python (RPi.GPIO or gpiozero)**
- 利点: 開発速度、ねおのの馴染み、ライブラリ充実
- 欠点: ループ速度（50ms tick は余裕だが、10ms以下は厳しい）
- 判定: **これでいい**。ローバーはリアルタイム制御不要

**MicroPython / C++**
- 不要。Piの処理能力で十分

## シミュレータの可能性

実機前に動きを検証するため、2Dシミュレータを作る価値はある：
- Python + pygame で平面上のローバーをシミュレート
- 壁、障害物、「来場者」（マウスカーソル）を配置
- 記憶・novelty・葛藤の各モジュールを同じコードで動かす
- パラメータ（DECAY_RATE、ルール閾値、FREEZE_THRESHOLD）を調整
- **動きの質**を目で見て確認できる

これは新TB6612FNG待ちの間にできる作業。

## 開いた問い

1. **センサー配置と個数** — 前方1個では方向判定が弱い。左右にも必要か。コスト・配線の複雑さとのトレードオフ
2. **オドメトリの精度** — モーター回転数を直接読めない（エンコーダなし）。PWM×時間の概算で「位置」と呼べるか
3. **TICK_INTERVAL** — 50msか100msか。振動の見え方に影響
4. **Phase転換の不可逆性** — 一度Phase 2に入ったら戻らない？リセット（新しい来場者が来たら）の設計

## この思考で見えた構造

007-013の議論が、実装可能なモジュール構成に収束した。

核心は**Conflict Resolution**モジュール。ここに013で特定した4つの運動学的シグネチャ（振動・旋回・凍結・突発的転換）が全て集約される。他のモジュールはこれに入力を与えるか、出力を受け取るだけ。

「葛藤が人格を生む」というのは比喩ではなく、文字通りアーキテクチャの中心にある。
