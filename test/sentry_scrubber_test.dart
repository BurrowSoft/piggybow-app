import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/sentry_scrubber.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  const typed = 'I felt awful after the meeting with Sam';

  test('drops user, request, message and free-text exception values', () {
    final event = SentryEvent(
      message: SentryMessage(typed),
      user: SentryUser(id: 'u1', email: 'someone@example.invalid'),
      request: SentryRequest(
        url: 'https://x.supabase.co/rest/v1/entries?text=$typed',
      ),
      exceptions: [
        SentryException(type: 'PostgrestException', value: 'bad input: $typed'),
        SentryException(type: 'PostgrestException', value: 'daily_limit'),
      ],
    );

    final out = SentryScrubber.beforeSend(event, Hint())!;

    expect(out.user, isNull);
    expect(out.request, isNull);
    expect(out.message, isNull);
    expect(out.exceptions![0].type, 'PostgrestException');
    expect(out.exceptions![0].value, '[redacted]');
    expect(
      out.exceptions![1].value,
      'daily_limit',
      reason: 'machine codes stay',
    );
    expect(out.toJson().toString(), isNot(contains('awful')));
  });

  test('keeps only allowlisted breadcrumbs, without messages or queries', () {
    final http = Breadcrumb.http(
      url: Uri.parse('https://x.supabase.co/rest/v1/entries'),
      method: 'POST',
    );
    final ui = Breadcrumb(category: 'ui.click', message: typed);
    final console = Breadcrumb(category: 'console', message: typed);
    final nav = Breadcrumb(
      category: 'navigation',
      message: typed,
      data: {'from': '/today?draft=$typed', 'to': '/timeline', 'args': typed},
    );

    expect(SentryScrubber.scrubBreadcrumb(http), isNull);
    expect(SentryScrubber.scrubBreadcrumb(ui), isNull);
    expect(SentryScrubber.scrubBreadcrumb(console), isNull);

    final kept = SentryScrubber.scrubBreadcrumb(nav)!;
    expect(kept.message, isNull);
    expect(kept.data, {'from': '/today', 'to': '/timeline'});
  });

  test(
    'drops flutter_error_details and unknown contexts, keeps device facts',
    () {
      final contexts = Contexts(device: SentryDevice(model: 'Pixel 9'))
        ..['flutter_error_details'] = {
          'information': 'Text("$typed") overflowed by 12 pixels',
          'library': 'rendering library',
        }
        ..['some_future_context'] = {'value': typed};
      final event = SentryEvent(contexts: contexts);

      final out = SentryScrubber.beforeSend(event, Hint())!;

      expect(out.contexts.containsKey('flutter_error_details'), isFalse);
      expect(out.contexts.containsKey('some_future_context'), isFalse);
      expect(out.contexts.device?.model, 'Pixel 9');
      expect(out.toJson().toString(), isNot(contains('awful')));
    },
  );

  test('beforeSend scrubs breadcrumbs attached to the event', () {
    final event = SentryEvent(
      breadcrumbs: [
        Breadcrumb(category: 'console', message: typed),
        Breadcrumb(category: 'app.lifecycle', message: typed),
      ],
    );
    final out = SentryScrubber.beforeSend(event, Hint())!;
    expect(out.breadcrumbs, hasLength(1));
    expect(out.breadcrumbs!.single.message, isNull);
  });

  group('hardening (Sentry review M1/M2/L1/L2)', () {
    const id = '3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f';

    test('M1: routes keep their pattern, never which day or entry', () {
      expect(
        SentryScrubber.normalizeRoute('/timeline/day/2026-10-02'),
        '/timeline/day/[date]',
      );
      expect(
        SentryScrubber.normalizeRoute('/insights/share/2026-10'),
        '/insights/share/[date]',
      );
      expect(
        SentryScrubber.normalizeRoute('/today/entry/$id/edit?draft=1#x'),
        '/today/entry/[id]/edit',
      );
      final crumb = SentryScrubber.scrubBreadcrumb(
        Breadcrumb(
          category: 'navigation',
          data: {'from': '/timeline/day/2026-10-02', 'to': '/today/entry/$id'},
        ),
      )!;
      expect(crumb.data, {
        'from': '/timeline/day/[date]',
        'to': '/today/entry/[id]',
      });
    });

    test(
      'M2: only known codes, or code-shaped values with a letter and a digit '
      'or _; never a bare number (it could be an amount)',
      () {
        final event = SentryEvent(
          exceptions: [
            SentryException(type: 'AppFailure', value: 'tired'),
            SentryException(type: 'AppFailure', value: 'offline'),
            SentryException(type: 'AppFailure', value: 'daily_limit'),
            SentryException(type: 'StateError', value: '23505'),
            SentryException(type: 'AppFailure', value: 'not_enough'),
            SentryException(type: 'StateError', value: '1250'),
            SentryException(type: 'StateError', value: '12_50'),
          ],
        );
        final values = [
          for (final e in SentryScrubber.beforeSend(event, Hint())!.exceptions!)
            e.value,
        ];
        expect(values, [
          '[redacted]',
          'offline',
          'daily_limit',
          '[redacted]',
          'not_enough',
          '[redacted]',
          '[redacted]',
        ]);
      },
    );

    test('L1: only SDK tags stay; mechanism data and description go', () {
      final event = SentryEvent(
        tags: {'event.origin': 'flutter', 'mood': 'awful', 'note': 'tired'},
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x_1',
            mechanism: Mechanism(
              type: 'generic',
              description: 'I felt awful',
              data: {'text': 'I felt awful'},
            ),
          ),
        ],
      );
      final out = SentryScrubber.beforeSend(event, Hint())!;
      expect(out.tags, {'event.origin': 'flutter'});
      final m = out.exceptions!.single.mechanism!;
      expect(m.data, isEmpty);
      expect(m.description, isNull);
      expect(m.type, 'generic');
      expect(out.toJson().toString(), isNot(contains('awful')));
    });

    test('L2: app view names normalised (ids and dates out)', () {
      final shown = SentryScrubber.beforeSend(
        SentryEvent(
          contexts: Contexts(
            app: SentryApp(viewNames: ['/timeline/day/2026-10-02']),
          ),
        ),
        Hint(),
      )!;
      expect(shown.contexts.app!.viewNames, ['/timeline/day/[date]']);
    });
  });

  // 1.4 H (PLAN-health-import § 8, R7): no Health value, interval or count
  // reaches Sentry: the allow-lists drop sleep/exercise/health keys wherever
  // they could ride along.
  test('Health keys never pass: breadcrumbs, extras, contexts', () {
    final crumb = SentryScrubber.scrubBreadcrumb(
      Breadcrumb(
        category: 'navigation',
        message: 'health read 7.5',
        data: {
          'to': '/today',
          'sleep': 7.5,
          'exercise': 30,
          'health': 'granted',
        },
      ),
    )!;
    expect(crumb.data, {'to': '/today'});
    expect(crumb.message, isNull);
    expect(
      SentryScrubber.scrubBreadcrumb(
        Breadcrumb(category: 'health', data: {'sleep': 7.5}),
      ),
      isNull,
    );
    final event = SentryEvent(
      // ignore: deprecated_member_use
      extra: {
        'sleep': 7.5,
        'exercise': 30,
        'health': [1, 2],
      },
      breadcrumbs: [Breadcrumb(category: 'health', message: '7.5 h')],
    );
    event.contexts['health'] = {'sleep': 7.5};
    final out = SentryScrubber.beforeSend(event, Hint())!;
    // ignore: deprecated_member_use
    expect(out.extra, isNull);
    expect(out.breadcrumbs, isEmpty);
    expect(out.contexts.containsKey('health'), isFalse);
  });
}
