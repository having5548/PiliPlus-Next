import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/space/space_season_series/season.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

/// vertical season/series card styled like a video card: cover on top,
/// title & meta below (official bilibili space style)
class SeasonSeriesCard extends StatelessWidget {
  const SeasonSeriesCard({
    super.key,
    required this.item,
    required this.onTap,
  });
  final SpaceSsModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: item.meta!.name,
      cover: item.meta!.cover,
    );
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        onTap: onTap,
        borderRadius: const .all(.circular(12)),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            AspectRatio(
              aspectRatio: Style.aspectRatio,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints boxConstraints) {
                  final double maxWidth = boxConstraints.maxWidth;
                  final double maxHeight = boxConstraints.maxHeight;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      NetworkImgLayer(
                        src: item.meta!.cover,
                        width: maxWidth,
                        height: maxHeight,
                        borderRadius: const .vertical(top: .circular(12)),
                      ),
                      PBadge(
                        text:
                            '${item.meta!.seasonId != null ? '合集' : '列表'}: ${item.meta!.total}',
                        bottom: 6,
                        right: 7,
                        size: .small,
                        type: .gray,
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const .all(8),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    item.meta!.name!,
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: const TextStyle(height: 1.42, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormatUtils.dateFormat(item.meta!.ptime),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1,
                      color: theme.colorScheme.outline,
                      overflow: .clip,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
