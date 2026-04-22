---
title: "アーキテクチャと赤ちゃんローバー設計要件の統合"
slug: aakitekucha-to-akachan-roobaa-sekkei-youken-no-tougou
date: 2026-03-02
order: 18
tags: []
---


## 目的

014の実装可能なアーキテクチャを、0301の「赤ちゃんローバー設計要件」と統合する。何を拡張し、何をそのまま使い、何が根本的に変わるかを整理する。

## 014から活かせるもの

### Conflict Resolution — そのまま使える
014の核心。pullベクトルの加算、conflict_levelの計算、4つの運動学的シグネチャ（振動・旋回・凍結・突発的転換）。これは新アーキテクチャでも変わらない。入力が増えるだけ。

### Motor Output — そのまま使える
差動駆動、PWM制御、振動の正弦波加算。物理層は変わらない。

### メインループの構造 — 骨格は維持
知覚→記憶→評価→葛藤解決→行動→ログの流れ。拡張するが壊さない。

### Logger — 拡張が必要だが土台は使える
記録項目に「誰がいたか」「表情状態」が加わる。

## 根本的に変わるもの

### 1. Memory — 空間記憶からエピソード記憶へ

**014の記憶:**
```python
SpatialMemory:
    position: Vec2
    sensor_values: float[]
    strength: float  # 指数減衰
    timestamp: float
```

**新しい記憶:**
```python
Episode:
    timestamp: float
    duration: float          # エピソードの長さ
    trigger: str             # 何がこのエピソードを開いたか（驚き、人の出現、等）
    sensor_snapshots: []     # 期間中のセンサー値
    position_trace: Vec2[]   # 移動軌跡
    novelty_peak: float      # 期間中の最大予測誤差
    who_present: str[]       # 誰がいたか（BLEビーコンID）
    valence: float           # 正負の符号つき（016参照）
    strength: float          # 減衰する。ただし想起で回復
    recall_count: int        # 想起された回数
```

**変更の核心:**
- 単位が「瞬間のセンサー値」から「時間幅を持つエピソード」に変わる
- `who_present` が入ることで「誰といたときの経験か」が記録される
- `recall_count` が入ることで「よく思い出す記憶はさらに思い出しやすくなる」ループが生まれる

**エピソードの区切り方:**
- 予測誤差が閾値を超えた瞬間 = エピソード境界
- 人の出現/消失 = エピソード境界
- 一定時間（30秒？）何も起きなかった = エピソード境界

### 2. Novelty → Prediction Engine（予測エンジン）

014のNoveltyモジュールは「記憶にない＝新しい」の単純な距離計算だった。新しい方向では、これを「世界モデルの予測と現実のズレ」に格上げする。

```python
class PredictionEngine:
    def predict(self, current_state, memory) -> Prediction:
        """今の状況から次に何が起きるか予測"""
        # 類似エピソードを検索
        similar = memory.recall(current_state, top_k=5)
        # 類似エピソードの「次に起きたこと」から予測を生成
        return weighted_average(similar.next_states)
    
    def error(self, prediction, reality) -> float:
        """予測誤差。これが驚き"""
        return distance(prediction, reality)
```

これは014のNoveltyの上位互換。空間的な「行ったことがない」だけでなく、「こうなるはずだったのに違った」が驚きになる。

### 3. If-Then Rules → 経験で変わるルール

014のルールは固定パラメータだった。新しい方向では、経験でパラメータが動く。

```python
rules = [
    # 壁際の警戒 — 初期値は一律。壁にぶつかった経験で強化
    {"if": dist_min < 0.15, 
     "then": "safety_pull += weight * backward",
     "weight": 0.8,  # ← この値が経験で変わる
     "weight_history": []},
    
    # 人がいるときの接近衝動
    {"if": person_detected,
     "then": "approach_pull += weight * toward_person",
     "weight": 0.5,  # 初期値。良い経験で上がり、悪い経験で下がる
     "per_person": {}},  # ← 人物ごとに異なる重み
]
```

**per_person** が鍵。「ねおのがいるときは接近衝動が強い」「むしはかせがいるときは警戒が弱い」——これが歪みの個体差。

