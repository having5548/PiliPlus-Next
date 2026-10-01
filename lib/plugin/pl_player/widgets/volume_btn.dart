import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/common_btn.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// volume button for the bottom control bar (desktop): click to mute /
/// restore, scroll wheel over the icon to step the volume
class VolumeButton extends StatefulWidget {
  const VolumeButton({super.key, required this.plPlayerController});

  final PlPlayerController plPlayerController;

  @override
  State<VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<VolumeButton> {
  PlPlayerController get plPlayerController => widget.plPlayerController;

  double _lastVolume = -1;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        final volume = plPlayerController.volume.value;
        final maxVolume = plPlayerController.maxVolume;
        final IconData icon;
        if (volume <= 0.001) {
          icon = Icons.volume_off;
        } else if (volume < maxVolume * 0.5) {
          icon = Icons.volume_down;
        } else {
          icon = Icons.volume_up;
        }
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              plPlayerController.setVolume(
                (volume + (event.scrollDelta.dy > 0 ? -0.05 : 0.05)).clamp(
                  0.0,
                  maxVolume,
                ),
              );
            }
          },
          child: ComBtn(
            width: 35,
            height: 30,
            tooltip: '音量: ${(volume / maxVolume * 100).round()}%',
            icon: Icon(icon, size: 22, color: Colors.white),
            onTap: () {
              if (volume > 0) {
                _lastVolume = volume;
                plPlayerController.setVolume(0);
              } else {
                plPlayerController.setVolume(
                  _lastVolume > 0 ? _lastVolume : maxVolume / 2,
                );
              }
            },
          ),
        );
      },
    );
  }
}
