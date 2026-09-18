import 'package:cnc_partner/core/notifications/notifications_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// An empty inbox and an inbox that failed to load are different things.
///
/// The screen's empty state reads "You're all caught up". Rendering that after
/// a failed fetch tells a partner there is no work waiting — and offers are
/// how they earn, so it is the worst way for this screen to be wrong.
void main() {
  group('NotifState', () {
    test('a fresh state has no error', () {
      const s = NotifState();
      expect(s.error, isNull);
      expect(s.items, isEmpty);
    });

    test('a failure is recorded so the screen can tell the two apart', () {
      const s = NotifState();
      final failed = s.copyWith(error: 'No internet connection');
      expect(failed.error, 'No internet connection');
      // Still empty — which is exactly why the flag has to exist: without it
      // this state is indistinguishable from a genuinely empty inbox.
      expect(failed.items, isEmpty);
    });

    test('copyWith carries an existing error forward', () {
      const s = NotifState(error: 'Timed out');
      expect(s.copyWith(loadingMore: true).error, 'Timed out');
    });

    test('clearError is the only way to drop it', () {
      // copyWith cannot express "set this to null" through a nullable
      // parameter, and every success path needs to.
      const s = NotifState(error: 'Timed out');
      expect(s.copyWith(clearError: true).error, isNull);
    });

    test('unread counts only what is actually unread', () {
      const s = NotifState();
      expect(s.unread, 0);
    });
  });
}
