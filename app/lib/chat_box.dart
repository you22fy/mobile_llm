import 'dart:io';

import 'package:app/entity/chat.dart';
import 'package:app/objectbox.g.dart';
import 'package:path_provider/path_provider.dart';

class ChatBox {
  late final Store store;
  late final Box<Chat> chatBox;

  Future<void> init() async {
    print('ChatBox.init');
    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${dir.path}/chat_box');

    store = await openStore(directory: dbDir.path);
    chatBox = Box<Chat>(store);
  }

  /// すべてのメッセージを削除する（デバッグ用）
  Future<void> reset() async {
    chatBox.removeAll();
  }

  /// メッセージを保存する
  /// [role] は 'user' または 'assistant' を指定
  /// [content] はメッセージ内容
  /// [prompt] はRAGプロンプト文字列（assistantの場合のみ）
  /// [rawContent] はLLMの生出力（assistantの場合のみ）
  /// [references] はRAG検索で使ったcontexts（assistantの場合のみ）
  Future<Chat> insertMessage({
    required String role,
    required String content,
    String? prompt,
    String? rawContent,
    List<String>? references,
    DateTime? createdAt,
  }) async {
    final chat = Chat(
      id: 0,
      message: content,
      role: role,
      prompt: prompt,
      rawMessage: rawContent,
      references: references ?? [],
      createdAt: createdAt ?? DateTime.now(),
    );
    chatBox.put(chat);
    return chat;
  }

  /// すべてのメッセージを取得する（作成日時の昇順）
  Future<List<Chat>> getAllMessages() async {
    final allChats = chatBox.getAll();
    allChats.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return allChats;
  }

  /// 最新のメッセージを指定件数取得する（作成日時の降順）
  Future<List<Chat>> getLatestMessages(int limit) async {
    final allChats = chatBox.getAll();
    allChats.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 降順
    final results = allChats.take(limit).toList();
    results.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // 昇順に戻す
    return results;
  }

  /// すべてのメッセージを削除する
  Future<void> clear() async {
    chatBox.removeAll();
  }
}
