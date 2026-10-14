import 'package:returner/services/secure_store.dart';

class FakeSecretsBackend implements SecretsBackend {
  FakeSecretsBackend({this.failing = false, this.dropWrites = false});

  final values = <String, String>{};
  final bool failing;
  final bool dropWrites;

  @override
  Future<String?> read(String key) async {
    if (failing) throw StateError('credential store unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failing) throw StateError('credential store unavailable');
    if (!dropWrites) values[key] = value;
  }
}
