import 'dart:io';

import 'package:app/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';

@Entity()
class Debug {
  Debug({required this.id, required this.text, required this.embedding});
  @Id()
  int id;
  final String text;
  @HnswIndex(dimensions: 3)
  @Property(type: PropertyType.floatVector)
  final List<double> embedding;
}

class DebugBox {
  late final Store store;
  late final Box<Debug> debugBox;

  Future<void> init() async {
    print('DebugBox.init');
    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${dir.path}/debug_box');

    // 開発用: スキーマ変更時に古い DB を自動削除してリセットする
    if (await dbDir.exists()) {
      await dbDir.delete(recursive: true);
    }

    store = await openStore(directory: dbDir.path);
    debugBox = Box<Debug>(store);
  }

  Future<void> insertSampleData() async {
    debugBox.putMany([
      Debug(id: 0, text: 'Hello, world!', embedding: [1.0, 1.0, 1.0]),
      Debug(id: 0, text: 'Hello, world2!', embedding: [-1.0, -1.0, -1.0]),
      Debug(id: 0, text: 'Hello, world3!', embedding: [0.0, 0.0, 0.0]),
    ]);
  }

  Future<List<ObjectWithScore<Debug>>> search({
    required Debug query,
    required int k,
  }) async {
    final q = debugBox
        .query(Debug_.embedding.nearestNeighborsF32(query.embedding, k))
        .build();
    final results = q.findWithScores();
    q.close();

    return results;
  }
}
