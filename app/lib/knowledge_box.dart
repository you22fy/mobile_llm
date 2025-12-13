import 'dart:io';

import 'package:app/entity/knowledge.dart';
import 'package:app/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';

class KnowledgeBox {
  late final Store store;
  late final Box<Knowledge> knowledgeBox;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${dir.path}/knowledge_box');
    store = await openStore(directory: dbDir.path);
    knowledgeBox = Box<Knowledge>(store);
  }

  /// ベクトル検索を実行する
  /// [query] は検索クエリの埋め込みベクトル（768次元）
  /// [k] は取得する結果の数
  /// 戻り値はスコア付きの検索結果リスト
  Future<List<ObjectWithScore<Knowledge>>> searchByEmbedding({
    required List<double> query,
    required int k,
  }) async {
    if (query.length != 768) {
      throw ArgumentError(
        'Query embedding must be 768 dimensions, got ${query.length}',
      );
    }

    final q = knowledgeBox
        .query(Knowledge_.embedding.nearestNeighborsF32(query, k))
        .build();
    final results = q.findWithScores();
    q.close();

    return results;
  }

  /// Storeを閉じる
  void close() {
    store.close();
  }
}
