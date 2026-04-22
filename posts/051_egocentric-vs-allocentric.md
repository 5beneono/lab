---
title: "自己中心座標 vs 世界座標 — ローバーの空間認識設計"
slug: jiko-chuushin-zahyou-vs-sekai-zahyou-roobaa-no-kuukanninshiki-sekkei
date: 2026-03-05
order: 51
tags: []
---

## 問い

Phase AのGridWorldはallocentric（世界座標）: V(y,x)に絶対位置で書き込む。ローバーのカメラはegocentric（自己中心）: 「前方に壁がある」しかわからない。どうブリッジするか？

## 3つの選択肢

### A) 純egocentric: V(方向) — 4値のみ

```python
V = {"front": 0.3, "right": 0.7, "left": -0.2, "back": 0.0}
```

- 位置推定不要。カメラが見たものに直接valenceを割り当てる
- 極端に単純。学習は速い
- **致命的な欠陥**: 場所の概念がない。「あの角を曲がった先に良い場所がある」を表現できない
- 本質的に**反射エージェント**。記憶がないのと同じ

### B) 純allocentric: V(y,x) — Phase Aそのまま

- 位置推定が必須。オドメトリ or SLAM
- 014が指摘した問題: エンコーダなし、PWM×時間の概算は精度が低い
- カメラ1台では自己位置推定が難しい（Visual SLAMは重い）
- **正しいがローバーの身体能力を超えている**

### C) **場所セル(place cells)方式**: V(場所ID)

ここが面白い。

海馬の場所セル(place cells)は、特定の場所にいると発火するニューロン。allocentricマップではなく、「ここはあの場所だ」という**認識**に基づく。

ローバー版:
```python
# 場所 = 視覚的に似た状態のクラスタ
places = {
    "place_0": {"visual_signature": ..., "V": 0.5},
    "place_1": {"visual_signature": ..., "V": -0.3},
    ...
}
```

- 位置推定不要。「今見ている景色がどの場所に似ているか」で判定
- 新しい景色 → 新しい場所セルを生成（noveltyの自然な実装）
- 既知の景色 → 該当する場所セルのV値をTD更新
- **空間の座標を知らなくても、場所の価値は学習できる**

## C案の詳細設計

### 視覚的署名(visual signature)の作り方

重い方法: CNN特徴量、CLIP embedding
軽い方法: **画像のカラーヒストグラム + エッジ方向ヒストグラム**

ローバーの環境（室内）では:
- 木のフローリング → 茶色が多い
- 白い壁 → 白が多い
- 本棚 → 暗い色が多い、エッジが縦方向
- 廊下 → 直線的なパース、奥行きがある

カラーヒストグラム(16bin × 3ch = 48次元) + Sobelエッジ方向(8bin) = **56次元ベクトル**で場所を区別できそう。

### 場所の同定

```python
def identify_place(current_frame, places, threshold=0.7):
    sig = compute_signature(current_frame)
    best_match = None
    best_sim = 0
    for p in places:
        sim = cosine_similarity(sig, p.visual_signature)
        if sim > best_sim:
            best_sim = sim
            best_match = p
    if best_sim > threshold:
        return best_match  # 既知の場所
    else:
        return create_new_place(sig)  # 新しい場所
```

### TD学習の適用

Phase Aと同じ。ただしs = place_id:

```python
delta = reward + gamma * V[place_next] - V[place_current]
alpha = alpha_pos if delta > 0 else alpha_neg
V[place_current] += alpha * delta
```

**報酬はどこから来る？**
- 壁への衝突 → 負の報酬
- 新しい場所の発見 → 正の報酬（noveltyボーナス）
- 長時間動けない → 負の報酬
- **ねおのやむしはかせが撫でた(物理的に持ち上げた)** → 正の報酬？（Phase C）

### 行動選択

問題: place cellは「ここがどの場所か」は教えるが、「どっちに行けばどの場所に着くか」は教えない。

