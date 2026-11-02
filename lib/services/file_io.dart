import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

class PickedFile {
  const PickedFile({required this.name, required this.bytes, required this.mimeType});
  final String name;
  final Uint8List bytes;
  final String mimeType;
}

/// Opens the system file picker and reads the chosen file into memory.
Future<PickedFile?> pickFile() async {
  final result = await FilePicker.pickFiles(withData: true);
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return PickedFile(name: file.name, bytes: bytes, mimeType: guessMimeType(file.name, bytes));
}

String guessMimeType(String name, Uint8List bytes) =>
    lookupMimeType(name, headerBytes: bytes.take(defaultMagicNumbersMaxLength).toList()) ??
    'application/octet-stream';

/// Save dialog on Android/iOS/macOS, browser download on web.
/// Returns false if the user cancelled.
Future<bool> saveBytes(Uint8List bytes, String fileName) async {
  final path = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
  // Web downloads return null even on success.
  return path != null || kIsWeb;
}

/// Hands the file to the OS share sheet (WhatsApp, Mail, AirDrop, …).
Future<void> shareBytes(BuildContext context, Uint8List bytes, String fileName, String mimeType) {
  final box = context.findRenderObject() as RenderBox?;
  return SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
    fileNameOverrides: [fileName],
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
