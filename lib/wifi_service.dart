import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// WiFiフィンガープリント取得サービス（Android専用）。
///
/// 周辺アクセスポイントの BSSID → RSSI(dBm) を読み取り、その場所の
/// 「WiFi指紋」を返す。位置推定に画像と併用する（option B）。
///
/// iOS や未対応端末、権限拒否、スキャン制限時は **空マップ** を返すため、
/// 呼び出し側はそのまま画像のみの推定にフォールバックできる。
class WifiService {
  WifiService._();
  static final WifiService instance = WifiService._();

  /// 周辺APをスキャンして {bssid: rssi(dBm)} を返す。失敗時は {}。
  Future<Map<String, int>> scan() async {
    if (!Platform.isAndroid) return {}; // iOS等はWiFiスキャン不可

    try {
      // 位置情報権限（WiFiスキャンに必須）と Android 13+ の近接WiFi権限を要求
      await [
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ].request();

      // スキャン可否を確認（必要なら権限ダイアログを出す）
      final can = await WiFiScan.instance.canStartScan();
      if (can == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        // スキャン完了を少し待つ
        await Future.delayed(const Duration(seconds: 2));
      }

      final canGet = await WiFiScan.instance.canGetScannedResults();
      if (canGet != CanGetScannedResults.yes) return {};

      final results = await WiFiScan.instance.getScannedResults();
      final map = <String, int>{};
      for (final ap in results) {
        if (ap.bssid.isEmpty) continue;
        // 同一BSSIDは強い方を採用
        final prev = map[ap.bssid];
        if (prev == null || ap.level > prev) {
          map[ap.bssid] = ap.level;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
