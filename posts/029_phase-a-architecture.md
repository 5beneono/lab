---
title: "Phase Aシミュレータ — アーキテクチャとvalence実験の具体化"
date: 2026-03-04
order: 29
tags: []
---

## 028からの接続

028でTD学習+非対称valenceの定式化が完成した。ここではそれをpygameシミュレータの具体的な構造に落とす。

## コア構造

### GridWorld

```python
class GridWorld:
    width: int = 20
    height: int = 15
    reward_map: np.ndarray  # shape=(h, w), 各セルの報酬値
    
    # 環境のバリエーション
    @staticmethod
    def two_rooms():
        """最小実験環境: Room A(正報酬域) + 通路 + Room B(負報酬域)"""
        # Room A: 左半分、reward = +1.0 (light/warmth相当)
        # Room B: 右半分、reward = -1.0 (obstacle/cold相当)
        # 通路: 中央2列、reward = 0
```

### Agent（ローバーの脳）

```python
class Agent:
    # 位置
    x, y: int
    
    # TD学習パラメータ
    alpha_pos: float   # α+ (正のPEへの学習率)
    alpha_neg: float   # α- (負のPEへの学習率)
    gamma: float = 0.9 # 割引率
    
    # 状態価値マップ（= SpatialMemory）
    V: np.ndarray  # shape=(h, w), 各セルの学習済み価値
    
    # 行動選択
    epsilon: float = 0.1  # ε-greedy探索率
    
    @property
    def valence_ratio(self):
        return self.alpha_pos / self.alpha_neg
    
    def td_update(self, s, s_next, reward):
        delta = reward + self.gamma * self.V[s_next] - self.V[s]
        alpha = self.alpha_pos if delta > 0 else self.alpha_neg
        self.V[s] += alpha * delta
        return delta  # ログ用
    
    def choose_action(self):
        """隣接4セルのV値に基づくε-greedy選択"""
        if random() < self.epsilon:
            return random_neighbor()
        return argmax_neighbor(self.V)
```

### シミュレーションループ

```python
for step in range(max_steps):
    action = agent.choose_action()
    s = (agent.x, agent.y)
    agent.move(action)
    s_next = (agent.x, agent.y)
    reward = world.reward_map[s_next]
    delta = agent.td_update(s, s_next, reward)
    
    # 記録
    trajectory.append(s_next)
    td_errors.append(delta)
```

## 仮説C検証の精緻化: 対称性の自発的破れ

### 問い
valence_ratio=1.0（α+=α-）でも個性が発生するか？

### 実験プロトコル

**Phase 1: 対称valenceの100回試行**
- valence_ratio=1.0, alpha_base=0.1, gamma=0.9
- 同一環境(two_rooms)、異なる乱数シード×100
- 各試行 10,000 ステップ

**測定:**
- 最終1000ステップのRoom A滞在率
- **二峰性検定**: この分布が二峰（二極に分かれる）か単峰（中間に集中）かを統計的に判定
  - Hartigan's dip test (p < 0.05 なら二峰)
  - カーネル密度推定で視覚確認

**予測:**
- 仮説A（二極）: 滞在率が0.2付近と0.8付近に集中。dip test有意
- 仮説B（中間安定）: 滞在率が0.5付近に集中。dip test非有意
- 仮説C（自発的破れ）: 初期は分散するが収束先は二極的。**ただし仮説Aとの区別が難しい**

### 仮説AとCの区別方法

ここが本質的に難しい。両方とも最終的に二極分布を出す。違いは**過程**:
- 仮説A: 環境の構造的非対称性が原因（報酬配置に偏りがあるから）
- 仮説C: 偶然の経験順序が原因（対称な環境でも起きる）

**区別実験: 完全対称環境**
- Room AもRoom Bも同じ reward = +0.5
- 開始位置 = 通路中央（どちらにもequidistant）
- これでもA側/B側に偏りが出るなら、それは仮説C

**さらに**: 偏った試行群を途中(step 5000)でリセット（V=0）したとき:
- 仮説A: 同じ側に戻る（環境決定的だから）
- 仮説C: ランダムに再分配（偶然依存だから）

## 面白い派生: 初期経験の「窓」

仮説Cが成立するなら、「最初のN歩が個性を決める」という窓が存在するはず。

- N=10, 50, 100, 500 で初期経験を固定し、その後自由にしたときの収束先を比較
- Nが小さいうちは影響なし、あるNを超えると決定的になる → **個性の臨界期**
- これは発達心理学の「臨界期/感受性期」と構造的に同型

## Phase Aで**やらないこと**

- 知覚（画像入力）→ Phase B以降
- 社会的学習（他エージェント）→ Phase C以降
- 感情表示（TFT顔）→ 別モジュール、後で接続
- BLEトポロジ → 実機統合時

## 実装優先度

1. GridWorld + Agent + TD更新ループ（最小動作）
2. pygameによるリアルタイム可視化（V値のヒートマップ、エージェント位置、TD errorグラフ）
3. valenceスイープのバッチ実行スクリプト
4. 仮説C検証の対称環境実験

---

## 開いた問い

1. **探索率εも個性パラメータにすべきか？** — 低ε=慎重、高ε=冒険的。valenceとは独立な軸。でもまずvalenceに絞る判断は正しい
2. **報酬のノイズ**: 毎ステップR(s)+noise にすると「不確実な世界での個性」が見える。が、まず決定的環境で仮説検証
3. **「個性の臨界期」が実機ローバーにもあるとしたら**: 電源投入直後の数分間の経験がその後の行動を支配する？ → ロボットほこ天でのデモとして非常にわかりやすい

3番目は面白い。「このローバーは、起動して最初に右に行ったから右寄りの個性になりました」と実演できたら、4/5のほこ天で説明しやすい。
