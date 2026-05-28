import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/settings_repository.dart';

/// 应用配置的单一可信源。
///
/// 设置页里**不再有「保存」按钮**——任何字段调整都走 [AppSettingsNotifier]
/// 的 [AppSettingsNotifier.set] / [AppSettingsNotifier.mutate]，先把新值
/// 发布到 `state`（UI 立刻反应：主题、语言、托盘等订阅者会即时重建），再
/// 异步持久化到 [SettingsRepository]。
///
/// `aria2DaemonProvider` 用 `selectAsync` 只盯连接相关字段，所以
/// theme / locale / 种子色这类变更**不会**重启 aria2；连接模式 / 远程端点 /
/// 远程 secret / 本机引擎初始化参数变了才触发 daemon 重建。
///
/// 注意：避免覆盖父类 `AsyncNotifier.update` 的签名——它在 Riverpod 里
/// 已有用作「读 → 转换 → 写」的固定形态，我们这里的语义不同，所以用 `set`。
class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => SettingsRepository.load();

  /// 用 [next] 替换当前配置；先写内存 [state] 再异步持久化。
  ///
  /// 失败时回滚到先前值，并通过 `AsyncError` 把异常暴露给监听方——设置写盘
  /// 失败应让 UI 感知，而非悄无声息地吞掉。
  Future<void> set(AppSettings next) async {
    final previous = state.valueOrNull ?? const AppSettings();
    if (previous == next) return;
    state = AsyncData(next);
    try {
      await SettingsRepository.save(next);
    } catch (e, st) {
      state = AsyncData(previous);
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// 把当前配置传给 [transform] 取得下一份 [AppSettings] 再 [set]。
  ///
  /// 适合「切到本机模式」这类只动一个字段的回调，省去 callsite 自行
  /// 读 future 再 copyWith 的样板。
  Future<void> mutate(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final current = state.valueOrNull ?? await future;
    await set(transform(current));
  }

  /// 清空所有持久化键，回到 [AppSettings.defaults]。
  Future<void> resetToDefaults() async {
    await SettingsRepository.resetToDefaults();
    state = const AsyncData(AppSettings());
  }
}

/// 从磁盘加载 [AppSettings]，并暴露写回 / 重置 API。
///
/// 保留 `appSettingsProvider` 旧名是为了让现有 `ref.watch(appSettingsProvider)`
/// / `ref.read(appSettingsProvider.future)` / `ref.invalidate(...)` 全部
/// 继续可用——`AsyncNotifierProvider` 对外契约与原 `FutureProvider` 一致。
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );
