import 'package:shared_preferences/shared_preferences.dart';

/// 一次性平台提示（如 iOS/Android/Web 推荐远程模式）。
abstract final class OnboardingRepository {
  static const _keyPlatformHint = 'onboarding.platform_hint_dismissed';
  static const _keyWelcomeRemote = 'onboarding.welcome_remote_shown';

  static Future<bool> isPlatformHintDismissed() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyPlatformHint) ?? false;
  }

  static Future<void> dismissPlatformHint() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyPlatformHint, true);
  }

  static Future<bool> isWelcomeRemoteShown() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyWelcomeRemote) ?? false;
  }

  static Future<void> setWelcomeRemoteShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyWelcomeRemote, true);
  }
}
