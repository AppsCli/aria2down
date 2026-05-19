import 'package:aria2down/core/rpc_error_message.dart';
import 'package:aria2down/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatRpcError maps connection refused', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final msg = formatRpcError(l10n, Exception('Connection refused'));
    expect(msg, l10n.rpcErrorConnection);
  });

  test('formatRpcError maps unauthorized', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final msg = formatRpcError(l10n, Exception('HTTP 401 Unauthorized'));
    expect(msg, l10n.rpcErrorUnauthorized);
  });

  test('formatRpcError maps timeout', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final msg = formatRpcError(
      l10n,
      Exception('SocketException: Connection timed out'),
    );
    expect(msg, l10n.rpcErrorConnection);
  });
}
