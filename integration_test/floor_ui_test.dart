// 実機UIテスト: 階層表示・階層プルダウン切替・階段移動を検証する。
// 実行: flutter test integration_test/floor_ui_test.dart -d <deviceId>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:astar_pathfinder/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // グラフ領域内の正規化座標(0〜1)をタップする
  Future<void> tapNodeAt(WidgetTester tester, double nx, double ny) async {
    final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is GraphPainter);
    final rect = tester.getRect(paint);
    await tester.tapAt(Offset(
      rect.left + nx * rect.width,
      rect.top + ny * rect.height,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('階層表示・プルダウン切替・階段移動', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GraphPage()));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 左上の階層プルダウンが「1階」を表示
    expect(find.text('1階'), findsWidgets);

    // EVノード(0.30, 0.60)をタップ → 詳細に ID|階層|座標(x,y,z)
    await tapNodeAt(tester, 0.30, 0.60);
    expect(find.textContaining('ID:ev'), findsOneWidget);
    expect(find.textContaining('階層:1階'), findsOneWidget);
    expect(find.textContaining('座標:(30,60,1)'), findsOneWidget);

    // 階段ノード(0.34, 0.54)をタップ → 階段移動ボタンが出る
    await tapNodeAt(tester, 0.34, 0.54);
    expect(find.text('🔼 上の階へ'), findsOneWidget);
    expect(find.text('🔽 下の階へ'), findsOneWidget);

    // 「上の階へ」→ 2階へ移動し、空フロアの表示になる
    await tester.tap(find.text('🔼 上の階へ'));
    await tester.pumpAndSettle();
    expect(find.text('2階のデータはまだありません'), findsOneWidget);

    // プルダウンで4階へ切替
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4階').last);
    await tester.pumpAndSettle();
    expect(find.text('4階のデータはまだありません'), findsOneWidget);

    // プルダウンで1階へ戻すとEVノードが再びタップ可能（データ復帰）
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1階').last);
    await tester.pumpAndSettle();
    await tapNodeAt(tester, 0.30, 0.60);
    expect(find.textContaining('座標:(30,60,1)'), findsOneWidget);
  });
}
