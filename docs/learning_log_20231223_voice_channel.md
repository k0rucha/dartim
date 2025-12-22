# 学習ログ: nyxx_lavalink でボイスチャンネルに接続する

**日付**: 2025-12-23  
**トピック**: nyxx v6 + nyxx_lavalink v4.0.0-dev.1 でのボイスチャンネル接続

---

## 1. PartialChannel vs Channel

| 種類 | 持っている情報 | 用途 |
|------|---------------|------|
| `PartialChannel` | `id` のみ | 軽量・キャッシュ節約 |
| `Channel` | `id`, `name`, メソッド全部 | 実際の操作に使用 |

`.get()` で `PartialChannel` → 完全な `Channel` に変換できる。

```dart
// voiceState.channel は PartialChannel（IDのみ）
final voiceChannel = await voiceState?.channel?.get();
```

---

## 2. VoiceChannel vs GuildVoiceChannel

| 種類 | 型 | `name` プロパティ |
|------|-----|------------------|
| `VoiceChannel` | 抽象型 | ❌ なし |
| `GuildVoiceChannel` | 具象型 | ✅ あり |

`connectLavalink()` は `VoiceChannel` に対する拡張メソッドだが、`name` は `GuildVoiceChannel` にしかない。

---

## 3. スマートキャスト（Smart Cast）

Dart では `is` / `is!` でチェック後、自動的に型がキャストされる。

```dart
if (voiceChannel is! GuildVoiceChannel) {
  // エラー処理
  return;
}
// この時点で voiceChannel は GuildVoiceChannel 型として扱われる
await voiceChannel.connectLavalink();
print(voiceChannel.name);  // ← name が使える！
```

**一石二鳥**: 型チェック＋キャストを同時に行える。

---

## 4. Extension（拡張メソッド）

既存クラスに**新しいメソッドを追加**する Dart の機能。継承なし・元のクラス変更なし。

```dart
// nyxx_lavalink 内の定義
extension LavalinkVoiceChannel on VoiceChannel {
  Future<LavalinkPlayer> connectLavalink() async {
    // Lavalink 接続処理
  }
}
```

**使い方**: `import` するだけで対象クラスに新メソッドが生える。

```dart
import 'package:nyxx_lavalink/nyxx_lavalink.dart';

// これで VoiceChannel に connectLavalink() が使えるようになる
await voiceChannel.connectLavalink();
```

### Override との違い

| 概念 | 説明 |
|------|------|
| **Override** | 継承した親クラスのメソッドを**上書き** |
| **Extension** | 既存クラスに**新しいメソッドを追加**（継承なし） |

---

## 5. 今回のエラーと解決

### 発生したエラー

```
error • The method 'connect' isn't defined for the type 'PartialChannel'
error • The getter 'name' isn't defined for the type 'PartialChannel'
```

### 原因と解決

| エラー | 原因 | 解決 |
|--------|------|------|
| `connect` がない | メソッド名が違う | `connectLavalink()` を使う |
| `name` がない | `VoiceChannel`（抽象）には `name` がない | `GuildVoiceChannel` で型チェック |
| 引数エラー | `connectLavalink()` は引数不要 | 引数を削除 |
| プラグイン未登録 | `lavalink` を plugins に渡していなかった | `plugins: [commands, lavalink]` に追加 |

---

## 6. 最終的なコード

```dart
final summonCommand = ChatCommand('summon', 'ボットを音声チャンネルに参加させます', (
  ChatContext context,
) async {
  final member = context.member;
  if (member == null) {
    context.respond(MessageBuilder(content: "あなたが誰なのか私にはわかりません。"));
    return;
  }

  final guild = await context.guild?.get();
  final voiceState = guild?.voiceStates[member.id];

  // PartialChannel → Channel に変換
  final voiceChannel = await voiceState?.channel?.get();
  if (voiceChannel == null) {
    context.respond(MessageBuilder(content: "Channelの取得に失敗しました"));
    return;
  }

  // スマートキャスト: GuildVoiceChannel でないならリターン
  if (voiceChannel is! GuildVoiceChannel) {
    context.respond(MessageBuilder(content: "ボイスチャンネルではありません"));
    return;
  }

  // この時点で voiceChannel は GuildVoiceChannel 型
  await voiceChannel.connectLavalink();
  context.respond(MessageBuilder(content: "${voiceChannel.name} に参加しました！"));
});
```

