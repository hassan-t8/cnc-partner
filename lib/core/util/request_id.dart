import 'dart:math';

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
final _rand = Random();

/// Mints an idempotency key for a money-moving request (deposit, withdraw,
/// partner-unassign).
///
/// Two rules the server cares about:
///
///  * **Length.** The money kernel validates ids against
///    `^[a-zA-Z0-9-]{32,64}$` and rejects a shorter one with a hard 400 rather
///    than rewriting it. The old minters produced 20-27 chars, which is a 400
///    waiting to happen as the backend tightens more routes onto that kernel.
///  * **Stability.** The id is the dedup anchor, so it must be minted ONCE per
///    user intent (a `late final` field on the form), never per attempt — a
///    retry after a network drop has to resend the SAME id or the server opens
///    a second checkout / second request.
String newRequestId(String prefix) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _rand.nextInt(1 << 32).toRadixString(36);
  var id = '$prefix-$ts-$r'.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');
  while (id.length < 32) {
    id += _alphabet[_rand.nextInt(_alphabet.length)];
  }
  return id.length > 64 ? id.substring(0, 64) : id;
}
