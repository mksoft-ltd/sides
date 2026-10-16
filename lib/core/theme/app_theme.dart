import 'package:flutter/material.dart';

import '../../features/digest/domain/digest.dart';

/// Colours for the two coverage axes.
///
/// Deliberately not red/blue: the US and UK use those colours for opposite
/// sides, so either mapping would read as partisan to half the audience.
/// Every colour is paired with a text label wherever it appears, and each
/// one clears 3:1 against its theme's surface (non-text contrast, WCAG 1.4.11).
@immutable
class PerspectiveColors extends ThemeExtension<PerspectiveColors> {
  const PerspectiveColors({
    required this.left,
    required this.centre,
    required this.right,
    required this.west,
    required this.east,
    required this.empty,
  });

  final Color left;
  final Color centre;
  final Color right;
  final Color west;
  final Color east;
  final Color empty;

  static const PerspectiveColors light = PerspectiveColors(
    left: Color(0xFF7B4FB8),
    centre: Color(0xFF5F6B73),
    right: Color(0xFFB0601A),
    west: Color(0xFF2E7D7A),
    east: Color(0xFF8E6C00),
    empty: Color(0xFFD5D9DC),
  );

  static const PerspectiveColors dark = PerspectiveColors(
    left: Color(0xFFB79CEB),
    centre: Color(0xFFA7B3BB),
    right: Color(0xFFF0A35E),
    west: Color(0xFF6CC5C0),
    east: Color(0xFFE0BE55),
    empty: Color(0xFF3A3F44),
  );

  Color forLean(Lean l) => switch (l) {
        Lean.left => left,
        Lean.centre => centre,
        Lean.right => right,
      };

  Color forBloc(Bloc b) => b == Bloc.west ? west : east;

  static PerspectiveColors of(BuildContext context) =>
      Theme.of(context).extension<PerspectiveColors>() ?? light;

  @override
  PerspectiveColors copyWith({
    Color? left,
    Color? centre,
    Color? right,
    Color? west,
    Color? east,
    Color? empty,
  }) =>
      PerspectiveColors(
        left: left ?? this.left,
        centre: centre ?? this.centre,
        right: right ?? this.right,
        west: west ?? this.west,
        east: east ?? this.east,
        empty: empty ?? this.empty,
      );

  @override
  PerspectiveColors lerp(PerspectiveColors? other, double t) {
    if (other == null) return this;
    return PerspectiveColors(
      left: Color.lerp(left, other.left, t)!,
      centre: Color.lerp(centre, other.centre, t)!,
      right: Color.lerp(right, other.right, t)!,
      west: Color.lerp(west, other.west, t)!,
      east: Color.lerp(east, other.east, t)!,
      empty: Color.lerp(empty, other.empty, t)!,
    );
  }
}

abstract final class AppTheme {
  static const Color _seed = Color(0xFF34505C);

  static ThemeData light() => _build(
        ColorScheme.fromSeed(seedColor: _seed),
        PerspectiveColors.light,
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        PerspectiveColors.dark,
      );

  static ThemeData _build(ColorScheme scheme, PerspectiveColors colors) {
    final ThemeData base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // 48 dp minimum tap targets everywhere, including on iOS.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[colors],
    );
    final TextTheme text = base.textTheme;
    return base.copyWith(
      // Reading app: headings carry a little more weight than M3's default,
      // body text keeps the platform font and a comfortable line height.
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 17, height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
        bodySmall: text.bodySmall?.copyWith(fontSize: 13, height: 1.4),
        labelLarge: text.labelLarge?.copyWith(fontSize: 14),
        labelMedium: text.labelMedium?.copyWith(fontSize: 13),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      // Source pills and jump chips: compact, outlined, stadium-shaped. The
      // 48 dp tap target comes from materialTapTargetSize.padded.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        iconTheme: IconThemeData(size: 16, color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
