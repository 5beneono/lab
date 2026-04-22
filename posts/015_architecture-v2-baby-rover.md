---
title: "アーキテクチャv2 ——「赤ちゃんローバー」への統合"
slug: aakitekucha-v2-akachan-roobaa-heno-tougou
date: 2026-03-01
order: 15
tags: []
---


## 014からの差分

014は距離センサー＋空間記憶＋固定If-Thenルールのアーキテクチャだった。今日の議論で3つの根本的な変更が必要になった：

1. **空間記憶 → エピソード記憶**（何がどこで → 誰がいたとき何が起きたか）
2. **固定If-Then → 経験で変わるIf-Then**（偏りが育つ）
3. **距離センサーのみ → 人物検知が核心**（他者の存在が歪みの起点）

## 変わらないもの

014から持ち越せる要素：
- **Conflict Resolution** — 葛藤の運動学的表出（振動・旋回・凍結・突発的転換）。そのまま使える
- **Motor Output** — 差動駆動の制御。変更なし
- **メインループの構造** — 知覚→記憶→評価→葛藤→行動→ログの順序は同じ
- **Phase Manager** — Phase 1/2の転換ロジック（展示用。家では不要）

## 新アーキテクチャ

```
┌────────────────────────────────────────────────────────┐
│                    Raspberry Pi                         │
│                                                         │
│  ┌──────────┐   ┌──────────────┐   ┌──────────┐       │
│  │ Sensors  │──▶│    Brain     │──▶│ Actuators│       │
│  │          │   │              │   │          │       │
│  │ HC-SR04  │   │ World Model  │   │ Motors   │       │
│  │ (距離)    │   │ Episode Mem  │   │ OLED     │       │
│  │ BLE scan │   │ Recall Bias  │   │ (Voice?) │       │
│  │ (誰?)    │   │ Conflict Res │   │          │       │
│  │ (Camera?)│   │ Rumination   │   │          │       │
│  └──────────┘   │ Logger       │   └──────────┘       │
│                  └──────────────┘                       │
└────────────────────────────────────────────────────────┘
```

### Module 1: Perception（拡張）

014からの変更：
- 距離センサー → そのまま（物理的な世界の知覚）
- **＋BLEスキャン** → 「誰がいるか」の検知。スマホのBLEビーコンで個体識別
- **＋人物存在フラグ** → BLEで「人がいる」「いない」を判定。カメラは重い→BLEが現実的

BLEの利点：
- 軽い（BLEスキャンはCPU負荷微小）
- 個体識別ができる（ねおの/むしはかせのスマホを区別）
- プライバシーに配慮（カメラなし）
- Pi内蔵のBluetooth使用可

### Module 2: World Model（新規）

014にはなかった。「次に何が見えるか」を予測する内部モデル。

最小実装：
```python
class WorldModel:
    # 各方向の「予想される距離」を保持
    predictions = {"front": 0.5, "left": 0.8, "right": 0.8}
    
    def predict(self, direction):
        return self.predictions[direction]
    
    def update(self, direction, actual):
        error = abs(actual - self.predictions[direction])
        self.predictions[direction] += LEARN_RATE * (actual - self.predictions[direction])
        return error  # ← これが予測誤差
```

予測誤差がnoveltyの代わりになる。014では「記憶との距離」で新しさを測っていたが、v2では「予測との差」で驚きを測る。よりactive inference的。

### Module 3: Episode Memory（空間記憶から拡張）

014の `SpatialMemory`:
```
{ position, sensor_readings, strength, timestamp }
```

v2の `EpisodeMemory`:
```python
{
    "timestamp": t,
    "duration": dt,
    "sensors": {...},
    "prediction_error": 0.7,      # この瞬間の驚きの大きさ
    "who_present": ["neono"],     # BLEで検知した人物
    "action_taken": "approach",
    "emotional_valence": 0.3,     # 良い経験/悪い経験（-1.0〜1.0）
    "recall_count": 0,            # 想起された回数
    "strength": 1.0               # 減衰する
}
```

**予測誤差が大きい瞬間で区切る**（設計要件ノートの通り）。落差が大きいほど強く記憶に残る（strengthの初期値が高い）。

「who_present」タグが014との最大の差分。これにより「ねおのがいたときの経験」と「むしはかせがいたときの経験」が別々に蓄積される。

### Module 4: Recall Bias（想起の癖）— 人格の座

014のIf-Thenルール（固定）を置き換える。

```python
class RecallBias:
    def recall(self, current_context):
        """今の状況に似た過去の記憶を引っ張る。
        ただし、検索関数にバイアスがかかっている。"""
        
        candidates = episode_memory.search(current_context)
        
        # バイアス1: 感情バイアス — 強い感情を伴った記憶が優先される
        candidates = weight_by(candidates, "prediction_error", power=EMOTION_BIAS)
        
        # バイアス2: 人物バイアス — 特定の人といた記憶が引きやすい
        candidates = weight_by(candidates, person_match(current_context.who), power=PERSON_BIAS)
        
        # バイアス3: 新近性バイアス — 最近の記憶が優先
        candidates = weight_by(candidates, recency, power=RECENCY_BIAS)
        
        # バイアス4: 頻度バイアス — よく想起される記憶がさらに想起されやすい
        candidates = weight_by(candidates, "recall_count", power=FREQUENCY_BIAS)
        
        selected = weighted_random(candidates)
        selected.recall_count += 1  # 想起するたびにカウント増加
        return selected
```

