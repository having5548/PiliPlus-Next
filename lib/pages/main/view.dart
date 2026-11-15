import 'dart:io';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/desktop/tray_controller.dart';
import 'package:PiliPlus/utils/desktop/window_controller.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/dynamics/view.dart';
import 'package:PiliPlus/pages/feature_feed/view.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with RouteAware, RouteAwareMixin, WidgetsBindingObserver {
  final _mainController = Get.put(MainController());
  late EdgeInsets _padding;
  late ColorScheme _colorScheme;
  Brightness? _brightness;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      WindowController.instance.init();
      TrayController.instance.init();
    }
    if (!Platform.isMacOS) {
      PiliScheme.init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    _colorScheme = ColorScheme.of(context);
    final brightness = _colorScheme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        nativeapi.Application.instance.setBrightness(
          brightness == .dark ? .dark : .light,
        );
      }
    }
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      WindowController.instance.dispose();
      TrayController.instance.dispose();
    }
    removeObserverMobile(this);
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyR &&
        HardwareKeyboard.instance.isMetaPressed &&
        _mainController.refreshRecommendations();
  }

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (Platform.isAndroid) {
      AndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (_mainController.directExitOnBack) {
      _onBack();
    } else {
      if (_mainController.selectedIndex.value != 0) {
        _mainController
          ..setIndex(0)
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    }
  }

  Widget? get _bottomNav {
    Widget? bottomNav;
    final bars = _mainController.navigationBars;
    if (bars.length > 1) {
      final barsLen = bars.length;

      // 底栏末尾追加「更多」:竖屏/窄窗口下，设置、账号、主题等入口都收进 dock
      void onSelected(int index) {
        if (index == barsLen) {
          _toggleDock();
        } else {
          _closeDock();
          _mainController.setIndex(index);
        }
      }

      const moreIcon = Icon(Icons.more_horiz);

      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            onDestinationSelected: onSelected,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: [
              ...bars.map(
                (e) => FloatingNavigationDestination(
                  label: e.label,
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              ),
              const FloatingNavigationDestination(
                label: '更多',
                icon: moreIcon,
                selectedIcon: moreIcon,
              ),
            ],
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: onSelected,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: [
              ...bars.map(
                (e) => NavigationDestination(
                  label: e.label,
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              ),
              const NavigationDestination(
                label: '更多',
                icon: moreIcon,
                selectedIcon: moreIcon,
              ),
            ],
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: onSelected,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: [
              ...bars.map(
                (e) => BottomNavigationBarItem(
                  label: e.label,
                  icon: _buildIcon(type: e),
                  activeIcon: _buildIcon(type: e, selected: true),
                ),
              ),
              const BottomNavigationBarItem(
                label: '更多',
                icon: moreIcon,
                activeIcon: moreIcon,
              ),
            ],
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        if (_mainController.barOffset case final barOffset?) {
          return Obx(
            () => FractionalTranslation(
              translation: Offset(
                0.0,
                barOffset.value / Style.topBarHeight,
              ),
              child: bottomNav,
            ),
          );
        }
        if (_mainController.showBottomBar case final showBottomBar?) {
          return Obx(
            () => AnimatedSlide(
              curve: Curves.easeInOutCubicEmphasized,
              duration: const Duration(milliseconds: 500),
              offset: Offset(0, showBottomBar.value ? 0 : 1),
              child: bottomNav,
            ),
          );
        }
      }
    }

    return bottomNav;
  }

  bool _dockOpen = false;
  double _barHeight = 0;
  final GlobalKey _barKey = GlobalKey();
  static const _dockDuration = Duration(milliseconds: 260);

  void _toggleDock() => setState(() => _dockOpen = !_dockOpen);

  void _closeDock() {
    if (_dockOpen) setState(() => _dockOpen = false);
  }

  /// 竖屏底栏「更多」点开的圆角 dock：列数随窗口宽度自适应
  Widget _buildDock(BuildContext context) {
    final colorScheme = _colorScheme;
    final mineController = Get.putOrFind(MineController.new);

    void go(void Function() action) {
      _closeDock();
      action();
    }

    final entries = <({String label, Widget icon, void Function() onTap})>[
      (
        label: '搜索',
        icon: const Icon(Icons.search_outlined),
        onTap: () => go(() => Get.toNamed('/search')),
      ),
      (
        label: '消息',
        icon: const Icon(Icons.notifications_none),
        onTap: () => go(() {
          _mainController
            ..clearUnreadMsg()
            ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
          Get.toNamed('/whisper');
        }),
      ),
      (
        label: '设置',
        icon: const Icon(Icons.settings_outlined),
        onTap: () =>
            go(() => Get.toNamed('/setting', preventDuplicates: false)),
      ),
      (
        label: '主题',
        icon: mineController.themeType.value.icon,
        onTap: () => go(mineController.onChangeTheme),
      ),
      (
        label: '账号',
        icon: const Icon(Icons.switch_account_outlined),
        onTap: () => go(() => LoginPageController.switchAccountDialog(context)),
      ),
      (
        label: '无痕',
        icon: MineController.anonymity.value
            ? const Icon(MdiIcons.incognito)
            : const Icon(MdiIcons.incognitoOff),
        onTap: () => go(MineController.onChangeAnonymity),
      ),
      if (GStorage.reply != null)
        (
          label: '评论记录',
          icon: const Icon(Icons.message_outlined),
          onTap: () => go(() => Get.toNamed('/myReply')),
        ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;
          // 列数跟着窗口宽度走，留 0.5 的浮点余量，免得刚好挤掉一列
          final columns = avail >= 520
              ? 6
              : avail >= 400
              ? 5
              : 4;
          final tileWidth = avail / columns - 0.5;
          return Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 4,
        children: entries
            .map(
              (e) => SizedBox(
                width: tileWidth,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: e.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconTheme.merge(
                          data: IconThemeData(
                            size: 22,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          child: e.icon,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
          );
        },
      ),
    );
  }

  Widget _sideBar() {
    // 非竖屏一律用侧边栏(桌面窗口与手机/平板横屏),竖屏才用底部导航
    return _desktopSideBar();
  }

  Widget _desktopSideBar() {
    return Obx(
      () {
        final navigationBars = _mainController.navigationBars;
        final selectedIndex = _mainController.selectedIndex.value;

        void gotoTab(NavigationBarType type) {
          final index = navigationBars.indexOf(type);
          if (index != -1) {
            _mainController.setIndex(index);
          } else {
            Get.to(
              Material(
                child: ViewSafeArea(
                  top: true,
                  child: switch (type) {
                    .home => const HomePage(),
                    .dynamics => const DynamicsPage(),
                    .featured => const FeaturedFeedPage(),
                    .mine => const MinePage(showBackBtn: true),
                  },
                ),
              ),
            );
          }
        }

        Widget tabBtn(NavigationBarType type) {
          final selected =
              navigationBars.length > 1 &&
              selectedIndex == navigationBars.indexOf(type);
          return IconButton(
            tooltip: type.label,
            onPressed: () => gotoTab(type),
            iconSize: 24,
            icon: _buildIcon(type: type, selected: selected),
          );
        }

        final mineController = Get.putOrFind(MineController.new);

        return Container(
          width: 64 + _padding.left,
          margin: .only(top: 12 + _padding.top, left: _padding.left),
          child: Column(
            children: [
              userAvatar(
                colorScheme: _colorScheme,
                mainController: _mainController,
              ),
              tabBtn(.home),
              tabBtn(.dynamics),
              if (navigationBars.contains(
                NavigationBarType.featured,
              )) ...[
                tabBtn(.featured),
              ],
              IconButton(
                tooltip: '搜索',
                onPressed: () => Get.toNamed('/search'),
                iconSize: 24,
                icon: const Icon(Icons.search_outlined),
              ),
              msgBadge(_mainController),
              tabBtn(.mine),
              const Spacer(),
              IconButton(
                tooltip: '设置',
                onPressed: () =>
                    Get.toNamed('/setting', preventDuplicates: false),
                iconSize: 24,
                icon: const Icon(Icons.settings_outlined),
              ),
              Obx(
                () => IconButton(
                  tooltip: '切换至${mineController.nextThemeType.label}主题',
                  onPressed: mineController.onChangeTheme,
                  iconSize: 24,
                  icon: mineController.themeType.value.icon,
                ),
              ),
              IconButton(
                tooltip: '切换账号',
                onPressed: () =>
                    LoginPageController.switchAccountDialog(context),
                iconSize: 24,
                icon: const Icon(Icons.switch_account_outlined),
              ),
              Obx(
                () {
                  final anonymity = MineController.anonymity.value;
                  return IconButton(
                    tooltip: "${anonymity ? '退出' : '进入'}无痕模式",
                    onPressed: MineController.onChangeAnonymity,
                    iconSize: 24,
                    icon: anonymity
                        ? const Icon(MdiIcons.incognito)
                        : const Icon(MdiIcons.incognitoOff),
                  );
                },
              ),
              if (GStorage.reply != null)
                IconButton(
                  tooltip: '评论记录',
                  onPressed: () => Get.toNamed('/myReply'),
                  iconSize: 24,
                  icon: const Icon(Icons.message_outlined),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 侧边栏固定 64 宽，纵向还要放得下十来个图标；只有宽和高都够才用侧边栏。
    // 这里每次 build 都按实时尺寸重算（不再放到 didChangeDependencies 里），
    // 拖动窗口边缘缩放时布局会立刻跟上，不会慢一拍或整块跳变。
    _mainController.useBottomNav = size.width < 600 || size.height < 520;

    Widget child;
    if (_mainController.mainTabBarView) {
      child = TabBarView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    } else {
      child = PageView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    }

    Widget? sideBar;
    Widget? bottomNav;
    final EdgeInsets padding;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      if (bottomNav != null) {
        bottomNav = MediaQuery.removePadding(
          key: _barKey,
          context: context,
          removeTop: true,
          child: bottomNav,
        );
      }
      padding = _padding.copyWith(bottom: 0);
    } else {
      sideBar = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: _colorScheme.outline.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: _sideBar(),
      );
      padding = .only(top: _padding.top, right: _padding.right);
    }

    child = Material(
      child: MainLayout(
        sideBar: sideBar,
        bottomNav: bottomNav,
        body: Padding(padding: padding, child: child),
      ),
    );

    if (_mainController.useBottomNav) {
      // 记录底栏实际高度,dock 要贴在它正上方
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
        final h = box?.size.height ?? 0;
        if ((h - _barHeight).abs() > 0.5) {
          setState(() => _barHeight = h);
        }
      });

      child = Stack(
        children: [
          Positioned.fill(child: child),
          if (_dockOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDock,
                child: const SizedBox.expand(),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _barHeight,
            child: IgnorePointer(
              ignoring: !_dockOpen,
              child: AnimatedOpacity(
                duration: _dockDuration,
                curve: Curves.easeOutCubic,
                opacity: _dockOpen ? 1 : 0,
                child: AnimatedSlide(
                  duration: _dockDuration,
                  curve: Curves.easeOutCubic,
                  offset: _dockOpen ? Offset.zero : const Offset(0, 0.18),
                  child: _buildDock(context),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (PlatformUtils.isMobile) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: _colorScheme.brightness,
          statusBarIconBrightness: _colorScheme.brightness.reverse,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: _colorScheme.brightness.reverse,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(
            () {
              final dynCount = _mainController.dynCount.value;
              return Badge(
                isLabelVisible: dynCount > 0,
                label: _mainController.dynamicBadgeMode == .number
                    ? Text(dynCount.toString())
                    : null,
                padding: const .symmetric(horizontal: 6),
                child: icon,
              );
            },
          )
        : icon;
  }

  Widget userAndSearchVertical() {
    return Column(
      children: [
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        IconButton(
          tooltip: '搜索',
          icon: const Icon(
            Icons.search_outlined,
            semanticLabel: '搜索',
          ),
          onPressed: () => Get.toNamed('/search'),
        ),
      ],
    );
  }
}
