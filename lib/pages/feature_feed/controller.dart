import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 精选:抖音式竖滑推荐流。
///
/// **推荐源跟随设置**,与首页推荐 tab 保持一致 —— 也就是
/// 「设置 → 推荐流设置 → 使用 App 推荐」(`Pref.appRcmd`):
/// 关掉它就是 **PC 网页端**推荐(`/x/web-interface/index/top/feed/rcmd`)。
/// 精选页以前写死了 App 端接口,所以那个开关对它不起作用。
///
/// 另外网页端接口会返回 `pubdate`,据此把**发布时间过旧**的老视频挡掉
/// (见 [_maxAgeDays]);App 端接口不返回 `pubdate`,这条对它无效。
class FeatureFeedController extends GetxController {
  /// 两种推荐源的公共基类:App 端 `RcmdVideoItemAppModel` 与
  /// 网页端 `RcmdVideoItemModel` 都继承它
  final RxList<BaseRcmdVideoItemModel> feedList =
      <BaseRcmdVideoItemModel>[].obs;
  final RxBool isLoading = false.obs;
  int _page = 0;
  bool _hasMore = true;

  /// 发布时间超过这个天数的视频不进精选流。
  ///
  /// 用户反馈"时间跨度大的视频也推我" —— 精选是竖滑的新鲜内容流,混进
  /// 几个月前的旧视频体验很差。实测网页端返回的流年龄跨度是 13~161 天,
  /// 取 **90 天**能真正裁掉那条长尾,又不至于把流抽干(拉不满时会自动
  /// 多拉几页,见 [loadMore] 里 guard 的 3 次上限)。要调就改这一个常量。
  ///
  /// 只在能拿到 `pubdate` 时有意义(网页端);拿不到(如 App 端接口)则跳过判定。
  static const int _maxAgeDays = 90;

  /// 这条推荐是否允许进流(纯判定,不含与已加载列表的去重)
  static bool _acceptRcmd(
    BaseRcmdVideoItemModel item,
    Set<String> excluded,
    int oldestPubdate,
  ) {
    // 只要普通投稿视频(live / 番剧 / 广告等一律不要)
    if (item.goto != 'av') return false;
    final bvid = item.bvid;
    if (bvid == null || item.cid == null) return false;
    // 主页推荐 tab 已经展示过的,不重复推
    if (excluded.contains(bvid)) return false;
    final pubdate = item.pubdate;
    if (pubdate != null && pubdate > 0 && pubdate < oldestPubdate) {
      return false;
    }
    return true;
  }

  /// 主页推荐 tab 已展示的 bvid(排除用)
  Set<String> _homeShownBvids() {
    try {
      if (Get.isRegistered<RcmdController>()) {
        final ctr = Get.find<RcmdController>();
        if (ctr.loadingState.value case Success(:final response)) {
          if (response != null) {
            return {
              for (final item in response)
                if (item.bvid != null) item.bvid!,
            };
          }
        }
      }
    } catch (_) {}
    return {};
  }

  Future<void> loadMore({bool refresh = false}) async {
    if (isLoading.value) return;
    if (refresh) {
      _page = 0;
      _hasMore = true;
    }
    if (!_hasMore) return;
    isLoading.value = true;
    final excluded = _homeShownBvids();
    // 推荐源跟随设置,与首页推荐 tab 一致
    final appRcmd = Pref.appRcmd;
    // "过旧"的判定基准:早于这个时间戳的不要
    final oldestPubdate =
        DateTime.now()
            .subtract(const Duration(days: _maxAgeDays))
            .millisecondsSinceEpoch ~/
        1000;
    try {
      int guard = 0;
      List<BaseRcmdVideoItemModel>? picked;
      // 一页推荐里可能大半都在主页出现过,多拉几页直到凑出内容
      while (picked == null || picked.isEmpty) {
        if (guard++ >= 3 || !_hasMore) break;
        // App 端与网页端返回的是不同的模型,统一收进基类列表
        List<BaseRcmdVideoItemModel>? got;
        if (appRcmd) {
          final res = await VideoHttp.rcmdVideoListApp(freshIdx: _page);
          if (res case Success(:final response)) {
            got = response;
          }
        } else {
          final res = await VideoHttp.rcmdVideoList(
            freshIdx: _page,
            ps: 20,
          );
          if (res case Success(:final response)) {
            got = response;
          }
        }
        _page++;
        if (got == null) {
          // 取流失败(非空但为空列表也算无更多)
          _hasMore = false;
          break;
        }
        if (got.isEmpty) {
          _hasMore = false;
          break;
        }
        picked = [
          for (final item in got)
            if (_acceptRcmd(item, excluded, oldestPubdate) &&
                !feedList.any((e) => e.bvid == item.bvid))
              item,
        ];
      }
      if (picked != null && picked.isNotEmpty) {
        if (refresh) {
          feedList
            ..clear()
            ..addAll(picked);
        } else {
          feedList.addAll(picked);
        }
      }
    } finally {
      isLoading.value = false;
    }
  }

