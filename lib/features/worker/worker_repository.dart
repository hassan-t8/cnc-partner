import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../bookings/models.dart';

/// Worker-scoped API (assignments + self-service). Mirrors workerApi.* in api.ts.
class WorkerRepository {
  final ApiClient _api;
  WorkerRepository(this._api);

  /// GET /booking-assignments?workerId&from&to[&status]
  Future<List<Assignment>> assignments({
    required int workerId,
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final res = await _api.get('/booking-assignments', query: {
      'workerId': workerId,
      if (from != null) 'from': from.toIso8601String(),
      if (to != null) 'to': to.toIso8601String(),
      if (status != null) 'status': status,
    });
    return pickList(res.data).map(Assignment.fromJson).toList();
  }

  /// GET /workers/me/bookings?status=upcoming|completed|all
  Future<List<Assignment>> myBookings({String status = 'all'}) async {
    final res =
        await _api.get('/workers/me/bookings', query: {'status': status});
    return pickList(res.data).map(Assignment.fromJson).toList();
  }

  /// GET /workers/me/today-summary
  Future<Map<String, dynamic>> todaySummary() async {
    final res = await _api.get('/workers/me/today-summary');
    return pickMap(res.data);
  }

  Future<void> accept(int assignmentId) =>
      _api.post('/booking-assignments/$assignmentId/accept');

  Future<void> decline(int assignmentId, {String? reason}) => _api.post(
      '/booking-assignments/$assignmentId/decline',
      body: {if (reason != null) 'reason': reason});

  /// Start a job. Throws ApiException(code: OTP_REQUIRED|OTP_INVALID) when gated.
  Future<void> start(int assignmentId, {String? otp}) => _api.post(
      '/booking-assignments/$assignmentId/start',
      body: {if (otp != null) 'otp': otp});

  Future<void> complete(int assignmentId) =>
      _api.post('/booking-assignments/$assignmentId/complete');
}

final workerRepositoryProvider = Provider<WorkerRepository>(
    (ref) => WorkerRepository(ref.read(apiClientProvider)));
