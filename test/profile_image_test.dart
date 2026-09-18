import 'package:cnc_partner/core/profile/profile_image_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The avatar shown on the app bar and the profile header.
///
/// It lives in memory, not in storage, so wiping prefs on sign-out left the
/// PREVIOUS user's photo on screen until something happened to overwrite it.
/// On a shared or handed-on handset that is someone else's face on the next
/// person's screen, which is why sign-out now clears it explicitly.
void main() {
  group('ProfileImageNotifier.urlFor', () {
    test('null and empty clear the avatar', () {
      // This is the sign-out path: setFromFilename(null) must resolve to no
      // image, not to a URL pointing at the API root.
      expect(ProfileImageNotifier.urlFor(null), isNull);
      expect(ProfileImageNotifier.urlFor(''), isNull);
    });

    test('an absolute URL is left alone', () {
      const u = 'https://cdn.example.com/a.jpg';
      expect(ProfileImageNotifier.urlFor(u), u);
    });

    test('an uploads path is qualified against the API host', () {
      final r = ProfileImageNotifier.urlFor('/uploads/x.png');
      expect(r, isNotNull);
      expect(r!.endsWith('/uploads/x.png'), isTrue);
      expect(r.startsWith('http'), isTrue);
    });

    test('a bare filename is treated as an upload', () {
      final r = ProfileImageNotifier.urlFor('x.png');
      expect(r, isNotNull);
      expect(r!.endsWith('/uploads/x.png'), isTrue);
    });
  });
}
