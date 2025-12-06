# iOS向けのLlama.cpp設定

[llama.cppのブリッジコード](./llama_bridge.md)の方に実装の詳細は記す。
本ドキュメントではiOSでのビルド時に困ったポイントを記す。　


## ヘッダファイルが読み込めない不具合
ブリッジコードでは `llama.h`のように`llama.cpp`に含まれるヘッダファイルを読み込む必要がある。
llama.cppのヘッダファイルは`*/include/`に含まれることが多く、Xcodeからこれが見える必要がある。

`Runner.xcworkspace`の中にある`Build Settings`タブから Header Search Pathsに `$(SRCROOT)/../../llama.cpp` を追加し、recursiveに設定する。
`llama.cpp/include/`の中にあるヘッダファイルだけでは不足していたので、`llama.cpp/**` に対して設定した。

理想的には必要最小限のヘッダファイルのみをflutterアプリケーション側に抽出して管理したい。

## llama.xcframeworkのビルド
llama.cppのiOS用のビルドが必要である。
`llama.cpp`側に用意されているシェルスクリプトで作成可能。

```bash
./build-ios.sh
```

これで `llama.xcframework` が作成される。

作成された`llama.xcframework`をRunnerにリンクさせる。
