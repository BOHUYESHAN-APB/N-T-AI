import 'dart:async';

class RateLimiterManager {
  RateLimiterManager._();
  static final RateLimiterManager instance = RateLimiterManager._();

  final Map<String, List<DateTime>> _requests = {};

  // 等待直到当前 provider 的 rpm 限制允许继续
  Future<void> waitIfNeeded(String providerId, {int? rpm}) async {
    if (rpm == null || rpm <= 0) return;
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(minutes: 1));
    final list = _requests.putIfAbsent(providerId, () => <DateTime>[]);
    // 清理 60 秒前的记录
    list.removeWhere((t) => t.isBefore(windowStart));
    if (list.length < rpm) return; // 还没到上限

    // 需要等待至最早一条记录超过 60 秒
    list.sort();
    final earliest = list.first;
    final waitMs = earliest.add(const Duration(minutes: 1)).difference(now).inMilliseconds;
    if (waitMs > 0) {
      await Future.delayed(Duration(milliseconds: waitMs));
    }
  }

  // 记录一次请求
  void record(String providerId) {
    final list = _requests.putIfAbsent(providerId, () => <DateTime>[]);
    final now = DateTime.now();
    list.add(now);
  }

  void reset(String providerId) {
    _requests.remove(providerId);
  }
}
