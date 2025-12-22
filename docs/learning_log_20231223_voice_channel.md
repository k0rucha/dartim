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