  /// 已播放视频的详情(真实点赞/评论/转发数与简介)
  final RxMap<int, VideoDetailData> details = <int, VideoDetailData>{}.obs;

  Future<void> _fetchDetail(int index) async {
    final item = feedList[index];
    final bvid = item.bvid;
    if (bvid == null || details.containsKey(index)) return;
    final res = await VideoHttp.videoIntro(bvid: bvid);
    if (res case Success(:final response)) {
      details[index] = response;
    }
  }

  /// 播放器实例。
  ///
  /// **必须缓存**,不能写成 `=> PlPlayerController.getInstance()`:
  /// 那个 getInstance 内部有 `.._playerCount += 1`(给多实例播放计数用的),
  /// 每取一次属性就涨一次。而视图会在 Obx 里、每帧的 _buildVideoLayer /
  /// _syncHasFrame 里读它 —— 计数会飙到几百,dispose() 时命中
  /// `_playerCount > 1` 分支只减 1 就返回,播放器**永远不会真正释放与重建**,
  /// 于是表现为:首次/切视频都不自动播放、进度与时长拿不到(拖进度条无效)。
  late final PlPlayerController playerController =
      PlPlayerController.getInstance();

  /// 最近一次播放失败的原因;为空表示没失败。
  /// 取流失败必须能被看见——旧实现直接 return,界面只会一直转圈。
  final RxString playerError = ''.obs;

  Timer? _frameFix;

  /// 注册"自动播放"回调。
  ///
  /// **这一步不能省**:`PlPlayerController.setDataSource(autoplay: true)` 内部
  /// 最终走的是 `_initializePlayer()` → `playIfExists()` → `_playCallBack?.call()`,
  /// 也就是**靠外部注册的回调真正开始播放**。视频详情页/直播间都会
  /// `setPlayCallBack(...)`,精选页以前没注册,于是 `_autoPlay` 是 true 却调了个
  /// 空回调 —— 表现就是"打开不自动播放、切下一个也不自动播放"。
  void bindAutoPlay() {
    PlPlayerController.setPlayCallBack(
      () => playerController.play(),
      playOwner: (tag: 'featureFeed', type: runtimeType),
    );
  }

  void unbindAutoPlay() {
    PlPlayerController.setPlayCallBack(null);
  }

  /// 播放第 index 个视频。
  ///
  /// 两个必须守住的性质:
  /// 1. **有界退出**:无论成功失败都要把状态落到终态,不能静默 return;
  /// 2. **首帧补救**:setDataSource 之后播放器可能已经建好纹理但宽高仍是
  ///    0x0,此时画面是一层均匀的浅色(用户描述为"糊了一层白")。上游那个
  ///    兜底要等 10 秒且只在播放中生效,这里提前主动重开输出。
  Future<void> playAt(int index, {bool autoplay = true}) async {
    if (index < 0 || index >= feedList.length) return;
    _frameFix?.cancel();
    playerError.value = '';
    try {
      final source = await buildSource(index).timeout(
        const Duration(seconds: 20),
      );
      if (source == null) {
        playerError.value = '这条推荐暂时取不到播放地址';
        return;
      }
      await playerController
          .setDataSource(source, autoplay: autoplay, seekTo: Duration.zero)
          .timeout(const Duration(seconds: 30));
      _fixFirstFrame(index);
    } catch (e) {
      playerError.value = '$e';
    }
  }

