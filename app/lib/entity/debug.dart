import 'package:objectbox/objectbox.dart';

@Entity()
class Debug {
  Debug({required this.id, required this.text, required this.embedding});
  @Id()
  int id;
  final String text;
  @HnswIndex(dimensions: 3, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  final List<double> embedding;
}
