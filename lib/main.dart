import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app.dart';
import 'core/app_paths.dart';
import 'core/log.dart';
import 'core/log_file.dart';
import 'services/lookup_service.dart';
import 'state/providers.dart';
import 'state/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve();
  await paths.ensure();
  Log.init(file: LogFile(paths.logs));
  Log.info('Returner started');
  runApp(
    ProviderScope(
      overrides: [
        appPathsProvider.overrideWithValue(paths),
        lookupServiceProvider.overrideWithValue(
          LookupService(
            client: http.Client(),
            iconDirectory: p.join(paths.root, 'icons'),
          ),
        ),
      ],
      child: const ReturnerApp(),
    ),
  );
}
