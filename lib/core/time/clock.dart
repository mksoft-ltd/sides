/// Injectable "now", so cache-policy decisions are testable.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();
