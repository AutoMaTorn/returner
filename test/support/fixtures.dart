import 'dart:io';

/// Reads a file from `test/fixtures/`.
String fixture(String relativePath) =>
    File('test/fixtures/$relativePath').readAsStringSync();
