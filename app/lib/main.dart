import 'dart:io';

import 'package:app/chat_box.dart';
import 'package:app/debug_page.dart';
import 'package:app/entity/chat.dart';
import 'package:app/llm.dart';
import 'package:app/llm_worker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

enum HomePageState { selectingModel, chatting }

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  HomePageState _state = HomePageState.selectingModel;
  late final ChatBox chatBox;
  late final LlmWorkerClient _workerClient;
  List<Chat> chats = [];
  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  bool isLoading = true;
  bool isInitialized = false;

  // モデル選択用
  Llm _selectedLlm = Llm.gemma3_270m;
  EmbeddingModel _selectedEmbeddingModel = EmbeddingModel.gemma300mQ4KM;
  bool _isLoadingModels = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    chatBox = ChatBox();
    _workerClient = LlmWorkerClient();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // ChatBoxを初期化
      await chatBox.init();
      final messages = await chatBox.getAllMessages();

      // ワーカーIsolateを起動
      await _workerClient.start(rootIsolateToken: RootIsolateToken.instance);

      setState(() {
        chats = messages;
        isLoading = false;
        isInitialized = true;
      });
      _scrollToBottom();
    } catch (e) {
      print('Error initializing: $e');
      setState(() {
        isLoading = false;
        isInitialized = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('初期化に失敗しました: $e')));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// assetsからモデルファイルをDocumentsにコピーする
  Future<String> _ensureModelCopied(String assetPath, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      return file.path;
    }

    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  /// モデルをロードしてチャットモードに遷移
  Future<void> _loadModelsAndStartChat() async {
    if (_isLoadingModels) return;

    setState(() {
      _isLoadingModels = true;
    });

    try {
      // モデルファイルをコピー（UI側で実行）
      final llmPath = await _ensureModelCopied(
        _selectedLlm.assetPath,
        '${_selectedLlm.displayName}.gguf',
      );
      final embeddingPath = await _ensureModelCopied(
        _selectedEmbeddingModel.assetPath,
        '${_selectedEmbeddingModel.displayName}.gguf',
      );

      // Knowledge DBディレクトリパスを解決（UI側で実行）
      final dir = await getApplicationDocumentsDirectory();
      final knowledgeDbDir = '${dir.path}/knowledge_box';

      // ワーカーにモデルロードを依頼
      await _workerClient.load(
        llmModelPath: llmPath,
        embeddingModelPath: embeddingPath,
        knowledgeDbDir: knowledgeDbDir,
      );

      setState(() {
        _state = HomePageState.chatting;
        _isLoadingModels = false;
      });
    } catch (e) {
      print('Error loading models: $e');
      setState(() {
        _isLoadingModels = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('モデルのロードに失敗しました: $e')));
      }
    }
  }

  /// 会話を終了してモデルをアンロード
  Future<void> _endConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('会話を終了しますか？'),
        content: const Text('モデルがメモリからアンロードされます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('終了'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // ワーカーにモデルアンロードを依頼
      await _workerClient.unload();
      setState(() {
        _state = HomePageState.selectingModel;
      });
    } catch (e) {
      print('Error unloading models: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('モデルのアンロードに失敗しました: $e')));
      }
    }
  }

  /// ベース知識を挿入
  Future<void> _seedBaseKnowledge() async {
    if (!isInitialized || _isGenerating || _state != HomePageState.chatting) {
      return;
    }

    try {
      setState(() {
        _isGenerating = true;
      });

      final result = await _workerClient.seedBaseKnowledge();
      final count = result['count'] as int;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ベース知識を${count}件追加しました'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error seeding base knowledge: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ベース知識の挿入に失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  /// AI応答の詳細（prompt/references）をBottomSheetで表示
  void _showChatDetailsBottomSheet(BuildContext context, Chat chat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ハンドル
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // タイトル
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'AI応答の詳細',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              // コンテンツ
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Promptセクション
                      Text(
                        'Prompt',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          chat.prompt ?? '(プロンプト情報なし)',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Referencesセクション
                      Text(
                        'References',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (chat.references.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '参照なし',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        )
                      else
                        ...chat.references.asMap().entries.map((entry) {
                          final index = entry.key;
                          final reference = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SelectableText(
                                    reference,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      // Raw replyセクション
                      Text(
                        'Raw reply',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          chat.rawMessage ?? '(raw出力なし)',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// チャット履歴をリセット（全削除）
  Future<void> _resetChatHistory() async {
    if (!isInitialized || _isGenerating) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('チャット履歴をリセットしますか？'),
        content: const Text('保存されているメッセージがすべて削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await chatBox.clear();
      if (!mounted) return;
      setState(() {
        chats = [];
      });
      inputController.clear();
      _scrollToBottom();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('チャット履歴を削除しました')));
    } catch (e) {
      print('Error clearing chat history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('チャット履歴の削除に失敗しました: $e')));
    }
  }

  /// 知識を全削除
  Future<void> _clearAllKnowledge() async {
    if (!isInitialized || _isGenerating || _state != HomePageState.chatting) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('知識を全削除しますか？'),
        content: const Text('保存されている知識がすべて削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _isGenerating = true;
      });

      final result = await _workerClient.clearKnowledge();
      final count = result['count'] as int;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('知識を${count}件削除しました'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error clearing knowledge: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('知識の削除に失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = inputController.text.trim();
    if (text.isEmpty ||
        !isInitialized ||
        _isGenerating ||
        _state != HomePageState.chatting) {
      return;
    }

    try {
      // ユーザーメッセージを保存
      final userChat = await chatBox.insertMessage(role: 'user', content: text);

      setState(() {
        chats.add(userChat);
        _isGenerating = true;
      });
      inputController.clear();
      _scrollToBottom();

      // 会話履歴を準備（直近20ターン）
      final recentChats = chats.length > 6
          ? chats.sublist(chats.length - 6)
          : chats;
      final history = recentChats
          .map((chat) => {'role': chat.role, 'content': chat.message})
          .toList()
          .cast<Map<String, String>>();

      // ワーカーでRAG応答を生成
      final result = await _workerClient.generateRag(
        userText: text,
        history: history,
        k: 3,
        maxTokens: 256,
      );

      // AI応答を保存（prompt、rawReplyText、referencesを含む）
      final aiChat = await chatBox.insertMessage(
        role: 'assistant',
        content: result['replyText'] as String,
        prompt: result['prompt'] as String?,
        rawContent: result['rawReplyText'] as String?,
        references:
            (result['contexts'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

      setState(() {
        chats.add(aiChat);
        _isGenerating = false;
      });
      _scrollToBottom();
    } catch (e) {
      print('Error sending message: $e');
      setState(() {
        _isGenerating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('メッセージの送信に失敗しました: $e')));
      }
    }
  }

  @override
  void dispose() {
    _workerClient.stop();
    inputController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: _state == HomePageState.chatting
            ? [
                IconButton(
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: _isGenerating ? null : _seedBaseKnowledge,
                  tooltip: 'ベース知識挿入',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _isGenerating ? null : _resetChatHistory,
                  tooltip: '履歴リセット',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever),
                  onPressed: _isGenerating ? null : _clearAllKnowledge,
                  tooltip: '知識全削除',
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _endConversation,
                  tooltip: '会話終了',
                ),
              ]
            : null,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const SizedBox(height: 60),
            ListTile(
              title: const Text('Debug'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DebugPage(title: 'Debug Page'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _state == HomePageState.selectingModel
          ? _buildModelSelectionView()
          : _buildChatView(),
    );
  }

  /// モデル選択画面を構築
  Widget _buildModelSelectionView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'モデルを選択してください',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            // LLM選択
            const Text('LLMモデル', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButton<Llm>(
              value: _selectedLlm,
              isExpanded: true,
              onChanged: _isLoadingModels
                  ? null
                  : (Llm? llm) {
                      if (llm != null) {
                        setState(() {
                          _selectedLlm = llm;
                        });
                      }
                    },
              items: Llm.values
                  .map(
                    (Llm llm) => DropdownMenuItem(
                      value: llm,
                      child: Text(llm.displayName),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            // Embeddingモデル選択
            const Text('Embeddingモデル', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButton<EmbeddingModel>(
              value: _selectedEmbeddingModel,
              isExpanded: true,
              onChanged: _isLoadingModels
                  ? null
                  : (EmbeddingModel? embeddingModel) {
                      if (embeddingModel != null) {
                        setState(() {
                          _selectedEmbeddingModel = embeddingModel;
                        });
                      }
                    },
              items: EmbeddingModel.values
                  .map(
                    (EmbeddingModel embeddingModel) => DropdownMenuItem(
                      value: embeddingModel,
                      child: Text(embeddingModel.displayName),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoadingModels ? null : _loadModelsAndStartChat,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: _isLoadingModels
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('ロードして開始'),
            ),
          ],
        ),
      ),
    );
  }

  /// チャット画面を構築
  Widget _buildChatView() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16.0),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final isUser = chat.role == 'user';
              return Align(
                alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: GestureDetector(
                  onTap: !isUser
                      ? () => _showChatDetailsBottomSheet(context, chat)
                      : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(18.0),
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    child: Text(
                      chat.message,
                      style: TextStyle(
                        color: isUser
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 4.0,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 12.0,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isGenerating ? null : _sendMessage,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.all(16.0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
