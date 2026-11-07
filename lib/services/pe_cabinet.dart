import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads [length] bytes at [offset]; may return fewer at the end of the file.
typedef ReadAt = Future<Uint8List> Function(int offset, int length);

/// Where a Microsoft Cabinet sits inside a file.
class CabinetLocation {
  const CabinetLocation(this.offset, this.length);

  final int offset;
  final int length;

  @override
  bool operator ==(Object other) =>
      other is CabinetLocation &&
      other.offset == offset &&
      other.length == length;

  @override
  int get hashCode => Object.hash(offset, length);

  @override
  String toString() => 'CabinetLocation($offset, $length)';
}

/// Finds the cabinet that Apple's Windows installers (`iTunes64Setup.exe`)
/// keep as a PE resource named `CABINET`.
///
/// Only the headers are read, so this works on a 200 MB file without loading
/// it. Returns null when the file is not a PE, has no such resource, or the
/// resource does not start with a cabinet header.
Future<CabinetLocation?> findCabinet(ReadAt read) async {
  try {
    return await _find(read);
  } on RangeError {
    return null;
  } on FormatException {
    return null;
  }
}

Future<CabinetLocation?> findCabinetInFile(String path) async {
  final file = await File(path).open();
  try {
    return await findCabinet((offset, length) async {
      await file.setPosition(offset);
      return file.read(length);
    });
  } finally {
    await file.close();
  }
}

Future<CabinetLocation?> _find(ReadAt read) async {
  Future<ByteData> bytes(int offset, int length) async {
    final data = await read(offset, length);
    if (data.length < length) throw RangeError('short read at $offset');
    return ByteData.sublistView(data);
  }

  final dos = await bytes(0, 64);
  if (dos.getUint16(0, Endian.little) != 0x5a4d) return null; // "MZ"
  final pe = dos.getUint32(0x3c, Endian.little);
  final coff = await bytes(pe, 24);
  if (coff.getUint32(0, Endian.little) != 0x00004550) return null; // "PE\0\0"
  final sectionCount = coff.getUint16(6, Endian.little);
  final optionalSize = coff.getUint16(20, Endian.little);
  if (sectionCount == 0 || sectionCount > 96) return null;
  final sections = await bytes(pe + 24 + optionalSize, 40 * sectionCount);

  int? rsrcVa, rsrcRaw, rsrcSize;
  for (var i = 0; i < sectionCount; i++) {
    final o = 40 * i;
    final name = ascii.decode(
      sections.buffer
          .asUint8List(sections.offsetInBytes + o, 8)
          .takeWhile((b) => b != 0)
          .toList(),
      allowInvalid: true,
    );
    if (name != '.rsrc') continue;
    rsrcVa = sections.getUint32(o + 12, Endian.little);
    rsrcSize = sections.getUint32(o + 16, Endian.little);
    rsrcRaw = sections.getUint32(o + 20, Endian.little);
  }
  if (rsrcVa == null || rsrcRaw == null || rsrcSize == null) return null;
  final va = rsrcVa, raw = rsrcRaw, size = rsrcSize;

  Future<String> nameAt(int offset) async {
    final length = (await bytes(raw + offset, 2)).getUint16(0, Endian.little);
    final chars = await bytes(raw + offset + 2, 2 * length);
    return String.fromCharCodes([
      for (var i = 0; i < length; i++) chars.getUint16(2 * i, Endian.little),
    ]);
  }

  // Resource tree: type → name → language → data entry. The cabinet is a
  // named resource; any level may carry the name.
  Future<CabinetLocation?> walk(int offset, int depth, bool named) async {
    if (depth > 3 || offset >= size) return null;
    final header = await bytes(raw + offset, 16);
    final count =
        header.getUint16(12, Endian.little) +
        header.getUint16(14, Endian.little);
    if (count > 4096) return null;
    final entries = await bytes(raw + offset + 16, 8 * count);
    for (var i = 0; i < count; i++) {
      final id = entries.getUint32(8 * i, Endian.little);
      final target = entries.getUint32(8 * i + 4, Endian.little);
      final isCabinet =
          named ||
          ((id & 0x80000000) != 0 &&
              await nameAt(id & 0x7fffffff) == 'CABINET');
      if ((target & 0x80000000) != 0) {
        final found = await walk(target & 0x7fffffff, depth + 1, isCabinet);
        if (found != null) return found;
      } else if (isCabinet) {
        final entry = await bytes(raw + target, 8);
        final location = CabinetLocation(
          entry.getUint32(0, Endian.little) - va + raw,
          entry.getUint32(4, Endian.little),
        );
        final cab = await bytes(location.offset, 12);
        if (cab.getUint32(0, Endian.little) != 0x4643534d) return null; // MSCF
        final cabSize = cab.getUint32(8, Endian.little);
        if (cabSize == 0 || cabSize > location.length) return null;
        return CabinetLocation(location.offset, cabSize);
      }
    }
    return null;
  }

  return walk(0, 0, false);
}
