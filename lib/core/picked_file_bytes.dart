import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Reads bytes from a [FilePicker] result on all platforms.
///
/// On Android scoped storage, [PlatformFile.path] is often null; use
/// [withData: true] when picking and fall back to [PlatformFile.bytes].
Future<Uint8List?> readPickedFileBytes(PlatformFile file) async {
  final inMemory = file.bytes;
  if (inMemory != null && inMemory.isNotEmpty) {
    return inMemory;
  }
  final path = file.path;
  if (path == null || path.isEmpty) return null;
  return File(path).readAsBytes();
}
