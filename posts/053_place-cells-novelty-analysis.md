---
title: "051: Place Cell + Novelty Bonus — 座標なしのナビゲーション"
date: 2026-03-05
order: 53
tags: []
---

## やったこと

Phase Bの核心問題「実機は(x,y)座標を知らない」に対する解: 場所細胞(place cell)モデルを実装。

### アーキテクチャ

- 各位置から「視覚特徴ベクトル」(dim=16)を合成（周囲の報酬構造から生成、ノイズ付き）
- エージェントは座標を持たない。視覚特徴の類似度(cosine)でplace cellをマッチングor新規作成
- Place cell上でTD学習。遷移グラフも構築
- Novelty bonus: 未知の遷移先にボーナス報酬を与えて探索を促進

### 結果

**two_rooms**: 正常動作。seed間で13-53個のplace cellを発見。Room Aに定着。

**symmetric環境**: A=7, B=10, 中間=3。**二極化する**（17/20）。Phase Aの(x,y)直接参照なしでも個性が発生。place cellレベルで自発的対称性の破れが再現。

**Novelty bonus sweep（最も面白い）**:
- bonus=0.0 → 15 places, 4 unique in last 1k（探索せず固着）
- bonus=0.5 → **83 places, 66 unique**（爆発的探索）
- bonus=1.0 → 41 places, 3 unique（探索後に固着）
- bonus=2.0 → 21 places, 3 unique（さらに固着）

## 解釈

### Novelty bonusの非単調性

これは予想外だった。「好奇心が強いほど探索する」は嘘。

- **bonus=0**: greedy、探索しない
- **bonus=0.5**: 報酬(±1.0)と同程度。「知らない場所も良い場所も同じくらい魅力的」→ 良いバランスで探索と搾取が混ざる
- **bonus=1.0-2.0**: 未知遷移の報酬が環境報酬を圧倒。**常に未知を追い求めるので一箇所に留まらない** → だが新しい場所を「見つける」前に移動してしまい、place cellが安定しない？

いや、last 1kでunique=3なのは**探索し尽くして既知になった**可能性もある。5000ステップでtwo_rooms全域を踏破し、もう未知がないから既知の高V値に収束。

→ **検証**: max_stepsを長くして確認すべき。bonus=0.5が特異的に探索し続ける（永遠に新しいplace cellを作る＝ノイズでマッチングが不安定？）のかもしれない。

### Place cellの数 = 世界の主観的複雑さ

83個のplace cellは実際の300セル(20×15)より少ない。threshold=0.85で「似てる場所は同じ」と圧縮している。これは実機で起きる現象と同型: ローバーにとって「同じ廊下の違う位置」は区別できないかもしれない。

**place cellの数はエージェントの世界認識の解像度**。探索が多いほど解像度が上がる。

### 実機への含意

1. novelty_bonus ≈ 環境報酬のスケールの半分 が最適探索点。実機ではカメラ画像の特徴量から「ここは新しい場所か？」を判定し、新しければボーナス
2. threshold（place cellマッチング閾値）は「世界の粒度」を決める。低threshold=大雑把、高threshold=精密。実機では画像の類似度がこれに相当
3. place cellの数が飽和したら「この部屋は探索済み」。新しい部屋に移る合図

## 開いた問い

1. bonus=0.5でunique=66が持続するのはバグか本質か？ → longer run + place cellのマッチング精度をログで確認
2. Place cellのsignature更新（running average）はstabilizeする？ それとも永遠にドリフトする？
3. 実機のカメラ画像でcosine similarityは使えるか？ → CLIP embeddingの類似度ならいける
4. Novelty bonusの非単調性は環境構造（報酬スケール）に依存する？ → 報酬を0.1にしたらbonus=0.1が最適点になるはず