### 4. 新規追加: Perception層の拡張

014はHC-SR04（距離センサー）のみ。新アーキテクチャでは:

```
Perception:
    距離センサー (HC-SR04 × 2-3) → 空間知覚
    BLEスキャナ → 人物検知・個体識別
    （将来）マイク → 音声イベント検知
```

BLEビーコンの検知は連続的ではなく離散的（スキャン間隔1-3秒）。これは問題ない。人の存在は「瞬間」ではなく「期間」で捉えるべきもの。

### 5. 新規追加: 想起モジュール（Recall）

014にはなかった。赤ちゃんローバーの核心。

```python
class RecallEngine:
    def recall(self, context, top_k=5) -> Episode[]:
        """文脈に応じて記憶を検索。ここに個性が宿る"""
        candidates = self.memory.all_episodes()
        
        scores = []
        for ep in candidates:
            score = 0.0
            # 基本: 文脈の類似度
            score += cosine_sim(context, ep.context_vector) * self.w_similarity
            # バイアス1: 強い記憶ほど思い出しやすい
            score += ep.strength * self.w_strength
            # バイアス2: よく想起される記憶ほどさらに想起されやすい
            score += log(ep.recall_count + 1) * self.w_frequency
            # バイアス3: valenceバイアス（楽観/悲観の個体差）
            score += ep.valence * self.w_valence_bias
            # バイアス4: 人物バイアス（今いる人に関連する記憶を優先）
            if context.who_present & ep.who_present:
                score += self.w_person_match
            
            scores.append(score)
        
        return top_k(candidates, scores)
    
    # w_* パラメータが想起の癖 = 人格の座
    # これらは初期値＋経験による微調整で個体差が生まれる
```

### 6. 新規追加: 反芻モード（Rumination）

人がいないとき、ローバーは動かず（または微動して）、過去の記憶を想起する。

```python
def rumination_tick(self):
    """人がいないとき、一定間隔で実行"""
    # ランダムまたは重みつきで記憶を1つ想起
    episode = self.recall.recall(self.current_context, top_k=1)[0]
    episode.recall_count += 1
    episode.strength = min(1.0, episode.strength + RECALL_BOOST)
    
    # 想起した記憶の文脈で表情を変える
    self.face.set_expression(episode.valence)
    
    # 想起結果をログに記録
    self.logger.log_rumination(episode)
```

反芻中の表情変化が外から見える唯一の手がかり。目を閉じて（´  `）、ときどき何かを思い出したように表情が変わる。

### 7. 新規追加: Face（OLED表情）

014ではPhase 2扱いだったOLEDが、新アーキテクチャでは最初から組み込み。

```python
class Face:
    expressions = {
        'neutral':   "´ω`",
        'relaxed':   "´ ω `",
        'surprised': "´○`",
        'sleepy':    "´_ `",
        'closed':    "´  `",   # 反芻中
    }
    
    def update(self, conflict_level, novelty, valence, is_ruminating):
        if is_ruminating:
            # 反芻中は目を閉じて、想起内容でときどき変化
            ...
        elif novelty > SURPRISE_THRESHOLD:
            self.set('surprised')
        elif conflict_level > 0.7:
            # 葛藤中は表情が不安定に揺れる
            ...
        else:
            # valenceに応じてneutral〜relaxedのグラデーション
            ...
