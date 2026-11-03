import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';

/// Thin adapter: the only file importing `package:firebase_remote_config`
/// (TC22). No realtime listener (T29 §6: battery).
final class FirebaseRemoteConfigClient implements RemoteConfigClient {
  new([this._injected]);

  final FirebaseRemoteConfig? _injected;

  FirebaseRemoteConfig get _rc => _injected ?? FirebaseRemoteConfig.instance;

  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) async {
    await _rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: fetchTimeout,
        minimumFetchInterval: minimumFetchInterval,
      ),
    );
    await _rc.setDefaults(defaults);
  }

  @override
  Future<bool> fetchAndActivate() => _rc.fetchAndActivate();

  @override
  String getString(String key) => _rc.getString(key);
}
