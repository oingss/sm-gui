// 生成托盘图标 PNG（运行中=绿色圆点 / 停止=灰色圆点）。
// 无第三方依赖，手写最小 PNG（IHDR + 存储型 deflate IDAT + IEND）。
// 运行：dart tool/gen_tray_icons.dart（在 apps/desktop 目录下）
import 'dart:io';
import 'dart:typed_data';

const int size = 32;

Future<void> main() async {
  await _write('assets/tray_running.png', 0x4C, 0xAF, 0x50); // Material green
  await _write('assets/tray_stopped.png', 0x9E, 0x9E, 0x9E); // Material grey
  stdout.writeln('托盘图标已生成到 assets/');
}

Future<void> _write(String path, int r, int g, int b) async {
  final png = _encodePng(_drawDot(r, g, b));
  final f = File(path);
  if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
  await f.writeAsBytes(png);
  stdout.writeln('写入 $path（${png.length} bytes）');
}

/// 4x 超采样画一个实心圆，边缘带抗锯齿。
Uint8List _drawDot(int r, int g, int b) {
  const radius = 10.0;
  const cx = (size - 1) / 2, cy = (size - 1) / 2;
  final rgba = Uint8List(size * size * 4);
  var p = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var hit = 0;
      for (final dy in const [0.125, 0.375, 0.625, 0.875]) {
        for (final dx in const [0.125, 0.375, 0.625, 0.875]) {
          final ddx = x + dx - cx;
          final ddy = y + dy - cy;
          if (ddx * ddx + ddy * ddy <= radius * radius) hit++;
        }
      }
      rgba[p++] = r;
      rgba[p++] = g;
      rgba[p++] = b;
      rgba[p++] = hit * 255 ~/ 16;
    }
  }
  return rgba;
}

/// 把 RGBA 像素编码为最小 PNG（color type 6, bit depth 8）。
Uint8List _encodePng(Uint8List rgba) {
  // 每行前置 filter byte 0（None）。
  final raw = Uint8List(size * (size * 4 + 1));
  for (var y = 0; y < size; y++) {
    final rowStart = y * (size * 4 + 1);
    raw[rowStart] = 0;
    raw.setRange(rowStart + 1, rowStart + 1 + size * 4,
        rgba.sublist(y * size * 4, (y + 1) * size * 4));
  }

  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // 签名
  out.add(_chunk('IHDR', _ihdr()));
  out.add(_chunk('IDAT', _zlibStored(raw)));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _ihdr() {
  final b = ByteData(13);
  b.setUint32(0, size); // width
  b.setUint32(4, size); // height
  b.setUint8(8, 8); // bit depth
  b.setUint8(9, 6); // color type: RGBA
  b.setUint8(10, 0); // compression
  b.setUint8(11, 0); // filter
  b.setUint8(12, 0); // interlace
  return b.buffer.asUint8List();
}

/// zlib 流（0x78 0x01）+ 单个「存储型」deflate 块 + adler32。
Uint8List _zlibStored(Uint8List data) {
  final out = BytesBuilder();
  out.add(const [0x78, 0x01]);
  var offset = 0;
  while (offset < data.length) {
    final n = (data.length - offset) > 65535 ? 65535 : data.length - offset;
    final finalBlock = offset + n >= data.length;
    out.addByte(finalBlock ? 1 : 0);
    final len = ByteData(2)..setUint16(0, n, Endian.little);
    out.add(len.buffer.asUint8List());
    final nlen = ByteData(2)..setUint16(0, n ^ 0xFFFF, Endian.little);
    out.add(nlen.buffer.asUint8List());
    out.add(data.sublist(offset, offset + n));
    offset += n;
  }
  final a = ByteData(4)..setUint32(0, _adler32(data), Endian.big);
  out.add(a.buffer.asUint8List());
  return out.toBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final b = BytesBuilder();
  final len = ByteData(4)..setUint32(0, data.length, Endian.big);
  b.add(len.buffer.asUint8List());
  final typeBytes = type.codeUnits;
  b.add(typeBytes);
  b.add(data);
  final crc = ByteData(4)
    ..setUint32(0, _crc32([...typeBytes, ...data]), Endian.big);
  b.add(crc.buffer.asUint8List());
  return b.toBytes();
}

final List<int> _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) == 1 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

int _adler32(Uint8List data) {
  var a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}
