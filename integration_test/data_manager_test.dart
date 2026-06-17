// 実機上で LocationService のデータ管理API（アップロード/一覧/削除）を検証する。
// 実際の sqflite DB に対して本番コードパスを走らせる。
//
// 実行: flutter test integration_test/data_manager_test.dart -d <deviceId>
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:astar_pathfinder/location_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('画像ファイルからのアップロードと削除', (tester) async {
    final svc = LocationService.instance;
    await svc.init();

    // スマホの画像ファイルの代わりにバンドル画像をバイト列として使用
    final data = await rootBundle.load('lib/images/ev.png');
    final bytes = data.buffer.asUint8List();

    // ① アップロード（addFromImage）
    final point = await svc.addFromImage(name: 'TEST_UPLOAD', bytes: bytes);
    expect(point, isNotNull, reason: 'アップロードに失敗');
    expect(point!.id >= 100, true, reason: '収集データIDは100以上であるべき');

    // ② 一覧に出る & 既存ノードは18件
    var entries = await svc.listEntries();
    expect(
      entries.any((e) => e.id == point.id && e.name == 'TEST_UPLOAD'),
      true,
      reason: 'アップロードした行が一覧に無い',
    );
    expect(entries.where((e) => e.isBase).length, 18,
        reason: '既存ノードが18件でない');

    // ③ 1件削除
    await svc.deleteEntry(point.id);
    entries = await svc.listEntries();
    expect(entries.any((e) => e.id == point.id), false,
        reason: '削除した行がまだ残っている');

    // ④ 2件追加してから収集データ一括削除
    await svc.addFromImage(name: 'A', bytes: bytes);
    await svc.addFromImage(name: 'B', bytes: bytes);
    final removed = await svc.deleteAllCollected();
    expect(removed >= 2, true, reason: '一括削除の件数が不正');

    entries = await svc.listEntries();
    expect(entries.where((e) => !e.isBase).length, 0,
        reason: '収集データが残っている');
    expect(entries.where((e) => e.isBase).length, 18,
        reason: '既存ノードまで消えてしまった');
  });
}
