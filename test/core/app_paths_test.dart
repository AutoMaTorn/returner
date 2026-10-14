import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:returner/core/app_paths.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('returner_paths_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test(
    'creates the data layout under a path with Cyrillic and spaces',
    () async {
      final paths = AppPaths(p.join(temp.path, 'Иван Петров', 'Returner'));
      await paths.ensure();

      for (final dir in [
        paths.ipatoolState,
        paths.library,
        paths.staging,
        paths.logs,
      ]) {
        expect(Directory(dir).existsSync(), isTrue, reason: dir);
      }

      final staged = File(p.join(paths.stagingFor('op-1'), 'app.ipa.tmp'));
      await staged.create(recursive: true);
      await staged.writeAsString('данные');
      expect(await staged.readAsString(), 'данные');
      expect(p.isWithin(paths.root, paths.database), isTrue);
    },
  );

  test('ensure is safe to call twice', () async {
    final paths = AppPaths(temp.path);
    await paths.ensure();
    await paths.ensure();
  });
}
