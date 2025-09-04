// lib/utils/link_utils.dart
// Open Google Maps route (uses url_launcher).

import 'package:url_launcher/url_launcher.dart';

class LinkUtils {
  static Future<void> openGoogleMapsRoute({required double lat, required double lng}) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  }
}
