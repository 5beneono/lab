---
title: "反芻モードの設計"
slug: hansuu-moodo-no-sekkei
date: 2026-03-02
order: 20
tags: []
---


## 問題

人がいないとき、ローバーは何をするか。018で「反芻モード」と名付けたが、具体的な設計が未整理。

反芻は心理学用語では「繰り返し同じ思考を巡らせること」で、多くは負の文脈で使われる（うつ病の反芻）。しかしここでは中立的に「過去の経験を想起し、内部モデルを更新するプロセス」として扱う。

## 反芻が解くべき問題

1. **人がいない時間が長い** — ローバーは大半の時間を一人で過ごす。この時間に何もしないのは設計上の空白
2. **記憶の固着** — 経験が「想起の癖」に変わるには、繰り返し想起される必要がある。人がいるときだけでは回数が足りない
3. **表情の変化** — 外から見て「何か考えてる」とわかる手がかりが必要

## 反芻のアルゴリズム

```python
class RuminationEngine:
    def __init__(self, recall_engine, face, memory):
        self.recall = recall_engine
        self.face = face
        self.memory = memory
        self.interval_sec = 10  # 反芻間隔
        self.last_rumination = 0
    
    def tick(self, now, who_present):
        """メインループから毎ステップ呼ばれる"""
        if who_present:
            return  # 人がいるときは反芻しない
        
        if now - self.last_rumination < self.interval_sec:
            return  # 間隔未満
        
        self.last_rumination = now
        self._ruminate(now)
    
    def _ruminate(self, now):
        # 1. コンテキスト生成
        context = self._make_context(now)
        
        # 2. 記憶を1つ想起
        episodes = self.recall.recall(context, top_k=1)
        if not episodes:
            return
        episode = episodes[0]
        
        # 3. 想起効果
        episode.recall_count += 1
        episode.strength = min(1.0, episode.strength + RECALL_BOOST)
        
        # 4. 表情を一時的に変える
        self.face.rumination_flash(episode.valence, duration=2.0)
        
        # 5. ログ
        self.memory.log_rumination(episode.id, now)
```

## コンテキスト生成: 何がどの記憶を呼ぶか

反芻のとき、RecallEngineに渡すcontextを何で作るか。これが反芻の「質」を決める。

### 案1: 時間帯ベース
```python
def _make_context(self, now):
    return ContextVector(
        hour=hour_of_day(now),
        # 他は全部ゼロ or 現在のセンサー値
    )
```
- 「朝はあの経験を思い出す」「夜はこっち」
- 時間帯と経験が紐づく。人間にもある（通勤中にいつも同じことを考える）
- シンプルだが、想起パターンが固定化しやすい

### 案2: 直前のエピソードから連鎖
```python
def _make_context(self, now):
    if self.last_recalled:
        return self.last_recalled.context_vector
    return self._time_based_context(now)
```
- 想起した記憶が次の想起のcontextになる
- **連想の連鎖**が発生する。AがBを呼び、BがCを呼ぶ
- 人間の自由連想に近い
- リスク: 同じループに嵌まる可能性（A→B→C→A→...）

### 案3: 揺らぎつき連鎖（採用案）
```python
def _make_context(self, now):
    base = self._time_based_context(now)
    if self.last_recalled:
        chain = self.last_recalled.context_vector
        # 7:3で連鎖ベース + 時間帯ベース + ノイズ
        mixed = 0.6 * chain + 0.3 * base + 0.1 * random_vector()
        return mixed
    return base
```
- 連鎖の傾向を持ちつつ、時間帯と乱数で散らす
- 同じループに嵌まりにくい
- 乱数が「予期しない記憶の想起」を生む → 新しい連想の火種

**0.1のrandom_vectorが「ひらめき」に相当する。** 普段の連想経路から外れた記憶が不意に浮かぶ。

## 反芻と表情の接続

