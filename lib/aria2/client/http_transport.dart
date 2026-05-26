import 'dart:convert';

import 'package:dio/dio.dart';

import 'aria2_exceptions.dart';
import 'rpc_transport.dart';

/// JSON-RPC 2.0 over HTTP POST to `/jsonrpc`。
final class Aria2HttpTransport implements Aria2RpcTransport {
  Aria2HttpTransport({required Uri endpoint, required String secret, Dio? dio})
    : _endpoint = endpoint,
      _secret = secret,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ),
          );

  final Uri _endpoint;
  final String _secret;
  final Dio _dio;
  int _id = 0;

  String _nextId() => '${++_id}';

  /// [params] are appended after `token:<secret>`.
  @override
  Future<Object?> call(String method, List<dynamic> params) async {
    final body = <String, Object?>{
      'jsonrpc': '2.0',
      'id': _nextId(),
      'method': method,
      'params': <dynamic>['token:$_secret', ...params],
    };
    try {
      final response = await _dio.post<String>(
        _endpoint.toString(),
        data: jsonEncode(body),
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final raw = response.data;
      if (raw == null || raw.isEmpty) {
        throw const Aria2TransportException('空响应');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw Aria2TransportException('响应不是 JSON 对象: ${decoded.runtimeType}');
      }
      final data = Map<String, dynamic>.from(decoded);
      if (data.containsKey('error')) {
        final err = data['error'];
        int? code;
        String msg = 'RPC error';
        if (err is Map<String, dynamic>) {
          // 非标准 RPC 代理偶尔会把 code 编为 num（含 `1.0` 这种浮点表达），
          // `as int?` 会失败抛 TypeError，丢掉真实错误码；用 `num?.toInt()`
          // 容错。
          code = (err['code'] as num?)?.toInt();
          final m = err['message'];
          if (m is String) msg = m;
        }
        throw Aria2RpcException(msg, code: code);
      }
      return data['result'];
    } on DioException catch (e, st) {
      Error.throwWithStackTrace(
        Aria2TransportException('HTTP 请求失败: ${e.message}', cause: e),
        st,
      );
    }
  }
}
