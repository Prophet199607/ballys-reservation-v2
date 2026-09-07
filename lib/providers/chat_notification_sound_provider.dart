import 'package:ballys_reservation_app/utils/chat_notification_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tone chat notifications make, as picked on the chat settings screen.
///
/// The value itself lives in [ChatNotificationSoundStore] — the push handler
/// reads it without a Riverpod container — and this notifier only mirrors it
/// for the UI.
class ChatNotificationSoundNotifier
    extends StateNotifier<ChatNotificationSound> {
  ChatNotificationSoundNotifier() : super(ChatNotificationSoundStore.current) {
    _load();
  }

  Future<void> _load() async {
    final stored = await ChatNotificationSoundStore.load();
    if (mounted) state = stored;
  }

  Future<void> select(ChatNotificationSound sound) async {
    if (state == sound) return;
    state = sound;
    await ChatNotificationSoundStore.save(sound);
  }

  /// Lets the user hear the app tone before committing to it.
  Future<void> preview() => ChatNotificationSoundStore.playPreview();
}

final chatNotificationSoundProvider =
    StateNotifierProvider<ChatNotificationSoundNotifier, ChatNotificationSound>(
      (ref) => ChatNotificationSoundNotifier(),
    );
