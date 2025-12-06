import 'dart:typed_data';

import 'package:objectbox/objectbox.dart';

@Entity()
class Knowledge {
  Knowledge({required this.id, required this.text, required this.embedding});

  @Id()
  int id;

  final String text;
  @HnswIndex(dimensions: 768)
  @Property(type: PropertyType.floatVector)
  final Float64List embedding;
}

class ObjectboxService {
  Future<void> init() async {}

  Future<void> insert() async {}

  Future<void> search() async {}
}