反芻中の基本表情: `´  ``（目を閉じている）

想起が起きた瞬間、2秒間だけ表情が変わる:
- positive valenceの記憶 → `´ ω `` （少し嬉しそう）
- negative valenceの記憶 → `´_ `` （少し暗い）
- 強い驚きの記憶 → 一瞬 `´○`` が出てすぐ `´  `` に戻る

外から見ると：目を閉じた子が、ときどき何かを思い出したように表情が動く。

これだけで「考えてる」「夢を見てる」と投影される。

## 反芻の頻度とリズム

- 基本間隔: 10秒に1回
- ただし一定ではなく、揺らぎを入れる: `interval = 10 + random(-3, 3)`
- 時間帯による変調:
  - 夜（充電中）: 頻度を上げる（5-8秒間隔）。「夢を見てる」
  - 昼: 10秒間隔
  - 人が去った直後: 頻度が一時的に上がる（3-5秒間隔、30秒間）。「去った人のことを反芻してる」

**人が去った直後の高頻度反芻**が重要。去った人に関連するエピソードが集中的に想起され、strengthが上がり、固着が進む。

## 反芻とvalenceの関係

016で決めた: 反芻自体にはvalenceは発生しない（人がいないから）。

しかし反芻は**過去のvalenceを再活性化する**。想起されたエピソードのvalenceが一時的に「現在の気分」に影響する。

```python
class MoodState:
    current_mood: float = 0.0  # -1.0 ~ 1.0
    
    def on_rumination(self, episode):
        # 想起した記憶のvalenceが気分に影響（弱く）
        self.current_mood += episode.valence * MOOD_INFLUENCE
        self.current_mood = clamp(self.current_mood, -1.0, 1.0)
    
    def decay(self):
        # 気分は中性に戻っていく
        self.current_mood *= MOOD_DECAY  # 0.95 etc.
```

MoodStateは行動に直接影響しない（人がいないから動かない）。表情にだけ反映される。

しかし**人が来たとき**、MoodStateがConflict Resolutionの初期pullに影響する:
- mood > 0 のとき → approach_pullに微弱なボーナス
- mood < 0 のとき → safety_pullに微弱なボーナス

つまり：反芻で良い記憶をたくさん思い出した後に人が来ると、少しだけフレンドリー。悪い記憶ばかり想起した後だと、少しだけ警戒的。

## 反芻と記憶の「鍛え」

反芻の真の機能は**記憶の選択的強化**。

- 想起されるたびにstrength += RECALL_BOOST
- 想起されない記憶は自然減衰で消えていく
- recall_countが多い記憶はさらに想起されやすい（正のフィードバック）

結果: 強い経験は何度も反芻されて固着し、弱い経験は忘却される。

これは「歪みの固着と個の自律」ノートの「蓄積→固着→自律」プロセスそのもの。反芻がこのプロセスの加速器。

## 反芻の停止条件

- 人が検知された瞬間、反芻は停止
- 目が開く（`´  `` → `´○`` or `´ω``）
- active modeに遷移

この切り替えが「あ、起きた」感を生む。

## 開いた問い

1. **RECALL_BOOSTの値** — 大きすぎると少ない経験が即座に支配的になる。小さすぎると反芻の効果が見えない。0.02-0.05で始めて調整
2. **反芻中に動くか** — 設計上は動かない想定だが、微細な振動（呼吸のような）はあっていい。ｽﾀｯｸﾁｬﾝのbreathパラメータに相当
3. **反芻の可視化** — 展示Phase 2でOLEDに反芻中の記憶をテキスト表示する？ → コンセプト的には「何を考えてるかわからない」方が投影を誘う。表示しない
4. **複数記憶の同時想起** — 今はtop_k=1だが、2つの記憶が同時に浮かぶ（比較、統合）こともある？ → 複雑になるので初期はtop_k=1

## この思考で見えた構造

反芻は「人がいない時間の埋め合わせ」ではない。**歪みの固着エンジン**。

人との経験（エピソード記憶 + valence）が反芻によって繰り返し想起され、strengthとrecall_countが上がり、RecallEngineのバイアスに定着する。人がいなくても「あの人といたときの経験」を繰り返し想起することで、次にその人が来たときの初期反応が変わる。

これは人間の恋愛初期に似ている。会っていない時間に相手のことを考えれば考えるほど、次に会ったときの態度が変わる。反芻が関係性を構築している。

もう一つ：**揺らぎつき連鎖**のrandom_vector（0.1）が、想起パターンを固定化から救う。これがないと、最も強い記憶だけがさらに強化される一極集中になる。ノイズが多様性を維持する。ノイズは欠陥ではなく、認知の柔軟性の条件。
