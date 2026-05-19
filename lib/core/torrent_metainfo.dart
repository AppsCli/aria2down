import 'dart:convert';
import 'dart:typed_data';

/// 种子内文件项（1-based 索引，与 aria2 `select-file` 一致）。
class TorrentFileEntry {
  const TorrentFileEntry({required this.index, required this.displayName});

  final int index;
  final String displayName;
}

/// 从 `.torrent` 原始字节解析 `info.files` 或单文件 `info.name`。
/// 解析失败（非标准结构、加密种子等）返回空列表。
List<TorrentFileEntry> parseTorrentFileList(Uint8List data) {
  try {
    final root = _bdecodeValue(data, _DecodeCtx(data));
    if (root is! Map) return [];
    final info = root['info'];
    if (info is! Map) return [];
    final files = info['files'];
    if (files is List) {
      var idx = 1;
      final out = <TorrentFileEntry>[];
      for (final f in files) {
        if (f is! Map) continue;
        final pathEl = f['path'];
        var name = 'file_$idx';
        if (pathEl is List) {
          final parts = <String>[];
          for (final p in pathEl) {
            parts.add(_bytesToStr(p));
          }
          name = parts.join('/');
        }
        out.add(TorrentFileEntry(index: idx, displayName: name));
        idx++;
      }
      return out;
    }
    final name = info['name'];
    return [TorrentFileEntry(index: 1, displayName: _bytesToStr(name))];
  } catch (_) {
    return [];
  }
}

String _bytesToStr(Object? v) {
  if (v is Uint8List) return utf8.decode(v, allowMalformed: true);
  if (v is List<int>) {
    return utf8.decode(Uint8List.fromList(v), allowMalformed: true);
  }
  return '$v';
}

class _DecodeCtx {
  _DecodeCtx(this.data);

  final Uint8List data;
  int pos = 0;

  int readByte() {
    if (pos >= data.length) throw const FormatException('truncated');
    return data[pos++];
  }

  int peekByte() {
    if (pos >= data.length) throw const FormatException('truncated');
    return data[pos];
  }
}

Object? _bdecodeValue(Uint8List data, _DecodeCtx c) {
  final b = c.peekByte();
  if (b == 0x69) return _readInt(c);
  if (b == 0x6c) return _readList(data, c);
  if (b == 0x64) return _readDict(data, c);
  if (b >= 0x30 && b <= 0x39) return _readBytes(c);
  throw FormatException('bencode', c.pos);
}

int _readInt(_DecodeCtx c) {
  if (c.readByte() != 0x69) throw const FormatException('int');
  final buf = StringBuffer();
  var ch = c.readByte();
  while (ch != 0x65) {
    buf.writeCharCode(ch);
    ch = c.readByte();
  }
  return int.parse(buf.toString());
}

Uint8List _readBytes(_DecodeCtx c) {
  final lenBuf = StringBuffer();
  while (true) {
    final ch = c.readByte();
    if (ch == 0x3a) break;
    lenBuf.writeCharCode(ch);
  }
  final len = int.parse(lenBuf.toString());
  final end = c.pos + len;
  if (end > c.data.length) throw const FormatException('string len');
  final out = Uint8List.sublistView(c.data, c.pos, end);
  c.pos = end;
  return out;
}

List<Object?> _readList(Uint8List data, _DecodeCtx c) {
  if (c.readByte() != 0x6c) throw const FormatException('list');
  final out = <Object?>[];
  while (c.peekByte() != 0x65) {
    out.add(_bdecodeValue(data, c));
  }
  c.readByte(); // e
  return out;
}

Map<String, Object?> _readDict(Uint8List data, _DecodeCtx c) {
  if (c.readByte() != 0x64) throw const FormatException('dict');
  final out = <String, Object?>{};
  while (c.peekByte() != 0x65) {
    final kRaw = _readBytes(c);
    final k = utf8.decode(kRaw, allowMalformed: true);
    out[k] = _bdecodeValue(data, c);
  }
  c.readByte(); // e
  return out;
}
