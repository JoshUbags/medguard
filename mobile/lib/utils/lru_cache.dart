/// Tiny in-memory LRU cache used by the search + safety-report paths to avoid
/// re-running expensive SQL or interaction-analysis work on the same keys.
///
/// Backed by a [LinkedHashMap] so insertion order is preserved; touching a key
/// (via [get] or [put]) moves it to the most-recently-used end. When the cache
/// exceeds [capacity], the oldest entry is evicted.
class LruCache<K, V> {
  LruCache({this.capacity = 100}) : assert(capacity > 0);

  final int capacity;
  final Map<K, V> _entries = <K, V>{};

  V? get(K key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key) as V;
    _entries[key] = value; // Move-to-back.
    return value;
  }

  void put(K key, V value) {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else if (_entries.length >= capacity) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  void invalidate(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }

  int get length => _entries.length;
}
