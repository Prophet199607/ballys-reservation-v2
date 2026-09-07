import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which tone a chat message notification makes.
///
/// Android carries the sound on the notification channel, and a channel's
/// sound is frozen the moment it is created — deleting and recreating one
/// under the same id gives it back its old sound. So each choice gets its own
/// channel ([ChatNotificationSound.channelKey]) and the setting simply decides
/// which channel the notification is posted to.
enum ChatNotificationSound {
  /// The app's own tone, `assets/sounds/messageReceiveNotification.mp3`
  /// (shipped to Android as `res/raw/message_receive_notification.mp3`).
  appTone,

  /// Whatever the phone plays for a notification.
  phoneDefault;

  /// Android channel that carries this tone.
  String get channelKey => this == ChatNotificationSound.appTone
      ? ChatNotificationSoundStore.toneChannelKey
      : ChatNotificationSoundStore.defaultChannelKey;

  String get label =>
      this == ChatNotificationSound.appTone ? 'My Tone' : 'Phone default';

  String get description => this == ChatNotificationSound.appTone
      ? 'The tone that ships with the app'
      : 'The notification sound set on this phone';
}

/// Reads and writes the choice, and plays the tone in-app.
///
/// Kept out of the Riverpod provider because [NotificationService] — a plain
/// singleton that also runs in the background isolate — has to read the same
/// value when a push arrives.
class ChatNotificationSoundStore {
  ChatNotificationSoundStore._();

  static const _prefsKey = 'chatNotificationSound';

  /// Channel keys. The suffix is a version marker: a channel's sound cannot be
  /// changed once Android has seen it, so a future change of tone needs a new
  /// key here rather than an edit to the existing channel.
  static const toneChannelKey = 'chat_message_tone_v1';
  static const defaultChannelKey = 'chat_message_default_v1';

  /// The tone as Android resolves it on the channel — no file extension.
  static const androidSoundResource =
      'resource://raw/message_receive_notification';

  static const assetPath = 'assets/sounds/messageReceiveNotification.mp3';

  static const ChatNotificationSound fallback = ChatNotificationSound.appTone;

  /// Last value read from disk, so the push path does not have to wait on
  /// SharedPreferences before it can pick a channel.
  static ChatNotificationSound _cached = fallback;

  static ChatNotificationSound get current => _cached;

  static Future<ChatNotificationSound> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      _cached = stored == 'phoneDefault'
          ? ChatNotificationSound.phoneDefault
          : fallback;
    } catch (e) {
      print('Error reading chat notification sound: $e');
    }
    return _cached;
  }

  static Future<void> save(ChatNotificationSound sound) async {
    _cached = sound;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, sound.name);
    } catch (e) {
      print('Error saving chat notification sound: $e');
    }
  }

  /// Plays the app tone through the media output.
  ///
  /// Used where no notification is posted and so no channel sound fires: the
  /// settings screen preview, a message for the conversation already on screen,
  /// and iOS in the foreground (where the banner — and its sound — is
  /// suppressed and only the badge is updated). The phone's own notification
  /// sound is not reachable from Dart, so [ChatNotificationSound.phoneDefault]
  /// stays silent on these paths and is heard on the notification itself.
  static Future<void> playPreview() async {
    final player = AudioPlayer();
    try {
      await player.setAsset(assetPath);
      await player.play();
    } catch (e) {
      print('Error playing chat notification tone: $e');
    } finally {
      await player.dispose();
    }
  }

  /// [playPreview], but only when the user is on the app tone.
  static Future<void> playIfAppTone() async {
    if (_cached == ChatNotificationSound.appTone) {
      await playPreview();
    }
  }
}
