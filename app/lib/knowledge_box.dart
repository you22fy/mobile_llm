import 'package:app/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';

@Entity()
class Knowledge {
  Knowledge({required this.id, required this.text, required this.embedding});

  @Id()
  int id;

  final String text;
  @HnswIndex(dimensions: 768)
  @Property(type: PropertyType.floatVector)
  final List<double> embedding;
}

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
