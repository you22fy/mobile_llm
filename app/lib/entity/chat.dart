import 'package:objectbox/objectbox.dart';

@Entity()
class Chat {
  Chat({
    required this.id,
    required this.message,
    required this.role,
    this.prompt,
    this.rawMessage,
    required this.references,
    required this.createdAt,
  });
  @Id()
  int id;

  final String message;
  final String role; // 'user' または 'assistant'
  final String? prompt; // RAGプロンプト文字列（assistantのみ）
  final String? rawMessage; // LLMの生出力（assistantのみ）
  final List<String> references; // RAG検索で使ったcontexts
  final DateTime createdAt;
}