---

## 参考リンク

- [nyxx VoiceChannel](https://pub.dev/documentation/nyxx/6.7.0/nyxx/VoiceChannel-class.html)
- [nyxx GuildVoiceChannel](https://pub.dev/documentation/nyxx/6.7.0/nyxx/GuildVoiceChannel-class.html)
- [nyxx_lavalink LavalinkVoiceChannel extension](https://pub.dev/documentation/nyxx_lavalink/4.0.0-dev.1/nyxx_lavalink/LavalinkVoiceChannel.html)

---

# 学習ログ: /leave コマンドの実装

**日付**: 2025-12-23  
**トピック**: ボイスチャンネルからの退出処理

---

## 7. LavalinkPlugin vs LavalinkPlayer

| 概念 | 役割 |
|------|------|
| `LavalinkPlugin` | Playerを管理するマネージャー。複数ギルドのPlayerを統括 |
| `LavalinkPlayer` | ギルドごとのボイスチャンネルセッション。1ギルド=1Player |

### 重要な発見

- `LavalinkPlugin`には`players`プロパティが**存在しない**
- Playerは接続時にStreamで発行され、プラグイン側では保持されていない
- `disconnect()`を呼ぶには別のアプローチが必要

---

## 8. updateVoiceState の理解

`updateVoiceState`は**汎用の状態変更API**であり、退出専用ではない。

| `channelId`の値 | 動作 |
|-----------------|------|
| `null` | ボイスチャンネルから**退出** |
| `Snowflake(ID)` | そのチャンネルに**移動/参加** |

```dart
// 退出処理
context.client.gateway.updateVoiceState(
  guildId,
  GatewayVoiceStateBuilder(
    channelId: null,  // ← null で退出
    isMuted: false,
    isDeafened: false,
  ),
);
```

---

## 9. context.client の活用

`ChatContext`から直接Discord clientにアクセス可能。

```dart
// コマンドハンドラ内で client にアクセス
context.client.gateway.updateVoiceState(...);
context.client.user.id  // ボット自身のID
```

これにより、`client`変数の定義位置に関係なくアクセスできる。

---

## 10. 防御的プログラミング

VoiceStateのチェックは**2つの条件**が必要：

```dart
if (botVoiceState == null || botVoiceState.channel == null) {
  // ボットがVCに参加していない
}
```

| 状態 | `botVoiceState` | `.channel` |
|------|-----------------|------------|
| 一度もVC参加なし | `null` | — |
| 過去に参加、今は退出済み | オブジェクトあり | `null` |
| 現在VCに参加中 | オブジェクトあり | IDあり |

**教訓**: キャッシュに過去の状態が残っている可能性を考慮する。

---

## 11. スコープの理解

`addCommand()`はハンドラの**外**で1回だけ呼ぶ。

```dart
// ❌ 間違い（ハンドラの中）
final leaveCommand = ChatCommand(..., () async {
    commands.addCommand(leaveCommand);  // 実行のたびに追加しようとする
});

// ✅ 正しい（ハンドラの外）
final leaveCommand = ChatCommand(..., () async { ... });
commands.addCommand(leaveCommand);
```

---

## 12. /leave コマンドの最終コード

```dart
final leaveCommand = ChatCommand('leave', 'ボットを音声チャンネルから退出させます', (
  ChatContext context,
) async {
  final guild = context.guild;
  if (guild == null) {
    context.respond(MessageBuilder(content: "サーバー内のみ有効なコマンドです。"));
    return;
  }
  final guildId = guild.id;

  // フルGuild取得（voiceStatesにアクセスするため）
  final fullGuild = await guild.get();
  final botVoiceState = fullGuild.voiceStates[context.client.user.id];

  // 防御的チェック
  if (botVoiceState == null || botVoiceState.channel == null) {
    context.respond(MessageBuilder(content: "音声チャンネルにBotがいません!"));
    return;
  }

  // 退出処理（channelId: null で退出）
  context.client.gateway.updateVoiceState(
    guildId,
    GatewayVoiceStateBuilder(
      channelId: null,
      isMuted: false,
      isDeafened: false,
    ),
  );
  context.respond(MessageBuilder(content: "退出しました!"));
});
commands.addCommand(leaveCommand);
```

---

## 参考リンク（追加）

- [nyxx_lavalink LavalinkPlayer.disconnect](https://pub.dev/documentation/nyxx_lavalink/4.0.0-dev.1/nyxx_lavalink/LavalinkPlayer/disconnect.html)
- [nyxx GatewayVoiceStateBuilder](https://pub.dev/documentation/nyxx/6.7.0/nyxx/GatewayVoiceStateBuilder-class.html)

---

# 学習ログ: /disconnect コマンドの実装（正攻法）

**日付**: 2025-12-23  
**トピック**: LavalinkPlayer.disconnect() を使った退出処理

---

## 13. 状態管理: コマンド間でデータを共有する

複数のコマンドで同じデータにアクセスするには、**グローバルスコープで変数を保持**する必要がある。

```dart
// mainスコープに定義（コマンド定義の前）
final Map<Snowflake, LavalinkPlayer> players = {};
```

### なぜ Map<Snowflake, LavalinkPlayer> か？

| 要件 | 解決策 |
|------|--------|
| 複数ギルドで同時に使われる可能性 | `guildId`をキーにする |
| summonとdisconnect両方からアクセス | グローバルスコープに配置 |
| 素早く検索したい | Mapで O(1) アクセス |

---

## 14. ライフサイクル管理

Playerオブジェクトには**ライフサイクル**がある：

```
作成（summon）→ 使用（play等）→ 削除（disconnect）
```

```dart
// summon時：作成して保存
final player = await voiceChannel.connectLavalink();
players[guild.id] = player;

// disconnect時：使用して削除
await player.disconnect();
players.remove(guildId);  // ← 忘れずに削除！
```

**教訓**: 作成したリソースは、使い終わったら必ずクリーンアップする。

---

## 15. 2つのアプローチの比較

| 項目 | `/leave`（updateVoiceState） | `/disconnect`（LavalinkPlayer） |
|------|------------------------------|--------------------------------|
| 状態管理 | 不要 | `Map<Snowflake, LavalinkPlayer>`必要 |
| Lavalinkとの整合性 | 手動でDiscordへ通知のみ | Lavalink側も正しくクリーンアップ |
| 複雑さ | シンプル | やや複雑 |
| 正攻法 | △（ワークアラウンド） | ✅（設計意図通り） |

### どちらを使うべきか？

- **簡易実装**: `/leave`（updateVoiceState）で十分
- **本格実装**: `/disconnect`（LavalinkPlayer）を推奨。将来的に queue 管理等をする場合、Player オブジェクトへの参照が必要になる

---

## 16. /disconnect コマンドの最終コード

```dart
// グローバルスコープ
final Map<Snowflake, LavalinkPlayer> players = {};

// summonCommand 内（変更箇所）
final player = await voiceChannel.connectLavalink();
players[guild.id] = player;

// disconnectCommand
final disconnectCommand = ChatCommand(
  'disconnect',
  'ボットを音声チャンネルから退出させます',
  (ChatContext context) async {
    final guild = context.guild;
    if (guild == null) {
      context.respond(MessageBuilder(content: "サーバー内のみ有効なコマンドです。"));
      return;
    }
    final guildId = guild.id;

    final player = players[guildId];
    if (player == null) {
      context.respond(MessageBuilder(content: "音声チャンネルに参加していません!"));
      return;
    }

    await player.disconnect();
    players.remove(guildId);
    context.respond(MessageBuilder(content: "退出しました！"));
  },
);
commands.addCommand(disconnectCommand);
```
