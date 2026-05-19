/// JSON-RPC 传输抽象（便于单测注入 Fake）。
abstract class Aria2RpcTransport {
  Future<Object?> call(String method, List<dynamic> params);
}
