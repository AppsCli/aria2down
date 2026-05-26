// `resolveDownloadDirForTask` 控制 AddTaskPage 提交任务时 aria2 `dir` 选项的
// 最终来源。优先级出错会让用户在 askEachTime 弹窗里挑的路径被设置页全局默
// 认值覆盖、或者本次输入框的临时路径被忽略——必须有单测把这条规则钉死。
//
// 这里不测试 `pickDownloadDirectory`（涉及 file_selector / path_provider 平
// 台 channel，与 widget 集成测一并覆盖更合适）。

import 'package:aria2down/core/download_dir_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveDownloadDirForTask', () {
    test('overrideDir 优先级最高（askEachTime 弹窗选定 / 按钮 picker 结果）', () {
      final dir = resolveDownloadDirForTask(
        overrideDir: '/picked',
        manualField: '/manual',
        globalDefault: '/global',
      );
      expect(dir, '/picked');
    });

    test('没有 overrideDir 时回退到 manualField（用户在高级选项手填）', () {
      final dir = resolveDownloadDirForTask(
        overrideDir: null,
        manualField: '/manual',
        globalDefault: '/global',
      );
      expect(dir, '/manual');
    });

    test('overrideDir 与 manualField 都空时回退到 globalDefault', () {
      final dir = resolveDownloadDirForTask(
        overrideDir: null,
        manualField: null,
        globalDefault: '/global',
      );
      expect(dir, '/global');
    });

    test('全部都空 / null 返回 null（让 aria2 daemon 用进程级默认）', () {
      expect(
        resolveDownloadDirForTask(
          overrideDir: null,
          manualField: null,
          globalDefault: null,
        ),
        isNull,
      );
    });

    test('trim 后为空串视为「未设置」继续往下找', () {
      // 用户在 askEachTime 弹窗里点了取消（picker 返回空串）、或在输入框
      // 里删干净留下空白——都不应该当成"显式选了空目录"覆盖全局默认。
      final dir = resolveDownloadDirForTask(
        overrideDir: '   ',
        manualField: '\t\n',
        globalDefault: '/Volumes/D/dl',
      );
      expect(dir, '/Volumes/D/dl');
    });

    test('返回值保持 trim（前后空白去掉）', () {
      final dir = resolveDownloadDirForTask(
        overrideDir: '  /tmp/dl  ',
        manualField: null,
        globalDefault: null,
      );
      expect(dir, '/tmp/dl');
    });
  });
}
