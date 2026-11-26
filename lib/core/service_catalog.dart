import 'activity.dart';
import 'rule_presets.dart';

/// A service people know by name, with the apps and websites it uses.
/// Bundled and offline: choosing from it makes no network requests.
class CatalogService {
  const CatalogService(
    this.name,
    this.category,
    this.sources, {
    this.aliases = const [],
    this.logo,
  });
  final String name;
  final String category;
  final Set<String> sources;

  /// Other names people search for ("ig", "twitter", "gmail").
  final List<String> aliases;

  /// The site to take the logo from when [sources] has no website.
  final String? logo;
}

/// A company's services offered as one choice, each part removable.
class CatalogFamily {
  const CatalogFamily(
    this.name,
    this.host,
    this.members, {
    this.aliases = const [],
  });
  final String name;

  /// The company's own website, for its logo.
  final String host;
  final List<String> members;
  final List<String> aliases;

  List<CatalogService> get services => [
    for (final member in members) serviceNamed(member)!,
  ];
  Set<String> get sources => {for (final s in services) ...s.sources};
}

const _social = 'Social';
const _messaging = 'Messaging';
const _video = 'Video';
const _music = 'Music and audio';
const _games = 'Games';
const _shopping = 'Shopping';
const _news = 'News and reading';
const _ai = 'AI chat';
const _browser = 'Whole browser';
const _dating = 'Dating';
const _work = 'Work and school';
const _tools = 'Tools';

const _presetDetails = <String, (String, List<String>)>{
  'Instagram': (_social, ['ig', 'insta']),
  'YouTube': (_video, ['yt']),
  'TikTok': (_social, ['tik tok', 'tt']),
  'Reddit': (_social, []),
  'X': (_social, ['twitter', 'tweet']),
  'Facebook': (_social, ['fb']),
  'Snapchat': (_social, ['snap']),
  'Twitch': (_video, []),
  'Discord': (_messaging, []),
  'WhatsApp': (_messaging, ['wa', 'whats app']),
  'Telegram': (_messaging, []),
  'Signal': (_messaging, []),
  'Messenger': (_messaging, ['facebook messenger']),
  'LinkedIn': (_social, []),
  'Pinterest': (_social, []),
  'Threads': (_social, []),
  'Bluesky': (_social, ['bsky']),
};

/// Whole categories offered as one-tap starters, in this order. Browsers,
/// work and everyday tools are left out: blocking them wholesale breaks too much.
final List<RulePreset> categoryPresets = List.unmodifiable([
  for (final (category, name) in const [
    (_social, 'Social media'),
    (_messaging, 'Messaging'),
    (_video, 'Video and streaming'),
    (_games, 'Games'),
    (_shopping, 'Shopping'),
    (_news, 'News and reading'),
    (_ai, 'AI chat'),
    (_dating, 'Dating'),
    (_music, 'Music and audio'),
  ])
    RulePreset(name, {
      for (final service in catalogServices)
        if (service.category == category) ...service.sources,
    }, isCategory: true),
]);