```

## 新アーキテクチャ全体図

```
┌──────────────────────────────────────────────────────────┐
│                     Raspberry Pi                          │
│                                                          │
│  ┌─────────────┐                    ┌──────────────┐    │
│  │ Perception   │                    │  Actuators    │    │
│  │              │                    │               │    │
│  │ HC-SR04 ×2-3│──┐                │  TB6612       │    │
│  │ BLE Scanner  │  │                │  Motor L/R    │    │
│  └─────────────┘  │                │  OLED (Face)  │    │
│                     ▼                └──────▲───────┘    │
│              ┌──────────────┐              │             │
│              │    Brain      │              │             │
│              │               │              │             │
│              │  ┌──────────┐ │              │             │
│              │  │Prediction│ │   ┌─────────┴──────┐     │
│              │  │Engine    │ │   │Conflict         │     │
│              │  └────┬─────┘ │   │Resolution       │     │
│              │       │       │   │(014そのまま)      │     │
│              │       ▼       │   └─────────▲──────┘     │
│              │  ┌──────────┐ │             │             │
│              │  │Rules     │─┼─ pulls ────┘             │
│              │  │(per_person│ │                          │
│              │  │ weights) │ │                          │
│              │  └──────────┘ │                          │
│              │       │       │                          │
│              │       ▼       │                          │
│              │  ┌──────────┐ │                          │
│              │  │Episode   │ │                          │
│              │  │Memory    │ │                          │
│              │  └────┬─────┘ │                          │
│              │       │       │                          │
│              │       ▼       │                          │
│              │  ┌──────────┐ │                          │
│              │  │Recall    │ │ ← 人格の座               │
│              │  │Engine    │ │                          │
│              │  └────┬─────┘ │                          │
│              │       │       │                          │
│              │       ▼       │                          │
│              │  ┌──────────┐ │                          │
│              │  │Rumination│ │ ← 人がいないとき          │
│              │  └──────────┘ │                          │
│              │               │                          │
│              │  Logger       │                          │
│              └───────────────┘                          │
└──────────────────────────────────────────────────────────┘
```

## 距離センサーだけの世界 vs 人物検知が入った世界

| 側面 | 距離センサーのみ（014） | + 人物検知（新） |
|---|---|---|
| 驚きの源 | 空間の変化のみ | 空間 + 人の出現/消失 |
| 記憶の内容 | 「どこで何を見たか」 | 「誰がいたときに何が起きたか」 |
| 想起のトリガー | 似た空間に来たとき | 似た空間 + 同じ人がいるとき |
| ルールの変化 | 固定（個体差なし） | 人物ごとに異なる重み（個体差） |
| 歪みの可能性 | なし（自然環境に歪みはない） | あり（人物ごとの経験蓄積） |
| 反芻の内容 | 場所の記憶 | 人との記憶を含む |
| 表情の駆動 | 空間的驚き/葛藤のみ | 人の存在で表情が変わる |
| 「その子らしさ」 | 動きのパターンのみ | 動き + 人への態度の偏り |

**結論:** 距離センサーだけでも「動きの個性」は出る。しかし「歪み」は原理的に発生しない。人物検知を入れて初めて、他者との摩擦→歪みの蓄積→固着→自律という設計要件の核心が機能する。

## 実装の段階

### Phase A: 距離センサー + 基本Brain（014ベース）
- 014のアーキテクチャをそのまま実装
- シミュレータで動きの質を検証
- ここまでは部品待ちの間にできる

### Phase B: エピソード記憶 + 想起
- SpatialMemory → Episode への拡張
- RecallEngineの実装
- 反芻モードの実装
- **ここで「想起の癖＝人格の座」が入る**

### Phase C: 人物検知 + 歪み
- BLEスキャナの統合
- per_person weights の実装
- who_present タグの記憶への組み込み
- **ここで「歪み」が始まる**

### Phase D: 表情（OLED）
- Face モジュール
- 内部状態→表情のマッピング
- Phase B-Cと並行可能

## 開いた問い

1. **BLEの実装詳細** — iBeacon vs Eddystone。Pi内蔵Bluetoothでのスキャン方法。bluezのpythonバインディング（bleak? bluepy?）。スキャン間隔とバッテリー消費のトレードオフ
2. **エピソード記憶の容量** — Piのメモリ制約。Episode構造体は014のSpatialMemoryより大きい。50個？100個？古い記憶の圧縮は必要か
3. **想起パラメータの初期値** — RecallEngineのw_*を何から始めるか。ランダム？均等？人間の赤ちゃんの認知バイアスを参考にする？
4. **valenceの源泉** — 016で議論した符号つき予測誤差。「良い驚き」と「悪い驚き」をどう区別するか。距離センサーだけでは曖昧。人がいる→正のvalenceバイアス？
5. **展示の時間スケール問題** — 歪みの固着には繰り返しの経験が必要。30分の展示で見えるか。2ヶ月の家庭生活で育てた「個」を展示に持っていくのが現実的か
