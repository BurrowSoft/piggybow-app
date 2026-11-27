import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/golden_manifest.dart';

/// The file name of a golden: `<screen>_<state>_<light|dark>_<width>x<scale>.png`
/// (decision 44). Throws an ArgumentError when a field breaks the rule.
String goldenName({
  required String screen,
  required String state,
  required Brightness brightness,
  required int width,
  required int textScale,
}) {
  final name = '${screen}_${state}_${brightness.name}_${width}x$textScale.png';
  if (!goldenNamePattern.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'golden name',
      'is not <screen>_<state>_<light|dark>_<width>x<scale>.png '
          'with kebab-case fields',
    );
  }
  return name;
}

/// The key matchesGoldenFile resolves against [testDir] (the running test
/// file's folder) to reach `test/goldens/<name>` under [packageRoot].
String goldenKey(
  String name, {
  required Uri testDir,
  required Uri packageRoot,
}) {
  String path(Uri u) {
    final p = u.path.endsWith('/') ? u.path : '${u.path}/';
    return Platform.isWindows ? p.toLowerCase() : p;
  }

  final dir = path(testDir);
  final root = path(packageRoot);
  if (!dir.startsWith(root)) {
    throw StateError('the test folder $testDir is not inside $packageRoot');
  }
  final depth = dir
      .substring(root.length)
      .split('/')
      .where((s) => s.isNotEmpty)
      .length;
  return '${'../' * depth}$goldensDir/$name';
}

/// The first element at or under [root] that has a Theme and a MediaQuery
/// above it: where the screen's brightness and text scale can be read.
Element _themed(Element root) {
  final queue = [root];
  for (var i = 0; i < queue.length && i < 5000; i++) {
    final e = queue[i];
    if (e.findAncestorWidgetOfExactType<Theme>() != null &&
        e.findAncestorWidgetOfExactType<MediaQuery>() != null) {
      return e;
    }
    e.visitChildren(queue.add);
  }
  throw StateError('no Theme and MediaQuery under the golden\'s widget');
}

/// Every golden goes through here (decision 44): never call
/// matchesGoldenFile directly. The file is named by the rule and kept in
/// test/goldens/. The view must be what the name says (device pixel ratio 3,
/// [width] dp wide, [brightness], [textScale]). While goldens.yaml renders
/// the baselines, the line its manifest is built from is printed, with
/// [stateId], the state's id in PB Mobile Tester's list (such as A2).
///
/// A file that calls this is tagged golden (`@Tags(['golden'])`) and loads
/// the app's fonts first: test/goldens_manifest_test.dart checks both.
Future<void> expectGolden(
  WidgetTester tester,
  Finder finder, {
  required String screen,
  required String state,
  required String stateId,
  required Brightness brightness,
  required int width,
  required int textScale,
}) async {
  final name = goldenName(
    screen: screen,
    state: state,
    brightness: brightness,
    width: width,
    textScale: textScale,
  );
  if (!stateIdPattern.hasMatch(stateId)) {
    throw ArgumentError.value(
      stateId,
      'stateId',
      'is not a state id such as A2',
    );
  }
  final view = tester.view;
  expect(view.devicePixelRatio, 3.0, reason: '$name: device pixel ratio 3');
  expect(
    view.physicalSize.width / view.devicePixelRatio,
    width.toDouble(),
    reason: '$name: the view is $width dp wide',
  );
  final screenElement = _themed(tester.element(finder));
  expect(
    Theme.of(screenElement).brightness,
    brightness,
    reason: '$name: the theme is ${brightness.name}',
  );
  expect(
    MediaQuery.textScalerOf(screenElement).scale(100),
    100.0 * textScale,
    reason: '$name: the text scale is $textScale',
  );
  // A golden shows the app as a finger leaves it: never the keyboard focus
  // ring a widget test can leave on a focused button (PB UX & PM's look at
  // the first render: the + button's ring, which no phone shows).
  final strategy = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
  await tester.pumpAndSettle();
  final comparator = goldenFileComparator;
  if (comparator is! LocalFileComparator) {
    throw StateError(
      'expectGolden needs the LocalFileComparator flutter test sets',
    );
  }
  final key = goldenKey(
    name,
    testDir: comparator.basedir,
    packageRoot: Directory.current.uri,
  );
  if (autoUpdateGoldenFiles) {
    // In the JSON report this line carries its test's id: the manifest's
    // "test" and "state" for this file.
    // ignore: avoid_print
    print('$goldenMarker${jsonEncode({'file': name, 'state': stateId})}');
  }
  await expectLater(finder, matchesGoldenFile(key));
}
