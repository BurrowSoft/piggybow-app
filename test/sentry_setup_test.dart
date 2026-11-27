import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/sentry_scrubber.dart';
import 'package:piggybow/core/sentry_setup.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('Sentry options: no identity, no sessions, nothing extra attached', () {
    final options = SentryFlutterOptions();
    configureSentry(
      options,
      const AppConfig(
        flavor: Flavor.prod,
        sentryDsn: 'https://k@o.ingest.sentry.io/1',
      ),
    );

    expect(options.sendDefaultPii, isFalse);
    expect(options.enableAutoSessionTracking, isFalse, reason: 'decision 49');
    expect(options.tracesSampleRate, 0);
    expect(options.attachScreenshot, isFalse);
    // ignore: experimental_member_use
    expect(options.attachViewHierarchy, isFalse);
    expect(options.enableLogs, isFalse);
    expect(options.replay.sessionSampleRate, 0);
    expect(options.replay.onErrorSampleRate, 0);
    // Dart errors only (decision 114): no native-origin events, which would
    // bypass the scrubber and could carry an installation id.
    expect(options.enableNativeCrashHandling, isFalse);
    expect(options.anrEnabled, isFalse);
    expect(options.enableWatchdogTerminationTracking, isFalse);
    expect(options.enableAppHangTracking, isFalse);
    expect(options.enableNdkScopeSync, isFalse);
    expect(options.enableAutoNativeBreadcrumbs, isFalse);
    expect(options.beforeSend, same(SentryScrubber.beforeSend));
    expect(options.beforeBreadcrumb, same(SentryScrubber.beforeBreadcrumb));
    expect(options.environment, 'prod');
  });

  test('lib/ never sets a Sentry user, scope, tag or context', () {
    final forbidden = RegExp(
      r'Sentry\s*\.\s*(configureScope|setUser|setTag|setExtra|setContexts)'
      r'|\.\s*setUser\s*\(|scope\s*\.\s*(setUser|setTag|setContexts|setExtra)'
      r'|SentryUser\s*\(',
    );
    final hits = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (forbidden.hasMatch(code)) {
          hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
