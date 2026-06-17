import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 散布図表示・DB保存用のノード1件
class NodePoint {
  final int id;
  final String name;
  final double pcaX;
  final double pcaY;
  final bool isBase; // 既存ノードか（true）/ 撮影追加分か（false）
  const NodePoint({
    required this.id,
    required this.name,
    required this.pcaX,
    required this.pcaY,
    required this.isBase,
  });
}

/// 既存ノードの定義（no07 の CSV ID 体系に合わせる）
class BaseNode {
  final int id;
  final String name;
  final String image; // lib/images/ 配下
  const BaseNode(this.id, this.name, this.image);
}

/// 画像埋め込み・PCA・SQLite をすべてオンデバイス(Dart)で完結させるサービス。
///
/// 既存ノードと撮影追加ノードを同一の記述子で埋め込み、同じPCA基底へ射影することで
/// 特徴空間の整合性を保証する。Python(view_db.py)はDB閲覧専用。
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // ── 既存ノード（DBの id 0〜17）──
  static const List<BaseNode> baseNodes = [
    BaseNode(0,  '入口',     'entrance.png'),
    BaseNode(1,  'EV',       'ev.png'),
    BaseNode(2,  '交差点',   'cr.png'),
    BaseNode(3,  '階段',     'stair.png'),
    BaseNode(4,  'ic',       'ic.png'),
    BaseNode(5,  '出口',     'exit.png'),
    BaseNode(6,  'ea',       'ea.png'),
    BaseNode(7,  'ロビー1',  'lobby1.png'),
    BaseNode(8,  'ロビー2',  'lobby2.png'),
    BaseNode(9,  '廊下1',    'corridor1.png'),
    BaseNode(10, '廊下2',    'corridor2.png'),
    BaseNode(11, '廊下3',    'corridor3.png'),
    BaseNode(12, '廊下4',    'corridor4.png'),
    BaseNode(13, '大講義室', 'lc.png'),
    BaseNode(14, '中講義室', 'mc.png'),
    BaseNode(15, 'sc',       'sc.png'),
    BaseNode(16, 'os',       'os.png'),
    BaseNode(17, 'WC',       'wc.png'),
  ];

  // 記述子パラメータ
  static const int _imgSize = 48;   // リサイズ後の一辺
  static const int _histBins = 6;   // チャンネルごとのヒストグラムbin数
  static const int _blocks = 4;     // 一辺のブロック分割数（4x4）

  bool _initialized = false;
  Future<void>? _initFuture;
  Database? _db;

  // PCA基底
  late List<double> _mean;   // 各次元の平均
  late List<double> _std;    // 各次元の標準偏差
  late List<double> _pc1;    // 第1主成分
  late List<double> _pc2;    // 第2主成分

  // 既存ノードの散布図座標（メモリ保持）
  final List<NodePoint> _basePoints = [];

  /// アプリ名等から画像ファイル名で既存ノードを引く
  static BaseNode? baseNodeByImage(String image) {
    for (final b in baseNodes) {
      if (b.image == image) return b;
    }
    return null;
  }

  // ─── 初期化（埋め込み計算・PCA構築・DB準備）──────────────
  /// 多重呼び出しに安全（同じFutureを返す）
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    if (_initialized) return;

    // 1) 既存ノードの埋め込みを抽出
    final vectors = <List<double>>[];
    for (final b in baseNodes) {
      final data = await rootBundle.load('lib/images/${b.image}');
      final feat = _featureFromBytes(data.buffer.asUint8List());
      vectors.add(feat ?? List<double>.filled(_descriptorDim, 0));
    }

    // 2) PCA基底を構築（標準化 → べき乗法で上位2主成分）
    _buildPca(vectors);

    // 3) 既存ノードの散布図座標を計算
    _basePoints.clear();
    for (int i = 0; i < baseNodes.length; i++) {
      final proj = _project(vectors[i]);
      _basePoints.add(NodePoint(
        id: baseNodes[i].id,
        name: baseNodes[i].name,
        pcaX: proj[0],
        pcaY: proj[1],
        isBase: true,
      ));
    }

    // 4) SQLite を準備し、既存ノードを（未登録なら）保存
    await _openDb(vectors);

    _initialized = true;
  }

  int get _descriptorDim =>
      _histBins * 3 + _blocks * _blocks * 3 + _blocks * _blocks;

  // ─── 記述子抽出 ────────────────────────────────────────
  /// カラーヒストグラム(18) + ブロック平均RGB(48) + ブロック輝度標準偏差(16)
  List<double>? _featureFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final im = img.copyResize(decoded, width: _imgSize, height: _imgSize);

    final hist = List<double>.filled(_histBins * 3, 0);
    final blockSum = List<double>.filled(_blocks * _blocks * 3, 0);
    final blockGray = List<List<double>>.generate(
        _blocks * _blocks, (_) => <double>[]);

    final blockPx = _imgSize ~/ _blocks;
    final binW = 256 / _histBins;

    for (int y = 0; y < _imgSize; y++) {
      for (int x = 0; x < _imgSize; x++) {
        final px = im.getPixel(x, y);
        final r = px.r.toDouble();
        final g = px.g.toDouble();
        final b = px.b.toDouble();

        // ヒストグラム
        hist[(r ~/ binW).clamp(0, _histBins - 1)] += 1;
        hist[_histBins + (g ~/ binW).clamp(0, _histBins - 1)] += 1;
        hist[_histBins * 2 + (b ~/ binW).clamp(0, _histBins - 1)] += 1;

        // ブロック
        final bx = (x ~/ blockPx).clamp(0, _blocks - 1);
        final by = (y ~/ blockPx).clamp(0, _blocks - 1);
        final bi = by * _blocks + bx;
        blockSum[bi * 3]     += r;
        blockSum[bi * 3 + 1] += g;
        blockSum[bi * 3 + 2] += b;
        blockGray[bi].add(0.299 * r + 0.587 * g + 0.114 * b);
      }
    }

    final feat = <double>[];

    // ヒストグラム（総画素数で正規化）
    final total = (_imgSize * _imgSize).toDouble();
    for (final h in hist) {
      feat.add(h / total);
    }

    // ブロック平均RGB
    final perBlock = (blockPx * blockPx).toDouble();
    for (int i = 0; i < _blocks * _blocks; i++) {
      feat.add(blockSum[i * 3]     / perBlock);
      feat.add(blockSum[i * 3 + 1] / perBlock);
      feat.add(blockSum[i * 3 + 2] / perBlock);
    }

    // ブロック輝度の標準偏差（テクスチャ）
    for (int i = 0; i < _blocks * _blocks; i++) {
      final vals = blockGray[i];
      final m = vals.reduce((a, b) => a + b) / vals.length;
      double s = 0;
      for (final v in vals) {
        s += (v - m) * (v - m);
      }
      feat.add(math.sqrt(s / vals.length));
    }

    return feat;
  }

  // ─── PCA構築（標準化 + べき乗法）───────────────────────
  void _buildPca(List<List<double>> vectors) {
    final n = vectors.length;
    final d = vectors[0].length;

    // 平均・標準偏差
    _mean = List<double>.filled(d, 0);
    _std = List<double>.filled(d, 0);
    for (final v in vectors) {
      for (int j = 0; j < d; j++) {
        _mean[j] += v[j];
      }
    }
    for (int j = 0; j < d; j++) {
      _mean[j] /= n;
    }
    for (final v in vectors) {
      for (int j = 0; j < d; j++) {
        final diff = v[j] - _mean[j];
        _std[j] += diff * diff;
      }
    }
    for (int j = 0; j < d; j++) {
      _std[j] = math.sqrt(_std[j] / n);
      if (_std[j] < 1e-8) _std[j] = 1.0; // 定数次元の保護
    }

    // 標準化
    final z = List.generate(
      n,
      (i) => List<double>.generate(d, (j) => (vectors[i][j] - _mean[j]) / _std[j]),
    );

    // 共分散行列 C = Z^T Z / (n-1)
    final c = List.generate(d, (_) => List<double>.filled(d, 0));
    for (int i = 0; i < n; i++) {
      for (int a = 0; a < d; a++) {
        final za = z[i][a];
        if (za == 0) continue;
        for (int b = 0; b < d; b++) {
          c[a][b] += za * z[i][b];
        }
      }
    }
    final denom = (n - 1).toDouble();
    for (int a = 0; a < d; a++) {
      for (int b = 0; b < d; b++) {
        c[a][b] /= denom;
      }
    }

    // 第1主成分（べき乗法）
    _pc1 = _powerIteration(c, d);
    // 第1主成分を除去（デフレーション）して第2主成分
    final lambda1 = _rayleigh(c, _pc1);
    for (int a = 0; a < d; a++) {
      for (int b = 0; b < d; b++) {
        c[a][b] -= lambda1 * _pc1[a] * _pc1[b];
      }
    }
    _pc2 = _powerIteration(c, d);
  }

  List<double> _powerIteration(List<List<double>> c, int d) {
    final rng = math.Random(42); // 決定的
    var v = List<double>.generate(d, (_) => rng.nextDouble() - 0.5);
    _normalize(v);
    for (int iter = 0; iter < 200; iter++) {
      final nv = List<double>.filled(d, 0);
      for (int a = 0; a < d; a++) {
        double s = 0;
        final row = c[a];
        for (int b = 0; b < d; b++) {
          s += row[b] * v[b];
        }
        nv[a] = s;
      }
      _normalize(nv);
      v = nv;
    }
    return v;
  }

  double _rayleigh(List<List<double>> c, List<double> v) {
    final d = v.length;
    double num = 0;
    for (int a = 0; a < d; a++) {
      double s = 0;
      for (int b = 0; b < d; b++) {
        s += c[a][b] * v[b];
      }
      num += v[a] * s;
    }
    return num; // v は単位ベクトルなので分母=1
  }

  void _normalize(List<double> v) {
    double n = 0;
    for (final x in v) {
      n += x * x;
    }
    n = math.sqrt(n);
    if (n < 1e-12) return;
    for (int i = 0; i < v.length; i++) {
      v[i] /= n;
    }
  }

  /// 生ベクトルを標準化してPCA基底へ射影 → [pcaX, pcaY]
  List<double> _project(List<double> vector) {
    final d = vector.length;
    double x = 0, y = 0;
    for (int j = 0; j < d; j++) {
      final zj = (vector[j] - _mean[j]) / _std[j];
      x += zj * _pc1[j];
      y += zj * _pc2[j];
    }
    return [x, y];
  }

  /// 記述子を z-score 標準化（次元ごとの尺度差を吸収して比較を安定化）
  List<double> _standardizeVec(List<double> v) {
    final d = v.length;
    final out = List<double>.filled(d, 0);
    for (int j = 0; j < d; j++) {
      out[j] = (v[j] - _mean[j]) / _std[j];
    }
    return out;
  }

  /// コサイン類似度
  double _cosine(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// DB行のノード画像ファイル名を解決（グラフ上の選択に使用）
  String? _imageForRow(int id, String name) {
    if (id < 100) {
      for (final b in baseNodes) {
        if (b.id == id) return b.image;
      }
    }
    // 撮影追加分は name から既存ノードへ対応付け
    for (final b in baseNodes) {
      if (b.name == name) return b.image;
    }
    return null;
  }

  // ─── SQLite ────────────────────────────────────────────
  Future<void> _openDb(List<List<double>> baseVectors) async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'node_data.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE embeddings(
            id INTEGER PRIMARY KEY,
            name TEXT,
            vector TEXT,
            pca_x REAL,
            pca_y REAL,
            wifi TEXT
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        // v1 → v2: WiFiフィンガープリント列を追加（既存データは保持）
        if (oldV < 2) {
          await db.execute('ALTER TABLE embeddings ADD COLUMN wifi TEXT');
        }
      },
    );

    // 既存ノードが未登録なら挿入
    final count = Sqflite.firstIntValue(
        await _db!.rawQuery('SELECT COUNT(*) FROM embeddings WHERE id < 100')) ?? 0;
    if (count == 0) {
      final batch = _db!.batch();
      for (int i = 0; i < baseNodes.length; i++) {
        final proj = _basePoints[i];
        batch.insert(
          'embeddings',
          {
            'id': baseNodes[i].id,
            'name': baseNodes[i].name,
            'vector': baseVectors[i].map((e) => e.toStringAsFixed(6)).join(','),
            'pca_x': proj.pcaX,
            'pca_y': proj.pcaY,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  // ─── 公開API ───────────────────────────────────────────

  /// 既存ノードの散布図座標（メモリキャッシュ）
  List<NodePoint> get basePoints => List.unmodifiable(_basePoints);

  /// 撮影画像から埋め込みを抽出し、推定座標を返す（DB保存はしない）。
  /// 返り値: `EstimationResult`（vector, pcaX, pcaY）
  EstimationResult? estimate(Uint8List photoBytes) {
    final feat = _featureFromBytes(photoBytes);
    if (feat == null) return null;
    final proj = _project(feat);
    return EstimationResult(vector: feat, pcaX: proj[0], pcaY: proj[1]);
  }

  /// 推定結果をDBへ登録（ランダムIDを採番）。登録した NodePoint を返す。
  ///
  /// [wifi] にその場所のWiFi指紋(bssid→rssi)を渡すと画像と一緒に保存され、
  /// 識別時に画像＋WiFiの併用（option B）で使われる。空/未指定なら画像のみ。
  Future<NodePoint> register({
    required String name,
    required EstimationResult est,
    Map<String, int>? wifi,
  }) async {
    // 適当に割り振るID（既存 id<100 と衝突しない大きな正の整数）
    final id = 100 +
        (DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF);
    await _db!.insert(
      'embeddings',
      {
        'id': id,
        'name': name,
        'vector': est.vector.map((e) => e.toStringAsFixed(6)).join(','),
        'pca_x': est.pcaX,
        'pca_y': est.pcaY,
        'wifi': (wifi == null || wifi.isEmpty) ? null : jsonEncode(wifi),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return NodePoint(
      id: id,
      name: name,
      pcaX: est.pcaX,
      pcaY: est.pcaY,
      isBase: false,
    );
  }

  /// 画像 ＋ WiFi指紋 を併用してDB全件と照合し、最類似1件を返す（option B）。
  ///
  /// - 画像: z-score標準化後のコサイン類似度 → [0,1] に変換
  /// - WiFi: [wifi]（現在のスキャン結果 bssid→rssi）と各行の保存指紋を
  ///   コサイン類似度で比較 → [0,1]
  /// - 統合スコア: 両方ある行は加重平均(既定 0.5/0.5)、WiFiが無い行は画像のみ。
  ///
  /// 既存ノード(id 0〜17)も撮影追加分(id≧100)も対象。WiFiが空（iOS/権限拒否等）
  /// なら自動的に画像のみの推定に縮退する。
  Future<IdentifyResult?> identifyFromDb(
    Uint8List photoBytes, {
    Map<String, int>? wifi,
    double imageWeight = 0.5,
    double wifiWeight = 0.5,
  }) async {
    await init();
    final feat = _featureFromBytes(photoBytes);
    if (feat == null || _db == null) return null;
    final q = _standardizeVec(feat);
    final hasQueryWifi = wifi != null && wifi.isNotEmpty;

    final rows = await _db!.query(
      'embeddings',
      columns: ['id', 'name', 'vector', 'wifi'],
    );
    IdentifyResult? best;
    double bestScore = -2.0;
    for (final r in rows) {
      final vstr = r['vector'] as String?;
      if (vstr == null) continue;
      final vec =
          vstr.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
      if (vec.length != feat.length) continue;

      // 画像類似度 [0,1]
      final imgCos = _cosine(q, _standardizeVec(vec));
      final imgSim = (imgCos.clamp(-1.0, 1.0) + 1) / 2;

      // WiFi類似度 [0,1]（双方に指紋がある場合のみ）
      final rowWifi = _decodeWifi(r['wifi'] as String?);
      final bool usedWifi = hasQueryWifi && rowWifi.isNotEmpty;
      final double wifiSim = usedWifi ? _wifiSimilarity(wifi, rowWifi) : 0.0;

      // 統合スコア
      final double score = usedWifi
          ? (imageWeight * imgSim + wifiWeight * wifiSim) /
              (imageWeight + wifiWeight)
          : imgSim;

      if (score > bestScore) {
        bestScore = score;
        final id = r['id'] as int;
        final name = (r['name'] as String?) ?? '';
        best = IdentifyResult(
          id: id,
          name: name,
          image: _imageForRow(id, name),
          similarity: score,
          imageSim: imgSim,
          wifiSim: usedWifi ? wifiSim : null,
          usedWifi: usedWifi,
          isBase: id < 100,
        );
      }
    }
    return best;
  }

  Map<String, int> _decodeWifi(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// 2つのWiFi指紋のコサイン類似度 [0,1]。
  /// RSSI(dBm)を [0,1] の信号強度に変換（-100dBm→0, -30dBm→1）し、
  /// 両指紋のBSSID和集合上でコサインを取る（共通の強いAPほど高評価）。
  double _wifiSimilarity(Map<String, int> a, Map<String, int> b) {
    final keys = <String>{...a.keys, ...b.keys};
    double dot = 0, na = 0, nb = 0;
    for (final k in keys) {
      final sa = _rssiToSignal(a[k]);
      final sb = _rssiToSignal(b[k]);
      dot += sa * sb;
      na += sa * sa;
      nb += sb * sb;
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  double _rssiToSignal(int? rssi) {
    if (rssi == null) return 0.0; // そのAPは観測されていない
    const floor = -100.0, ceil = -30.0;
    return ((rssi - floor) / (ceil - floor)).clamp(0.0, 1.0);
  }

  /// DBファイルのパス（view_db.py で参照するため）
  Future<String> dbPath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, 'node_data.db');
  }
}

class EstimationResult {
  final List<double> vector;
  final double pcaX;
  final double pcaY;
  const EstimationResult({
    required this.vector,
    required this.pcaX,
    required this.pcaY,
  });
}

/// DB照合による現在地推定の結果1件
class IdentifyResult {
  final int id;          // DBのID（既存 0〜17 / 撮影追加分 ≧100）
  final String name;     // ノード名
  final String? image;   // 対応するノード画像（グラフ選択用、解決できなければnull）
  final double similarity; // 統合スコア [0,1]
  final double imageSim; // 画像のみの類似度 [0,1]
  final double? wifiSim; // WiFiのみの類似度 [0,1]（未使用なら null）
  final bool usedWifi;   // この結果でWiFiを併用したか
  final bool isBase;     // 既存ノードか（true）/ 撮影追加分か（false）
  const IdentifyResult({
    required this.id,
    required this.name,
    required this.image,
    required this.similarity,
    required this.imageSim,
    required this.wifiSim,
    required this.usedWifi,
    required this.isBase,
  });
}
