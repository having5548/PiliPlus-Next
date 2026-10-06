import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/pages/feature_feed/controller.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

String _fmt(num? v) => v == null || v < 10000
    ? '${v ?? 0}'
    : '${(v / 10000).toStringAsFixed(1)}万';

/// 精选:抖音式竖滑推荐视频流(嵌入主框架,显示侧边栏)
class FeaturedFeedPage extends StatefulWidget {
  const FeaturedFeedPage({super.key});

  @override
  State<FeaturedFeedPage> createState() => _FeaturedFeedPageState();
}

class _FeaturedFeedPageState extends State<FeaturedFeedPage> {
  final FeatureFeedController _controller = Get.put(FeatureFeedController());
  final PageController _pageController = PageController();
  late final MainController _mainController = Get.find<MainController>();

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

  Future<void> _playAt(int index) async {
    final source = await _controller.buildSource(index);
    if (source == null || !mounted) {
      return;
    }
    _controller.playerController.setDataSource(
      source,
      autoplay: true,
      seekTo: Duration.zero,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    Get.delete<FeatureFeedController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = _controller.feedList;
      if (list.isEmpty) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      }
      return PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        itemCount: list.length + 1,
        onPageChanged: (index) {
          if (index >= list.length) {
            _controller.loadMore();
            return;
          }
          if (index + 2 >= list.length) {
            _controller.loadMore();
          }
          _playAt(index);
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
          return _buildPage(context, list[index], index);
        },
      );
    });
  }

  Widget _buildPage(
    BuildContext context,
    RcmdVideoItemAppModel item,
    int index,
  ) {
    final plPlayerController = _controller.playerController;
    return Obx(() {
      final videoController = plPlayerController.videoController;
      final inited = plPlayerController.dataStatus.value != DataStatus.loading;
      final detail = _controller.details[index];
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoController != null && inited)
              GestureDetector(
                onTap: () {
                  plPlayerController.videoPlayerController?.playOrPause();
                },
                child: Video(
                  controller: videoController,
                  controls: (state) => const SizedBox.shrink(),
                  fit: BoxFit.contain,
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            // 底部信息
            Positioned(
              left: 16,
              right: 88,
              bottom: 24,
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
                        shadows: [
                          Shadow(blurRadius: 6, color: Colors.black54),
                        ],
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
            // 右侧操作栏
            Positioned(
              right: 12,
              bottom: 24,
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
        ),
      );
    });
  }

  void _openDetail(RcmdVideoItemAppModel item) {
    final bvid = item.bvid;
    if (bvid == null) return;
    // 评论区/简介/选集走完整视频详情页
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
