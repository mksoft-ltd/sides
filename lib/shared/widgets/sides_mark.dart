import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';

/// The app icon's cube, seen from the corner: three faces pulled apart along
/// their normals so a Y-shaped seam separates them. Same geometry as
/// `store_assets/icon/build_icon.py` (`faces()`: gap = 18 / 340 of the
/// circumradius), painted in the theme's lean colours so it stays crisp and
/// clears 3:1 against the app bar in both themes.
class SidesMark extends StatelessWidget {
  const SidesMark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    final PerspectiveColors c = PerspectiveColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: SidesMarkPainter(
          top: c.centre,
          left: c.left,
          right: c.right,
        ),
      ),
    );
  }
}

class SidesMarkPainter extends CustomPainter {
  const SidesMarkPainter({
    required this.top,
    required this.left,
    required this.right,
  });

  final Color top;
  final Color left;
  final Color right;

  static const double _gapRatio = 18 / 340;
  static final double _cos30 = math.cos(math.pi / 6);

  /// Unit-circumradius quads (top, left, right), already pulled apart.
  static List<List<Offset>> unitFaces() {
    final double c = _cos30;
    const Offset o = Offset.zero;
    const Offset top = Offset(0, -1);
    final Offset ur = Offset(c, -0.5);
    final Offset lr = Offset(c, 0.5);
    const Offset bot = Offset(0, 1);
    final Offset ll = Offset(-c, 0.5);
    final Offset ul = Offset(-c, -0.5);
    List<Offset> pull(List<Offset> pts, Offset n) =>
        <Offset>[for (final Offset p in pts) p + n * _gapRatio];
    return <List<Offset>>[
      pull(<Offset>[top, ur, o, ul], const Offset(0, -1)),
      pull(<Offset>[ul, o, bot, ll], Offset(-c, 0.5)),
      pull(<Offset>[o, ur, lr, bot], Offset(c, 0.5)),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final List<List<Offset>> faces = unitFaces();
    final double reach = faces
        .expand((List<Offset> q) => q)
        .map((Offset p) => p.distance)
        .reduce(math.max);
    final double scale = size.shortestSide / 2 / reach;
    final Offset centre = size.center(Offset.zero);
    final List<Color> colours = <Color>[top, left, right];
    for (int i = 0; i < faces.length; i++) {
      final Path path = Path()
        ..addPolygon(
          <Offset>[for (final Offset p in faces[i]) centre + p * scale],
          true,
        );
      canvas.drawPath(path, Paint()..color = colours[i]);
    }
  }

  @override
  bool shouldRepaint(SidesMarkPainter old) =>
      old.top != top || old.left != left || old.right != right;
}

/// "Sides" with the cube mark before it, for the list app bars.
class SidesWordmark extends StatelessWidget {
  const SidesWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SidesMark(),
        SizedBox(width: 8),
        Flexible(child: Text(AppConfig.appName, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
