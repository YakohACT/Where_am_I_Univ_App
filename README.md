# Where am I Univ App
## 概要
このアプリはとりあえず設計せずに作成したものを、途中からGitで管理してるついでに公開してるものです。
概要に書いている通り、近畿大学E館(KDIX)の位置情報推定を画像とWifiで探るものです。\
 ~E館(情報学部棟)の略称は"KDIX"で、情報学部の略称も"KDIX"らしい~ \
使ってもらう前提ではないので、あえて使い方は掲載しないです。(E館めちゃくちゃ小さいからまず迷うことないだろうし)

## 推定方法
推定方法はただただ自慢したいため、紹介します。\
推定方法は**画像**と**Wifi**の2つを併用します。

### 画像について
撮影したものをSQLに保管しており、迷った場所で撮影したものとSQLの写真をコサイン類似度を利用して、ここだと考えられるところを推定します。

### Wifiについて
Wifi ESSIフィンガープリントを利用します。WifiのSSIDや電波強度をSQLに保存し、迷った場所でWifiを参照し、SQLに登録されているものに近い場所を特定します。(大学がWifiを買い替えたりSSIDを変更しない前提)

## 使用言語,ツール
- Dart アプリの制御とUI
- Python DB閲覧と編集、機械学習
  - sqlite3
  - pandas
  - numpy
  - PIL
- Kotlin Androidホスト
- Swift iOSホスト
- Java プラグインの登録
- SQLite DB
- Flutter
- Git,GitHub,GitHub Actions

## ライセンス
言語、ランタイム、ビルド、CLI、開発ツール
|名称|ライセンス|
|---|---|
|Dart SDK,Flutter SDK|BSD-3-Clause|
|Kotlin, Swift|Aoache-2.0|
|Java Open SDK|GPL-2.0 WITH Classpath-exception|
|Python|PSF License|
|SQLite|public Domain|
|Gradle, Android Gradle Plugin|Apache-2.0|
|Android SDK, adb|Apache2.0, Android SDK License|
|Xcode, Apple SDK|プロプライエタリ|
|Git|GPL-2.0|
|flutter-actions|MIT License|

Dart,Flutter依存パッケージ
|名称|バージョン|ライセンス|
|---|---|---|
|camera|0.12.0+1|BSD-3-Clause|
|image_picker|1.2.2|BSD-3-Clause, Apache-2.0|
|image|4.9.1|MIT License|
|sqflite|2.4.3|BSD-2-Clause|
|path|1.9.1|BSD-3-Clause|
|path_proider|2.1.5|BSD-3-Clause|
|wifi_scan|0.4.1+2|MIT License|
|permission_handler|11.4.0|MIT License|
|cupertino_icons|1.0.9|MIT License|
|flutter_lints|6.0.0|BSD-3-Clause|

Pythonライブラリ
|名称|ライセンス|
|---|---|
|sqlite3|PSF License|
|pandas, Numpy|BSD-3-Clause|
|Pillow(PIL)|MIT-CMU|
