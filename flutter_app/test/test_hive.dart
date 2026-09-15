import 'dart:io';

import 'package:hive/hive.dart';
import 'package:paper_graph/core/services/hive_service.dart';

class TestHiveEnvironment {
  late final Directory directory;

  Future<void> start() async {
    directory = await Directory.systemTemp.createTemp('papergraph_test_');
    Hive.init(directory.path);
    await Hive.openBox(HiveService.favoritesBoxName);
    await Hive.openBox(HiveService.settingsBoxName);
    await Hive.openBox(HiveService.canonicalPapersBoxName);
    await Hive.openBox(HiveService.cachedGraphsBoxName);
    await Hive.openBox(HiveService.paperNotesBoxName);
    HiveService.setActiveUserScope('test-user');
  }

  Future<void> reset() async {
    for (final boxName in [
      HiveService.favoritesBoxName,
      HiveService.settingsBoxName,
      HiveService.canonicalPapersBoxName,
      HiveService.cachedGraphsBoxName,
      HiveService.paperNotesBoxName,
    ]) {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      await Hive.box(boxName).clear();
    }
    HiveService.setActiveUserScope('test-user');
  }

  Future<void> stop() async {
    await Hive.close();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}
