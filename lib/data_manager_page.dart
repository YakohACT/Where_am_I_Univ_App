import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'location_service.dart';

/// データ管理画面。
/// - スマホの画像ファイル（ギャラリー）からDBへアップロード
/// - 収集データの削除（既存ノードは保護）
class DataManagerPage extends StatefulWidget {
  const DataManagerPage({super.key});

  @override
  State<DataManagerPage> createState() => _DataManagerPageState();
}

class _DataManagerPageState extends State<DataManagerPage> {
  final ImagePicker _picker = ImagePicker();
  List<DbEntry> _entries = [];
  bool _loading = true;
  bool _busy = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final list = await LocationService.instance.listEntries();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  // ─── 画像ファイルからアップロード ───────────────────────
  Future<void> _uploadFromFiles() async {
    final List<XFile> files = await _picker.pickMultiImage();
    if (files.isEmpty) return;
    if (!mounted) return;

    // 登録名を選択（既存ノード名から選ぶ or 自由入力）
    final name = await _askName();
    if (name == null || name.isEmpty) return;

    setState(() {
      _busy = true;
      _progress = '0 / ${files.length}';
    });

    int ok = 0, fail = 0;
    for (int i = 0; i < files.length; i++) {
      try {
        final bytes = await File(files[i].path).readAsBytes();
        final res = await LocationService.instance
            .addFromImage(name: name, bytes: bytes);
        if (res != null) {
          ok++;
        } else {
          fail++;
        }
      } catch (_) {
        fail++;
      }
      if (!mounted) return;
      setState(() => _progress = '${i + 1} / ${files.length}');
    }

    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('アップロード完了: 成功 $ok 件 / 失敗 $fail 件（名前: $name）'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 登録名を選ぶダイアログ（既存ノード名のドロップダウン＋自由入力）
  Future<String?> _askName() async {
    final names = LocationService.baseNodes.map((b) => b.name).toList();
    String? selected = names.first;
    final custom = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('登録する場所の名前'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('既存ノードから選択:'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selected,
                    items: names
                        .map((n) =>
                            DropdownMenuItem(value: n, child: Text(n)))
                        .toList(),
                    onChanged: (v) => setLocal(() => selected = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('または自由入力（入力時はこちらを優先）:'),
                  TextField(
                    controller: custom,
                    decoration: const InputDecoration(
                      hintText: '例: 3階廊下',
                      isDense: true,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = custom.text.trim().isNotEmpty
                        ? custom.text.trim()
                        : selected;
                    Navigator.pop(ctx, name);
                  },
                  child: const Text('決定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── 削除 ──────────────────────────────────────────────
  Future<void> _deleteOne(DbEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text('「${e.name}」(ID: ${e.id}) を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocationService.instance.deleteEntry(e.id);
    await _reload();
  }

  Future<void> _deleteAllCollected() async {
    final collected = _entries.where((e) => !e.isBase).length;
    if (collected == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除できる収集データがありません')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一括削除の確認'),
        content: Text('収集データ $collected 件をすべて削除しますか？\n（既存ノードは残ります）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('全削除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await LocationService.instance.deleteAllCollected();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('収集データ $n 件を削除しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseCount = _entries.where((e) => e.isBase).length;
    final collectedCount = _entries.where((e) => !e.isBase).length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('データ管理',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: '収集データを全削除',
            onPressed: _busy ? null : _deleteAllCollected,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // アップロードボタン
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _uploadFromFiles,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file),
                label: Text(_busy
                    ? 'アップロード中 $_progress'
                    : '画像ファイルからアップロード'),
              ),
            ),
          ),
          // 件数サマリ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _chip('既存ノード $baseCount', const Color(0xFF4A90E2)),
                const SizedBox(width: 8),
                _chip('収集データ $collectedCount', const Color(0xFF4CAF50)),
              ],
            ),
          ),
          const Divider(height: 1),
          // 一覧
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) => _tile(_entries[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _tile(DbEntry e) {
    final wifi = e.wifiCount > 0 ? 'WiFi ${e.wifiCount}件' : '画像のみ';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: e.isBase
            ? const Color(0xFF4A90E2)
            : const Color(0xFF4CAF50),
        child: Icon(
          e.isBase ? Icons.place : Icons.photo_camera_back,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(e.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'ID: ${e.id} ｜ pca(${e.pcaX.toStringAsFixed(1)}, ${e.pcaY.toStringAsFixed(1)}) ｜ $wifi'
        '${e.isBase ? ' ｜ 既存' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: e.isBase
          ? const Tooltip(
              message: '既存ノードは削除できません',
              child: Icon(Icons.lock_outline, color: Colors.black26),
            )
          : IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFE53935)),
              onPressed: () => _deleteOne(e),
            ),
    );
  }
}
