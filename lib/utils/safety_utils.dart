// lib/utils/safety_utils.dart
// Safety helpers for call & share route

import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class SafetyUtils {
  static Future<void> callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  static String buildRouteUrl({required double lat, required double lng}) {
    return 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
  }

  static Future<void> shareRoute({required double lat, required double lng, String? message}) async {
    final url = buildRouteUrl(lat: lat, lng: lng);
    final text = (message == null || message.isEmpty) ? url : '$message\n$url';
    await Share.share(text);
  }

  static Future<void> shareText(String text) async {
    await Share.share(text);
  }
}
