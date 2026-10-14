import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Parses an Apple property list in XML or binary (`bplist00`) form into
/// plain Dart values: Map, List, String, int, double, bool, DateTime,
/// Uint8List. Throws [FormatException] on malformed input.
Object? parsePlist(Uint8List data) {
  if (data.length >= 8 && ascii.decode(data.sublist(0, 6)) == 'bplist') {
    return _BinaryPlist(data).parse();
  }
  return _parseXml(utf8.decode(data, allowMalformed: true));
}

Object? _parseXml(String text) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw FormatException('Invalid XML plist: ${e.message}');
  }
  final root = document.rootElement;
  if (root.name.local != 'plist') {
    throw const FormatException('Not a property list');
  }
  final value = root.childElements.firstOrNull;
  if (value == null) throw const FormatException('Empty property list');
  return _xmlValue(value, 0);
}

Object? _xmlValue(XmlElement element, int depth) {
  if (depth > 64) throw const FormatException('Property list is too deep');
  final text = element.innerText;
  switch (element.name.local) {
    case 'dict':
      final result = <String, Object?>{};
      String? key;
      for (final child in element.childElements) {
        if (child.name.local == 'key') {
          key = child.innerText;
        } else if (key != null) {
          result[key] = _xmlValue(child, depth + 1);
          key = null;
        }
      }
      return result;
    case 'array':
      return [for (final c in element.childElements) _xmlValue(c, depth + 1)];
    case 'string':
      return text;
    case 'integer':
      return int.tryParse(text.trim()) ?? 0;
    case 'real':
      return double.tryParse(text.trim()) ?? 0.0;
    case 'true':
      return true;
    case 'false':
      return false;
    case 'date':
      return DateTime.tryParse(text.trim());
    case 'data':
      return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
    default:
      throw FormatException('Unknown plist element <${element.name.local}>');
  }
}

class _BinaryPlist {
  _BinaryPlist(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  late final int _offsetSize;
  late final int _refSize;
  late final int _objectCount;
  late final int _offsetTable;

  Object? parse() {
    if (_bytes.length < 40) throw const FormatException('Truncated bplist');
    final trailer = _bytes.length - 32;
    _offsetSize = _bytes[trailer + 6];
    _refSize = _bytes[trailer + 7];
    _objectCount = _uint(trailer + 8, 8);
    final top = _uint(trailer + 16, 8);
    _offsetTable = _uint(trailer + 24, 8);
    if (_offsetSize < 1 ||
        _offsetSize > 8 ||
        _refSize < 1 ||
        _refSize > 8 ||
        _objectCount > _bytes.length ||
        _offsetTable + _objectCount * _offsetSize > trailer) {
      throw const FormatException('Invalid bplist trailer');
    }
    return _object(top, 0);
  }

  int _uint(int offset, int size) {
    if (offset < 0 || offset + size > _bytes.length) {
      throw const FormatException('bplist offset out of range');
    }
    var value = 0;
    for (var i = 0; i < size; i++) {
      value = (value << 8) | _bytes[offset + i];
    }
    return value;
  }

  int _objectOffset(int index) {
    if (index < 0 || index >= _objectCount) {
      throw const FormatException('bplist object index out of range');
    }
    return _uint(_offsetTable + index * _offsetSize, _offsetSize);
  }

  /// Reads the length that follows a marker: either the low nibble or, when
  /// it is 0xF, an integer object. Returns (length, offset of the payload).
  (int, int) _length(int offset, int nibble) {
    if (nibble != 0xF) return (nibble, offset + 1);
    final marker = _uint(offset + 1, 1);
    if (marker >> 4 != 0x1) throw const FormatException('Bad bplist length');
    final size = 1 << (marker & 0xF);
    return (_uint(offset + 2, size), offset + 2 + size);
  }

  Object? _object(int index, int depth) {
    if (depth > 64) throw const FormatException('Property list is too deep');
    final offset = _objectOffset(index);
    final marker = _uint(offset, 1);
    final type = marker >> 4;
    final nibble = marker & 0xF;
    switch (type) {
      case 0x0:
        return switch (nibble) {
          0x8 => false,
          0x9 => true,
          _ => null,
        };
      case 0x1:
        final size = 1 << nibble;
        if (size > 8) return 0; // 128-bit integers do not occur in Info.plist
        final value = _uint(offset + 1, size);
        return size == 8 ? value.toSigned(64) : value;
      case 0x2:
        return switch (nibble) {
          2 => _data.getFloat32(offset + 1),
          3 => _data.getFloat64(offset + 1),
          _ => throw const FormatException('Bad bplist real'),
        };
      case 0x3:
        // Seconds since 2001-01-01 UTC.
        final seconds = _data.getFloat64(offset + 1);
        return DateTime.utc(2001)
            .add(Duration(microseconds: (seconds * 1e6).round()));
      case 0x4:
        final (length, start) = _length(offset, nibble);
        _uint(start, 0);
        return Uint8List.sublistView(_bytes, start, _end(start, length));
      case 0x5:
        final (length, start) = _length(offset, nibble);
        return ascii.decode(
          _bytes.sublist(start, _end(start, length)),
          allowInvalid: true,
        );
      case 0x6:
        final (length, start) = _length(offset, nibble);
        _end(start, length * 2);
        return String.fromCharCodes([
          for (var i = 0; i < length; i++) _data.getUint16(start + i * 2),
        ]);
      case 0x8:
        return _uint(offset + 1, nibble + 1);
      case 0xA:
        final (length, start) = _length(offset, nibble);
        _end(start, length * _refSize);
        return [
          for (var i = 0; i < length; i++)
            _object(_uint(start + i * _refSize, _refSize), depth + 1),
        ];
      case 0xD:
        final (length, start) = _length(offset, nibble);
        _end(start, length * _refSize * 2);
        final result = <String, Object?>{};
        for (var i = 0; i < length; i++) {
          final key = _object(_uint(start + i * _refSize, _refSize), depth + 1);
          final value = _object(
            _uint(start + (length + i) * _refSize, _refSize),
            depth + 1,
          );
          if (key is String) result[key] = value;
        }
        return result;
      default:
        throw FormatException(
          'Unknown bplist object type 0x${type.toRadixString(16)}',
        );
    }
  }

  int _end(int start, int length) {
    final end = start + length;
    if (length < 0 || end > _bytes.length) {
      throw const FormatException('bplist object runs past the end');
    }
    return end;
  }
}
