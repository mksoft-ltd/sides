import 'package:flutter/material.dart';

import '../../features/digest/domain/digest.dart';
import 'outlet_avatar.dart';

/// An outlet's own thumbnail for one article, loaded from the outlet's image
/// server (never stored by Sides). While it loads, or when the feed has no
/// image or the load fails, the outlet's initials show instead, so a row
/// never jumps or shows a broken image. Decorative: the outlet's name is
/// always next to it, so it is excluded from semantics.
class ArticleThumb extends StatelessWidget {
  const ArticleThumb({
    super.key,
    required this.article,
    required this.outlet,
    this.width = 64,
    this.height = 48,
    this.radius = 8,
  });

  final Article article;
  final Outlet? outlet;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Widget fallback = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: cs.surfaceContainerHighest,
      child: OutletAvatar(
        outlet: outlet,
        fallbackName: article.outletId,
        size: (height * 0.6).clamp(20, 40),
      ),
    );
    final String? url = article.imageUrl;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: height,
          child: url == null
              ? fallback
              : Image.network(
                  url,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  cacheWidth: (width * dpr).round(),
                  gaplessPlayback: true,
                  loadingBuilder: (_, Widget child, ImageChunkEvent? p) =>
                      p == null ? child : fallback,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
