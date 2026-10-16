import 'dart:async';

import 'package:flutter/material.dart';

/// Motion for the analysis page. Every animation here is short, runs once,
/// and is skipped entirely when the platform asks for reduced motion
/// (`MediaQuery.disableAnimations`), so the page is identical for a reader
/// who turned animations off.
abstract final class Motion {
  static const Duration reveal = Duration(milliseconds: 320);
  static const Duration stagger = Duration(milliseconds: 45);
  static const Duration grow = Duration(milliseconds: 600);
  static const Duration count = Duration(milliseconds: 700);
  static const Duration axisSwitch = Duration(milliseconds: 260);
  static const Duration flash = Duration(milliseconds: 1100);
  static const Curve curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// Fades and slides [child] up into place after [delay]. Used to stagger the
/// blocks of a story page as it opens.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;

  /// Starting vertical offset, in dp.
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.reveal,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.curve,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (BuildContext context, Widget? child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curve.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Grows [child] from the left to its full width once, for bars.
class GrowIn extends StatelessWidget {
  const GrowIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return _Delayed(
      delay: delay,
      builder: (bool go) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: go ? 1 : 0),
        duration: Motion.grow,
        curve: Motion.curve,
        builder: (BuildContext context, double t, Widget? child) => ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: t,
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Scales and fades [child] in once, for avatars; [index] staggers a set.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return _Delayed(
      delay: Motion.stagger * index,
      builder: (bool go) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: go ? 1 : 0),
        duration: Motion.reveal,
        curve: Curves.easeOutBack,
        builder: (BuildContext context, double t, Widget? child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        ),
        child: child,
      ),
    );
  }
}

/// A number that counts up from zero to [value] once.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context) || value == 0) {
      return Text('$value', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: Motion.count,
      curve: Motion.curve,
      builder: (BuildContext context, double t, _) =>
          Text('${t.round()}', style: style),
    );
  }
}

/// Builds with `go == false` until [delay] has passed, then `go == true`,
/// so a tween can start late without its own controller.
class _Delayed extends StatefulWidget {
  const _Delayed({required this.delay, required this.builder});
  final Duration delay;
  final Widget Function(bool go) builder;

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  bool _go = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _go = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _go = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_go);
}

/// Fades and slides between the two axes' sections: switching to West /
/// East slides in from the right, back to Political lean from the left.
class AxisSwitcher extends StatelessWidget {
  const AxisSwitcher({
    super.key,
    required this.child,
    required this.forward,
  });

  /// The current axis's sections, keyed by axis.
  final Widget child;

  /// True when the new axis is to the right of the old one.
  final bool forward;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: Motion.axisSwitch,
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget c, Animation<double> a) {
        // The incoming child animates 0 → 1; the outgoing one 1 → 0.
        final bool incoming = c.key == child.key;
        final double dx = incoming ? (forward ? 0.08 : -0.08) : (forward ? -0.08 : 0.08);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                .animate(a),
            child: c,
          ),
        );
      },
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[...previous, ?current],
      ),
      child: child,
    );
  }
}
