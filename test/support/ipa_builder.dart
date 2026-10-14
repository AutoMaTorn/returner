import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// `Info.plist` in XML form.
String infoPlistXml({
  String bundleId = 'com.example.app',
  String? displayName = 'Example',
  String version = '1.2.3',
  String build = '45',
  String? minimumOS = '15.0',
}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$bundleId</string>
  ${displayName == null ? '' : '<key>CFBundleDisplayName</key><string>$displayName</string>'}
  <key>CFBundleName</key><string>ExampleBundle</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  ${minimumOS == null ? '' : '<key>MinimumOSVersion</key><string>$minimumOS</string>'}
  <key>LSRequiresIPhoneOS</key><true/>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
</dict>
</plist>
''';

/// Builds a small `.ipa`-shaped ZIP. [files] maps entry names to contents.
Uint8List buildZip(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(bytes)));
  });
  return ZipEncoder().encodeBytes(archive);
}

/// Writes a minimal valid package and returns its path.
String writeIpa(
  Directory directory, {
  String name = 'app.ipa',
  List<int>? infoPlist,
  Map<String, List<int>> extra = const {},
}) {
  final file = File('${directory.path}/$name');
  file.writeAsBytesSync(
    buildZip({
      'Payload/Example.app/Info.plist':
          infoPlist ?? utf8.encode(infoPlistXml()),
      'Payload/Example.app/Example': List<int>.filled(4096, 7),
      'Payload/Example.app/PlugIns/Widget.appex/Info.plist': utf8.encode(
        infoPlistXml(bundleId: 'com.example.app.widget'),
      ),
      'iTunesMetadata.plist': utf8.encode(
        '<plist version="1.0"><dict/></plist>',
      ),
      ...extra,
    }),
  );
  return file.path;
}
