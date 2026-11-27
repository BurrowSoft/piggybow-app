import 'package:flutter/widgets.dart';

/// After a share sheet closes, focus (keyboard and TalkBack) goes back to
/// the link that opened it, not wherever the system put it (UX, 0.9.6: it
/// landed on "Language & region"). After the frame: the link is disabled
/// while the export runs.
void returnFocusAfterFrame(State state, FocusNode node) =>
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.mounted && node.context != null) node.requestFocus();
    });
