import 'dart:io';
import 'package:google_api_availability/google_api_availability.dart';

/// Checks whether FCM (Google Play Services) is available on the current device.
///
/// - Android: queries GoogleApiAvailability — returns true only if GMS is present and up-to-date
/// - iOS / web / other: always returns null (not applicable, no need to report)
Future<bool?> checkFCMAvailability() async {
  if (!Platform.isAndroid) return null;

  try {
    final status = await GoogleApiAvailability.instance
        .checkGooglePlayServicesAvailability();
    return status == GooglePlayServicesAvailability.success;
  } catch (_) {
    return null;
  }
}
