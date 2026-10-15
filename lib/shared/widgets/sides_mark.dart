import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';

/// The app icon's newspaper, drawn as vectors: a front page with a headline
/// bar, a photo block and three columns of text bars, and two sheets fanned
/// out behind it, violet on the left and orange on the right.
///
/// The outline follows `store_assets/icon/icon_mark.png` (760 x 491 px), the
/// tight mark `store_assets/icon/build_icon.py` cuts from the generated icon.
/// The page furniture is simplified so it still reads at the 20 dp app-bar
/// size: fewer, thicker text bars. As in the icon, the furniture is cut out of
/// the page, so whatever surface the mark sits on shows through as the ink.
///
/// The three fills are the active theme's lean colours, not the icon's brand
/// hexes, so each one clears 3:1 against the app bar in both themes. The icon's
/// dark plate is not part of the mark.
class SidesMark extends StatelessWidget {
  const SidesMark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    final PerspectiveColors c = PerspectiveColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: SidesMarkPainter(page: c.centre, left: c.left, right: c.right),
      ),
    );
  }
}

class SidesMarkPainter extends CustomPainter {
  const SidesMarkPainter({
    required this.page,
    required this.left,
    required this.right,
  });

  final Color page;
  final Color left;
  final Color right;

  /// The design space: `icon_mark.png`'s pixel grid.
  static const Size designSize = Size(760, 491);

  /// The front page.
  static const Rect pageRect = Rect.fromLTRB(181, 0, 578, 491);

  /// The violet sheet peeking out on the left.
  static const List<Offset> leftSheet = <Offset>[
    Offset(0, 101),
    Offset(164, 28),
    Offset(164, 463),
  ];

  /// The orange sheet peeking out on the right.
  static const List<Offset> rightSheet = <Offset>[
    Offset(596, 30),
    Offset(760, 102),
    Offset(596, 463),
  ];

  /// The holes cut out of the front page: headline bar, photo block, two lines
  /// beside the photo, then three rows of three text columns.
  static List<Rect> pageHoles() {
    const double l = 217, r = 543, gap = 24;
    const double colW = (r - l - 2 * gap) / 3;
    final List<Rect> holes = <Rect>[
      const Rect.fromLTRB(l, 38, r, 92), // headline bar
      const Rect.fromLTRB(l, 128, 360, 232), // photo block
      const Rect.fromLTRB(392, 128, r, 162),
      const Rect.fromLTRB(392, 198, 500, 232),
    ];
    for (final (int row, double top) in <(int, double)>[
      (0, 270),
      (1, 340),
      (2, 410),
    ]) {
      for (int col = 0; col < 3; col++) {
        final double x = l + col * (colW + gap);
        // The last line of the last column is short, like a paragraph end.
        final double w = row == 2 && col == 2 ? colW * 0.6 : colW;
        holes.add(Rect.fromLTWH(x, top, w, 34));
      }
    }
    return holes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = math.min(
      size.width / designSize.width,
      size.height / designSize.height,
    );
    final Offset origin =
        size.center(Offset.zero) -
        Offset(designSize.width, designSize.height) * scale / 2;
    Offset at(Offset p) => origin + p * scale;
    Rect rect(Rect r) => Rect.fromPoints(at(r.topLeft), at(r.bottomRight));

    canvas
      ..drawPath(
        Path()
          ..addPolygon(<Offset>[for (final Offset p in leftSheet) at(p)], true),
        Paint()..color = left,
      )
      ..drawPath(
        Path()..addPolygon(<Offset>[
          for (final Offset p in rightSheet) at(p),
        ], true),
        Paint()..color = right,
      );

    final Path front = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect(pageRect));
    for (final Rect hole in pageHoles()) {
      front.addRect(rect(hole));
    }
    canvas.drawPath(front, Paint()..color = page);
  }

  @override
  bool shouldRepaint(SidesMarkPainter old) =>
      old.page != page || old.left != left || old.right != right;
}

/// "Sides" with the newspaper mark before it, for the list app bars.
class SidesWordmark extends StatelessWidget {
  const SidesWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SidesMark(),
        SizedBox(width: 8),
        Flexible(
          child: Text(AppConfig.appName, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
