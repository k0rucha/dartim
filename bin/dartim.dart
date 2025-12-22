import 'package:dotenv/dotenv.dart';
import 'package:nyxx/nyxx.dart';
import 'package:nyxx_commands/nyxx_commands.dart';
import 'package:nyxx_lavalink/nyxx_lavalink.dart';

void main() async {
  print('Hello world!');

  // Load .env
  var env = DotEnv(includePlatformEnvironment: true)..load();

  // envからdiscord tokenを取り出す
  final botToken = env['DISCORD_TOKEN'];
  // botTokenの定義時エラーハンドリング
  if (botToken == null) {
    throw Exception(".envにDISCORD_TOKENが定義されていませんでした");
  }

  final commands = CommandsPlugin(
    prefix: null,
    guild: Snowflake(868799385096572968),
    options: CommandsOptions(logErrors: true),
  );

  final lavalink = LavalinkPlugin(
    base: Uri.http("localhost:2333"),
    password: "lavalinkpass",
  );

  final pingCommand = ChatCommand('ping', 'BotがPong!と返します', (
    ChatContext context,
  ) async {
    context.respond(MessageBuilder(content: 'Pong!'));
  });

  commands.addCommand(pingCommand);






  final summonCommand = ChatCommand('summon', 'ボットを音声チャンネルに参加させます', (
    ChatContext context,
  ) async {
    final member = context.member; // コマンドを送信したユーザーのIDをここで取得してる

    if (member == null) {
      context.respond(MessageBuilder(content: "あなたが誰なのか私にはわかりません。"));
      return;
    }

    final guild = await context.guild?.get();
    final voiceState = guild?.voiceStates[member.id];

    // voiceState.channel は PartialChannel（IDのみ）
    // .get() で Discord API から完全な Channel 情報を取得
    final voiceChannel = await voiceState?.channel?.get();

    if (voiceChannel == null) {
      context.respond(MessageBuilder(content: "Channelの取得に失敗しました"));
      return;
    }

    // VoiceChannel は抽象型なので、GuildVoiceChannel にキャストする必要があります
    if (voiceChannel is! GuildVoiceChannel) {
      context.respond(MessageBuilder(content: "ボイスチャンネルではありません"));
      return;
    }

    // スマートキャストにより voiceChannel は GuildVoiceChannel 型として扱われる
    await voiceChannel.connectLavalink();
    context.respond(MessageBuilder(content: "${voiceChannel.name} に参加しました！"));
  });

  commands.addCommand(summonCommand);








  // discord bot仕様のintentsを設定
  // GatewayIntentsにはたくさんの権限フラグが用意されている
  // 今回はallUnprivileged(許可不要なやつ全部)とmessageContent(メッセージの中身をみれる)を設定
  // messageContentを別で書いた理由はprivilegedという許可が必要な特権だから。
  final intents =
      GatewayIntents.allUnprivileged | GatewayIntents.messageContent;

  print("Connecting...");
  final client = await Nyxx.connectGateway(
    botToken,
    intents,
    options: GatewayClientOptions(plugins: [commands, lavalink]),
  );
  // clientの接続を確立しただけだと、client.userはidまでしか取得できない。
  // そこで、client.user.get()でuserの情報を取得する。
  final botInfo = await client.user.get();
  print("logged in as ${botInfo.username}");
}