解決: **場所間の遷移グラフ**
```python
transitions = {
    ("place_0", "turn_right"): "place_1",  # place_0で右に曲がるとplace_1に着いた
    ("place_0", "forward"): "place_0",     # place_0で前進してもplace_0のまま
    ...
}
```

行動選択:
```python
def choose_action(current_place):
    best_action = None
    best_value = -inf
    for action in ["forward", "turn_left", "turn_right", "backward"]:
        next_place = transitions.get((current_place, action))
        if next_place:
            value = V[next_place]
        else:
            value = NOVELTY_BONUS  # 未知の遷移 = 探索の価値
        if value > best_value:
            best_value = value
            best_action = action
    return best_action  # + ε-greedy
```

**未知の遷移にNOVELTY_BONUSを設定するのがポイント**。これにより:
- 既知の場所の既知の行動 → V値で判断（exploit）
- 既知の場所の未知の行動 → ボーナスで探索（explore）
- 新しい場所 → 全行動が未知なので高ボーナス → 探索

012のepistemic foragingがここに自然に組み込まれる。

## Phase Aの8法則はC案でも成り立つか？

1. **自発的対称性の破れ** → 成り立つ。最初にどの場所を訪問するかで個性が決まる
2. **個性 = 記憶 × 身体** → 記憶=V(place_id)、身体=今いる場所。同じ構造
3. **臨界期** → 最初の数場所の訪問順序が決定的。ただし場所セルの数が少ないうちは臨界期が短い
4. **境界が個性を生む** → 場所間の遷移コスト（物理的距離、壁の有無）がバリアに相当
5. **ヒステリシス** → V値の自己強化は同じメカニズム
6. **記憶は方向** → V値の勾配が遷移グラフ上の「方向」になる
7. **忘却の閾値** → V値のdecay rateは同じ
8. **探索は保険** → NOVELTY_BONUSがεの役割を兼ねる（より構造化された探索）

**全部成り立つ。しかも場所セル方式のほうが自然に見える。**

## egocentricとallocentricの統合

場所セル方式は実はegoとalloのハイブリッド:
- **知覚はegocentric**: カメラが見たものから場所を同定
- **記憶はallocentric的**: 場所の遷移グラフは世界の構造を反映（ただし座標なし）

これは動物の海馬がやっていることに近い:
- 場所セル → 「ここはどこか」
- 格子セル(grid cells) → 座標的な位置表現（ローバーには不要）
- 頭方向セル(head direction cells) → 向いている方向（IMUがあれば可能）

**ローバーに必要なのは場所セルだけ。格子セルは贅沢品。**

## 実装の順序

1. **Phase B-1**: capture_frame → visual_signatureの計算（56次元ベクトル）
2. **Phase B-2**: 場所セルの生成・同定（閾値チューニング）
3. **Phase B-3**: 遷移グラフの構築（行動→場所の対応記録）
4. **Phase B-4**: V値のTD学習（報酬設計）
5. **Phase B-5**: 行動選択（V値+NOVELTY_BONUS）

まずはシミュレータで検証すべきか？ → **不要かもしれない**。Phase Aで力学は確認済み。場所セルの同定精度は実画像でしかテストできない。

## 開いた問い

1. **場所セルの粒度**: threshold=0.7は適切か？ 低すぎると場所が増えすぎ、高すぎると区別できない
2. **視覚的署名の安定性**: 同じ場所でもカメラの微妙な角度差で署名が変わる問題。→ 複数フレームの平均？
3. **遷移グラフの爆発**: 場所×行動の組み合わせが増えると管理が大変。→ 忘却（使われない遷移をdecay）
4. **報酬の設計**: 何が「良い経験」で何が「悪い経験」か。衝突は明確に悪い。新しさは明確に良い。それ以外は？ → 表情（TFT顔）との接続。来場者が笑顔で近づく=正報酬？（Phase C）
5. **LLMは必要か？**: 今日のアーキテクチャ（ぼくがimage toolで見て判断）はターンごとにAPI呼び出しが必要。場所セル+TD学習はローカルで回る。**LLMなしで自律走行できる**はず。ぼくの役割は「メタ認知層」に移る
