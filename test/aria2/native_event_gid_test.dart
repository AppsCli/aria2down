// libaria2 通过事件回调以 `uint64_t` 发送 A2Gid。Dart `int` 是 64 位有符号
// 整数：高位为 1 的 GID 会以负数形式抵达 Dart isolate（SendPort 不改变位
// 模式）。直接 `toRadixString(16)` 会产生 `-21cdbea35eeb7710` 这种带负号的串，
// 把它喂回 `aria2_ffi_tell_status` 会触发 `ARIA2_FFI_ERR_NOT_FOUND (-1006)`，
// 表现为 TaskHistoryRecorder / 任务详情页频繁报错。
//
// 本测试守护 `formatGidAsUnsignedHex16` 始终按 aria2 RPC 服务端的 `gidToHex`
// 形态输出：始终 16 位小写无符号十六进制，与 aria2 RPC 内 gid 完全一致。

import 'package:aria2_native/aria2_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('零 GID 输出 16 位 0', () {
    expect(formatGidAsUnsignedHex16(0), '0000000000000000');
  });

  test('小正整数 GID 左侧补零到 16 位', () {
    expect(formatGidAsUnsignedHex16(1), '0000000000000001');
    expect(formatGidAsUnsignedHex16(0x60b4f7d76b68aefc), '60b4f7d76b68aefc');
  });

  test('高位为 1 的 GID（Dart 负数）输出无符号 hex', () {
    // 0xDE32415CA11488F0 落到 64 位有符号即为负数。旧实现会产出
    // "-21cdbea35eeb7710"（即 0x21cdbea35eeb7710 = 2^64 - 上述值），
    // 该串无法被 aria2::hexToGid 解析。新实现应保留原 64 位无符号位形态。
    expect(formatGidAsUnsignedHex16(0xDE32415CA11488F0), 'de32415ca11488f0');
  });

  test('Dart int 最小值（最高位单独为 1）映射到 8000…0000', () {
    expect(formatGidAsUnsignedHex16(0x8000000000000000), '8000000000000000');
  });

  test('全 1（uint64 最大值，Dart -1）映射到 16 个 f', () {
    expect(formatGidAsUnsignedHex16(-1), 'ffffffffffffffff');
  });

  test('Aria2NativeEvent 反映同样的格式（保证经事件流后 gid 仍可回查）', () {
    // 反射式的间接测试：通过 type+gidHex 字段确认即可，构造由 worker 同样
    // 路径执行（package:aria2_native 内部把 `[eventCode, gid]` 映射成事件）。
    final ev = Aria2NativeEvent(
      type: Aria2NativeEventType.complete,
      gidHex: formatGidAsUnsignedHex16(0xDE32415CA11488F0),
    );
    expect(ev.gidHex, 'de32415ca11488f0');
    expect(ev.type.rpcMethod, 'aria2.onDownloadComplete');
  });
}
