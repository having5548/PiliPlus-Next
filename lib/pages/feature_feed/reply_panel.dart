import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';

/// 精选页右侧评论区的控制器。
///
/// 刻意**不复用** `VideoReplyController`:那个类在字段初始化时就
/// `Get.find<VideoDetailController>(tag: ...)`,也就是必须挂在视频详情页上。
/// 精选页没有视频详情页,用了会在展开评论时直接抛 "not found"。
///
/// 这里照 `MainReplyController` 的形状自己写一个,区别是
/// **oid / replyType 走构造参数**,不依赖 `Get.arguments`
/// (后者是全局的,嵌入式使用会被别的页面覆盖)。
class FeatureReplyController extends ReplyController<MainListReply> {
  FeatureReplyController({required this.oid, required this.replyType});

  final int oid;
  final int replyType;

  @override
  int get sourceId => oid;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    type: replyType,
    oid: oid,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
  );

  @override
  List<ReplyInfo>? getDataList(MainListReply response) => response.replies;
}

/// 精选页右侧的评论面板:结构对齐 `MainReplyPage`,但去掉了页面外壳
/// (AppBar / SimpleScaffold),因为它是嵌在精选页右侧的一条窄栏。
class FeatureReplyPanel extends StatefulWidget {
  const FeatureReplyPanel({
    super.key,
    required this.oid,
    required this.heroTag,
    this.replyType = 1,
    this.scrollController,
    this.onClose,
  });

  final int oid;
  final String heroTag;

  /// 1 = 投稿视频(与 VideoType.ugc.replyType 一致)
  final int replyType;

  /// 由外层传入,这样方向键可以滚这个列表(而不是切换视频)
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  @override
  State<FeatureReplyPanel> createState() => _FeatureReplyPanelState();
}

class _FeatureReplyPanelState extends State<FeatureReplyPanel>
    with SingleTickerProviderStateMixin, BaseFabMixin, FabMixin {
  late final FeatureReplyController _controller = Get.put(
    FeatureReplyController(oid: widget.oid, replyType: widget.replyType),
    tag: widget.heroTag,
  );

  @override
  void dispose() {
    Get.delete<FeatureReplyController>(tag: widget.heroTag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: fabAnimWrapper(
                    child: refreshIndicator(
                      onRefresh: _controller.onRefresh,
                      child: CustomScrollView(
                        controller: widget.scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          _header(colorScheme),
                          Obx(
                            () => _body(
                              colorScheme,
                              _controller.loadingState.value,
                            ),
                          ),
                          // 给底部发送栏留出高度,避免最后一条评论被挡
                          const SliverToBoxAdapter(child: SizedBox(height: 56)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 6,
                  child: IconButton(
                    tooltip: '关闭评论',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
              ],
            ),
          ),
          _sendBar(colorScheme),
        ],
      ),
    );
  }

  /// 底部发送栏:点它进入项目自带的评论编辑页(ReplyPage)。
  /// 用它而不是自己拼发送请求 —— 防刷校验、@ 提及、图片、草稿都交给它,
  /// 发完回来后 `onReply` 会把新评论插进列表。
  Widget _sendBar(ColorScheme colorScheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _onSend,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _hint,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '发送评论',
              onPressed: _onSend,
              icon: Icon(Icons.send, size: 20, color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  String get _hint {
    final (inputDisable, hint) = _controller.replyHint;
    if (inputDisable) return hint ?? '当前无法评论';
    return hint ?? '发一条友善的评论';
  }

  void _onSend() {
    _controller.onReply(
      null,
      oid: widget.oid,
      replyType: widget.replyType,
    );
  }

  Widget _header(ColorScheme colorScheme) {
    final secondary = colorScheme.secondary;
    return SliverFloatingHeaderWidget(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 2.5, 6, 2.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Obx(() {
              final count = _controller.count.value;
              return Text(
                '${count == -1 ? 0 : NumUtils.numFormat(count)}条评论',
                style: const TextStyle(fontSize: 13),
              );
            }),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: _controller.queryBySort,
              icon: Icon(Icons.sort, size: 16, color: secondary),
              label: Obx(
                () => Text(
                  _controller.sortType.value.descShort,
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    ColorScheme colorScheme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => const SliverPrototypeExtentList(
        prototypeItem: VideoReplySkeleton(),
        delegate: SliverSingleChildDelegate(
          count: 8,
          child: VideoReplySkeleton(),
        ),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length + 1,
                itemBuilder: (context, index) {
                  if (index == response.length) {
                    _controller.onLoadMore();
                    return Container(
                      alignment: Alignment.center,
                      height: 80,
                      child: Text(
                        _controller.isEnd ? '没有更多了' : '加载中...',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    );
                  }
                  return ReplyItemGrpc(
                    replyItem: response[index],
                    replyLevel: 1,
                    replyReply: (replyItem, id) =>
                        _replyReply(context, replyItem, id, colorScheme),
                    onReply: _controller.onReply,
                    onDelete: (item, subIndex) =>
                        _controller.onRemove(index, item, subIndex),
                    upMid: _controller.upMid,
                    onCheckReply: _controller.onCheckReply,
                    onToggleTop: (item) => _controller.onToggleTop(
                      item,
                      index,
                      _controller.oid,
                      _controller.replyType,
                    ),
                  );
                },
              )
            : HttpError(
                errMsg: '还没有评论',
                onReload: _controller.onReload,
              ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  void _replyReply(
    BuildContext context,
    ReplyInfo replyItem,
    int? id,
    ColorScheme colorScheme,
  ) {
    EasyThrottle.throttle('featureReplyReply', const Duration(milliseconds: 500), () {
      final rpid = replyItem.id.toInt();
      Get.to(
        SimpleScaffold(
          appBar: AppBar(title: const Text('评论详情')),
          body: ViewSafeArea(
            child: VideoReplyReplyPanel(
              enableSlide: false,
              id: id,
              oid: replyItem.oid.toInt(),
              rpid: rpid,
              isVideoDetail: false,
              replyType: _controller.replyType,
              firstFloor: replyItem,
              upMid: _controller.upMid,
            ),
          ),
        ),
        routeName: 'featureFeedReplyReply',
      );
    });
  }
}