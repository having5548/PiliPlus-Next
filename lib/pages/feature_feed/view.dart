import 'dart:async';

import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/feature_feed/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/volume_btn.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

String _fmt(num? v) => v == null || v < 10000
    ? '${v ?? 0}'
    : '${(v / 10000).toStringAsFixed(1)}万';

/// 精选:抖音式竖滑推荐视频流(嵌入主框架,显示侧边栏)。
///
/// 三个必须守住的点(都是踩过坑换来的):
/// 1. **视频层提到 PageView 之外**做成常驻层,翻页只重建文字/按钮,
///    纹理不销毁重建 → 切视频不会黑一下;
/// 2. **只有拿到有效画面尺寸才画纹理** —— mpv 会先建好纹理但宽高仍是
///    0x0,这时铺满屏幕就是一层均匀的浅色(用户报的"一层灰/白");
/// 3. 控制条与音量按钮**不受播放就绪门控**,加载中/失败也能操作。
class FeaturedFeedPage extends StatefulWidget {
  const FeaturedFeedPage({super.key});

  @override
  State<FeaturedFeedPage> createState() => _FeaturedFeedPageState();
}

class _FeaturedFeedPageState extends State<FeaturedFeedPage> {
  final FeatureFeedController _controller = Get.put(FeatureFeedController());
  final PageController _pageController = PageController();
  late final MainController _mainController = Get.find<MainController>();

  /// 控制条是否显示。**必须初始为 true** —— 否则启动时它压根不会出现
  /// (用非响应式的 playerStatus 判断"暂停时常驻"时踩过这个坑)
  final RxBool _showBar = true.obs;

  /// 播放状态必须用**响应式**变量:PlPlayerController.playerStatus 是普通
  /// 字段,读它不会触发 Obx 重建。这里从 media_kit 的 playing 流同步。
  final RxBool _playing = false.obs;
  StreamSubscription<bool>? _playingSub;

  /// 播放器是否已报告**有效画面尺寸**(防"一层白"的关键门控)
  final RxBool _hasFrame = false.obs;
  Timer? _frameProbe;

  Timer? _barTimer;
  Timer? _wheelLock;
  double _wheelAccum = 0;
  double? _dragValue;

