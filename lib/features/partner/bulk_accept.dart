import '../../core/network/api_client.dart';

/// Progress / outcome of an "Accept all" run on the Requests screen.
class BulkAcceptProgress {
  const BulkAcceptProgress({
    required this.total,
    this.done = 0,
    this.ok = 0,
    this.failed = 0,
    this.errors = const [],
  });

  final int total;
  final int done;
  final int ok;
  final int failed;

  /// `#<offerId>: <reason>` per failure, in order.
  final List<String> errors;

  double get fraction => total == 0 ? 0 : done / total;

  /// One-line result, worded like the portal's summary toast.
  String get summary {
    if (failed == 0) return 'Accepted $ok booking${ok == 1 ? '' : 's'}';
    if (ok == 0) {
      return 'All $failed accept${failed == 1 ? '' : 's'} failed — '
          'first: ${errors.first}';
    }
    return 'Accepted $ok, failed $failed — the failed ones stay on the '
        'list to retry';
  }
}

/// Accepts [offerIds] ONE AT A TIME, like the portal's bulk accept
/// (requests/page.tsx, 2026-09-23): sequential so the dispatcher never sees
/// two claims on the same worker at once, and a failure (expired, already
/// taken, worker busy) is counted and skipped rather than stopping the run.
///
/// [onProgress] fires after every offer. The ids are a snapshot: a refresh
/// landing mid-run does not change what is being accepted.
Future<BulkAcceptProgress> runBulkAccept(
  List<int> offerIds,
  Future<void> Function(int offerId) accept, {
  void Function(BulkAcceptProgress progress)? onProgress,
}) async {
  final ids = List<int>.of(offerIds);
  var p = BulkAcceptProgress(total: ids.length);
  for (final id in ids) {
    String? error;
    try {
      await accept(id);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    }
    p = BulkAcceptProgress(
      total: p.total,
      done: p.done + 1,
      ok: p.ok + (error == null ? 1 : 0),
      failed: p.failed + (error == null ? 0 : 1),
      errors: error == null
          ? p.errors
          : [...p.errors, '#$id: ${error.replaceAll('_', ' ')}'],
    );
    onProgress?.call(p);
  }
  return p;
}
