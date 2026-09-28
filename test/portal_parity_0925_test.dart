import 'package:flutter_test/flutter_test.dart';
import 'package:cnc_partner/core/network/api_client.dart';
import 'package:cnc_partner/features/bookings/cash_submissions.dart';
import 'package:cnc_partner/features/partner/bulk_accept.dart';
import 'package:cnc_partner/features/partner/partner_models.dart';
import 'package:cnc_partner/widgets/image_source_sheet.dart';

void main() {
  group('runBulkAccept', () {
    test('accepts sequentially and counts every success', () async {
      final calls = <int>[];
      var inFlight = 0;
      final r = await runBulkAccept([1, 2, 3], (id) async {
        inFlight++;
        expect(inFlight, 1, reason: 'never two accepts at once');
        calls.add(id);
        await Future<void>.delayed(Duration.zero);
        inFlight--;
      });
      expect(calls, [1, 2, 3]);
      expect(r.ok, 3);
      expect(r.failed, 0);
      expect(r.done, 3);
      expect(r.summary, 'Accepted 3 bookings');
    });

    test('a failure is counted and the run continues', () async {
      final seen = <BulkAcceptProgress>[];
      final r = await runBulkAccept(
        [7, 8, 9],
        (id) async {
          if (id == 8) throw ApiException('OFFER_EXPIRED', status: 409);
        },
        onProgress: seen.add,
      );
      expect(r.ok, 2);
      expect(r.failed, 1);
      expect(r.errors, ['#8: OFFER EXPIRED']);
      expect(seen.map((p) => p.done), [1, 2, 3]);
      expect(r.summary, contains('Accepted 2, failed 1'));
    });

    test('all failing names the first reason', () async {
      final r = await runBulkAccept([4], (_) async => throw Exception('x'));
      expect(r.ok, 0);
      expect(r.summary, startsWith('All 1 accept failed — first: #4:'));
    });

    test('works on a snapshot of the ids', () async {
      final ids = [1, 2];
      final r = await runBulkAccept(ids, (id) async {
        if (id == 1) ids.add(3);
      });
      expect(r.total, 2);
      expect(r.done, 2);
    });
  });

  group('isCashAwaitingApproval', () {
    test('true while the due is unchanged since the submission', () {
      expect(isCashAwaitingApproval({5: 250}, 5, 250), isTrue);
      expect(isCashAwaitingApproval({5: 250}, 5, 250.001), isTrue);
    });

    test('lapses once an admin approves part of it', () {
      expect(isCashAwaitingApproval({5: 250}, 5, 100), isFalse);
    });

    test('false for bookings never submitted', () {
      expect(isCashAwaitingApproval({5: 250}, 6, 250), isFalse);
      expect(isCashAwaitingApproval(const {}, 5, 250), isFalse);
    });

    test('an assignment without a booking id is never awaiting', () {
      expect(isCashAwaitingApproval({5: 250}, null, 250), isFalse);
    });
  });

  test('isPdfPath', () {
    expect(isPdfPath('/tmp/slip.PDF'), isTrue);
    expect(isPdfPath('/tmp/slip.pdf '), isTrue);
    expect(isPdfPath('/tmp/slip.jpg'), isFalse);
    expect(isPdfPath('/tmp/pdf.png'), isFalse);
  });

  group('WalletTransaction.proofImageUrl', () {
    test('reads the proof an admin attached to a deposit', () {
      final t = WalletTransaction.fromJson({
        'id': 1,
        'type': 'adjustment',
        'direction': 'credit',
        'amount': '500',
        'description': '[Admin Deposit — Cash] ok',
        'proofImageUrl': '/uploads/abc.pdf',
      });
      expect(t.proofImageUrl, '/uploads/abc.pdf');
    });

    test('empty when absent', () {
      expect(WalletTransaction.fromJson({'id': 2}).proofImageUrl, '');
    });
  });
}
