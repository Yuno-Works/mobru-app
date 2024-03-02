import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:miru_app/data/providers/anilist_provider.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/controllers/watch/reader_controller.dart';
import 'package:miru_app/data/services/database_service.dart';
import 'package:miru_app/utils/log.dart';
import 'package:miru_app/views/widgets/watch/playlist.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:extended_image/extended_image.dart';
import 'package:miru_app/utils/miru_storage.dart';
import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

class ComicController extends ReaderController<ExtensionMangaWatch> {
  ComicController({
    required super.title,
    required super.playList,
    required super.detailUrl,
    required super.playIndex,
    required super.episodeGroupId,
    required super.runtime,
    required super.cover,
    required super.anilistID,
  });
  Map<String, MangaReadMode> readmode = {
    'standard': MangaReadMode.standard,
    'rightToLeft': MangaReadMode.rightToLeft,
    'webTonn': MangaReadMode.webTonn,
  };
  final String setting = MiruStorage.getSetting(SettingKey.readingMode);
  // final readType = MangaReadMode.standard.obs;
  // final StreamController<double> visbility = StreamController();
  final currentScale = 1.0.obs;
  // 当前页码
  final pageController = ExtendedPageController().obs;
  final itemPositionsListener = ItemPositionsListener.create();
  // 是否已经恢复上次阅读
  final isRecover = false.obs;
  final readType = MangaReadMode.standard.obs;
  final globalScrollController = ScrollController();
  final currentOffset = 0.0.obs;
  final isZoom = false.obs;
  final isScrollEnd = false.obs;
  final positionedindex = 0.obs;
  final scrollController = ScrollController();
  final RxDouble height = (-1.0).obs;
  late final List<List<GlobalKey>> keys =
      List.generate(playList.length, (index) => []);
  @override
  void onInit() async {
    _initSetting();
    getContent();
    // getTartgetContent(playIndex);
    // Timer.periodic(const Duration(milliseconds: 500), (timer) {
    //   // if (globalItemScrollController.isAttached) {
    //   //   globalItemScrollController.jumpTo(index: index.value);
    //   //   timer.cancel();
    //   // }
    // });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    enableWakeLock.value = MiruStorage.getSetting(SettingKey.enableWakelock);
    WakelockPlus.toggle(enable: enableWakeLock.value);
    //webtoon 模式的scrollcontroller
    scrollController.addListener(_onscroll);

    // itemPositionsListener.itemPositions.addListener(() {
    //   if (itemPositionsListener.itemPositions.value.isEmpty) {
    //     return;
    //   }
    //   final pos = itemPositionsListener.itemPositions.value.first;
    //   currentGlobalProgress.value = pos.index;
    // });
    // scrollOffsetListener.changes.listen((event) {
    //   hideControlPanel();
    // });
    // ever(height, (callback) {
    //   super.height.value = callback;
    // });
    mouseTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (setControllPanel.value) {
        isShowControlPanel.value = true;
        return;
      }
      isShowControlPanel.value = false;
    });
    ever(readType, (callback) {
      if (items.isNotEmpty) {
        _jumpToPage(currentGlobalProgress.value);
      }
      // 保存设置
      DatabaseService.setMangaReaderType(
        super.detailUrl,
        callback,
      );
    });
    ever(enableAutoScroll, (callback) {
      if (callback) {
        autoScrollTimer = Timer.periodic(
            Duration(milliseconds: autoScrollInterval.value), (timer) {
          if (isScrolled.value) {
            scrollOffsetController.animateScroll(
              duration: const Duration(milliseconds: 100),
              curve: Curves.ease,
              offset: autoScrollOffset.value,
            );
          }
        });
        return;
      }
      autoScrollTimer?.cancel();
    });
    //control footer 的 slider 改變時，更新頁碼
    ever(progress, (callback) {
      // 防止逆向回饋
      if (!updateSlider.value) {
        return;
      }
      logger.info(progress);
      currentGlobalProgress.value = callback;
      _jumpToPage(callback);
    });

    ever(currentGlobalProgress, (callback) async {
      await Future.delayed(const Duration(milliseconds: 50));
      if (updateSlider.value) {
        progress.value = callback;
      }
      updateSlider.value = false;
      int fullIndex = 0;
      // debugPrint(currentLocalProgress.value.toString());
      for (int i = 0; i < itemlength.length; i++) {
        fullIndex += itemlength[i];
        if (fullIndex > callback) {
          index.value = i;
          super.index.value = i;
          currentLocalProgress.value = callback - (fullIndex - itemlength[i]);
          break;
        }
      }
    });
    ever(super.watchData, (callback) async {
      if (isRecover.value || callback == null) {
        return;
      }
      loadTargetContent(playIndex);
      isRecover.value = true;
      // 获取上次阅读的页码
      final history = await DatabaseService.getHistoryByPackageAndUrl(
        super.runtime.extension.package,
        super.detailUrl,
      );

      if (history == null ||
          history.progress.isEmpty ||
          episodeGroupId != history.episodeGroupId ||
          history.episodeId != index.value) {
        return;
      }
      currentGlobalProgress.value = int.parse(history.progress);
      _jumpToPage(currentGlobalProgress.value);
    });
    super.onInit();
  }

  void _onscroll() {
    if (updateSlider.value) {
      hideControlPanel();
    }
    // 現在位置
    // final pos =
    //     scrollController.offset - scrollController.position.minScrollExtent;
    // currentGlobalProgress.value = pos ~/ height.value;
  }

  @override
  Future<void> loadTargetContent(int targetIndex) async {
    try {
      if (targetIndex < 0 ||
          targetIndex == itemlength.length ||
          items[targetIndex].isNotEmpty) {
        return;
      }
      final dynamic updatedData =
          await runtime.watch(playList[targetIndex].url);
      items[targetIndex] = updatedData.urls as List<String>;
      itemlength[targetIndex] = updatedData.urls.length;
      keys[targetIndex] =
          List.generate(updatedData.urls.length, (index) => GlobalKey());
      isScrollEnd.value = false;
    } catch (e) {
      error.value = e.toString();
    }
  }

  onKey(KeyEvent event) {
    // 按下 ctrl
    isZoom.value = event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight;
    // 上下
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (readType.value == MangaReadMode.webTonn) {
        return previousPage();
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (readType.value == MangaReadMode.webTonn) {
        return nextPage();
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (readType.value == MangaReadMode.rightToLeft) {
        return nextPage();
      }
      previousPage();
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (readType.value == MangaReadMode.rightToLeft) {
        return previousPage();
      }
      nextPage();
    }
  }

  _initSetting() async {
    readType.value = readmode[setting] ?? MangaReadMode.standard;
    readType.value = await DatabaseService.getMnagaReaderType(
      super.detailUrl,
      readType.value,
    );
  }

  _jumpToPage(int page) async {
    if (readType.value == MangaReadMode.webTonn) {
      // final local = globalToLocalProgress(page);
      // final localpage = local[0];
      // final chap = local[1];
      // if (keys[chap][localpage].currentContext == null) {
      //   return;
      // }
      // Scrollable.ensureVisible(keys[chap][localpage].currentContext!,
      //     alignment: 0.0, duration: const Duration(milliseconds: 10));
      // if (itemScrollController.isAttached) {
      //   itemScrollController.jumpTo(
      //     index: page,
      //   );
      // }
      // if (scrollController.hasClients) {
      //   scrollController.jumpTo(
      //       scrollController.position.minScrollExtent + page * height.value);
      // }

      return;
    }
    if (pageController.value.hasClients) {
      pageController.value.jumpToPage(page);
      return;
    }
    pageController.value = ExtendedPageController(initialPage: page);
  }

  // 下一页
  @override
  void nextPage() {
    if (readType.value != MangaReadMode.webTonn) {
      pageController.value.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    } else {
      if (keys[index.value][currentLocalProgress.value + 1].currentContext ==
          null) {
        return;
      }
      Scrollable.ensureVisible(
          keys[index.value][currentLocalProgress.value + 1].currentContext!,
          alignment: 0.0,
          duration: const Duration(milliseconds: 300));
      // scrollOffsetController.animateScroll(
      //   duration: const Duration(milliseconds: 100),
      //   curve: Curves.ease,
      //   offset: 200.0,
      // );
      // scrollController.animateTo(
      //     scrollController.offset + scrollController.position.viewportDimension,
      //     duration: const Duration(milliseconds: 300),
      //     curve: Curves.ease);
    }
  }

  // 上一页
  @override
  void previousPage() {
    if (readType.value != MangaReadMode.webTonn) {
      pageController.value.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    } else {
      if (keys[index.value][currentLocalProgress.value - 1].currentContext ==
          null) {
        return;
      }
      Scrollable.ensureVisible(
          keys[index.value][currentLocalProgress.value - 1].currentContext!,
          alignment: 0.0,
          duration: const Duration(milliseconds: 300));
      // scrollController.animateTo(
      //     scrollController.offset - scrollController.position.viewportDimension,
      //     duration: const Duration(milliseconds: 300),
      //     curve: Curves.ease);
    }
  }

  @override
  Future<void> loadNextChapter() async {
    await loadTargetContent(index.value + 1);
    return;
  }

  @override
  Future<void> loadPrevChapter() async {
    await loadTargetContent(index.value - 1);
    // if (itemScrollController.isAttached) {
    //   itemScrollController.scrollTo(
    //       index: itemlength[index.value - 1],
    //       duration: const Duration(milliseconds: 10));
    //   return;
    // }
    if (pageController.value.hasClients) {
      pageController.value.jumpToPage(itemlength[index.value - 1]);
    }
  }

  @override
  Future<void> getContent() async {
    try {
      error.value = '';
      watchData.value =
          await runtime.watch(cuurentPlayUrl) as ExtensionMangaWatch;
      itemlength[index.value] = watchData.value!.urls.length;
      items[index.value] = watchData.value!.urls;
      keys[index.value] = List.generate(
        watchData.value!.urls.length,
        (index) => GlobalKey(),
      );
      positionedindex.value = index.value;
    } catch (e) {
      error.value = e.toString();
    }
  }

  @override
  void onClose() async {
    if (super.watchData.value != null) {
      // 获取所有页数量
      final pages = super.watchData.value!.urls.length;
      super.addHistory(
        currentLocalProgress.value.toString(),
        pages.toString(),
      );
    }
    autoScrollTimer?.cancel();
    if (MiruStorage.getSetting(SettingKey.autoTracking) && anilistID != "") {
      AniListProvider.editList(
        status: AnilistMediaListStatus.current,
        progress: playIndex + 1,
        mediaId: anilistID,
      );
    }

    mouseTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!Platform.isAndroid) {
      await WindowManager.instance.setFullScreen(false);
    }
    scrollController.dispose();
    super.onClose();
  }
}