final List<CatalogService> catalogServices = List.unmodifiable([
  for (final preset in individualRulePresets)
    CatalogService(
      preset.name,
      _presetDetails[preset.name]!.$1,
      preset.sources,
      aliases: _presetDetails[preset.name]!.$2,
      logo: preset.name == 'Signal' ? 'signal.org' : null,
    ),
  // Google
  const CatalogService(
    'Google Search',
    _tools,
    {'web:google.com', 'android:com.google.android.googlequicksearchbox'},
    aliases: ['google', 'search'],
  ),
  const CatalogService(
    'Gmail',
    _tools,
    {'web:gmail.com', 'web:mail.google.com', 'android:com.google.android.gm'},
    aliases: ['google mail', 'email'],
  ),
  const CatalogService(
    'YouTube Music',
    _music,
    {'web:music.youtube.com', 'android:com.google.android.apps.youtube.music'},
    aliases: ['yt music'],
  ),
  const CatalogService(
    'Google Maps',
    _tools,
    {'android:com.google.android.apps.maps'},
    aliases: ['maps'],
    logo: 'maps.google.com',
  ),
  const CatalogService(
    'Google Drive',
    _tools,
    {'web:drive.google.com', 'android:com.google.android.apps.docs'},
    aliases: ['drive'],
  ),
  const CatalogService(
    'Google Docs, Sheets and Slides',
    _work,
    {
      'web:docs.google.com',
      'android:com.google.android.apps.docs.editors.docs',
      'android:com.google.android.apps.docs.editors.sheets',
      'android:com.google.android.apps.docs.editors.slides',
    },
    aliases: ['docs', 'sheets', 'slides'],
  ),
  const CatalogService('Google Photos', _tools, {
    'web:photos.google.com',
    'android:com.google.android.apps.photos',
  }),
  const CatalogService('Google News', _news, {
    'web:news.google.com',
    'android:com.google.android.apps.magazines',
  }),
  const CatalogService(
    'Google Play Store',
    _tools,
    {'web:play.google.com', 'android:com.android.vending'},
    aliases: ['play store', 'google play'],
  ),
  const CatalogService(
    'Gemini',
    _ai,
    {'web:gemini.google.com', 'android:com.google.android.apps.bard'},
    aliases: ['bard', 'google ai'],
  ),
  const CatalogService(
    'Google Translate',
    _tools,
    {'web:translate.google.com', 'android:com.google.android.apps.translate'},
    aliases: ['translate'],
  ),
  // Microsoft
  const CatalogService('Bing', _tools, {
    'web:bing.com',
    'android:com.microsoft.bing',
  }),
  const CatalogService(
    'Outlook',
    _work,
    {
      'web:outlook.com',
      'web:outlook.live.com',
      'web:outlook.office.com',
      'android:com.microsoft.office.outlook',
      'windows:outlook.exe',
      'windows:olk.exe',
    },
    aliases: ['hotmail', 'email'],
  ),
  const CatalogService(
    'Microsoft Teams',
    _work,
    {
      'web:teams.microsoft.com',
      'web:teams.live.com',
      'android:com.microsoft.teams',
      'windows:ms-teams.exe',
      'windows:teams.exe',
    },
    aliases: ['teams'],
  ),
  const CatalogService(
    'Microsoft 365',
    _work,
    {
      'web:office.com',
      'web:microsoft365.com',
      'android:com.microsoft.office.officehubrow',
    },
    aliases: ['office'],
  ),
  const CatalogService(
    'Word',
    _work,
    {'android:com.microsoft.office.word', 'windows:winword.exe'},
    aliases: ['microsoft word'],
    logo: 'microsoft365.com',
  ),
  const CatalogService(
    'Excel',
    _work,
    {'android:com.microsoft.office.excel', 'windows:excel.exe'},
    aliases: ['microsoft excel'],
    logo: 'microsoft365.com',
  ),
  const CatalogService(
    'PowerPoint',
    _work,
    {'android:com.microsoft.office.powerpoint', 'windows:powerpnt.exe'},
    aliases: ['microsoft powerpoint', 'ppt'],
    logo: 'microsoft365.com',
  ),
  const CatalogService('OneDrive', _tools, {
    'web:onedrive.live.com',
    'android:com.microsoft.skydrive',
  }),
  const CatalogService(
    'Copilot',
    _ai,
    {'web:copilot.microsoft.com', 'android:com.microsoft.copilot'},
    aliases: ['microsoft copilot'],
  ),
  const CatalogService('Xbox', _games, {
    'web:xbox.com',
    'android:com.microsoft.xboxone.smartglass',
    'windows:xboxpcapp.exe',
  }),
  const CatalogService('Skype', _messaging, {
    'web:skype.com',
    'android:com.skype.raider',
    'windows:skype.exe',
  }),
  const CatalogService('Minecraft', _games, {
    'web:minecraft.net',
    'android:com.mojang.minecraftpe',
    'windows:minecraft.windows.exe',
    'windows:minecraftlauncher.exe',
  }),
  // Amazon
  const CatalogService(
    'Amazon',
    _shopping,
    {
      'web:amazon.com',
      'web:amazon.co.uk',
      'web:amazon.de',
      'web:amazon.co.jp',
      'web:amazon.in',
      'web:amazon.ca',
      'android:com.amazon.mShop.android.shopping',
    },
    aliases: ['amazon shopping'],
  ),
  const CatalogService(
    'Prime Video',
    _video,
    {'web:primevideo.com', 'android:com.amazon.avod.thirdpartyclient'},
    aliases: ['amazon prime', 'prime'],
  ),
  const CatalogService(
    'Audible',
    _music,
    {'web:audible.com', 'android:com.audible.application'},
    aliases: ['audiobooks'],
  ),
  const CatalogService(
    'Kindle',
    _news,
    {'web:read.amazon.com', 'android:com.amazon.kindle', 'windows:kindle.exe'},
    aliases: ['ebooks'],
  ),
  // Video
  const CatalogService('Netflix', _video, {
    'web:netflix.com',
    'android:com.netflix.mediaclient',
  }),
  const CatalogService(
    'Disney+',
    _video,
    {'web:disneyplus.com', 'android:com.disney.disneyplus'},
    aliases: ['disney', 'disney plus'],
  ),
  const CatalogService('Hulu', _video, {
    'web:hulu.com',
    'android:com.hulu.plus',
  }),
  const CatalogService(
    'Max',
    _video,
    {'web:max.com', 'web:hbomax.com', 'android:com.wbd.stream'},
    aliases: ['hbo', 'hbo max'],
  ),
  const CatalogService(
    'Crunchyroll',
    _video,
    {'web:crunchyroll.com', 'android:com.crunchyroll.crunchyroid'},
    aliases: ['anime'],
  ),
  const CatalogService('Vimeo', _video, {
    'web:vimeo.com',
    'android:com.vimeo.android.videoapp',
  }),
  const CatalogService('Dailymotion', _video, {
    'web:dailymotion.com',
    'android:com.dailymotion.dailymotion',
  }),
  const CatalogService('Kick', _video, {'web:kick.com'}),
  const CatalogService('Plex', _video, {
    'web:plex.tv',
    'android:com.plexapp.android',
    'windows:plex.exe',
  }),
  const CatalogService('Peacock', _video, {
    'web:peacocktv.com',
    'android:com.peacocktv.peacockandroid',
  }),
  const CatalogService(
    'Paramount+',
    _video,
    {'web:paramountplus.com', 'android:com.cbs.app'},
    aliases: ['paramount', 'paramount plus'],
  ),
  const CatalogService('Tubi', _video, {
    'web:tubitv.com',
    'android:com.tubitv',
  }),
  const CatalogService('Apple TV', _video, {'web:tv.apple.com'}),
  const CatalogService('Bilibili', _video, {
    'web:bilibili.com',
    'web:bilibili.tv',
    'android:tv.danmaku.bili',
    'android:com.bstar.intl',
  }),
  const CatalogService('Viu', _video, {
    'web:viu.com',
    'android:com.vuclip.viu',
  }),
  const CatalogService('Vidio', _video, {
    'web:vidio.com',
    'android:com.vidio.android',
  }),
  const CatalogService('iQIYI', _video, {
    'web:iq.com',
    'android:com.iqiyi.i18n',
  }),
  const CatalogService('WeTV', _video, {
    'web:wetv.vip',
    'android:com.tencent.qqlivei18n',
  }),
  // Music and audio
  const CatalogService('Spotify', _music, {
    'web:spotify.com',
    'android:com.spotify.music',
    'windows:spotify.exe',
  }),
  const CatalogService('SoundCloud', _music, {
    'web:soundcloud.com',
    'android:com.soundcloud.android',
  }),
  const CatalogService('Apple Music', _music, {
    'web:music.apple.com',
    'android:com.apple.android.music',
  }),
  const CatalogService('Deezer', _music, {
    'web:deezer.com',
    'android:deezer.android.app',
  }),
  const CatalogService(
    'Pocket Casts',
    _music,
    {'web:pocketcasts.com', 'android:au.com.shiftyjelly.pocketcasts'},
    aliases: ['podcasts'],
  ),
  // Social
  const CatalogService('Tumblr', _social, {
    'web:tumblr.com',
    'android:com.tumblr',
  }),
  const CatalogService('Quora', _social, {
    'web:quora.com',
    'android:com.quora.android',
  }),
  const CatalogService(
    'VK',
    _social,
    {'web:vk.com', 'android:com.vkontakte.android'},
    aliases: ['vkontakte'],
  ),
  const CatalogService('Weibo', _social, {
    'web:weibo.com',
    'android:com.sina.weibo',
  }),
  const CatalogService(
    '9GAG',
    _social,
    {'web:9gag.com', 'android:com.ninegag.android.app'},
    aliases: ['memes'],
  ),
  const CatalogService('BeReal', _social, {
    'web:bereal.com',
    'android:com.bereal.ft',
  }),
  const CatalogService('Lemon8', _social, {
    'web:lemon8-app.com',
    'android:com.bd.nproject',
  }),
  const CatalogService('Likee', _social, {
    'web:likee.video',
    'android:video.like',
  }),
  const CatalogService('Kwai', _social, {
    'web:kwai.com',
    'android:com.kwai.video',
  }),
  const CatalogService('Mastodon', _social, {
    'web:mastodon.social',
    'android:org.joinmastodon.android',
  }),
  const CatalogService('Imgur', _social, {
    'web:imgur.com',
    'android:com.imgur.mobile',
  }),
  // Dating
  const CatalogService('Tinder', _dating, {
    'web:tinder.com',
    'android:com.tinder',
  }),
  const CatalogService('Bumble', _dating, {
    'web:bumble.com',
    'android:com.bumble.app',
  }),
  const CatalogService('Hinge', _dating, {
    'web:hinge.co',
    'android:co.hinge.app',
  }),
  // Messaging
  const CatalogService('LINE', _messaging, {
    'web:line.me',
    'android:jp.naver.line.android',
    'windows:line.exe',
  }),
  const CatalogService('Viber', _messaging, {
    'web:viber.com',
    'android:com.viber.voip',
    'windows:viber.exe',
  }),
  const CatalogService(
    'WeChat',
    _messaging,
    {
      'web:wechat.com',
      'android:com.tencent.mm',
      'windows:wechat.exe',
      'windows:weixin.exe',
    },
    aliases: ['weixin'],
  ),
  const CatalogService(
    'KakaoTalk',
    _messaging,
    {'android:com.kakao.talk', 'windows:kakaotalk.exe'},
    aliases: ['kakao'],
    logo: 'kakaocorp.com',
  ),
  const CatalogService('Slack', _work, {
    'web:slack.com',
    'android:com.Slack',
    'windows:slack.exe',
  }),
  const CatalogService('Zoom', _work, {
    'web:zoom.us',
    'android:us.zoom.videomeetings',
    'windows:zoom.exe',
  }),
  // Games
  const CatalogService('Steam', _games, {
    'web:steampowered.com',
    'web:steamcommunity.com',
    'android:com.valvesoftware.android.steam.community',
    'windows:steam.exe',
  }),
  const CatalogService(
    'Epic Games',
    _games,
    {'web:epicgames.com', 'windows:epicgameslauncher.exe'},
    aliases: ['epic'],
  ),
  const CatalogService('Roblox', _games, {
    'web:roblox.com',
    'android:com.roblox.client',
    'windows:robloxplayerbeta.exe',
  }),
  const CatalogService('Fortnite', _games, {
    'web:fortnite.com',
    'windows:fortniteclient-win64-shipping.exe',
  }),
  const CatalogService(
    'League of Legends',
    _games,
    {
      'web:leagueoflegends.com',
      'windows:leagueclient.exe',
      'windows:league of legends.exe',
    },
    aliases: ['lol', 'league'],
  ),
  const CatalogService('Valorant', _games, {
    'web:playvalorant.com',
    'windows:valorant-win64-shipping.exe',
  }),
  const CatalogService(
    'Riot Client',
    _games,
    {'windows:riotclientservices.exe'},
    aliases: ['riot'],
    logo: 'riotgames.com',
  ),
  const CatalogService(
    'Genshin Impact',
    _games,
    {'android:com.miHoYo.GenshinImpact', 'windows:genshinimpact.exe'},
    aliases: ['genshin'],
    logo: 'genshin.hoyoverse.com',
  ),
  const CatalogService(
    'Honkai: Star Rail',
    _games,
    {'android:com.HoYoverse.hkrpgoversea', 'windows:starrail.exe'},
    aliases: ['star rail', 'hsr'],
    logo: 'hsr.hoyoverse.com',
  ),
  const CatalogService(
    'PUBG',
    _games,
    {'android:com.tencent.ig', 'windows:tslgame.exe'},
    aliases: ['pubg mobile', 'battlegrounds'],
    logo: 'pubg.com',
  ),
  const CatalogService(
    'Mobile Legends',
    _games,
    {'android:com.mobile.legends'},
    aliases: ['mlbb', 'ml'],
    logo: 'mobilelegends.com',
  ),
  const CatalogService(
    'Free Fire',
    _games,
    {'android:com.dts.freefireth', 'android:com.dts.freefiremax'},
    aliases: ['ff'],
    logo: 'ff.garena.com',
  ),
  const CatalogService(
    'Clash of Clans',
    _games,
    {'android:com.supercell.clashofclans'},
    aliases: ['coc'],
    logo: 'clashofclans.com',
  ),
  const CatalogService('Clash Royale', _games, {
    'android:com.supercell.clashroyale',
  }),
  const CatalogService('Brawl Stars', _games, {
    'android:com.supercell.brawlstars',
  }),
  const CatalogService(
    'Candy Crush Saga',
    _games,
    {'android:com.king.candycrushsaga'},
    aliases: ['candy crush'],
    logo: 'clashroyale.com',
  ),
  const CatalogService(
    'Pokémon GO',
    _games,
    {'android:com.nianticlabs.pokemongo'},
    aliases: ['pokemon', 'pokemon go'],
    logo: 'brawlstars.com',
  ),
  const CatalogService(
    'Call of Duty',
    _games,
    {'android:com.activision.callofduty.shooter', 'windows:cod.exe'},
    aliases: ['cod', 'warzone'],
    logo: 'king.com',
  ),
  const CatalogService('Among Us', _games, {
    'android:com.innersloth.spacemafia',
    'windows:among us.exe',
  }),
  const CatalogService('Subway Surfers', _games, {
    'android:com.kiloo.subwaysurf',
  }),
  const CatalogService(
    'Chess.com',
    _games,
    {'web:chess.com', 'android:com.chess'},
    aliases: ['chess'],
    logo: 'pokemongolive.com',
  ),
  const CatalogService(
    'Lichess',
    _games,
    {'web:lichess.org', 'android:org.lichess.mobileV2'},
    aliases: ['chess'],
    logo: 'callofduty.com',
  ),
  const CatalogService(
    'Battle.net',
    _games,
    {'web:battle.net', 'windows:battle.net.exe'},
    aliases: ['blizzard'],
    logo: 'innersloth.com',
  ),
  const CatalogService(
    'EA app',
    _games,
    {'web:ea.com', 'windows:eadesktop.exe'},
    aliases: ['ea', 'origin'],
    logo: 'subwaysurfers.com',
  ),
  const CatalogService('Dota 2', _games, {'windows:dota2.exe'}),
  const CatalogService(
    'Counter-Strike 2',
    _games,
    {'windows:cs2.exe'},
    aliases: ['cs2', 'csgo', 'counter strike'],
    logo: 'dota2.com',
  ),
  const CatalogService(
    'osu!',
    _games,
    {'web:osu.ppy.sh', 'windows:osu!.exe'},
    aliases: ['osu'],
    logo: 'counter-strike.net',
  ),
  // Shopping
  const CatalogService('eBay', _shopping, {
    'web:ebay.com',
    'android:com.ebay.mobile',
  }),
  const CatalogService('AliExpress', _shopping, {
    'web:aliexpress.com',
    'android:com.alibaba.aliexpresshd',
  }),
  const CatalogService('Temu', _shopping, {
    'web:temu.com',
    'android:com.einnovation.temu',
  }),
  const CatalogService('Shein', _shopping, {
    'web:shein.com',
    'android:com.zzkko',
  }),
  const CatalogService('Shopee', _shopping, {
    'web:shopee.co.id',
    'web:shopee.com.my',
    'web:shopee.ph',
    'web:shopee.sg',
    'web:shopee.co.th',
    'web:shopee.vn',
    'web:shopee.tw',
    'web:shopee.com.br',
    'android:com.shopee.id',
    'android:com.shopee.my',
    'android:com.shopee.ph',
    'android:com.shopee.sg',
    'android:com.shopee.th',
    'android:com.shopee.vn',
    'android:com.shopee.tw',
    'android:com.shopee.br',
  }),
  const CatalogService('Tokopedia', _shopping, {
    'web:tokopedia.com',
    'android:com.tokopedia.tkpd',
  }),
  const CatalogService('Lazada', _shopping, {
    'web:lazada.co.id',
    'web:lazada.com.my',
    'web:lazada.com.ph',
    'web:lazada.sg',
    'web:lazada.co.th',
    'web:lazada.vn',
    'android:com.lazada.android',
  }),
  const CatalogService('Etsy', _shopping, {
    'web:etsy.com',
    'android:com.etsy.android',
  }),
  const CatalogService('Walmart', _shopping, {
    'web:walmart.com',
    'android:com.walmart.android',
  }),
  // News and reading
  const CatalogService('Medium', _news, {
    'web:medium.com',
    'android:com.medium.reader',
  }),
  const CatalogService(
    'Hacker News',
    _news,
    {'web:news.ycombinator.com'},
    aliases: ['hn', 'ycombinator'],
  ),
  const CatalogService(
    'BBC News',
    _news,
    {'web:bbc.com', 'web:bbc.co.uk', 'android:bbc.mobile.news.ww'},
    aliases: ['bbc'],
  ),
  const CatalogService('CNN', _news, {
    'web:cnn.com',
    'android:com.cnn.mobile.android.phone',
  }),
  const CatalogService(
    'The New York Times',
    _news,
    {'web:nytimes.com', 'android:com.nytimes.android'},
    aliases: ['nyt', 'new york times'],
  ),
  const CatalogService(
    'The Guardian',
    _news,
    {'web:theguardian.com', 'android:com.guardian'},
    aliases: ['guardian'],
  ),
  const CatalogService('Flipboard', _news, {
    'web:flipboard.com',
    'android:flipboard.app',
  }),
  const CatalogService(
    'Wikipedia',
    _news,
    {'web:wikipedia.org', 'android:org.wikipedia'},
    aliases: ['wiki'],
  ),
  const CatalogService(
    'Webtoon',
    _news,
    {'web:webtoons.com', 'android:com.naver.linewebtoon'},
    aliases: ['comics', 'manhwa'],
  ),
  const CatalogService('Wattpad', _news, {
    'web:wattpad.com',
    'android:wp.wattpad',
  }),
  const CatalogService('Substack', _news, {
    'web:substack.com',
    'android:com.substack.app',
  }),
  const CatalogService(
    'ESPN',
    _news,
    {'web:espn.com', 'android:com.espn.score_center'},
    aliases: ['sports'],
  ),
  const CatalogService('Detik', _news, {'web:detik.com'}),
  const CatalogService('Kompas', _news, {'web:kompas.com'}),
  // AI chat
  const CatalogService(
    'ChatGPT',
    _ai,
    {
      'web:chatgpt.com',
      'web:chat.openai.com',
      'android:com.openai.chatgpt',
      'windows:chatgpt.exe',
    },
    aliases: ['openai', 'gpt'],
  ),
  const CatalogService(
    'Claude',
    _ai,
    {'web:claude.ai', 'android:com.anthropic.claude', 'windows:claude.exe'},
    aliases: ['anthropic'],
  ),
  const CatalogService('Perplexity', _ai, {
    'web:perplexity.ai',
    'android:ai.perplexity.app.android',
  }),
  const CatalogService(
    'Character.AI',
    _ai,
    {'web:character.ai', 'android:ai.character.app'},
    aliases: ['character ai', 'c.ai'],
  ),
  const CatalogService('DeepSeek', _ai, {
    'web:deepseek.com',
    'android:com.deepseek.chat',
  }),
  const CatalogService('Grok', _ai, {'web:grok.com', 'android:ai.x.grok'}),
  // Whole browsers: blocks every website in them, so never part of a family.
  const CatalogService(
    'Chrome',
    _browser,
    {'android:com.android.chrome', 'windows:chrome.exe'},
    aliases: ['google chrome', 'browser'],
    logo: 'chrome.google.com',
  ),
  const CatalogService(
    'Microsoft Edge',
    _browser,
    {'android:com.microsoft.emmx', 'windows:msedge.exe'},
    aliases: ['edge', 'browser'],
    logo: 'microsoft.com',
  ),
  const CatalogService(
    'Firefox',
    _browser,
    {'android:org.mozilla.firefox', 'windows:firefox.exe'},
    aliases: ['mozilla', 'browser'],
    logo: 'firefox.com',
  ),
  const CatalogService(
    'Zen Browser',
    _browser,
    {'windows:zen.exe'},
    aliases: ['zen', 'browser'],
    logo: 'zen-browser.app',
  ),
  const CatalogService(
    'Brave',
    _browser,
    {'android:com.brave.browser', 'windows:brave.exe'},
    aliases: ['browser'],
    logo: 'brave.com',
  ),
  const CatalogService(
    'Opera',
    _browser,
    {'android:com.opera.browser', 'windows:opera.exe'},
    aliases: ['browser'],
    logo: 'opera.com',
  ),
  const CatalogService(
    'Samsung Internet',
    _browser,
    {'android:com.sec.android.app.sbrowser'},
    aliases: ['browser'],
    logo: 'samsung.com',
  ),
]);

