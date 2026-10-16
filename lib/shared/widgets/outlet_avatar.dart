import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/digest/domain/digest.dart';

/// Two or three letters that stand for an outlet: an all-caps first word of
/// up to four letters as is ("BBC", "NBC", "CGTN"), otherwise the initials
/// of the first three words after a leading "The" ("New York Times" → NYT,
/// "New York Post" → NYP, "Fox News" → FN), or the first two letters of a
/// single word ("Axios" → AX). Letters, never logos: no outlet artwork
/// appears in the app.
String outletInitials(String name) {
  final List<String> words = name
      .replaceAll(RegExp(r'[()]'), ' ')
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.length > 1 && words.first.toLowerCase() == 'the') {
    words.removeAt(0);
  }
  if (words.isEmpty) return '?';
  final String first = words.first;
  if (first.length <= 4 && RegExp(r'^[A-Z0-9]+$').hasMatch(first)) {
    return first.substring(0, math.min(3, first.length));
  }
  if (words.length >= 2) {
    return words.take(3).map((String w) => w[0]).join().toUpperCase();
  }
  return first.substring(0, math.min(2, first.length)).toUpperCase();
}

/// A circle in the outlet's lean colour (bloc colour for outlets off the
/// lean scale) carrying its initials. Purely visual: the outlet's name is
/// always next to it or in the enclosing semantics label, so the avatar
/// itself is excluded from semantics.
class OutletAvatar extends StatelessWidget {
  const OutletAvatar({
    super.key,
    required this.outlet,
    this.fallbackName,
    this.size = 24,
  });

  /// Null when the digest does not list the outlet (then [fallbackName] is
  /// used and the circle is neutral).
  final Outlet? outlet;
  final String? fallbackName;
  final double size;

  static Color colorFor(Outlet? o, PerspectiveColors colors, ColorScheme cs) =>
      switch (o) {
        null => cs.surfaceContainerHighest,
        Outlet(lean: final Lean l) => colors.forLean(l),
        Outlet(bloc: final Bloc b) => colors.forBloc(b),
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fill = colorFor(outlet, PerspectiveColors.of(context), theme.colorScheme);
    final Color ink =
        ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
            ? Colors.white
            : const Color(0xFF13232A);
    final String text = outletInitials(outlet?.name ?? fallbackName ?? '?');
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Text(
          text,
          maxLines: 1,
          // Fixed sizes: the avatar does not grow with the text scale, so
          // the letters must not either.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: ink,
            fontSize: size * (text.length > 2 ? 0.34 : 0.42),
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
