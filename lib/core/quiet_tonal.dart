import 'package:flutter/material.dart';

/// A tonal button's style that really is quieter than the content around
/// it. The theme's filled-button style gives every FilledButton, the tonal
/// ones included, the accent fill; this gives the tonal look back.
ButtonStyle quietTonalStyle(ThemeData theme) => FilledButton.styleFrom(
  backgroundColor: theme.colorScheme.secondaryContainer,
  foregroundColor: theme.colorScheme.onSecondaryContainer,
);
