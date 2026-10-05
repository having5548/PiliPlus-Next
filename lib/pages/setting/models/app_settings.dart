import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/auto_start.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 软件设置:应用级行为(开机自启、托盘等);外观设置与推荐流设置作为
/// 置顶的三级页面入口收纳于此,顶层列表不再重复展示
List<SettingsModel> get appSettings => [
  NormalModel(
    title: '外观设置',
    subtitle: '主题、字号、图片质量、帧率、首页与侧栏样式等',
    leading: const Icon(Icons.style_outlined),
    onTap: (_, _) => Get.to(
      () => const CommonSetting(settingType: SettingType.styleSetting),
    ),
  ),
  NormalModel(
    title: '推荐流设置',
    subtitle: '推荐来源(web/app)、刷新保留内容、过滤器',
    leading: const Icon(Icons.explore_outlined),
    onTap: (_, _) => Get.to(
      () => const CommonSetting(settingType: SettingType.recommendSetting),
    ),
  ),
  if (AutoStart.isSupported)
    SwitchModel(
      title: '开机自启',
      subtitle: '登录系统后自动启动应用',
      leading: const Icon(Icons.rocket_launch_outlined),
      setKey: SettingBoxKey.autoStart,
      defaultVal: AutoStart.enabled,
      onChanged: AutoStart.setEnabled,
    ),
  if (AutoStart.isSupported)
    SwitchModel(
      title: '关闭时最小化到托盘',
      subtitle: '点击关闭按钮时隐藏到托盘而不是退出',
      leading: const Icon(Icons.exit_to_app),
      setKey: SettingBoxKey.minimizeOnExit,
      defaultVal: true,
      onChanged: (_) {},
    ),
];
