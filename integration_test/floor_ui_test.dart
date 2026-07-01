// 実機UIテスト: 階層表示・階層プルダウン切替・階段移動を検証する。
// 実行: flutter test integration_test/floor_ui_test.dart -d <deviceId>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:astar_pathfinder/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 参照図基準の正規化座標(0〜1)を、実際の描画マッピングでタップする
  Future<void> tapNodeAt(WidgetTester tester, double nx, double ny,
      [Size diagram = kFloor1Diagram]) async {
    final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is GraphPainter);
    final rect = tester.getRect(paint);
    final p = mapNodeToScreen(Offset(nx, ny), rect.size, diagram);
    await tester.tapAt(rect.topLeft + p);
    await tester.pumpAndSettle();
  }

  testWidgets('階層表示・プルダウン切替・階段移動', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GraphPage()));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 左上の階層プルダウンが「1階」を表示
    expect(find.text('1階'), findsWidgets);

    // EVノード(0.237, 0.649)をタップ → 詳細に ID|階層|座標(x,y,z)
    await tapNodeAt(tester, 0.237, 0.649);
    expect(find.textContaining('ID:ev'), findsOneWidget);
    expect(find.textContaining('階層:1階'), findsOneWidget);
    expect(find.textContaining('座標:(24,65,1)'), findsOneWidget);
    // EVも階段と同様に上下移動ボタンが出る
    expect(find.text('🔼 上の階へ'), findsOneWidget);
    expect(find.text('🔽 下の階へ'), findsOneWidget);

    // 階段ノード(0.300, 0.548)をタップ → 階段移動ボタンが出る
    await tapNodeAt(tester, 0.300, 0.548);
    expect(find.text('🔼 上の階へ'), findsOneWidget);
    expect(find.text('🔽 下の階へ'), findsOneWidget);

    // 「上の階へ」→ 2階へ移動。2階のノード（演習室）が表示される
    await tester.tap(find.text('🔼 上の階へ'));
    await tester.pumpAndSettle();
    expect(find.text('2階'), findsWidgets); // プルダウンが2階表示
    await tapNodeAt(tester, 0.648, 0.080, kPdfDiagram); // 演習室
    expect(find.textContaining('ID:enshu'), findsOneWidget);
    expect(find.textContaining('階層:2階'), findsOneWidget);

    // プルダウンで4階へ切替 → サーバールームが表示される
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4階').last);
    await tester.pumpAndSettle();
    await tapNodeAt(tester, 0.596, 0.541, kPdfDiagram); // サーバールーム
    expect(find.textContaining('ID:server'), findsOneWidget);
    expect(find.textContaining('階層:4階'), findsOneWidget);

    // プルダウンで1階へ戻すとEVノードが再びタップ可能（データ復帰）
    await tester.tap(find.byType(DropdownButton<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1階').last);
    await tester.pumpAndSettle();
    await tapNodeAt(tester, 0.237, 0.649);
    expect(find.textContaining('座標:(24,65,1)'), findsOneWidget);
  });
}
