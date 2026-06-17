# 設計図 (no10)

屋内ナビゲーションアプリ (A* Path Finder / Network Detail View) の設計図一式です。
すべて [PlantUML](https://plantuml.com/) 形式 (`.puml`) で記述しています。

## 図の一覧

| ファイル | 種類 | 内容 |
|---|---|---|
| [01_class_diagram.puml](01_class_diagram.puml) | クラス図 | UI層・位置登録画面・サービス層・外部依存の全クラスと関係 |
| [02_sequence_register.puml](02_sequence_register.puml) | シーケンス図 | 新しい写真の位置登録（画面遷移→撮影→座標推定→DB登録） |
| [03_sequence_identify.puml](03_sequence_identify.puml) | シーケンス図 | カメラ撮影による現在地識別（コサイン類似度） |
| [04_activity_astar.puml](04_activity_astar.puml) | アクティビティ図 | A* による経路探索の処理フロー |
| [05_er_database.puml](05_er_database.puml) | ER図 | SQLite `node_data.db` の `embeddings` テーブル定義 |
| [06_component.puml](06_component.puml) | コンポーネント図 | システム全体構成（層・外部パッケージ・Python） |

## 画像への変換方法

### 方法1: PlantUML CLI（要 Java + plantuml.jar）
```bash
cd no10/docs
# 全 .puml を PNG に変換
java -jar plantuml.jar *.puml
# SVG にする場合
java -jar plantuml.jar -tsvg *.puml
```

### 方法2: VS Code 拡張
`PlantUML`（jebbs）拡張をインストールし、`.puml` を開いて `Alt+D` でプレビュー。

### 方法3: オンライン
[PlantUML Web Server](https://www.plantuml.com/plantuml/uml/) に `.puml` の中身を貼り付け。

## アーキテクチャ概要

- **オンデバイス完結**: 画像の記述子抽出(82次元)・PCA(べき乗法で上位2主成分)・
  SQLite保存をすべて Dart で実装。Python は DB 閲覧専用（`view_db.py`）。
- **2つの推定系統**:
  - 位置登録画面（PCA散布図）: `LocationService` の 82次元記述子 + PCA射影
  - 現在地識別（カメラボタン）: 32×32グレースケール + コサイン類似度
- **本番 / テスト**: `no10`(=本番, 撮影分をDB保存) と `no09_test`(撮影分を保存しない) で
  `LocationService.register()` の挙動のみ異なる。
