import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:get/get.dart';

/// 精选:抖音式竖滑推荐流。
/// 内容来自 app 推荐接口,但排除主页推荐 tab 已经展示过的视频。
class FeatureFeedController extends GetxController {
  final RxList<RcmdVideoItemAppModel> feedList = <RcmdVideoItemAppModel>[].obs;
  final RxBool isLoading = false.obs;
  int _page = 0;
  bool _hasMore = true;

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
    try {
      int guard = 0;
      List<RcmdVideoItemAppModel>? picked;
      // 一页推荐里可能大半都在主页出现过,多拉几页直到凑出内容
      while (picked == null || picked.isEmpty) {
        if (guard++ >= 3 || !_hasMore) break;
        final res = await VideoHttp.rcmdVideoListApp(freshIdx: _page);
        _page++;
        if (res case Success(:final response)) {
          if (response.isEmpty) {
            _hasMore = false;
            break;
          }
          picked = [
            for (final item in response)
              if (item.goto == 'av' &&
                  item.bvid != null &&
                  item.cid != null &&
                  !excluded.contains(item.bvid) &&
                  !feedList.any((e) => e.bvid == item.bvid))
                item,
          ];
        } else {
          _hasMore = false;
          break;
        }
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

  PlPlayerController get playerController => PlPlayerController.getInstance();

  /// 最近一次播放失败的原因;为空表示没失败。
  /// 取流失败必须能被看见——旧实现直接 return,界面只会一直转圈。
  final RxString playerError = ''.obs;

  Timer? _frameFix;

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

  @override
  void onClose() {
    _frameFix?.cancel();
    playerController
      ..pause(notify: false)
      ..dispose();
    super.onClose();
  }
}