  void _attachPlayingStream() {
    if (_playingSub != null) return;
    final player = _player.videoPlayerController;
    if (player == null) return;
    _playing.value = player.state.playing;
    _playingSub = player.stream.playing.listen((v) => _playing.value = v);
    _syncHasFrame();
    _frameProbe ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _syncHasFrame(),
    );
  }

  /// 把播放器的画面尺寸(非响应式字段)同步成可观测的 _hasFrame
  void _syncHasFrame() {
    if (!mounted) return;
    final player = _player.videoPlayerController;
    final has =
        player != null && player.state.width > 0 && player.state.height > 0;
    if (_hasFrame.value != has) _hasFrame.value = has;
  }

  @override
  void initState() {
    super.initState();
    _controller.loadMore(refresh: true).then((_) {
      if (_controller.feedList.isNotEmpty) {
        _playAt(0);
      }
    });
    // 切到其它标签时暂停播放,回到精选时恢复
    _mainController.selectedIndex.listen((index) {
      final player = _controller.playerController.videoPlayerController;
      if (player == null) return;
      final featuredIndex =
          _mainController.navigationBars.indexOf(NavigationBarType.featured);
      if (featuredIndex == -1) return;
      if (index == featuredIndex) {
        if (!player.state.playing) {
          player.play();
        }
      } else if (player.state.playing) {
        player.pause();
      }
    });
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _frameProbe?.cancel();
    _barTimer?.cancel();
    _wheelLock?.cancel();
    _pageController.dispose();
    Get.delete<FeatureFeedController>();
    super.dispose();
  }

  PlPlayerController get _player => _controller.playerController;

  // ---- 播放 ----

  Future<void> _playAt(int index) async {
    await _controller.playAt(index);
    _attachPlayingStream();
    _scheduleBarHide();
  }

  void _togglePlay() {
    _player.videoPlayerController?.playOrPause();
    _showBar.value = true;
    _scheduleBarHide();
  }

  void _pokeBar() {
    _showBar.value = true;
    _scheduleBarHide();
  }

  void _scheduleBarHide() {
    _barTimer?.cancel();
    _barTimer = Timer(const Duration(seconds: 3), () {
      if (_playing.value) _showBar.value = false;
    });
  }

  /// 当前第几个视频(键盘/滚轮判界用;非响应式,避免 build 期间改 Rx)
  int get _current {
    if (!_pageController.hasClients) return 0;
    return _pageController.page?.round() ?? 0;
  }

  int get _lastIndex => _controller.feedList.length - 1;

  void _gotoPage(int index) {
    if (!_pageController.hasClients) return;
    if (index < 0 || index > _lastIndex) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// 键盘:上/下切换视频,空格播放暂停
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _gotoPage(_current + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _gotoPage(_current - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 滚轮:一格一个;动画期间丢弃后续事件,避免粘黏/连跳
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_wheelLock?.isActive ?? false) return;
    _wheelAccum += event.scrollDelta.dy;
    if (_wheelAccum.abs() < 60) return;
    final step = _wheelAccum > 0 ? 1 : -1;
    _wheelAccum = 0;
    final target = _current + step;
    if (target < 0 || target > _lastIndex) return;
    _gotoPage(target);
    _wheelLock?.cancel();
    _wheelLock = Timer(const Duration(milliseconds: 320), () {});
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_controller.feedList.isEmpty) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      }
      final list = _controller.feedList;

      final pages = PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        itemCount: list.length + 1,
        onPageChanged: (index) {
          if (index >= list.length) {
            _controller.loadMore();
            return;
          }
          _playAt(index);
          if (index + 2 >= list.length) _controller.loadMore();
        },
        itemBuilder: (context, index) {
          if (index >= list.length) {
            return const ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
          }
          return _buildOverlay(context, list[index], index);
        },
      );

      final stage = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: pages),
          _buildVideoLayer(),
          _buildControlBar(),
        ],
      );

      final focused = Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: stage,
      );

      if (!PlatformUtils.isDesktop) return focused;
      return Listener(onPointerSignal: _onWheel, child: focused);
    });
  }

  /// 常驻视频层:整个页面只有这里画纹理,翻页不会重建它。
  /// 未拿到有效画面尺寸时**什么都不画** —— 避免把 0x0 的空纹理铺满屏幕。
  Widget _buildVideoLayer() {
    _attachPlayingStream();
    return Obx(() {
      final controller = _player.videoController;
      if (controller == null || !_hasFrame.value) {
        return const SizedBox.shrink();
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Video(
              controller: controller,
              controls: (state) => const SizedBox.shrink(),
              fit: BoxFit.contain,
            ),
          ),
          // 弹幕层:按当前视频的 cid 重建,不拦手势
          Obx(() {
            final index = _current;
            final list = _controller.feedList;
            if (index < 0 || index >= list.length) {
              return const SizedBox.shrink();
            }
            final cid = list[index].cid;
            final inited = _player.dataStatus.value != .loading;
            if (cid == null || !inited || !_player.enableShowDanmaku.value) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: PlDanmaku(
                key: ValueKey(cid),
                cid: cid,
                playerController: _player,
                isFullScreen: false,
                isFileSource: false,
                size: MediaQuery.sizeOf(context),
              ),
            );
          }),
        ],
      );
    });
  }

  /// 底部控制条:暂停常驻,播放中 3 秒后滑出隐藏
  Widget _buildControlBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Obx(
        () {
          final show = _showBar.value || !_playing.value;
          return AnimatedSlide(
            offset: show ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 220),
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Obx(
                      () => Icon(
                        _playing.value ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  Obx(
                    () => Text(
                      DurationUtils.formatDuration(_player.progress),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Obx(() {
                      final dur = _player.duration.value;
                      final value = _dragValue?.clamp(0.0, dur.toDouble()) ??
                          _player.progress.toDouble();
                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                        ),
                        child: Slider(
                          value: dur > 0 ? value : 0,
                          max: dur > 0 ? dur.toDouble() : 1,
                          onChanged: dur > 0
                              ? (v) => setState(() => _dragValue = v)
                              : null,
                          onChangeEnd: (v) {
                            _player.seekTo(
                              Duration(seconds: v.round()),
                              isSeek: true,
                            );
                            setState(() => _dragValue = null);
                            _pokeBar();
                          },
                        ),
                      );
                    }),
                  ),
                  Obx(
                    () => Text(
                      DurationUtils.formatDuration(_player.duration.value),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  VolumeButton(plPlayerController: _player),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 每一页的文字与操作按钮(视频不在这里,所以翻页重建无妨)
  Widget _buildOverlay(
    BuildContext context,
    RcmdVideoItemAppModel item,
    int index,
  ) {
    return Obx(() {
      final detail = _controller.details[index];
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_player.dataStatus.value == .loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          Positioned(
            left: 16,
            right: 88,
            bottom: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail?.title ?? item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if ((detail?.desc ?? '').isNotEmpty)
                  Text(
                    detail!.desc!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Text(
                  '@${detail?.owner?.name ?? item.owner.name}'
                  '  ${DurationUtils.formatDuration(item.duration)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 56,
            child: Column(
              children: [
                _action(
                  icon: Icons.thumb_up_outlined,
                  label: _fmt(detail?.stat?.like ?? item.stat.like),
                  onTap: () => _openDetail(item),
                ),
                const SizedBox(height: 18),
                _action(
                  icon: Icons.chat_bubble_outline,
                  label: _fmt(detail?.stat?.reply ?? item.stat.danmu),
                  onTap: () => _openDetail(item),
                ),
                const SizedBox(height: 18),
                _action(
                  icon: Icons.reply_outlined,
                  label: _fmt(detail?.stat?.share ?? item.stat.view),
                  onTap: () => _openDetail(item),
                ),
                const SizedBox(height: 18),
                _action(
                  icon: Icons.more_vert,
                  label: '详情',
                  onTap: () => _openDetail(item),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  void _openDetail(RcmdVideoItemAppModel item) {
    final bvid = item.bvid;
    if (bvid == null) return;
    PageUtils.toVideoPage(
      bvid: bvid,
      cid: item.cid ?? 0,
      title: item.title,
      cover: item.cover,
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 28),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}