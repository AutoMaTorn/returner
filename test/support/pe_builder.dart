import 'dart:typed_data';

/// Bytes that start like a Microsoft Cabinet of [length] bytes in total.
Uint8List fakeCabinet(int length, {bool header = true}) {
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  if (header) data.setUint32(0, 0x4643534d, Endian.little); // MSCF
  data.setUint32(8, length, Endian.little);
  for (var i = 36; i < length; i++) {
    bytes[i] = i & 0xff;
  }
  return bytes;
}

/// A minimal PE file whose only section is `.rsrc` with one resource:
/// RT_RCDATA (10) / [resourceName] / 1033 → [payload]. The same layout as
/// Apple's `iTunes64Setup.exe`, without any code.
Uint8List fakeInstaller(Uint8List payload, {String resourceName = 'CABINET'}) {
  const rawPointer = 0x200;
  const virtualAddress = 0x1000;
  const dataOffset = 0x80;
  final name = resourceName.codeUnits;
  final rsrcLength = dataOffset + payload.length;
  final bytes = Uint8List(rawPointer + rsrcLength);
  final d = ByteData.sublistView(bytes);
  void u16(int o, int v) => d.setUint16(o, v, Endian.little);
  void u32(int o, int v) => d.setUint32(o, v, Endian.little);

  u16(0, 0x5a4d); // MZ
  u32(0x3c, 0x40);
  u32(0x40, 0x00004550); // PE\0\0
  u16(0x44, 0x8664);
  u16(0x46, 1); // one section
  u16(0x54, 0); // no optional header
  const section = 0x58;
  bytes.setAll(section, '.rsrc'.codeUnits);
  u32(section + 8, rsrcLength);
  u32(section + 12, virtualAddress);
  u32(section + 16, rsrcLength);
  u32(section + 20, rawPointer);

  const r = rawPointer;
  // Root: one id entry, type 10.
  u16(r + 14, 1);
  u32(r + 16, 10);
  u32(r + 20, 0x80000000 | 0x18);
  // Type 10: one named entry.
  u16(r + 0x18 + 12, 1);
  u32(r + 0x18 + 16, 0x80000000 | 0x58);
  u32(r + 0x18 + 20, 0x80000000 | 0x30);
  // Name: one language entry pointing at a data entry.
  u16(r + 0x30 + 14, 1);
  u32(r + 0x30 + 16, 1033);
  u32(r + 0x30 + 20, 0x48);
  // Data entry.
  u32(r + 0x48, virtualAddress + dataOffset);
  u32(r + 0x48 + 4, payload.length);
  // Resource name.
  u16(r + 0x58, name.length);
  for (var i = 0; i < name.length; i++) {
    u16(r + 0x5a + 2 * i, name[i]);
  }
  bytes.setAll(r + dataOffset, payload);
  return bytes;
}
