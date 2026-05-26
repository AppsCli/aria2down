import 'package:aria2down/l10n/app_localizations.dart';

/// 将 RPC / 网络异常转为用户可读文案。
String formatRpcError(AppLocalizations l10n, Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('connection refused') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection reset') ||
      s.contains('connection timed out') ||
      s.contains('timed out') ||
      s.contains('socketexception')) {
    return l10n.rpcErrorConnection;
  }
  if (s.contains('unauthorized') ||
      s.contains('401') ||
      s.contains('wrong secret') ||
      s.contains('token')) {
    return l10n.rpcErrorUnauthorized;
  }
  return l10n.rpcErrorGeneric(error.toString());
}
