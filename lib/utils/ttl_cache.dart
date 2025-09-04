// lib/utils/ttl_cache.dart
// Simple in-memory TTL cache for small computed values (counts, lookups).

class TtlCache<T> {
  final Duration ttl;
  final Map<String, _Entry<T>> _map = {};

  TtlCache({required this.ttl});

  T? get(String key) {
    final e = _map[key];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expiry)) {
      _map.remove(key);
      return null;
    }
    return e.value;
  }

  void set(String key, T value) {
    _map[key] = _Entry(value, DateTime.now().add(ttl));
  }

  void invalidate(String key) => _map.remove(key);
  void clear() => _map.clear();
}

class _Entry<T> {
  final T value;
  final DateTime expiry;
  _Entry(this.value, this.expiry);
}
