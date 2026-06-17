import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'location_service.dart';
import 'wifi_service.dart';

/// 「新しい写真の位置登録」画面。
/// 上部: カメラライブプレビュー（撮影後は静止画）
/// 下部: 対象ノードと他ノードの位置関係（PCA散布図）
class PhotoRegisterPage extends StatefulWidget {
  final int targetNodeId;
  final String targetNodeName;

  const PhotoRegisterPage({
    super.key,
    required this.targetNodeId,
    required this.targetNodeName,
  });

  @override
  State<PhotoRegisterPage> createState() => _PhotoRegisterPageState();
}

class _PhotoRegisterPageState extends State<PhotoRegisterPage> {
  CameraController? _camera;
  bool _cameraReady = false;
  String? _cameraError;

  File? _captured;            // 撮影した静止画
  EstimationResult? _est;     // 推定結果
  NodePoint? _estPoint;       // 散布図に出す推定点
  Map<String, int> _wifi = {}; // 撮影地点のWiFi指紋(bssid→rssi)
  bool _processing = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'カメラが見つかりません');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = 'カメラ初期化に失敗: $e');
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  // 写真を撮影して位置を計算
  Future<void> _captureAndEstimate() async {
    if (_camera == null || !_cameraReady || _processing) return;
    setState(() => _processing = true);
    try {
      final shot = await _camera!.takePicture();
      final bytes = await File(shot.path).readAsBytes();
      final est = LocationService.instance.estimate(bytes);
      if (est == null) {
        setState(() => _processing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('画像を解析できませんでした')),
          );
        }
        return;
      }
      // 撮影地点のWiFi指紋も取得（画像と併用して登録）
      final wifi = await WifiService.instance.scan();
      if (!mounted) return;
      setState(() {
        _captured = File(shot.path);
        _est = est;
        _wifi = wifi;
        _estPoint = NodePoint(
          id: -1,
          name: widget.targetNodeName,
          pcaX: est.pcaX,
          pcaY: est.pcaY,
          isBase: false,
        );
        _processing = false;
      });
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('撮影に失敗しました: $e')),
        );
      }
    }
  }

  // 撮り直す
  void _retake() {
    setState(() {
      _captured = null;
      _est = null;
      _estPoint = null;
      _wifi = {};
      _saved = false;
    });
  }

  // この場所をDBに登録
  Future<void> _saveToDb() async {
    if (_est == null || _saved) return;
    setState(() => _processing = true);
    final point = await LocationService.instance.register(
      name: widget.targetNodeName,
      est: _est!,
      wifi: _wifi,
    );
    if (!mounted) return;
    setState(() {
      _processing = false;
      _saved = true;
      _estPoint = point;
    });
    final wifiMsg = _wifi.isEmpty ? '画像のみ' : 'WiFi ${_wifi.length}件併用';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'DBに登録しました（ID: ${point.id} / ${point.name} / $wifiMsg）'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasShot = _captured != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          '新しい写真の位置登録',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── 上部: カメラ / 撮影画像 ──
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              child: _buildCameraArea(hasShot),
            ),
          ),

          // ── 下部: 位置関係の散布図 ──
          Expanded(
            flex: 6,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                children: [
                  // 対象ノード見出し
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F2FB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.place,
                            color: Color(0xFF4A90E2), size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '対象ノード: ${widget.targetNodeName} (ID: ${widget.targetNodeId})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A4E80),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // WiFi取得状況（撮影後のみ）
                  if (hasShot) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _wifi.isEmpty ? Icons.wifi_off : Icons.wifi,
                          size: 16,
                          color: _wifi.isEmpty
                              ? Colors.grey
                              : const Color(0xFF4CAF50),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _wifi.isEmpty
                              ? 'WiFi指紋なし（画像のみで登録）'
                              : 'WiFi指紋 ${_wifi.length}件を併用',
                          style: TextStyle(
                            fontSize: 13,
                            color: _wifi.isEmpty
                                ? Colors.grey
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),

                  // 散布図
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: ScatterPainter(
                          points: LocationService.instance.basePoints,
                          targetId: widget.targetNodeId,
                          estimated: _estPoint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── ボタン群 ──
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: hasShot ? _buildAfterButtons() : _buildCaptureButton(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea(bool hasShot) {
    if (hasShot) {
      return Image.file(_captured!, fit: BoxFit.contain);
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }
    if (!_cameraReady || _camera == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(child: CameraPreview(_camera!));
  }

  Widget _buildCaptureButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _processing ? null : _captureAndEstimate,
        icon: _processing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text(
          '写真を撮影して位置を計算',
          style: TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5C6BC0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildAfterButtons() {
    return Row(
      children: [
        // 撮り直す
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _processing ? null : _retake,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text(
                '撮り直す',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // この場所をDBに登録
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: (_processing || _saved) ? null : _saveToDb,
              icon: Icon(
                _saved ? Icons.check_circle : Icons.cloud_upload,
                color: Colors.white,
              ),
              label: Text(
                _saved ? '登録済み' : 'この場所をDBに登録',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF66BB6A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 散布図 Painter ─────────────────────────────────────────

class ScatterPainter extends CustomPainter {
  final List<NodePoint> points;
  final int targetId;
  final NodePoint? estimated;

  ScatterPainter({
    required this.points,
    required this.targetId,
    this.estimated,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // 全点（既存 + 推定点）から座標範囲を求める
    final all = <NodePoint>[...points];
    if (estimated != null) all.add(estimated!);

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final p in all) {
      minX = math.min(minX, p.pcaX);
      maxX = math.max(maxX, p.pcaX);
      minY = math.min(minY, p.pcaY);
      maxY = math.max(maxY, p.pcaY);
    }
    double rangeX = maxX - minX;
    double rangeY = maxY - minY;
    if (rangeX == 0) rangeX = 1;
    if (rangeY == 0) rangeY = 1;

    const padX = 28.0;
    const padY = 22.0;
    final drawW = size.width - 2 * padX;
    final drawH = size.height - 2 * padY;

    Offset toScreen(NodePoint p) {
      final sx = padX + (p.pcaX - minX) / rangeX * drawW;
      // y は上下反転（PCAのy増加を上方向に）
      final sy = padY + (1 - (p.pcaY - minY) / rangeY) * drawH;
      return Offset(sx, sy);
    }

    // 中央十字の補助線
    final gridPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width / 2, padY),
        Offset(size.width / 2, size.height - padY), gridPaint);
    canvas.drawLine(Offset(padX, size.height / 2),
        Offset(size.width - padX, size.height / 2), gridPaint);

    // 既存ノードを描画
    for (final p in points) {
      final pos = toScreen(p);
      final isTarget = p.id == targetId;
      final color = isTarget
          ? const Color(0xFFE53935)
          : _colorForId(p.id);
      final radius = isTarget ? 8.0 : 4.0;

      canvas.drawCircle(pos, radius, Paint()..color = color);

      // ラベル
      _drawLabel(canvas, p.name, pos, isTarget);
    }

    // 推定点（赤の大きな点）
    if (estimated != null) {
      final pos = toScreen(estimated!);
      // 外周リング
      canvas.drawCircle(
        pos, 13,
        Paint()..color = const Color(0x33E53935),
      );
      canvas.drawCircle(pos, 9, Paint()..color = const Color(0xFFE53935));
      canvas.drawCircle(
        pos, 9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, bool emphasize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: emphasize ? const Color(0xFFC62828) : Colors.black87,
          fontSize: emphasize ? 12 : 10,
          fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx + 6, pos.dy - tp.height / 2));
  }

  Color _colorForId(int id) {
    const palette = [
      Color(0xFF7E57C2), // purple
      Color(0xFF42A5F5), // blue
      Color(0xFF66BB6A), // green
      Color(0xFFEF5350), // red-ish
      Color(0xFFFFA726), // orange
      Color(0xFF26A69A), // teal
      Color(0xFFEC407A), // pink
      Color(0xFF8D6E63), // brown
    ];
    return palette[id % palette.length];
  }

  @override
  bool shouldRepaint(covariant ScatterPainter old) =>
      old.points != points ||
      old.targetId != targetId ||
      old.estimated != estimated;
}
