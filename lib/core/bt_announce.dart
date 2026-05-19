/// 从 aria2 `tellStatus` 返回的 `bittorrent` 字典解析 announce 分层结构。
/// 与 `announce-list` 一致：外层列表为 tier，内层为该 tier 内多个 tracker URL。
List<List<String>> announceTiersFromBittorrent(Map<String, dynamic>? bt) {
  if (bt == null) return const [];
  final tiers = <List<String>>[];
  final al = bt['announceList'];
  if (al is List) {
    for (final tier in al) {
      final urls = <String>[];
      if (tier is List) {
        for (final u in tier) {
          if (u is String && u.isNotEmpty) urls.add(u);
        }
      } else if (tier is String && tier.isNotEmpty) {
        urls.add(tier);
      }
      if (urls.isNotEmpty) tiers.add(urls);
    }
  }
  if (tiers.isEmpty) {
    final single = bt['announce'];
    if (single is String && single.isNotEmpty) {
      return [
        [single],
      ];
    }
  }
  return tiers;
}
