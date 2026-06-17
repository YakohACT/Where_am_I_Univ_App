import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'location_service.dart';
import 'photo_register_page.dart';
import 'wifi_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Network Detail View',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const GraphPage(),
    );
  }
}

// ─── データモデル ─────────────────────────────────────────────

class GraphNode {
  final String id;
  final String label;
  final Offset position; // 正規化座標 (0.0 〜 1.0)
  final String image;    // lib/images/ 配下の画像ファイル名
  const GraphNode(this.id, this.label, this.position, this.image);
}

class GraphEdge {
  final String from;
  final String to;
  const GraphEdge(this.from, this.to);
}

// ─── GraphPage ───────────────────────────────────────────────

class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  // ノード定義
  static const List<GraphNode> nodes = [
    GraphNode('exit',     '出口',   Offset(0.40, 0.30), 'exit.png'),
    GraphNode('cross',    '交差点', Offset(0.40, 0.46), 'cr.png'),
    GraphNode('sc',       'sc',     Offset(0.12, 0.46), 'sc.png'),
    GraphNode('stair',    '階段',   Offset(0.34, 0.54), 'stair.png'),
    GraphNode('ev',       'EV',     Offset(0.30, 0.60), 'ev.png'),
    GraphNode('lobby2',   'ロビー2',Offset(0.42, 0.60), 'lobby2.png'),
    GraphNode('wc',       'WC',     Offset(0.54, 0.60), 'wc.png'),
    GraphNode('hall1',    '廊下1',  Offset(0.54, 0.46), 'corridor1.png'),
    GraphNode('hall2',    '廊下2',  Offset(0.68, 0.46), 'corridor2.png'),
    GraphNode('hall3',    '廊下3',  Offset(0.82, 0.46), 'corridor3.png'),
    GraphNode('hall4',    '廊下4',  Offset(0.94, 0.46), 'corridor4.png'),
    GraphNode('os',       'os',     Offset(0.68, 0.34), 'os.png'),
    GraphNode('big',      '大講義', Offset(0.94, 0.34), 'lc.png'),
    GraphNode('mid',      '中講義', Offset(0.94, 0.62), 'mc.png'),
    GraphNode('ic',       'ic',     Offset(0.20, 0.60), 'ic.png'),
    GraphNode('ea',       'ea',     Offset(0.13, 0.68), 'ea.png'),
    GraphNode('lobby1',   'ロビー1',Offset(0.28, 0.68), 'lobby1.png'),
    GraphNode('entrance', '入口',   Offset(0.40, 0.74), 'entrance.png'),
  ];

  // エッジ定義
  static const List<GraphEdge> edges = [
    GraphEdge('exit',    'cross'),
    GraphEdge('sc',      'cross'),
    GraphEdge('sc',      'ic'),
    GraphEdge('cross',   'hall1'),
    GraphEdge('cross',   'stair'),
    GraphEdge('cross',   'lobby2'),
    GraphEdge('stair',   'ev'),
    GraphEdge('ev',      'lobby2'),
    GraphEdge('lobby2',  'wc'),
    GraphEdge('lobby2',  'lobby1'),
    GraphEdge('hall1',   'hall2'),
    GraphEdge('hall2',   'hall3'),
    GraphEdge('hall3',   'hall4'),
    GraphEdge('hall2',   'os'),
    GraphEdge('hall4',   'big'),
    GraphEdge('hall4',   'mid'),
    GraphEdge('ic',      'ea'),
    GraphEdge('ic',      'lobby1'),
    GraphEdge('ic',      'ev'),
    GraphEdge('ea',      'lobby1'),
    GraphEdge('lobby1',  'entrance'),
    GraphEdge('entrance','lobby2'),
  ];

  GraphNode? _selectedNode;
  String?    _startNodeId;
  String?    _goalNodeId;
  List<String> _path = [];

  // カメラで撮影し登録した画像（ノードID → 保存先ファイルパス）
  final Map<String, String> _capturedImages = {};
  final ImagePicker _picker = ImagePicker();

  // 画像識別（類似度判定）用
  bool _identifying = false;          // 判定処理中フラグ
  String? _matchBanner;               // 判定結果バナー文言（一定時間表示）
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    // 埋め込み・PCA・DBを準備（散布図に必要）
    LocationService.instance.init();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  // ─── カメラで撮影 → 画像＋WiFiでDB全件と照合し場所を推定（option B）──
  // 既存ノード(id 0〜17)＋SQLite蓄積分を対象に、画像記述子とWiFi指紋を
  // 併用して最類似ノードを推定する（LocationService.identifyFromDb）。
  Future<void> _identifyByPhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (photo == null) return; // キャンセル

      if (!mounted) return;
      setState(() => _identifying = true);

      final queryBytes = await File(photo.path).readAsBytes();
      // 現在地のWiFi指紋を取得（Android。失敗時は空→画像のみで推定）
      final wifi = await WifiService.instance.scan();
      // DB全件（既存ノード + 撮影蓄積分）と画像＋WiFiで照合
      final match = await LocationService.instance
          .identifyFromDb(queryBytes, wifi: wifi);

      if (!mounted) return;
      if (match == null) {
        setState(() => _identifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('撮影画像を解析できませんでした')),
        );
        return;
      }

      // 一致したDB行をグラフ上のノードへ対応付け（画像ファイル名で照合）
      GraphNode? best;
      for (final n in nodes) {
        if (n.image == match.image) {
          best = n;
          break;
        }
      }

      final percent = (match.similarity.clamp(0.0, 1.0) * 100);
      final label = best?.label ?? match.name;
      final source = match.isBase ? '既存' : '蓄積';
      // 画像/WiFiの内訳（WiFi併用時のみ）
      final method = match.usedWifi
          ? '画像${(match.imageSim * 100).toStringAsFixed(0)}% + WiFi${((match.wifiSim ?? 0) * 100).toStringAsFixed(0)}%'
          : '画像のみ';

      setState(() {
        _identifying = false;
        if (best != null) _selectedNode = best; // 最類似ノードを選択状態に
        _matchBanner =
            '推定地点: $label  (一致度 ${percent.toStringAsFixed(1)}% / $source / $method)';
      });

      // 一定時間後にバナーを消す
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _matchBanner = null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _identifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('カメラの起動に失敗しました: $e')),
      );
    }
  }

  // ─── 「新しい写真の位置登録」画面へ遷移 ──────────────────
  Future<void> _openPhotoRegister(GraphNode node) async {
    // 画像ファイル名から既存ノードの整数ID・名前を引く（DB体系に合わせる）
    final base = LocationService.baseNodeByImage(node.image);
    final id = base?.id ?? -1;
    final name = base?.name ?? node.label;

    // 散布図に必要な埋め込み・PCAの準備が終わるまで待機
    await LocationService.instance.init();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoRegisterPage(
          targetNodeId: id,
          targetNodeName: name,
        ),
      ),
    );
  }

  // ─── A* アルゴリズム ─────────────────────────────────
  List<String> _astar(String start, String goal) {
    final posMap = {for (final n in nodes) n.id: n.position};
    final adj = <String, List<String>>{for (final n in nodes) n.id: []};
    for (final e in edges) {
      adj[e.from]!.add(e.to);
      adj[e.to]!.add(e.from);
    }

    double h(String a, String b) => (posMap[a]! - posMap[b]!).distance;

    final gScore = <String, double>{for (final n in nodes) n.id: double.infinity};
    final fScore = <String, double>{for (final n in nodes) n.id: double.infinity};
    final cameFrom = <String, String>{};

    gScore[start] = 0;
    fScore[start] = h(start, goal);

    final open = SplayTreeSet<String>(
      (a, b) {
        final d = fScore[a]!.compareTo(fScore[b]!);
        return d != 0 ? d : a.compareTo(b);
      },
    )..add(start);

    while (open.isNotEmpty) {
      final current = open.first;
      if (current == goal) {
        final path = <String>[];
        String? node = goal;
        while (node != null) {
          path.insert(0, node);
          node = cameFrom[node];
        }
        return path;
      }
      open.remove(current);
      for (final nb in adj[current]!) {
        final tg = gScore[current]! + (posMap[current]! - posMap[nb]!).distance;
        if (tg < gScore[nb]!) {
          open.remove(nb);
          cameFrom[nb] = current;
          gScore[nb] = tg;
          fScore[nb] = tg + h(nb, goal);
          open.add(nb);
        }
      }
    }
    return [];
  }

  // ─── タップ検出 ──────────────────────────────────────
  GraphNode? _findTappedNode(Offset tap, Size size) {
    const hitR = 24.0;
    GraphNode? found;
    double minDist = double.infinity;
    for (final n in nodes) {
      final p = Offset(n.position.dx * size.width, n.position.dy * size.height);
      final d = (tap - p).distance;
      if (d < hitR && d < minDist) {
        minDist = d;
        found = n;
      }
    }
    return found;
  }

  void _onTap(TapUpDetails d, Size size) {
    final node = _findTappedNode(d.localPosition, size);
    setState(() {
      _selectedNode = node; // null なら選択解除
    });
  }

  // 始点・目的地セット後に自動で経路探索
  void _setStart(GraphNode node) {
    setState(() {
      if (_startNodeId == node.id) {
        _startNodeId = null;
      } else {
        if (_goalNodeId == node.id) _goalNodeId = null;
        _startNodeId = node.id;
      }
      _updatePath();
    });
  }

  void _setGoal(GraphNode node) {
    setState(() {
      if (_goalNodeId == node.id) {
        _goalNodeId = null;
      } else {
        if (_startNodeId == node.id) _startNodeId = null;
        _goalNodeId = node.id;
      }
      _updatePath();
    });
  }

  void _updatePath() {
    if (_startNodeId != null && _goalNodeId != null) {
      _path = _astar(_startNodeId!, _goalNodeId!);
    } else {
      _path = [];
    }
  }

  // ─── ビルド ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ── AppBar ──────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: const Text(
          'Network Detail View',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _identifying ? null : _identifyByPhoto,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black87, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),

      // ── Body ────────────────────────────────────────
      body: Stack(
        children: [
          Column(
            children: [
              // ── グラフエリア（上半分）──
              Expanded(
                child: Container(
                  color: const Color(0xFFEEEFF5),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        onTapUp: (d) => _onTap(d, size),
                        child: CustomPaint(
                          size: size,
                          painter: GraphPainter(
                            nodes: nodes,
                            edges: edges,
                            selectedNodeId: _selectedNode?.id,
                            startNodeId: _startNodeId,
                            goalNodeId: _goalNodeId,
                            path: _path,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── 詳細パネル（ノード選択時のみ表示）──
              if (_selectedNode != null) ...[
                const Divider(height: 1, thickness: 1, color: Colors.black26),
                _DetailPanel(
                  node: _selectedNode!,
                  capturedImagePath: _capturedImages[_selectedNode!.id],
                  onCapture:  () => _openPhotoRegister(_selectedNode!),
                  onSetStart: () => _setStart(_selectedNode!),
                  onSetGoal:  () => _setGoal(_selectedNode!),
                ),
              ],
            ],
          ),

          // ── 判定結果バナー（一定時間表示）──
          if (_matchBanner != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _ResultBanner(text: _matchBanner!),
            ),

          // ── 判定処理中のオーバーレイ ──
          if (_identifying)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        '画像を解析中...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 判定結果バナー ──────────────────────────────────────────

class _ResultBanner extends StatelessWidget {
  final String text;
  const _ResultBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF323232),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.place, color: Color(0xFF7BB7FF), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 詳細パネル Widget ────────────────────────────────────────

class _DetailPanel extends StatelessWidget {
  final GraphNode node;
  final String? capturedImagePath; // カメラ撮影済みなら優先表示
  final VoidCallback onCapture;
  final VoidCallback onSetStart;
  final VoidCallback onSetGoal;

  const _DetailPanel({
    required this.node,
    required this.capturedImagePath,
    required this.onCapture,
    required this.onSetStart,
    required this.onSetGoal,
  });

  @override
  Widget build(BuildContext context) {
    // 表示用座標（正規化値を100倍してピクセルっぽく表示）
    final int cx = (node.position.dx * 100).round();
    final int cy = (node.position.dy * 100).round();

    // 写真ウィジェット（撮影画像があればそれを、なければアセットを表示）
    final Widget photo = capturedImagePath != null
        ? Image.file(
            File(capturedImagePath!),
            width: 170,
            height: 260,
            fit: BoxFit.cover,
          )
        : Image.asset(
            'lib/images/${node.image}',
            width: 170,
            height: 260,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text(
                  '選択した\nノードの\n写真',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black54,
                  ),
                ),
              );
            },
          );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 写真エリア ──
          Container(
            width: 170,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87, width: 2.5),
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: photo,
          ),

          const SizedBox(width: 20),

          // ── ノード情報 & ボタン ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ノード名
                Text(
                  node.label,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                // ID & 座標
                Text(
                  'ID:${node.id} | 座標:($cx,$cy)',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 18),

                // ボタン：新しい写真を登録する
                _ActionButton(
                  label: '新しい写真を登録する',
                  color: const Color(0xFF4A90E2),
                  onTap: onCapture,
                ),
                const SizedBox(height: 11),

                // ボタン：ここを始点にする
                _ActionButton(
                  label: 'ここを始点にする',
                  color: const Color(0xFF4CAF50),
                  onTap: onSetStart,
                ),
                const SizedBox(height: 11),

                // ボタン：ここを目的地とする
                _ActionButton(
                  label: 'ここを目的地とする',
                  color: const Color(0xFFE53935),
                  onTap: onSetGoal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── アクションボタン ─────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

// ─── GraphPainter ────────────────────────────────────────────

class GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? selectedNodeId;
  final String? startNodeId;
  final String? goalNodeId;
  final List<String> path;

  static const Color _defaultColor  = Color(0xFF4A90E2);
  static const Color _selectedColor = Color(0xFF1A6CC8);
  static const Color _startColor    = Color(0xFF4CAF50);
  static const Color _goalColor     = Color(0xFFE53935);
  static const Color _pathColor     = Color(0xFFFF9500);

  const GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
    this.startNodeId,
    this.goalNodeId,
    this.path = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pos = {
      for (final n in nodes)
        n.id: Offset(n.position.dx * size.width, n.position.dy * size.height),
    };

    // 経路エッジ集合
    final pathEdgeSet = <String>{};
    for (int i = 0; i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      pathEdgeSet.add('$a-$b');
      pathEdgeSet.add('$b-$a');
    }

    // ── エッジ描画 ──
    final normalEdge = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final pathEdge = Paint()
      ..color = _pathColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final e in edges) {
      final isPath = pathEdgeSet.contains('${e.from}-${e.to}');
      canvas.drawLine(pos[e.from]!, pos[e.to]!, isPath ? pathEdge : normalEdge);
    }

    // ── ノード & ラベル描画 ──
    final pathSet = path.toSet();

    for (final n in nodes) {
      final p = pos[n.id]!;
      final isSelected = n.id == selectedNodeId;
      final isStart    = n.id == startNodeId;
      final isGoal     = n.id == goalNodeId;
      final isOnPath   = pathSet.contains(n.id);

      // ノード色
      Color nodeColor = _defaultColor;
      if (isStart) {
        nodeColor = _startColor;
      } else if (isGoal) {
        nodeColor = _goalColor;
      } else if (isOnPath) {
        nodeColor = _pathColor;
      } else if (isSelected) {
        nodeColor = _selectedColor;
      }

      double radius = 9;
      if (isStart || isGoal) radius = 11;

      // 選択中のリング
      if (isSelected && !isStart && !isGoal) {
        canvas.drawCircle(
          p, radius + 4,
          Paint()..color = Colors.black26,
        );
        canvas.drawCircle(
          p, radius + 3,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      canvas.drawCircle(p, radius, Paint()..color = nodeColor);

      // 始点・目的地に白縁
      if (isStart || isGoal) {
        canvas.drawCircle(
          p, radius,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // ラベル
      final tp = TextPainter(
        text: TextSpan(
          text: n.label,
          style: TextStyle(
            color: isOnPath ? _pathColor : Colors.black87,
            fontSize: 13,
            fontWeight: (isStart || isGoal || isOnPath)
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, _labelOffset(n.id, p, tp.size));
    }
  }

  Offset _labelOffset(String id, Offset p, Size s) {
    switch (id) {
      case 'sc':
      case 'ea':
      case 'ic':
        return Offset(p.dx - s.width - 12, p.dy - s.height / 2);
      case 'cross':
      case 'hall1':
      case 'hall2':
      case 'hall3':
      case 'hall4':
        return Offset(p.dx + 10, p.dy - s.height - 4);
      case 'ev':
        return Offset(p.dx - s.width / 2, p.dy + 10);
      default:
        return Offset(p.dx + 12, p.dy - s.height / 2);
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter old) =>
      old.selectedNodeId != selectedNodeId ||
      old.startNodeId    != startNodeId    ||
      old.goalNodeId     != goalNodeId     ||
      old.path           != path;
}
