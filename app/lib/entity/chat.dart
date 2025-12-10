import 'package:app/objectbox.g.dart';

@Entity()
class Chat {
  Chat({
    required this.id,
    required this.message,
    required this.prompt,
    required this.references,
    required this.createdAt,
  });
  @Id()
  int id;

  final String message;
  final String? prompt;
  final List<String> references;
  final DateTime createdAt;
}
