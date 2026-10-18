import 'package:flutter_test/flutter_test.dart';
import 'package:step_messenger/src/data/polling.dart';

void main() {
  final now = DateTime(2026, 10, 18, 9);

  test('polls on every tick while realtime is down', () {
    expect(
      PollingPolicy.shouldPoll(
        realtimeLive: false,
        lastRefresh: now.subtract(const Duration(seconds: 5)),
        now: now,
      ),
      isTrue,
    );
  });

  test('skips polling while realtime is live and data is fresh', () {
    expect(
      PollingPolicy.shouldPoll(
        realtimeLive: true,
        lastRefresh: now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      isFalse,
    );
  });

  test('still refreshes as a safety net once a minute when live', () {
    expect(
      PollingPolicy.shouldPoll(
        realtimeLive: true,
        lastRefresh: now.subtract(const Duration(seconds: 60)),
        now: now,
      ),
      isTrue,
    );
  });
}