const catalogFamilies = [
  CatalogFamily(
    'Google',
    'google.com',
    [
      'Google Search',
      'Gmail',
      'YouTube',
      'YouTube Music',
      'Google Maps',
      'Google Drive',
      'Google Docs, Sheets and Slides',
      'Google Photos',
      'Google News',
      'Google Play Store',
      'Gemini',
      'Google Translate',
    ],
    aliases: ['alphabet', 'all google'],
  ),
  CatalogFamily(
    'Microsoft',
    'microsoft.com',
    [
      'Bing',
      'Outlook',
      'Microsoft Teams',
      'Microsoft 365',
      'Word',
      'Excel',
      'PowerPoint',
      'OneDrive',
      'Copilot',
      'Xbox',
      'Skype',
      'LinkedIn',
      'Minecraft',
    ],
    aliases: ['all microsoft'],
  ),
  CatalogFamily(
    'Meta',
    'meta.com',
    ['Facebook', 'Instagram', 'WhatsApp', 'Messenger', 'Threads'],
    aliases: ['all meta', 'facebook family'],
  ),
  CatalogFamily(
    'Amazon',
    'amazon.com',
    ['Amazon', 'Prime Video', 'Twitch', 'Audible', 'Kindle'],
    aliases: ['all amazon'],
  ),
];

