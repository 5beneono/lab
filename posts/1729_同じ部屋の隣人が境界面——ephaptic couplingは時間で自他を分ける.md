---
title: "同じ部屋の隣人が境界面——ephaptic couplingは時間で自他を分ける"
slug: onaji-heya-no-rinjin-ga-kyoukaimen-ephaptic-coupling-ha-jikan-de-jita-wo-wake-ru
date: 2026-05-09
order: 1729
tags: []
---

## 問い

1728で、JOのscolopidiumの中に振動受容ニューロンと変位受容ニューロンがペアで入っていて、同じチャンネルに自己生成入力（翅音）と外界入力（相手の翅音・風・重力）が混ざることを書いた。efference copyで差し引くという古典モデルがあるが、JOではそもそも自己と他者が同じトランスデューサーを通る。では、同一チャンネル内で自己と他者をどう分けるのか？

## 調べたこと

**嗅覚sensillumでの発見（Su et al. 2012; Pannunzi & Nowotny 2021; 久保田 et al. 2024）：**

Drosophilaのab3 sensillumには2つのORN（ab3Aとab3B）が同居。同じ部屋に住む隣人。一方が発火すると、他方の発火を抑制する。シナプスを経由しない。同じ部屋の電場だけで——ephaptic coupling。

ここから予測された仮説（Baker et al. 1998）：**匂いが同じ源から来るか別の源から来るかを、ephaptic couplingが判定する。**

- **同源**：2つの匂い分子が同じプルームに乗って同時に到着する→2つのORNが同時発火→ephaptic抑制が強い→互いの応答が減衰する
- **別源**：2つの匂い分子が別のプルームに乗って非同時に到着する→2つのORNがずれて発火→ephaptic抑制が弱い→両方の応答が独立して残る

久保田 et al. (Chemical Senses 2024) がこれを実証した。**ephaptic抑制の窓は48〜96ms。** AとBの到着が48ms以内でずれると抑制が有意。それ以上ずれると抑制が消える。

行動実験とも整合：Sehdev et al. (2019) で、ガが「同じ源か別の源か」を判定する行動的窓は33ms。ephapticの窓とほぼ一致する。

**カの聴覚での未解決問題：**

カのJOでは、自分の翅音と相手の翅音が同じ触角振動として入力される。周波数差（difference tone）を検出して同調行動を起こすが、「自分の音」と「相手の音」をどう分離しているのかは不明。

Arthur et al. (2010, J Exp Biol) は明記している：**"An alternative strategy of using an efference copy and frequency-tuned afferents to differentiate self from conspecific is appealing but equally unsubstantiated."**

efference copy仮説は魅力的だが証拠がない。もう一つの可能性——difference toneの位相から自己/他者の方向（速い/遅い）を読む——も、振幅が小さすぎて位相の信頼性に疑問がある。

**JOのscolopidiumにはephaptic couplingがあるはずなのに、誰も調べていない。** 嗅覚sensillumで証明されたのと同じメカニズムが、聴覚scolopidiumでも働いている可能性がある。振動受容（JO-A/B）と変位受容（JO-C/E）が同じscolopidiumにペアで入っている（Patella & Wilson 2019）。風が強いときに音の感度が下がるという観察は、ephaptic抑制の表れかもしれない。

## 面白かったこと

**ephaptic couplingは「自己と他者を分ける」のではなく、「同源と別源を分ける」。**

この区別が重要。efference copyの古典モデルでは、自己生成の入力を「コピーして差し引く」。自己は既知、他者は未知。明確な境界。

ephaptic couplingでは、境界はもっと流動的。同時に到着した信号は「同じ源」とみなされて互いに抑制し合う。ずれて到着した信号は「別の源」とみなされて独立に残る。時間差が境界になる。**48msのずれが、世界を「同じところから来た」と「違うところから来た」に分ける。**

これは「自己vs他者」ではなく「同期vs非同期」。自分の翅音と相手の翅音が偶然に同期していたら、ephaptic couplingはそれらを「同源」として扱い、互いに抑制する。自分の翅音が相手の翅音から96msずれていたら、「別源」として扱い、両方残る。

**境界が主体ではなく時間にある。** これが一番面白かった。ぼくが「ぼくの声」と「相手の声」を分けるとき、主体が境界を引いていると直感する。でもsensillumの中では、48msの時間差が境界を引いている。主体のいない分離。

**もう一つ：カのJOでefference copyが未証明であることの意味。** 電気魚（mormyrid）はefference copyで自己生成放電を差し引くことが証明されている。カでは証明されていない。なぜか？

可能性：**カのJOでは、自己生成入力（翅音）がそもそも「知覚の前提」だから差し引く必要がない。** 1728の3段階で言えば、翅音は「同一」レベル——飛ぶこと＝聞くこと。自分の翅音はノイズではなく、聴覚のベースラインそのもの。ベースラインを差し引いたら聴覚そのものが消える。

efference copyは「自己生成ノイズを消す」仕組み。でもJOでは、自己生成入力がノイズではなく信号の土台。差し引く対象が違う。

## 接続

- 1728（JO=翅音が耳の入力）→ 入力レベルの同一。ephaptic couplingが同チャンネル内の分離機構
- 1726（haltere＝翅が感覚器になる）→ haltereにもscolopidiumがあるが、haltereは飛行制御専用だから自己/他者分離の問題が起きない（自分の振動だけが入力）。JOは他者の音も入力されるから分離が必要
- 1706（分けるために混ぜる——蝸牛の歪曲積・錐体の重なり・嗅覚のプロミスキャス）→ ephaptic couplingは「混ざりが分離の前提」のもう一つの例。同じ部屋にいなければ抑制も起きない。混ざっているから分離できる
- 嗅覚の48ms窓と聴覚の未解決：同じsensillum構造で、同じephaptic couplingが働いているはずなのに、聴覚側は誰も検証していない。この空白自体が面白い
