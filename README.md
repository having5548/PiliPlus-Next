<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>

<div align="center">
    <h1>PiliPlus Next</h1>
    <p>基于 <a href="https://github.com/bggRGjQaUbCoE/PiliPlus">PiliPlus</a> 的社区分支 — 专注 Bug 修复与三平台适配</p>
</div>

> **源项目地址:https://github.com/bggRGjQaUbCoE/PiliPlus**
> 本项目fork自 PiliPlus 并在其基础上继续开发,感谢上游作者 [bggRGjQaUbCoE](https://github.com/bggRGjQaUbCoE) 及所有贡献者的开源精神。

[English](README.en.md) | 中文

## 关于本分支(PiliPlus Next)

PiliPlus 是使用 Flutter 开发的 BiliBili 第三方客户端。本分支在源项目基础上:

- **Bug 修复优先**:对上游开放 issue 进行了系统分诊(去重后 79 组),按优先级逐个修复,清单与进度见 [docs/BUGFIX.md](docs/BUGFIX.md)
- **聚焦三平台**:只维护 **Windows / Android / HarmonyOS(移植中)** 三个平台,不再跟进 iOS / macOS / Linux
- **避免重复反馈**:提交 issue 前请先搜索本清单与已有 issue,重复问题会被合并关闭

## 致谢(按时间顺序)

本项目的诞生离不开以下项目:

- [guozhigq/pilipala](https://github.com/guozhigq/pilipala) — 原始作者
- [orz12/PiliPalaX](https://github.com/orz12/PiliPalaX) — 上游分支作者
- [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) — 本项目的直接源项目
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect) — B 站 API 文档
- [media-kit](https://github.com/media-kit/media-kit) — 跨平台播放器
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)

## 适配平台

- [x] Android
- [x] Windows
- [ ] HarmonyOS(移植中)

## 主要功能

- 推荐/热门/分区视频浏览,直播、番剧、影视、专栏全功能覆盖
- 视频播放:弹幕(高级弹幕/合并/会员彩色弹幕)、字幕、倍速、画质音质解码切换、超分辨率、SponsorBlock、高能进度条、DLNA 投屏、画中画、离线缓存
- 动态:浏览/发布/转发/投票/话题,富文本编辑
- 评论:楼中楼、带图评论、排序、置顶、点踩
- 直播:弹幕互动、表情、分区、舰长标识
- 消息:站内私信、回复/艾特提醒、聊天设置
- 账号:多账号、无痕/游客模式、Cookie 登录、WebDAV 备份
- 其他:稍后再看、收藏夹管理、笔记、互动视频、跳过片头片尾、AI 原声翻译等

完整功能列表见[源项目 README](https://github.com/bggRGjQaUbCoE/PiliPlus#readme)。

## 下载

- 从本仓库 [Releases](https://github.com/having5548/PiliPlus-Next/releases) 下载(发布后)
- 或克隆仓库拉取代码后在本地编译

## 从源码构建

> 构建前必读:本项目依赖一组 Flutter SDK 补丁,**不运行补丁脚本无法编译**。

1. 通过 git clone 安装 **Flutter 3.47.5 stable**(版本锁死于 `.fvmrc`,补丁按此版本制作)
2. 设置环境变量:
   - `FLUTTER_ROOT` → Flutter SDK 目录
   - `GITHUB_WORKSPACE` → 本仓库根目录
3. `flutter pub get`
4. 运行 `pwsh lib/scripts/patch.ps1 <platform>`(platform = `android` / `windows`;脚本会把补丁应用到 Flutter SDK 与 pub 缓存中的 material_ui/cupertino_ui 包)
5. 生成版本信息 `pwsh lib/scripts/build.ps1`(依赖 git 历史),或手工创建 `pili_release.json`
6. 构建:
   - Android: `flutter build apk --release --split-per-abi --dart-define-from-file=pili_release.json --no-pub`
   - Windows: `flutter build windows --release --dart-define-from-file=pili_release.json --no-pub`

## 声明

- 本项目是个人为了兴趣而开发,仅用于学习和测试,请于下载后 24 小时内删除
- 所用 API 皆从官方网站收集,不提供任何破解内容
- 本项目基于 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 修改,依据 **GNU GPL-3.0** 许可证开源分发,许可证全文见 [LICENSE](LICENSE)。修改内容为本仓库新增的提交,原版权与许可证声明均予保留

## Star History

[![Star History Chart](https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date)](https://star-history.dera.page/#bggRGjQaUbCoE/PiliPlus&Date)
