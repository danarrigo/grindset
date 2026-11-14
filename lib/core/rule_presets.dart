/// Editable suggestions, never automatically persisted or enforced.
/// Package references and maintenance notes: docs/rule-presets.md.
class RulePreset {
  const RulePreset(this.name, this.sources);

  final String name;
  final Set<String> sources;
  int get dailyMinutes => 30;
}

const rulePresets = [
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
  RulePreset('Discord', {'web:discord.com', 'android:com.discord'}),
];
