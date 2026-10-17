import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/copy.dart';
import '../../../shared/widgets/motion.dart';
import 'search_controller.dart';

/// What the search is doing, shown only once it has taken longer than
/// [delay], so a quick search never flashes it. A checklist of the steps
/// (done, running, waiting, not needed), each with a plain sentence on what
/// it does; a progress bar (indeterminate, or for a new comparison an
/// estimate that fills over about a minute and never claims to finish); and
/// for the comparison, a line that changes every few seconds to say which
/// part of the work is likely under way.
class SearchProgress extends StatefulWidget {
  const SearchProgress({super.key, required this.state});

  final SearchState state;

  static const Duration delay = Duration(milliseconds: 500);
  static const Key panelKey = Key('search-progress');

  @override
  State<SearchProgress> createState() => _SearchProgressState();
}

class _SearchProgressState extends State<SearchProgress> {
  Timer? _show;
  Timer? _tick;
  bool _visible = false;

  /// Seconds the comparison step has been running, counted by this panel's
  /// own ticks (so it follows the test clock as well as the real one).
  int _compareSeconds = 0;

  @override
  void initState() {
    super.initState();
    _show = Timer(SearchProgress.delay, () {
      if (mounted) setState(() => _visible = true);
    });
    // Re-render once a second: the estimate bar and the rotating line.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.state.status(SearchStep.compare) == StepStatus.running) {
        _compareSeconds++;
      }
      if (_visible) setState(() {});
    });
  }

  @override
  void dispose() {
    _show?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = Motion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 250),
      child: _visible
          ? _Panel(
              key: SearchProgress.panelKey,
              state: widget.state,
              elapsed: Duration(seconds: _compareSeconds),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.state, required this.elapsed});
  final SearchState state;

  /// How long the comparison has been running.
  final Duration elapsed;

  /// 0 → 0.9 over about a minute, easing out, never reaching the end until
  /// the comparison really finishes.
  static double estimate(Duration elapsed) {
    final double t = (elapsed.inMilliseconds / 60000).clamp(0, 1);
    return 0.9 * Curves.easeOutCubic.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool comparing =
        state.status(SearchStep.compare) == StepStatus.running;
    final bool reduced = Motion.reduced(context);

    return Semantics(
      container: true,
      liveRegion: true,
      label: Copy.searchProgressLabel(_current(state)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: comparing && !reduced
                  ? TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: estimate(elapsed)),
                      duration: const Duration(milliseconds: 900),
                      builder: (_, double v, _) =>
                          LinearProgressIndicator(value: v, minHeight: 6),
                    )
                  : const LinearProgressIndicator(minHeight: 6),
            ),
            const SizedBox(height: 14),
            for (final SearchStep s in SearchStep.values)
              if (state.status(s) != StepStatus.skipped)
                _StepRow(step: s, status: state.status(s), state: state),
            if (comparing) ...<Widget>[
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 400),
                child: Text(
                  Copy.compareStage(elapsed),
                  key: ValueKey<String>(Copy.compareStage(elapsed)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static SearchStep _current(SearchState s) => SearchStep.values.firstWhere(
        (SearchStep x) => s.status(x) == StepStatus.running,
        orElse: () => SearchStep.phone,
      );
}

/// One step: a status mark, the step's name, and what it is doing.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.status,
    required this.state,
  });

  final SearchStep step;
  final StepStatus status;
  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Widget mark = switch (status) {
      StepStatus.done => Icon(Icons.check_circle, size: 20, color: cs.primary),
      StepStatus.running => const SizedBox(
          width: 20,
          height: 20,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      _ => Icon(Icons.radio_button_unchecked, size: 20, color: cs.outline),
    };
    final bool active = status == StepStatus.running;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(padding: const EdgeInsets.only(top: 1), child: mark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Copy.stepTitle(step, status),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: status == StepStatus.waiting
                        ? cs.onSurfaceVariant
                        : cs.onSurface,
                  ),
                ),
                if (active || status == StepStatus.done) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    Copy.stepDetail(
                      step,
                      status,
                      phoneHits: state.phoneHits,
                      outlets: state.outletsPolled,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A grey stand-in for a result card while the first results are on their
/// way, gently pulsing (static under reduced motion).
class ResultSkeleton extends StatefulWidget {
  const ResultSkeleton({super.key});

  @override
  State<ResultSkeleton> createState() => _ResultSkeletonState();
}

class _ResultSkeletonState extends State<ResultSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              bar(64, 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    bar(double.infinity, 14),
                    const SizedBox(height: 8),
                    bar(180, 14),
                    const SizedBox(height: 12),
                    bar(110, 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
