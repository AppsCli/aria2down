import 'package:aria2down/core/bt_announce.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('announceTiersFromBittorrent 仅 announce', () {
    final r = announceTiersFromBittorrent({'announce': 'http://a/announce'});
    expect(r, [
      ['http://a/announce'],
    ]);
  });

  test('announceTiersFromBittorrent announce-list 多 tier', () {
    final r = announceTiersFromBittorrent({
      'announceList': [
        ['http://t1', 'http://t2'],
        ['http://t3'],
      ],
    });
    expect(r, [
      ['http://t1', 'http://t2'],
      ['http://t3'],
    ]);
  });

  test('announceTiersFromBittorrent 有 announce-list 时忽略孤立 announce', () {
    final r = announceTiersFromBittorrent({
      'announce': 'http://legacy/announce',
      'announceList': [
        ['http://only/'],
      ],
    });
    expect(r, [
      ['http://only/'],
    ]);
  });
}
