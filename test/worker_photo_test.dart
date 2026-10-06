import 'dart:io';

import 'package:cnc_partner/core/network/api_client.dart';
import 'package:cnc_partner/core/notifications/notifications_controller.dart';
import 'package:cnc_partner/features/partner/partner_models.dart';
import 'package:cnc_partner/features/partner/partner_repository.dart';
import 'package:cnc_partner/features/partner/worker_form.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Worker profile photo (backend 2026-10-05, 54780c5): a partner can set a
/// worker's photo on create/edit — multipart `photo` on `PUT /workers/:id`,
/// stored as `Worker.photoUrl` — and remove it with `photoUrl: ''`.

class _Capture implements HttpClientAdapter {
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    // Read the body as a real request would, which also releases the file.
    await requestStream?.drain<void>();
    return ResponseBody.fromString('{"success":true}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _FakeRepo extends PartnerRepository {
  _FakeRepo() : super(ApiClient());
  final updates = <Map<String, dynamic>>[];
  final uploads = <String>[];

  @override
  Future<List<Zone>> zones() async => const [];
  @override
  Future<List<Van>> vans() async => const [];
  @override
  Future<List<MyService>> myServices() async => const [];
  @override
  Future<List<Map<String, dynamic>>> workerZones(int id) async => const [];
  @override
  Future<WorkerServicesLink> workerServicesLink(int id) async =>
      const WorkerServicesLink();
  @override
  Future<void> updateWorker(int id, Map<String, dynamic> body) async =>
      updates.add(body);
  @override
  Future<void> syncWorkerZones(
          int id, List<int> zoneIds, int? primaryZoneId) async {}
  @override
  Future<void> syncWorkerServices(int id, List<int> basePriceIds,
      {Map<int, List<int>> itemsByBp = const {}}) async {}
  @override
  Future<void> uploadWorkerPhoto(int id, String filePath) async =>
      uploads.add(filePath);
}

class _NoNotifications extends NotificationsController {
  @override
  NotifState build() => const NotifState();
}

const _worker = Worker(
  id: 7,
  firstName: 'Sara',
  lastName: 'Khan',
  email: 'sara@example.com',
  phone: '+971 501234567',
  roles: ['crew'],
  status: 'active',
  primaryZoneId: 3,
  photoUrl: 'abc.jpg',
);

void main() {
  group('the model', () {
    test('reads photoUrl; none is empty', () {
      expect(Worker.fromJson({'id': 1, 'photoUrl': 'x.png'}).photoUrl, 'x.png');
      expect(Worker.fromJson({'id': 1, 'photoUrl': null}).photoUrl, '');
      expect(Worker.fromJson({'id': 1}).photoUrl, '');
    });

    test('an optimistic status edit keeps the photo', () {
      expect(_worker.copyWith(status: 'on_leave').photoUrl, 'abc.jpg');
    });
  });

  group('the upload request', () {
    test('PUT /workers/:id, multipart, the file under `photo` and nothing else',
        () async {
      final dir = Directory.systemTemp.createTempSync('worker_photo_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/face.jpg')..writeAsBytesSync([1, 2, 3]);
      final cap = _Capture();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = cap;
      await PartnerRepository(ApiClient(dio: dio))
          .uploadWorkerPhoto(7, file.path);

      final req = cap.last!;
      expect(req.method, 'PUT');
      expect(req.path, '/workers/7');
      final form = req.data as FormData;
      expect(form.files.map((f) => f.key), ['photo']);
      expect(form.files.single.value.filename, 'face.jpg');
      // Only the photo — no other field goes through multipart's strings.
      expect(form.fields, isEmpty);
    });
  });

  group('the worker form', () {
    late _FakeRepo repo;

    setUp(() {
      repo = _FakeRepo();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('PonnamKarthik/fluttertoast'),
              (_) async => true);
    });

    Future<void> pump(WidgetTester tester, Worker? w) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          partnerRepositoryProvider.overrideWithValue(repo),
          notificationsProvider.overrideWith(_NoNotifications.new),
        ],
        child: MaterialApp(home: WorkerForm(worker: w)),
      ));
      await tester.pump();
    }

    testWidgets('a new worker offers Upload, nothing to remove',
        (tester) async {
      await pump(tester, null);
      expect(find.text('Profile photo'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('an edit with a photo offers Replace and Remove',
        (tester) async {
      await pump(tester, _worker);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('Remove clears it on Save with photoUrl \'\'', (tester) async {
      await pump(tester, _worker);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);

      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump();
      expect(repo.updates, hasLength(1));
      expect(repo.updates.single['photoUrl'], '');
      expect(repo.uploads, isEmpty);
    });

    testWidgets('an edit that leaves the photo alone does not touch it',
        (tester) async {
      await pump(tester, _worker);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Last name'), 'Ali');
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump();
      expect(repo.updates, hasLength(1));
      expect(repo.updates.single.containsKey('photoUrl'), isFalse);
      expect(repo.uploads, isEmpty);
    });
  });
}
