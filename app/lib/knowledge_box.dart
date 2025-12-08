import 'package:app/entity/knowledge.dart';
import 'package:app/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';

class KnowledgeBox {
  late final Store store;
  late final Box<Knowledge> knowledgeBox;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    store = await openStore(directory: '${dir.path}/objectbox');
    knowledgeBox = Box<Knowledge>(store);
  }

  Future<void> insert() async {}

  Future<void> search() async {}
}
