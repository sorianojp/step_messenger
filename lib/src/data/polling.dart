/// How often screens refresh over HTTP.
///
/// Realtime events already trigger a refresh, so while the socket is live we
/// only poll as a slow safety net (for missed events). When it is down we fall
/// back to frequent polling.
abstract final class PollingPolicy {
  /// Refresh interval while realtime is live.
  static const liveInterval = Duration(seconds: 60);

  static bool shouldPoll({
    required bool realtimeLive,
    required DateTime lastRefresh,
    required DateTime now,
  }) => !realtimeLive || now.difference(lastRefresh) >= liveInterval;
}
