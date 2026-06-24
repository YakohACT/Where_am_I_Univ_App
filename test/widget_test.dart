// 既存ノード定義（プラグイン非依存）の健全性テスト。
//
// 注: アプリ本体(MyApp)を pump すると LocationService.init() が
// sqflite / rootBundle などのプラットフォームプラグインを呼び、デバイスの無い
// CI(flutter test) では失敗する。そのため、ここではプラグイン不要で決定的な
// 純Dartロジック（baseNodes と baseNodeByImage）のみを検証する。
import 'package:flutter_test/flutter_test.dart';
import 'package:astar_pathfinder/location_service.dart';

void main() {
  group('LocationService.baseNodes', () {
    test('既存ノードは18件ある', () {
      expect(LocationService.baseNodes.length, 18);
    });

    test('IDは 0〜17 で重複なし', () {
      final ids = LocationService.baseNodes.map((b) => b.id).toList();
      expect(ids.toSet().length, 18, reason: 'IDが重複している');
      expect(ids.reduce((a, b) => a < b ? a : b), 0);
      expect(ids.reduce((a, b) => a > b ? a : b), 17);
    });

    test('画像ファイル名は重複なし', () {
      final images = LocationService.baseNodes.map((b) => b.image).toList();
      expect(images.toSet().length, 18, reason: '画像名が重複している');
    });
  });

  group('LocationService.baseNodeByImage', () {
    test('既知の画像から正しいノードを引ける', () {
      final ev = LocationService.baseNodeByImage('ev.png');
      expect(ev, isNotNull);
      expect(ev!.id, 1);
      expect(ev.name, 'EV');
    });

    test('未知の画像では null を返す', () {
      expect(LocationService.baseNodeByImage('unknown.png'), isNull);
    });
  });
}
