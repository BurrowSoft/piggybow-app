// Where pig tips are asked: the tips project (TIPS_URL, with its publishable
// key and its region), or, in a staging debug build only, the tester's mock
// tips server (TIPS_TEST_URL).

import 'package:flutter/foundation.dart' show immutable, kDebugMode;
import 'package:flutter/services.dart' show appFlavor;

import '../core/app_config.dart';

/// The tester's mock tips server: staging debug builds only. A compile-time
/// constant, false in every release, profile and prod build, so they never
/// read TIPS_TEST_URL at all (TipsEndpoint.fromConfig, the one place).
const kTipsTestHook = appFlavor == 'staging' && kDebugMode;

@immutable
class TipsEndpoint {
  const TipsEndpoint({
    required this.base,
    required this.publishableKey,
    required this.region,
    this.mock = false,
  });

  /// The project's base, `https://<ref>.supabase.co`, or the mock's.
  final Uri base;

  /// The project's publishable key: the `apikey` header, never
  /// `Authorization`. Not a secret.
  final String publishableKey;

  /// The project's region, sent as `x-region` so the function runs next to
  /// its database; empty sends none.
  final String region;

  /// The tester's mock server, not the tips project.
  final bool mock;

  /// From the build: the tips project, once its URL (HTTPS) and key are set;
  /// in a staging debug build with TIPS_TEST_URL, the tester's mock. Null
  /// when neither is: no tips.
  static TipsEndpoint? fromConfig(AppConfig config) {
    if (kTipsTestHook) {
      const test = String.fromEnvironment('TIPS_TEST_URL');
      final url = Uri.tryParse(test);
      if (test.isNotEmpty && url != null && url.hasScheme && url.host.isNotEmpty) {
        return TipsEndpoint(
          base: url,
          publishableKey: config.tipsAnonKey,
          region: config.tipsRegion,
          mock: true,
        );
      }
    }
    final url = Uri.tryParse(config.tipsUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        config.tipsAnonKey.isEmpty) {
      return null;
    }
    return TipsEndpoint(
      base: url,
      publishableKey: config.tipsAnonKey,
      region: config.tipsRegion,
    );
  }

  /// [path] on this endpoint (an absolute path, with its query).
  Uri at(String path) => base.resolve(path);
}
