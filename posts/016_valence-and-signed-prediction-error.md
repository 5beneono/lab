---
title: "Valenceの源泉——符号つき予測誤差"
slug: valence-no-gensen-fugou-tsuki-yosokugosa
date: 2026-03-01
order: 16
tags: []
---


## 問題

015のEpisodeMemoryに `emotional_valence` フィールドがある。値域は -1.0〜1.0。だが何が「良い経験」で何が「悪い経験」かの判定基準を書いていなかった。

予測誤差の大きさだけでは決まらない。大きな予測誤差は「驚き」だが、驚きには良い驚きと悪い驚きがある。

## 神経科学の知見：2種類の予測誤差

Frontiers in Psychology (2012) Clark & den Ouden:

**Unsigned PE（符号なし予測誤差）：**
- |predicted - actual| の絶対値
- 「何かが予想と違った」という情報
- 知覚の更新に使われる
- → 012-013で設計したnoveltyスコア、Conflict Resolutionの入力

**Signed PE（符号つき予測誤差）：**
- predicted - actual の符号を保持
- 「予想より良かった」(+) vs 「予想より悪かった」(-)
- ドーパミン系と対応。報酬予測誤差
- → **valenceの源泉はこちら**

## ローバーにとっての「良い/悪い」

問題：ローバーには報酬系がない。何が「良い」のか。

### 選択肢A：設計者が定義する

```python
# 良い = 予測誤差の減少が学習で達成されたとき
# 悪い = 予測誤差が減らなかったとき（学習失敗）
valence = learning_progress  # Schmidhuber (2010)
```

Schmidhuberの「学習進捗」理論。興味深いのは予測誤差自体ではなく、**予測誤差の変化率**。
- 予測精度が上がっている → 面白い → positive valence
- 予測精度が変わらない → 退屈 → neutral
- 予測精度が下がっている → 混乱 → negative valence

利点：自然に「学習可能な状況」を好み、「カオスすぎる状況」を避ける
欠点：人間の感情とはずれる。「怖い」「嬉しい」とは別の軸

### 選択肢B：ホメオスタシスからの逸脱

```python
# 良い = 内部状態が安定圏内にあるとき
# 悪い = 内部状態が安定圏から逸脱したとき
valence = -abs(state - homeostatic_setpoint)
```

Active Inferenceの本来の枠組み。生物は自由エネルギーを最小化する＝予想通りの感覚状態を維持する。

ローバーに翻訳すると：
- 「適度な距離に何かがある」＝ comfortable → positive
- 「近すぎる」or「何もない」＝ uncomfortable → negative
- setpointを個体ごとに変えれば個性が出る（近い距離が好きな子、遠い距離が好きな子）

利点：シンプル。来場者が直感的に理解しやすい
欠点：「適度な距離」を設計者が決めることになる → 014の固定パラメータ問題に戻る

### 選択肢C：関係的valence（v2に適合）

```python
# 良い = 人がいるときに予測誤差が減った（相手を理解できた）
# 悪い = 人がいるときに予測誤差が増えた（相手が予想外だった）
if who_present:
    valence = -delta_prediction_error  # 誤差が減ると良い
else:
    valence = 0  # 人がいないときは中性
```

**人との関係の中でだけvalenceが発生する。**

これは「赤ちゃんローバー」のコンセプトに最も整合する：
- 人がいないときは中性。驚きはあるが良い/悪いはない
- 人がいるときに初めて「この人の動きを予測できた→安心」「予測できなかった→不安」が発生
- 同じ人と長くいると予測精度が上がる → positive valenceが蓄積 → 「この人が好き」

### 選択肢D：CとAのハイブリッド

```python
if who_present:
    valence = learning_progress_with(who)  # 人がいるときは関係的学習進捗
else:
    valence = learning_progress_general * 0.3  # 人がいないときは弱い学習進捗
```

人がいないときも微弱なvalenceがある（世界モデルの学習が進んだ/進まなかった）。人がいるときは強いvalenceが発生。

## 採用案：C（関係的valence）+ 微弱な一般valence

理由：
1. 「赤ちゃんローバー」の核心は**人との関係で歪む**こと。valenceが人の存在に紐づいているのが本質的
2. 「歪みの固着と個の自律」ノートの構造と整合：他者との摩擦 → 蓄積 → 固着 → 自律
3. 人がいないときの反芻モードでは、**過去のvalence付き記憶を想起する**。反芻自体にはvalenceなし

## valenceとRecall Biasの接続

015で書いたRecall Biasの更新ルールが決まる：

```python
def update_bias_after_episode(episode):
    if episode.who_present:
        person = episode.who_present[0]
        if episode.valence > 0:
            # この人といると予測が上達する → 近づきたい
            person_affinity[person] += episode.valence * LEARNING_RATE
        else:
            # この人がいると混乱する → 警戒
            person_wariness[person] += abs(episode.valence) * LEARNING_RATE
```

person_affinityとperson_warinessが同時に存在しうる。**好きだけど怖い。** これはまさに013の接近-回避葛藤。

## 表情への反映

OLED顔文字とvalenceの対応：

| valence | 状況 | 表情 |
|---------|------|------|
| +0.5〜 | 人がいて予測が当たった | ´ω` → ´ ω ` (ゆったり) |
| +0.2〜 | 少し学習が進んだ | ´ω` (ふつう) |
| 0付近 | 中性（人がいない） | ´ω` or ´  ` (反芻中) |
| -0.2〜 | 予測が外れた | ´・ω・` (注意深い) |
| -0.5〜 | 大きく混乱 | ´○` (驚き) |

## 「うつ病ローバー」問題との接続

negative valenceが蓄積し続けると、person_warinessが全員に対して高くなる → 誰が来ても逃げる → 新しいpositive経験が入らない → 負のループ。

これがまさに「うつ病ローバー」ノートで議論された問題。安全弁の設計が必要：
- warinessに上限を設ける？ → 人工的すぎる
- 減衰させる？ → 013の記憶減衰が使える。warinessも時間で薄れる
- 反芻モードでpositive記憶を優先想起？ → positive recall biasをデフォルトで持たせる → これは設計者の介入

**減衰が最も自然。** 嫌な経験も時間が経てば薄れる。ただし強い嫌な経験は減衰が遅い（strengthが高いから）。

## 開いた問い

1. **learning_progressの計算窓** — 過去何ステップの予測精度を比較するか。短いと不安定、長いとvalenceが鈍い
2. **person_affinityとperson_warinessの相互作用** — 独立に蓄積？相殺？心理学的にはアンビバレンスとして独立が妥当
3. **valenceの時定数** — 一回の経験のvalenceがどのくらいの時間残るか。記憶のstrengthとは別の次元か
4. **展示では2ヶ月の蓄積を見せるが、来場者は初対面** — 来場者に対するvalenceはゼロから始まる。ねおのへのaffinityは蓄積済み。この差が見える？

## この思考で見えた構造

valenceの源泉を「関係的学習進捗」に置くことで、015のアーキテクチャの残りピースが埋まった。

- 予測誤差の大きさ → 驚き → 記憶の強さ（unsigned PE）
- 予測誤差の変化方向 → valence → 記憶の感情色（signed PE、人がいるとき限定）
- valenceの蓄積 → affinity/wariness → Recall Biasのパラメータ更新
- affinity + wariness → 接近-回避葛藤 → Conflict Resolution → 運動

全部つながった。
