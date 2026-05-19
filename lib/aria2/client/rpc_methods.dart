/// JSON-RPC method names for aria2.
/// See https://aria2.github.io/manual/en/html/aria2c.html#rpc-interface
abstract final class RpcMethods {
  static const addUri = 'aria2.addUri';
  static const addTorrent = 'aria2.addTorrent';
  static const addMetalink = 'aria2.addMetalink';
  static const remove = 'aria2.remove';
  static const forceRemove = 'aria2.forceRemove';
  static const pause = 'aria2.pause';
  static const pauseAll = 'aria2.pauseAll';
  static const forcePause = 'aria2.forcePause';
  static const forcePauseAll = 'aria2.forcePauseAll';
  static const unpause = 'aria2.unpause';
  static const unpauseAll = 'aria2.unpauseAll';
  static const purgeDownloadResult = 'aria2.purgeDownloadResult';
  static const removeDownloadResult = 'aria2.removeDownloadResult';
  static const getFiles = 'aria2.getFiles';
  static const getPeers = 'aria2.getPeers';
  static const tellStatus = 'aria2.tellStatus';
  static const tellActive = 'aria2.tellActive';
  static const tellWaiting = 'aria2.tellWaiting';
  static const tellStopped = 'aria2.tellStopped';
  static const getGlobalStat = 'aria2.getGlobalStat';
  static const getGlobalOption = 'aria2.getGlobalOption';
  static const changeGlobalOption = 'aria2.changeGlobalOption';
  static const getOption = 'aria2.getOption';
  static const changeOption = 'aria2.changeOption';
  static const getVersion = 'aria2.getVersion';
  static const shutdown = 'aria2.shutdown';
  static const forceShutdown = 'aria2.forceShutdown';
}
