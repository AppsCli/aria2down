import 'package:aria2down/core/reveal_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractUrisFromTask 读取 files.uris', () {
    final task = <String, dynamic>{
      'gid': '1',
      'files': [
        {
          'uris': [
            {'uri': 'https://a/x.zip'},
          ],
        },
      ],
    };
    expect(extractUrisFromTask(task), ['https://a/x.zip']);
  });

  test('resolveRevealPath 优先文件路径', () {
    final task = <String, dynamic>{
      'dir': '/downloads',
      'files': [
        {'path': '/downloads/f.bin'},
      ],
    };
    expect(resolveRevealPath(task), '/downloads/f.bin');
  });

  test('resolveRevealPath 回退到 dir', () {
    final task = <String, dynamic>{
      'dir': '/tmp',
      'files': [
        {'path': ''},
      ],
    };
    expect(resolveRevealPath(task), '/tmp');
  });
}