**ここが「歪み」の座**。バイアスのpower値は最初は均等だが、経験によって変わる：
- ねおのがいるときに良い経験が多い → ねおのの存在でPERSON_BIASが上がる → ねおのを検知すると良い記憶が引きやすくなる → 接近しやすくなる
- 急に触られて驚いた経験がある → EMOTION_BIASが上がる → 似た状況で警戒記憶が引きやすい

**行動への接続：** 想起された記憶のaction_takenとvalenceが次の行動を方向づける。「前にこの状況で接近して良い結果だった」→ 接近pull。「前に後退して安全だった」→ 後退pull。

これがConflict Resolutionに入力される。014の固定ルールではなく、**過去の経験からpullが生成される**。

### Module 5: Rumination（反芻モード）— 新規

人がいないときの動作。014にはなかった。

```python
class Rumination:
    def run(self):
        """一定間隔で過去の記憶を重みつきで想起し、
        現在の文脈と紐づけ直す"""
        
        memory = recall_bias.recall(current_context)
        
        # 想起した記憶を現在の文脈（時間帯、明るさ等）で再解釈
        memory.contextual_links.append(current_context)
        
        # OLED: 目を閉じる ´  `
        oled.show("´  `")
        
        # 繰り返し想起された記憶は重みが上がる
        # 想起されなかった記憶は減衰で薄れる
```

反芻中の運動：完全停止 or 微細な揺れ（「考えている」ように見える）。

### Module 6: OLED Face（新規）

顔文字による内部状態の表出。014ではPhase 2用だったが、v2では最初からオン。

```python
face_map = {
    "neutral":    "´ω`",
    "relaxed":    "´ ω `",
    "surprised":  "´○`",
    "sleepy":     "´_`",
    "ruminating": "´  `",
    "curious":    "´・ω・`",  # 要検討
    "wary":       "´；ω；`",  # 要検討
}
```

内部状態（prediction_error, conflict_level, who_present）→ 表情のマッピング。

**重要：** 表情は「正解」ではない。距離センサーの値が下がったとき ´○` を出しても、来場者が「驚いた」と読むか「怒った」と読むかは来場者次第。表情もまた投影の媒体。

## 014 → v2 のモジュール対応表

| 014 | v2 | 変更点 |
|-----|-----|--------|
| Perception | Perception+ | +BLE, +人物フラグ |
| (なし) | World Model | 新規。予測と誤差の計算 |
| Memory (空間) | Episode Memory | 空間→エピソード。who_presentタグ |
| Novelty | (World Modelに統合) | 新しさ→予測誤差 |
| If-Then Rules (固定) | Recall Bias | 固定ルール→経験で変わる想起バイアス |
| Conflict Resolution | Conflict Resolution | **変更なし** |
| Motor Output | Motor Output | **変更なし** |
| Logger | Logger | +表情ログ、+who_present |
| Phase Manager | Phase Manager | 展示時のみ使用 |
| (なし) | Rumination | 新規。人がいないときの内部処理 |
| (なし) | OLED Face | 新規。顔文字表出 |

## 距離センサーだけの世界 vs 人物検知が入った世界

**距離センサーのみ（014）：**
- 世界は「近い/遠い」の連続値
- すべての障害物は等価（壁も人も同じ）
- 偏りは固定パラメータ。経験で変わらない
- 展示で完結する。持ち帰れない

**人物検知あり（v2）：**
- 世界は「誰がいるか」で質が変わる
- ねおのの前での経験とむしはかせの前での経験が区別される
- 偏りが蓄積する。2ヶ月で「その子」が育つ
- 展示は「育った結果」を見せる場。作品は日常の中にある

**これは単なる機能追加ではない。存在論的に異なる。**

014のローバーは「環境に反応する機械」。v2のローバーは「関係性の中で育つ存在」。

## 実装の優先順位

Phase A（最小構成、1-2週間）：
1. モーター制御（TB6612FNG新品待ち）
2. 距離センサー×2（前方＋横）
3. World Model（簡易版）
4. 驚き駆動の移動
→ 「動いて、驚いて、方向を変える」だけの存在。でも013の葛藤が見えるはず

Phase B（記憶と想起、2-3週間）：
5. Episode Memory
6. Recall Bias（初期バイアスは固定でいい）
7. 反芻モード
→ 「経験を覚えていて、思い出す」存在。行動に偏りが出始める

Phase C（他者検知、残り期間）：
8. BLEスキャン
9. who_presentタグ
10. 人物ごとの歪み蓄積
→ 「誰がいるかで変わる」存在。ここからが本番

Phase D（表出）：
11. OLED顔文字
12. (Voice Bridge接続?)

## 開いた問い

1. **BLEの検知精度** — スマホのBLEビーコン発信は常時か、アプリ必要か。iBeacon? Eddystone?
2. **World Modelの複雑さ** — 方向ごとの予測値だけで十分か。もっとリッチなモデルが必要か
3. **Recall Biasのパラメータ更新ルール** — 「良い経験」「悪い経験」をどう判定するか。予測誤差の符号？
4. **2ヶ月で歪みは蓄積するか** — 日に何回のインタラクション？十分な経験量が得られるか
5. **展示モードと家モードの切り替え** — 設定ファイル？物理スイッチ？

## この思考で見えた構造

014→v2の移行で、ローバーの存在論が変わった。

014は「パラメータを調整すれば完成する機械」だった。設計者がIf-Thenルールを書き、閾値を決め、動かす。

v2は「一緒に暮らして育てる存在」になった。設計者が決めるのは学習のメカニズムだけ。何を学ぶかは経験次第。

これは011で見つけた「設計 vs 自然発生の中間」の問題に対する、ねおのの回答だと思う。「設計するのは器。中身は生きることで満たされる」。