final Map<String, CatalogService> _byName = {
  for (final service in catalogServices) service.name: service,
};

CatalogService? serviceNamed(String name) => _byName[name];

/// Answers by identifier. The catalog never changes, and identifiers come
/// from the apps and sites seen, so this stays small.
final _serviceFor = <String, CatalogService?>{};

/// The service an identifier belongs to, if it is in the catalog. Asked for
/// every usage record when Activity is built, so answers are remembered.
CatalogService? serviceFor(String source) {
  if (_serviceFor.containsKey(source)) return _serviceFor[source];
  if (_serviceFor.length > 10000) _serviceFor.clear();
  return _serviceFor[source] = _findService(source);
}

CatalogService? _findService(String source) {
  if (source.startsWith('windows:')) source = source.toLowerCase();
  for (final service in catalogServices) {
    if (service.sources.contains(source)) return service;
  }
  if (!source.startsWith('web:')) return null;
  for (final service in catalogServices) {
    if (service.sources.any((s) => matchesSource(s, source))) return service;
  }
  return null;
}

String _plain(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// How well [query] matches a name or one of its aliases; lower is better,
/// null for no match.
int? _score(
  String query,
  String name,
  List<String> aliases,
  Set<String> sources,
) {
  final q = _plain(query);
  if (q.isEmpty) return null;
  final n = _plain(name);
  if (n == q) return 0;
  if (n.startsWith(q)) return 1;
  final a = aliases.map(_plain);
  if (a.any((alias) => alias == q)) return 1;
  if (a.any((alias) => alias.startsWith(q))) return 2;
  if (n.split(' ').any((word) => word.startsWith(q))) return 2;
  final compact = q.replaceAll(' ', '');
  if (sources.any(
    (s) =>
        s.startsWith('web:') &&
        s.substring(4).replaceAll('.', '').startsWith(compact),
  )) {
    return 3;
  }
  if (n.contains(q)) return 4;
  return null;
}

/// Catalog matches for a search, best first; families before services on a tie.
List<Object> searchCatalog(String query) {
  final scored = <(int, int, Object)>[];
  for (final family in catalogFamilies) {
    final score = _score(query, family.name, family.aliases, const {});
    if (score != null) scored.add((score, 0, family));
  }
  for (final service in catalogServices) {
    final score = _score(query, service.name, service.aliases, service.sources);
    if (score != null) scored.add((score, 1, service));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  return [for (final entry in scored) entry.$3];
}

/// The website whose logo stands for a source: a known service's main site,
/// otherwise the website itself. Apps outside the catalog have none.
String? logoHost(String source) {
  final service = serviceFor(source);
  final site =
      service?.sources.where((s) => s.startsWith('web:')).firstOrNull ??
      (source.startsWith('web:') ? source : null);
  return site != null ? websiteHost(site.substring(4)) : service?.logo;
}

/// The name people know a source by: its catalog service, or a readable
/// form of the identifier.
String sourceName(String source) {
  final service = serviceFor(source);
  if (service != null) return service.name;
  final raw = source.split(':').last;
  if (source.startsWith('windows:')) {
    return raw.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');
  }
  if (source.startsWith('android:')) {
    final last = raw.split('.').last;
    return last.isEmpty ? raw : last[0].toUpperCase() + last.substring(1);
  }
  return raw;
}
