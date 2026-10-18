import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/http/danmaku.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 控制条里的**内联弹幕输入框**。
///
/// 关键点:它必须渲染在控制条**内部** —— 视频页放在底部条的
/// `PlayerBar.title` 槽位里(整条由 `AppBarAni` 统一滑动进出),
/// 精选页放在控制条那一行里(整条由 `AnimatedSlide` 统一滑动)。
/// 所以它会和控制条的其它控件**同时出现、同时消失**,
/// 不会出现"按钮收了输入框还飘在那"的割裂感。
///
/// 行为对齐 B 站客户端:点输入框直接打字,回车或点「发送」即发一条
/// **纯文本弹幕**(滚动 / 25 号 / 白色),发完即清空并立刻上屏。
/// 需要挑颜色、位置、字号时,长按输入框可以走原来的样式面板
/// (由 [onLongPress] 提供,视频页会打开 `SendDanmakuPanel`)。
class DanmakuInputBar extends StatefulWidget {
  const DanmakuInputBar({
    super.key,
    required this.plPlayerController,
    required this.cid,
    required this.bvid,
    this.progress,
    this.onLongPress,
  });

  final PlPlayerController plPlayerController;

  /// 当前视频的 cid;为空时输入框不可用(如本地文件/直播源)
  final int? cid;

  /// 当前视频的 bvid
  final String? bvid;

  /// 弹幕出现的时间(毫秒)。不传则用播放器当前位置
  final int? progress;

  /// 长按输入框时的回调(用来打开带样式选项的原面板)
  final VoidCallback? onLongPress;

  @override
  State<DanmakuInputBar> createState() => _DanmakuInputBarState();
}

class _DanmakuInputBarState extends State<DanmakuInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _hasText = false;

  static const _hint = '发个友善的弹幕见证当下';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _dataReady => widget.cid != null && widget.bvid != null;

  bool get _dmClosed =>
      widget.cid != null &&
      widget.plPlayerController.dmState.contains(widget.cid);

  bool get _canSend => _hasText && !_sending && _dataReady && !_dmClosed;

  void _onChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _submit() {
    if (!_dataReady) {
      SmartDialog.showToast('当前视频不支持发送弹幕');
      return;
    }
    if (_dmClosed) {
      SmartDialog.showToast('UP主已关闭弹幕');
      return;
    }
    if (!_canSend) return;
    _send();
  }

  Future<void> _send() async {
    final msg = _controller.text.trim();
    if (msg.isEmpty || _sending) return;
    final cid = widget.cid;
    final bvid = widget.bvid;
    if (cid == null || bvid == null) return;

    setState(() => _sending = true);
    SmartDialog.showLoading(msg: '发送中...');
    try {
      final res = await DanmakuHttp.shootDanmaku(
        oid: cid,
        bvid: bvid,
        progress:
            widget.progress ??
            widget.plPlayerController.positionInMilliseconds,
        msg: msg,
        mode: 1,
        fontSize: 25,
        color: 0xFFFFFF,
      );
      SmartDialog.dismiss();
      if (res case Success(:final response)) {
        _controller.clear();
        if (mounted) setState(() => _hasText = false);
        SmartDialog.showToast('发送成功');
        VideoDanmaku? extra;
        if (response.dmid case final dmid?) {
          extra = VideoDanmaku(
            id: dmid,
            mid: widget.plPlayerController.midHash,
          );
        }
        // 发完立刻上屏,不用等下一次拉弹幕
        widget.plPlayerController.danmakuController?.addDanmaku(
          DanmakuContentItem(
            msg,
            color: Colors.white,
            type: DanmakuItemType.scroll,
            selfSend: true,
            extra: extra,
          ),
        );
      } else {
        res.toast();
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _dataReady && !_dmClosed;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 420),
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(
                CustomIcons.dm_on,
                size: 15,
                color: Colors.white.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: enabled,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(100),
                  ],
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white,
                  ),
                  cursorColor: Colors.white,
                  cursorHeight: 14,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: enabled ? _hint : '当前无法发送弹幕',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 发送按钮:有内容才高亮,和 B 站客户端一致
              GestureDetector(
                onTap: _canSend ? _submit : null,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _canSend
                        ? ColorScheme.of(context).primary
                        : Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _sending ? '发送中' : '发送',
                    style: TextStyle(
                      fontSize: 12,
                      color: _canSend
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
