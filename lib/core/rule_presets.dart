import 'activity.dart';

/// Editable suggestions, never automatically persisted or enforced.
/// Identifier references and coverage limits: docs/rule-presets.md.
class RulePreset {
  const RulePreset(this.name, this.sources, {this.isCategory = false});

  final String name;
  final Set<String> sources;

  /// A whole category (Social media, Games...) sharing one daily limit.
  final bool isCategory;
  int get dailyMinutes => 30;
}

const individualRulePresets = [
  RulePreset('Instagram', {
    'web:instagram.com',
    'android:com.instagram.android',
  }),
  RulePreset('YouTube', {
    'web:youtube.com',
    'web:youtu.be',
    'android:com.google.android.youtube',
  }),
  RulePreset('TikTok', {
    'web:tiktok.com',
    'android:com.zhiliaoapp.musically',
    'android:com.ss.android.ugc.trill',
  }),
  RulePreset('Reddit', {
    'web:reddit.com',
    'web:redd.it',
    'android:com.reddit.frontpage',
  }),
  RulePreset('X', {
    'web:x.com',
    'web:twitter.com',
    'android:com.twitter.android',
  }),
  RulePreset('Facebook', {'web:facebook.com', 'android:com.facebook.katana'}),
  RulePreset('Snapchat', {'web:snapchat.com', 'android:com.snapchat.android'}),
  RulePreset('Twitch', {'web:twitch.tv', 'android:tv.twitch.android.app'}),
  RulePreset('Discord', {
    'web:discord.com',
    'android:com.discord',
    'windows:discord.exe',
    'windows:discordptb.exe',
    'windows:discordcanary.exe',
  }),
  RulePreset('WhatsApp', {
    'web:whatsapp.com',
    'android:com.whatsapp',
    'windows:whatsapp.exe',
    'windows:whatsapp.root.exe',
  }),
  RulePreset('Telegram', {
    'web:telegram.org',
    'web:t.me',
    'android:org.telegram.messenger',
    'windows:telegram.exe',
  }),
  RulePreset('Signal', {
    'android:org.thoughtcrime.securesms',
    'windows:signal.exe',
  }),
  RulePreset('Messenger', {'web:messenger.com', 'android:com.facebook.orca'}),
  RulePreset('LinkedIn', {'web:linkedin.com', 'android:com.linkedin.android'}),
  RulePreset('Pinterest', {'web:pinterest.com', 'android:com.pinterest'}),
  RulePreset('Threads', {
    'web:threads.com',
    'web:threads.net',
    'android:com.instagram.barcelona',
  }),
  RulePreset('Bluesky', {'web:bsky.app', 'android:xyz.blueskyweb.app'}),
];

/// Offer missing native coverage without silently broadening existing rules.
Set<String> missingDesktopSources(Iterable<String> sources) {
  final current = sources.toSet();
  return {
    for (final preset in individualRulePresets)
      if (preset.sources.any(
        (candidate) =>
            current.any((source) => matchesSource(candidate, source)),
      ))
        for (final source in preset.sources)
          if (source.startsWith('windows:') &&
              !current.any((existing) => matchesSource(source, existing)))
            source,
  };
}