  /// 1.2 秒还没有画面尺寸就 refreshPlayer() 重开一次输出,最多两次
  void _fixFirstFrame(int index) {
    var tries = 0;
    _frameFix = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      if (isClosed) {
        t.cancel();
        return;
      }
      final player = playerController.videoPlayerController;
      if (player == null) return;
      if (player.state.width > 0 && player.state.height > 0) {
        t.cancel();
        _frameFix = null;
        return;
      }
      if (tries >= 2) {
        t.cancel();
        _frameFix = null;
        return;
      }
      tries++;
      playerController.refreshPlayer();
    });
  }

  /// 取指定视频的播放地址(默认画质,音视频分离)
  Future<NetworkSource?> buildSource(int index) async {
    final item = feedList[index];
    if (item.bvid == null || item.cid == null) {
      return null;
    }
    _fetchDetail(index);
    final res = await VideoHttp.videoUrl(
      bvid: item.bvid,
      cid: item.cid!,
      qn: Pref.defaultVideoQa,
      tryLook: true,
      videoType: VideoType.ugc,
    );
    if (res case Success(:final response)) {
      return _pickSource(response);
    }
    return null;
  }

  NetworkSource? _pickSource(PlayUrlModel data) {
    try {
      final video = data.dash!.video!.first;
      final videoUrl = VideoUtils.getCdnUrl(video.playUrls);
      String? audioUrl;
      final audio = data.dash?.audio;
      if (audio != null && audio.isNotEmpty) {
        audioUrl = VideoUtils.getCdnUrl(audio.first.playUrls, isAudio: true);
      }
      return NetworkSource(
        videoSource: videoUrl,
        audioSource: audioUrl,
      );
    } catch (_) {
      return null;
    }
  }

  // ---- 互动:点赞 / 投币 / 评论区(像抖音那样右侧展开) ----

  /// 按页下标记录已赞/已投币,避免翻页回来状态丢失
  final RxMap<int, bool> liked = <int, bool>{}.obs;
  final RxMap<int, bool> coined = <int, bool>{}.obs;

  /// 右侧评论区是否展开,以及当前评论的是哪条视频
  final RxBool showReply = false.obs;
  final RxString replyBvid = ''.obs;

  /// 评论区需要一个稳定的 tag(与视频详情页同款控制器,收藏/展开状态都靠它)
  String replyTagFor(String bvid) => 'featureFeedReply_$bvid';

  bool get isLogin => Accounts.main.isLogin;

  String shareLink(int index) {
    final bvid = feedList[index].bvid;
    return bvid == null ? '' : 'https://www.bilibili.com/video/$bvid';
  }

  /// 首次进入某条视频时拉一次关系状态(是否已赞/已投币)
  Future<void> syncRelation(int index) async {
    if (index < 0 || index >= feedList.length) return;
    final bvid = feedList[index].bvid;
    if (bvid == null || !isLogin) return;
    try {
      final res = await VideoHttp.videoRelation(bvid: bvid);
      if (res case Success(:final response)) {
        liked[index] = response.like ?? false;
        coined[index] = (response.coin ?? 0) > 0;
      }
    } catch (_) {
      // 关系状态拿不到不影响播放
    }
  }

  /// 点赞/取消点赞
  Future<void> toggleLike(int index) async {
    if (index < 0 || index >= feedList.length) return;
    final bvid = feedList[index].bvid;
    if (bvid == null) return;
    if (!isLogin) {
      SmartDialog.showToast('请先登录');
      return;
    }
    final next = !(liked[index] ?? false);
    final res = await VideoHttp.likeVideo(bvid: bvid, type: next);
    if (res case Success()) {
      liked[index] = next;
      final detail = details[index];
      if (detail != null) {
        final stat = detail.stat;
        final base = stat?.like ?? 0;
        if (stat != null) {
          stat.like = next ? base + 1 : (base > 0 ? base - 1 : 0);
        }
        details[index] = detail;
      }
      SmartDialog.showToast(next ? '点赞成功' : '已取消点赞');
    } else {
      res.toast();
    }
  }

  /// 投币(面板里选好数量后回调)
  Future<void> coin(
    int index,
    int multiply, {
    bool coinWithLike = false,
  }) async {
    if (index < 0 || index >= feedList.length) return;
    final bvid = feedList[index].bvid;
    if (bvid == null) return;
    final res = await VideoHttp.coinVideo(
      bvid: bvid,
      multiply: multiply,
      selectLike: coinWithLike ? 1 : 0,
    );
    if (res case Success()) {
      coined[index] = true;
      if (coinWithLike) liked[index] = true;
      GlobalData().afterCoin(multiply);
      SmartDialog.showToast('投币成功');
    } else {
      res.toast();
    }
  }

  /// 展开/收起右侧评论区
  void openReply(int index) {
    if (index < 0 || index >= feedList.length) return;
    final bvid = feedList[index].bvid;
    if (bvid == null) {
      SmartDialog.showToast('这条推荐暂时没有评论区');
      return;
    }
    if (showReply.value && replyBvid.value == bvid) {
      showReply.value = false;
      return;
    }
    replyBvid.value = bvid;
    showReply.value = true;
  }

  @override
  void onClose() {
    _frameFix?.cancel();
    playerController
      ..pause(notify: false)
      ..dispose();
    super.onClose();
  }
}
