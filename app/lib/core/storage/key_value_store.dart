/// Small persistent settings (T29 §7 signature; T25 A5). Values are
/// preferences only: never coordinates or destination names.
library;

abstract interface class KeyValueStore {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);

  Future<int?> getInt(String key);

  Future<void> setInt(String key, int value);
}
