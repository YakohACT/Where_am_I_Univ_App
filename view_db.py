#!/usr/bin/env python3
"""
node_data.db (SQLite) の中身を確認するツール。

使い方:
    python view_db.py [DBファイルパス]

DBファイルパスを省略すると node_data.db を参照します。
実機から取得した node_data.db を引数に渡して中身を確認できます。

スキーマ:  embeddings(id, name, vector, pca_x, pca_y)
    - id     : ノードID（既存ノードは 0〜17、撮影追加分は大きな整数）
    - name   : ノード名
    - vector : 画像埋め込み（カンマ区切りの数値列）
    - pca_x  : PCA第1主成分への射影
    - pca_y  : PCA第2主成分への射影
"""

import sys
import sqlite3

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "node_data.db"


def main():
    try:
        conn = sqlite3.connect(DB_PATH)
    except Exception as e:  # noqa
        print(f"DBを開けませんでした: {e}")
        sys.exit(1)

    cur = conn.cursor()

    # --- テーブル一覧 ---
    print("--- 存在するテーブル一覧 ---")
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [r[0] for r in cur.fetchall()]
    print("        name")
    for i, t in enumerate(tables):
        print(f"{i}  {t}")
    print()
    print("=" * 50)
    print()

    # pandas があれば DataFrame 表示、なければ簡易表示
    try:
        import pandas as pd
        use_pandas = True
    except ImportError:
        use_pandas = False

    for t in tables:
        print(f"--- テーブル名: {t} のデータ ---")
        if use_pandas:
            import pandas as pd
            df = pd.read_sql_query(f"SELECT * FROM {t}", conn)
            # vector 列は長いので先頭だけ表示
            if "vector" in df.columns:
                df_disp = df.copy()
                df_disp["vector"] = df_disp["vector"].apply(_short_vector)
                with pd.option_context(
                    "display.max_rows", None,
                    "display.width", None,
                    "display.max_colwidth", 60,
                ):
                    print(df_disp.to_string())
            else:
                print(df.to_string())

            # CSV 出力
            csv_name = f"{t}_exported.csv"
            df.to_csv(csv_name, index=False)
            print("-" * 50)
            print(f"→ {csv_name} に CSV出力しました。")
        else:
            cur.execute(f"PRAGMA table_info({t})")
            cols = [c[1] for c in cur.fetchall()]
            print("\t".join(cols))
            cur.execute(f"SELECT * FROM {t}")
            for row in cur.fetchall():
                cells = []
                for col, val in zip(cols, row):
                    if col == "vector" and isinstance(val, str):
                        cells.append(_short_vector(val))
                    else:
                        cells.append(str(val))
                print("\t".join(cells))
        print()
        print("=" * 50)
        print()

    conn.close()


def _short_vector(v, n=40):
    """vector文字列の先頭だけを表示用に切り詰める"""
    if not isinstance(v, str):
        return v
    return v[:n] + "..." if len(v) > n else v


if __name__ == "__main__":
    main()
