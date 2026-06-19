import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());

/// Thin wrapper over local_auth for fingerprint / Face ID gating.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// True if the device has biometrics (or a device passcode) we can use.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && (canCheck || await _hasEnrolled());
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasEnrolled() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// A friendly label for the available biometric (Face ID / fingerprint).
  Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) return 'fingerprint';
      if (types.contains(BiometricType.iris)) return 'iris';
    } catch (_) {}
    return 'biometrics';
  }

  /// Prompt the user. Returns true on success.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
