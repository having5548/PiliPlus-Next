import 'dart:async';

import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/pages/danmaku/view.dart';
import 'package:PiliPlus/pages/feature_feed/controller.dart';
import 'package:PiliPlus/pages/feature_feed/reply_panel.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/video/pay_coins/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
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

  /// 拖动进度条时的预览位置(毫秒);-1 表示没在拖。
  /// 用响应式变量而不是 setState —— 拖动时每帧 setState 会重建整页,
  /// 拖起来发涩,而且容易和页面里的手势打架。
  final RxInt _dragMs = (-1).obs;

  /// 光标是否停在画面上。悬停即显示控制条(不必先点一下或暂停)。
  final RxBool _hovering = false.obs;
  Timer? _hoverTimer;

  /// 光标是否停在底部控制条上(非响应式即可,只用于滚轮判界)
  bool _pointerOnBar = false;

  /// 静音前的音量,用于取消静音时恢复
  double _lastVolume = -1;

  /// 评论区自己的滚动控制器:评论面板打开时方向键滚它,而不是切视频
  final ScrollController _replyScrollCtrl = ScrollController();

  /// 弹幕设置面板是否展开(内联面板,不走 navigator)
  final RxBool _probeOpen = false.obs;

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
    // 兜底同步播放状态:stream.playing 偶发漏发时 _playing 会卡在 false,
    // 表现为"视频在放但控制条永不自动隐藏、播放/暂停图标也不对"。
    final playing = player?.state.playing ?? false;
    if (_playing.value != playing) _playing.value = playing;
  }

  @override
  void initState() {
    super.initState();
    // 必须先绑自动播放回调,否则 setDataSource(autoplay: true) 会调空回调
    _controller.bindAutoPlay();
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
    _hoverTimer?.cancel();
    _replyScrollCtrl.dispose();
    _pageController.dispose();
    // 取消自动播放回调,否则控制器已销毁时 playIfExists 会打到旧实例上
    _controller.unbindAutoPlay();
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

  /// 控制条自动隐藏。
  /// 光标还停在画面上、或者正在拖进度条时**不隐藏** —— 否则拖到一半条就没了。
  void _scheduleBarHide() {
    _barTimer?.cancel();
    _barTimer = Timer(const Duration(seconds: 3), () {
      if (!_playing.value) return;
      if (_hovering.value) return;
      if (_dragMs.value >= 0) return;
      if (_probeOpen.value) return;
      _showBar.value = false;
    });
  }

  /// 光标进入底部热区 → 显示控制条(不用先点一下或者暂停)
  void _onEnterBarZone() {
    _hoverTimer?.cancel();
    _hovering.value = true;
    _pokeBar();
  }

  /// 光标离开底部热区:稍等一下再判定,避免在控件之间移动时闪来闪去
  void _onExitBarZone() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _hovering.value = false;
      _barTimer?.cancel();
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

  /// 键盘:上/下切换视频,空格播放暂停。
  /// **评论面板打开时把方向键让给评论列表** —— 用户只是想看/滚评论,
  /// 这时候再切视频非常烦人。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_controller.showReply.value) {
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        if (_replyScrollCtrl.hasClients) {
          final pos = _replyScrollCtrl.position;
          final delta = key == LogicalKeyboardKey.arrowDown ? 120.0 : -120.0;
          final target = (pos.pixels + delta).clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          );
          _replyScrollCtrl.jumpTo(target);
        }
        return KeyEventResult.handled;
      }
      // 空格之类也交给评论面板,不要在看不见的播放器上生效
      return KeyEventResult.ignored;
    }

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

  /// 滚轮:一格一个;动画期间丢弃后续事件,避免粘黏/连跳。
  /// **光标在控制条上时不响应** —— 否则在音量按钮上滚轮调音量会连视频一起切。
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_pointerOnBar) return;
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
          // 页面本身只负责手势与占位;文字被提到视频层之上单独画,
          // 否则会被 BoxFit.contain 的黑边盖住。
          return const SizedBox.expand();
        },
      );
      // 左侧舞台:视频层 + 底部渐变遮罩 + 文字 + 操作栏 + 控制条。
      // 这些 overlay 必须**排在视频层之后**才会画在纹理之上,
      // 否则会被视频盖住(用户反馈"UP名称与简介被视频遮挡"、
      // "点赞/评论按钮被视频挡住")。
      final stage = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black, child: pages),
          _buildVideoLayer(),
          _buildTextOverlay(),
          _buildActionRail(),
          _buildControlBar(),
          // 弹幕设置面板直接画在 Stack 里(不走 navigator)。
          // 原来用 showModalBottomSheet,按钮能收到点击但面板始终不弹出 ——
          // 内联渲染绕开 navigator/Overlay 依赖,必定可见。
          Obx(() => _probeOpen.value
              ? Positioned(
                  right: 76,
                  bottom: 56,
                  width: 320,
                  child: _DanmakuSettingPanel(
                    onClose: () => _probeOpen.value = false,
                  ),
                )
              : const SizedBox.shrink()),
          // 悬停热区:**只是画面底部一条**(控制条所在区域 + 上方一点),
          // 不是整屏。用户明确要求"范围别那么大" —— 光标扫过画面中央不该弹条。
          // opaque:false 保证它不吃点击,下面的播放手势照常收到。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 96,
            child: MouseRegion(
              opaque: false,
              onEnter: (_) => _onEnterBarZone(),
              onExit: (_) => _onExitBarZone(),
              onHover: (_) => _onEnterBarZone(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      );

      // 键盘与滚轮:**只作用在舞台上** —— 评论区在 Row 的另一侧,
      // 所以滚轮滚评论、方向键滚评论都不会再触发"切换视频"。
      Widget stageWrapped = Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: stage,
      );
      if (PlatformUtils.isDesktop) {
        stageWrapped = Listener(
          onPointerSignal: _onWheel,
          child: stageWrapped,
        );
      }

      // 评论区像抖音那样从右侧展开:展开时左侧舞台自动缩窄,播放器跟着变小
      final body = Obx(() {
        final bvid = _controller.replyBvid.value;
        final open = _controller.showReply.value && bvid.isNotEmpty;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: stageWrapped),
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: open ? 400 : 0,
              child: open
                  ? FeatureReplyPanel(
                      key: ValueKey(bvid),
                      oid: IdUtils.bv2av(bvid),
                      heroTag: _controller.replyTagFor(bvid),
                      scrollController: _replyScrollCtrl,
                      onClose: () => _controller.showReply.value = false,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      });

      return body;
    });
  }

  /// 常驻视频层:整个页面只有这里画纹理,翻页不会重建它。
  /// 未拿到有效画面尺寸时**什么都不画** —— 避免把 0x0 的空纹理铺满屏幕。
  Widget _buildVideoLayer() {
    _attachPlayingStream();
    return Obx(() {
      final controller = _player.videoController;
      // 必须同时满足:① 取流完成(dataStatus 离开 loading)——基线就是靠它避免
      // 在纹理未初始化时就把占位表面画出来(那片均匀浅灰);② 播放器已报告
      // 真实画面尺寸,避免把 0x0 空纹理铺满屏幕。
      final inited = _player.dataStatus.value != .loading;
      if (controller == null || !inited || !_hasFrame.value) {
        return const SizedBox.shrink();
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: RepaintBoundary(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SimpleVideo(
                  controller: controller,
                  fill: Colors.black,
                ),
              ),
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

  /// 底部控制条:光标在画面上时出现;播放中且光标离开、没在拖时滑出隐藏
  Widget _buildControlBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Obx(
        () {
          final show = _showBar.value || !_playing.value || _hovering.value;
          return AnimatedSlide(
            offset: show ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 220),
            child: MouseRegion(
              // 光标在控制条上:显示条 + 让滚轮只作用于控件(调音量),
              // 不要再去切换视频
              onEnter: (_) {
                _pointerOnBar = true;
                _pokeBar();
              },
              onExit: (_) {
                _pointerOnBar = false;
                _onExitBarZone();
              },
              child: Container(
                color: Colors.black.withValues(alpha: 0.55),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                    // 进度条:**只让它负责画**,手势由外面这层自己做。
                    //
                    // 为什么不让 ProgressBar 自己收手势:它是 LeafRenderObjectWidget,
                    // 命中区域就是它自己的渲染框,而那个框只有 barHeight(3.5) ~
                    // 圆点直径(10) 那么高 —— 必须**精确压在那条细线上**才抓得住。
                    // 用户反馈"暂停时拖不动"就是这个原因(能拖到纯属 y 碰巧对上)。
                    // 现在外面套一层 26px 高的手势区,点/拖都宽松得多。
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final barW = constraints.maxWidth;
                          void seekToDx(double dx) {
                            final dur = _player.duration.value;
                            if (dur <= 0 || barW <= 0) return;
                            final ratio = (dx / barW).clamp(0.0, 1.0);
                            _player.seekTo(
                              Duration(milliseconds: (dur * ratio).round()),
                              isSeek: true,
                            );
                          }

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) {
                              _pokeBar();
                              seekToDx(d.localPosition.dx);
                            },
                            onHorizontalDragStart: (d) {
                              _pokeBar();
                              final dur = _player.duration.value;
                              if (dur > 0 && barW > 0) {
                                _dragMs.value =
                                    (dur *
                                            (d.localPosition.dx / barW)
                                                .clamp(0.0, 1.0))
                                        .round();
                              }
                            },
                            onHorizontalDragUpdate: (d) {
                              final dur = _player.duration.value;
                              if (dur > 0 && barW > 0) {
                                _dragMs.value =
                                    (dur *
                                            (d.localPosition.dx / barW)
                                                .clamp(0.0, 1.0))
                                        .round();
                              }
                            },
                            onHorizontalDragEnd: (_) {
                              final ms = _dragMs.value;
                              if (ms > 0) {
                                _player.seekTo(
                                  Duration(milliseconds: ms),
                                  isSeek: true,
                                );
                              }
                              _dragMs.value = -1;
                              _pokeBar();
                            },
                            onHorizontalDragCancel: () => _dragMs.value = -1,
                            child: SizedBox(
                              height: 26,
                              child: Center(
                                child: Obx(() {
                                  final dur = _player.duration.value;
                                  final maxMs = dur <= 0 ? 0 : dur;
                                  final dragMs = _dragMs.value;
                                  final shown = dragMs >= 0
                                      ? Duration(milliseconds: dragMs).inSeconds
                                      : _player.progress;
                                  return ProgressBar(
                                    progress: shown.clamp(0, maxMs),
                                    buffered: _player.buffered.value.clamp(
                                      0,
                                      maxMs,
                                    ),
                                    total: dur,
                                    progressBarColor: const Color(0xFFFB7299),
                                    baseBarColor: const Color(0x33FFFFFF),
                                    bufferedBarColor: const Color(0x66FB7299),
                                    thumbColor: const Color(0xFFFB7299),
                                    thumbGlowColor: const Color(0x50FB7299),
                                    barHeight: 3.5,
                                    thumbRadius: 5,
                                  );
                                }),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Obx(
                    () => Text(
                      DurationUtils.formatDuration(_player.duration.value),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 弹幕开关 + 弹幕设置(与全屏播放器一样挨着音量放)
                  _danmakuButton(),
                  const SizedBox(width: 2),
                  _danmakuSettingButton(context),
                  // 音量:图标(点击静音) + **可见滑条**。
                  // 之前只有一个图标、只能滚轮调,而且滚轮会连视频一起切 ——
                  // 这里给一条能拖的滑条,并把滚轮事件挡在控制条里。
                  _volumeIcon(),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SizedBox(
                      width: 96,
                      child: Obx(() {
                        final maxV = _player.maxVolume;
                        final v = _player.volume.value.clamp(0.0, maxV);
                        return SliderTheme(
                          data: const SliderThemeData(
                            trackHeight: 3,
                            activeTrackColor: Color(0xFFFB7299),
                            inactiveTrackColor: Color(0x33FFFFFF),
                            thumbColor: Color(0xFFFB7299),
                            overlayColor: Color(0x33FB7299),
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: RoundSliderOverlayShape(
                              overlayRadius: 11,
                            ),
                          ),
                          child: Slider(
                            value: v,
                            max: maxV <= 0 ? 1 : maxV,
                            onChanged: (nv) {
                              _player.setVolume(nv, showIndicator: false);
                              _pokeBar();
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          );
        },
      ),
    );
  }

  /// 音量图标:点击静音 / 恢复
  Widget _volumeIcon() {
    return Obx(() {
      final volume = _player.volume.value;
      final maxVolume = _player.maxVolume;
      final icon = volume <= 0.001
          ? Icons.volume_off
          : (volume < maxVolume * 0.5 ? Icons.volume_down : Icons.volume_up);
      return IconButton(
        tooltip: '音量 ${(maxVolume <= 0 ? 0 : (volume / maxVolume * 100)).round()}%',
        onPressed: () {
          if (volume > 0) {
            _lastVolume = volume;
            _player.setVolume(0, showIndicator: false);
          } else {
            _player.setVolume(
              _lastVolume > 0 ? _lastVolume : maxVolume / 2,
              showIndicator: false,
            );
          }
          _pokeBar();
        },
        icon: Icon(icon, color: Colors.white, size: 20),
      );
    });
  }

  /// 弹幕显示开关(一键开关,不用进设置)
  Widget _danmakuButton() {
    return Obx(
      () => IconButton(
        tooltip: '弹幕开关',
        onPressed: () {
          _player.enableShowDanmaku.toggle();
          _pokeBar();
        },
        icon: Icon(
          _player.enableShowDanmaku.value
              ? Icons.subtitles
              : Icons.subtitles_off_outlined,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  /// 弹幕设置:展开与视频页一致的弹幕样式面板
  Widget _danmakuSettingButton(BuildContext context) {
    return IconButton(
      tooltip: '弹幕设置',
      onPressed: () {
        _probeOpen.toggle();
        _pokeBar();
      },
      icon: const Icon(Icons.tune, color: Colors.white, size: 20),
    );
  }


  /// 当前这条视频的文字层(**常驻,画在视频层之上**)。
  /// 之前把它放在 PageView 的每一页里,会被 BoxFit.contain 的视频连同黑边
  /// 一起盖住 —— 用户看到的就是"UP 名称与简介被视频遮挡"。
  Widget _buildTextOverlay() {
    return Obx(() {
      final index = _current;
      final list = _controller.feedList;
      final loading = _player.dataStatus.value == .loading;
      if (index < 0 || index >= list.length) {
        return loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : const SizedBox.shrink();
      }
      final item = list[index];
      final detail = _controller.details[index];
      final error = _controller.playerError.value;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          if (error.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
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
                    shadows: [Shadow(blurRadius: 4, color: Colors.black), Shadow(blurRadius: 10, color: Colors.black54)],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if ((detail?.desc ?? '').isNotEmpty)
                  Text(
                    detail!.desc!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.4,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black), Shadow(blurRadius: 10, color: Colors.black54)],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Text(
                  '@${detail?.owner?.name ?? item.owner.name}'
                  '  ${DurationUtils.formatDuration(item.duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black), Shadow(blurRadius: 10, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// 右侧操作栏。**独立成层并排在视频层之后**,才不会被视频纹理盖住。
  Widget _buildActionRail() {
    return Obx(() {
      final index = _current;
      final list = _controller.feedList;
      if (index < 0 || index >= list.length) return const SizedBox.shrink();
      final item = list[index];
      final detail = _controller.details[index];
      final liked = _controller.liked[index] ?? false;
      final coined = _controller.coined[index] ?? false;
      final replyOpen = _controller.showReply.value &&
          item.bvid != null &&
          _controller.replyBvid.value == item.bvid;
      return Positioned(
        right: 12,
        bottom: 56,
        child: Column(
          children: [
            _action(
              icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
              iconColor: liked ? const Color(0xFFFB7299) : Colors.white,
              label: _fmt(detail?.stat?.like ?? item.stat.like),
              onTap: () => _controller.toggleLike(index),
            ),
            const SizedBox(height: 18),
            _action(
              icon: coined
                  ? Icons.monetization_on
                  : Icons.monetization_on_outlined,
              iconColor: coined ? const Color(0xFFF5C542) : Colors.white,
              label: _fmt(detail?.stat?.coin ?? 0),
              onTap: () => _showCoinPanel(index),
            ),
            const SizedBox(height: 18),
            _action(
              icon: replyOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
              iconColor: replyOpen ? const Color(0xFFFB7299) : Colors.white,
              label: _fmt(detail?.stat?.reply ?? item.stat.danmu),
              onTap: () => _controller.openReply(index),
            ),
            const SizedBox(height: 18),
            _action(
              icon: Icons.reply_outlined,
              label: _fmt(detail?.stat?.share ?? item.stat.view),
              onTap: () {
                Clipboard.setData(
                  ClipboardData(text: _controller.shareLink(index)),
                );
                SmartDialog.showToast('链接已复制');
              },
            ),
            const SizedBox(height: 18),
            _action(
              icon: Icons.more_vert,
              label: '详情',
              onTap: () => _openDetail(item),
            ),
          ],
        ),
      );
    });
  }

  /// 投币:用**原版**的投币面板(带 1币/2币 与「同时点赞」),与视频详情页一致
  void _showCoinPanel(int index) {
    if (!_controller.isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }
    if (_controller.coined[index] ?? false) {
      SmartDialog.showToast('已经投过币啦');
      return;
    }
    final detail = _controller.details[index];
    PayCoinsPage.toPayCoinsPage(
      onPayCoin: (coin, coinWithLike) =>
          _controller.coin(index, coin, coinWithLike: coinWithLike),
      hasCoin: _controller.coined[index] ?? false,
      // copyright == 1 才允许投币;拿不到详情时按允许处理
      hasCopyright: (detail?.copyright ?? 1) == 1,
    );
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
    Color iconColor = Colors.white,
  }) {
    return Column(
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: iconColor, size: 28),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
/// 弹幕设置面板:改完即时生效(updateOption)并写回偏好。
/// 与视频页共用同一套 DanmakuOptions / danmakuOpacity,所以两边同步。
class _DanmakuSettingPanel extends StatelessWidget {
  const _DanmakuSettingPanel({this.onClose});

  final VoidCallback? onClose;

  PlPlayerController get _player => PlPlayerController.getInstance();

  void _apply() {
    _player.danmakuController?.updateOption(
      DanmakuOptions.get(notFullscreen: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: Colors.white, fontSize: 13);
    return Material(
      color: const Color(0xF21E1E22),
      borderRadius: BorderRadius.circular(12),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '弹幕设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '收起',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Obx(
              () => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('显示弹幕', style: labelStyle),
                value: _player.enableShowDanmaku.value,
                onChanged: (v) {
                  _player.enableShowDanmaku.value = v;
                  GStorage.setting.put(SettingBoxKey.enableShowDanmaku, v);
                },
              ),
            ),
            Obx(
              () => _slider(
                label: '不透明度 '
                    '${(_player.danmakuOpacity.value * 100).toStringAsFixed(0)}%',
                value: _player.danmakuOpacity.value.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                onChanged: (v) {
                  _player.danmakuOpacity.value = v;
                  DanmakuOptions.save(v);
                },
              ),
            ),
            _slider(
              label: '字体大小 '
                  '${(DanmakuOptions.danmakuFontScale * 100).toStringAsFixed(0)}%',
              value: DanmakuOptions.danmakuFontScale.clamp(0.5, 2.0),
              min: 0.5,
              max: 2.0,
              onChanged: (v) {
                DanmakuOptions.danmakuFontScale = v;
                DanmakuOptions.save(_player.danmakuOpacity.value);
                _apply();
              },
            ),
            _slider(
              label: '显示区域 '
                  '${(DanmakuOptions.danmakuShowArea * 100).toStringAsFixed(0)}%',
              value: DanmakuOptions.danmakuShowArea.clamp(0.1, 1.0),
              min: 0.1,
              max: 1.0,
              onChanged: (v) {
                DanmakuOptions.danmakuShowArea = v;
                DanmakuOptions.save(_player.danmakuOpacity.value);
                _apply();
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 2,
            activeTrackColor: Color(0xFFFB7299),
            thumbColor: Color(0xFFFB7299),
            overlayColor: Color(0x33FB7299),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}