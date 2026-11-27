const _flavor = String.fromEnvironment('FLAVOR');

/// Staging/dev-only checks (decision 144). A compile-time constant, and
/// fail-closed: only an explicit staging or dev FLAVOR turns it on; prod and
/// a missing FLAVOR are off, so the code behind it is tree-shaken out of the
/// store build.
const stagingToolsEnabled = _flavor == 'staging' || _flavor == 'dev';

/// The synthetic error's message: no user text, nothing personal.
const stagingTestErrorMessage = 'PiggybowTestError: manual staging check';

/// Me → 7 taps on the version: one unhandled Dart error, so it reaches
/// Sentry through the normal path (decision 76: one event verified from each
/// platform's release build).
void throwStagingTestError() => throw StateError(stagingTestErrorMessage);
