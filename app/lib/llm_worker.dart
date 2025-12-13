import 'dart:async';
import 'dart:isolate';

import 'package:app/entity/knowledge.dart';
import 'package:app/natives/llama.dart';
import 'package:app/objectbox.g.dart';
import 'package:flutter/services.dart';

/// LLM+RAGワーカーIsolateのクライアント
class LlmWorkerClient {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  final Map<int, Completer<Map<String, Object?>>> _pendingRequests = {};
  int _requestIdCounter = 0;
  bool _isStopped = false;

  /// ワーカーIsolateを起動して接続
  Future<void> start({RootIsolateToken? rootIsolateToken}) async {
    if (_isolate != null) {
      return; // 既に起動済み
    }

    _isStopped = false;
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _exitPort = ReceivePort();

    _isolate = await Isolate.spawn<_WorkerInit>(
      _workerEntryPoint,
      _WorkerInit(
        mainSendPort: _receivePort!.sendPort,
        rootIsolateToken: rootIsolateToken,
      ),
      debugName: 'llm_rag_worker',
      onError: _errorPort!.sendPort,
      onExit: _exitPort!.sendPort,
      errorsAreFatal: true,
    );

    _errorPort!.listen((message) {
      // message is typically [errorString, stackString]
      _log('[UI] worker onError: $message');
      _failAllPending('Worker error: $message');
    });
    _exitPort!.listen((_) {
      _log('[UI] worker onExit');
      _sendPort = null;
      _isolate = null;
      _failAllPending('Worker exited unexpectedly');
    });

    // 初期メッセージ（SendPort）を受信
    final completer = Completer<SendPort>();
    _receivePort!.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is Map<String, Object?>) {
        _handleResponse(message);
      } else {
        _log('[UI] unknown message from worker: $message');
      }
    });

    _sendPort = await completer.future;
    _log('[UI] worker connected');
  }

  /// ワーカーを停止
  Future<void> stop() async {
    _isStopped = true;
    if (_isolate != null) {
      _isolate!.kill(priority: Isolate.immediate);
      _isolate = null;
      _sendPort = null;
      _receivePort?.close();
      _receivePort = null;
      _errorPort?.close();
      _errorPort = null;
      _exitPort?.close();
      _exitPort = null;
      _failAllPending('Worker stopped');
      _pendingRequests.clear();
    }
  }

  /// モデルをロード
  Future<void> load({
    required String llmModelPath,
    required String embeddingModelPath,
    required String knowledgeDbDir,
  }) async {
    final response = await _sendRequest({
      'type': 'load',
      'llmModelPath': llmModelPath,
      'embeddingModelPath': embeddingModelPath,
      'knowledgeDbDir': knowledgeDbDir,
    });

    if (response['error'] != null) {
      throw Exception(response['error']);
    }
  }

  /// RAGで応答を生成
  Future<Map<String, Object?>> generateRag({
    required String userText,
    required List<Map<String, String>> history,
    int k = 3,
    int maxTokens = 128,
  }) async {
    final response = await _sendRequest({
      'type': 'generateRag',
      'userText': userText,
      'history': history,
      'k': k,
      'maxTokens': maxTokens,
    });

    if (response['error'] != null) {
      throw Exception(response['error']);
    }

    return {
      'replyText': response['replyText'] as String,
      'rawReplyText': response['rawReplyText'] as String,
      'contexts':
          (response['contexts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      'scores':
          (response['scores'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      'prompt': response['prompt'] as String?,
    };
  }

  /// モデルをアンロード
  Future<void> unload() async {
    final response = await _sendRequest({'type': 'unload'});

    if (response['error'] != null) {
      throw Exception(response['error']);
    }
  }

  /// ユーザー入力から知識を生成して追加
  Future<Map<String, Object?>> addKnowledgeFromUserText({
    required String userText,
  }) async {
    final response = await _sendRequest({
      'type': 'addKnowledgeFromUserText',
      'userText': userText,
    });

    if (response['error'] != null) {
      throw Exception(response['error']);
    }

    return {
      'savedText': response['savedText'] as String,
      'id': response['id'] as int,
    };
  }

  /// ベース知識を挿入
  Future<Map<String, Object?>> seedBaseKnowledge() async {
    final response = await _sendRequest({'type': 'seedBaseKnowledge'});

    if (response['error'] != null) {
      throw Exception(response['error']);
    }

    return {'count': response['count'] as int};
  }

  /// 知識を全削除
  Future<Map<String, Object?>> clearKnowledge() async {
    final response = await _sendRequest({'type': 'clearKnowledge'});

    if (response['error'] != null) {
      throw Exception(response['error']);
    }

    return {'count': response['count'] as int};
  }

  /// リクエストを送信して応答を待つ
  Future<Map<String, Object?>> _sendRequest(Map<String, Object?> request) {
    if (_isStopped) {
      return Future.error(StateError('Worker is stopped'));
    }
    final sendPort = _sendPort;
    if (sendPort == null) {
      return Future.error(StateError('Worker is not connected'));
    }

    final requestId = _requestIdCounter++;
    final completer = Completer<Map<String, Object?>>();
    _pendingRequests[requestId] = completer;

    final message = {...request, 'requestId': requestId};
    _log('[UI] -> worker $message');
    sendPort.send(message);

    // ネイティブクラッシュ等で応答が返らないケースがあるためタイムアウトを付ける
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw TimeoutException('Worker request timed out: ${request['type']}');
      },
    );
  }

  /// 応答を処理
  void _handleResponse(Map<String, Object?> response) {
    final requestId = response['requestId'] as int?;
    if (requestId == null) return;

    final completer = _pendingRequests.remove(requestId);
    _log('[UI] <- worker $response');
    completer?.complete(response);
  }

  void _failAllPending(String message) {
    for (final entry in _pendingRequests.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete({'requestId': entry.key, 'error': message});
      }
    }
    _pendingRequests.clear();
  }
}

class _WorkerInit {
  final SendPort mainSendPort;
  final RootIsolateToken? rootIsolateToken;

  const _WorkerInit({
    required this.mainSendPort,
    required this.rootIsolateToken,
  });
}

/// ワーカーIsolateのエントリーポイント
void _workerEntryPoint(_WorkerInit init) {
  // background isolate でも platform channel を使えるように初期化（必要になるケースがある）
  if (init.rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(init.rootIsolateToken!);
  }

  final workerReceivePort = ReceivePort();
  init.mainSendPort.send(workerReceivePort.sendPort);

  final worker = _LlmWorker(init.mainSendPort);
  // 例外を握りつぶさずにonErrorへ流す
  runZonedGuarded(
    () {
      workerReceivePort.listen((message) async {
        if (message is Map<String, Object?>) {
          await worker.handleRequest(message);
        } else {
          _log('[WORKER] unknown message: $message');
        }
      });
    },
    (error, stack) {
      _log('[WORKER] zone error: $error\n$stack');
      // zoneエラーはfatalになりうるので、そのまま落としてonErrorへ
      throw error;
    },
  );
}

/// ワーカー内部実装
class _LlmWorker {
  final SendPort _mainSendPort;
  LlamaModel? _llmModel;
  LlamaEmbeddingModel? _embeddingModel;
  Store? _store;
  Box<Knowledge>? _knowledgeBox;

  _LlmWorker(this._mainSendPort);

  /// LLMの出力から `<response>...</response>` 内の本文だけを抽出する。
  /// - タグが見つからない場合は raw を trim して返す（モデルが制約を破ったときのフォールバック）
  /// - 複数マッチする場合は先頭を採用
  String _extractResponseText(String raw) {
    final match = RegExp(
      r'<response>([\s\S]*?)</response>',
      caseSensitive: false,
    ).firstMatch(raw);
    final extracted = match?.group(1);
    return (extracted ?? raw).trim();
  }

  /// リクエストを処理（直列実行）
  Future<void> handleRequest(Map<String, Object?> request) async {
    final requestId = request['requestId'] as int;
    final type = request['type'] as String;

    try {
      _log('[WORKER][$requestId] start type=$type');
      final sw = Stopwatch()..start();
      Map<String, Object?> response;

      switch (type) {
        case 'load':
          await _handleLoad(request);
          response = {'requestId': requestId, 'success': true};
          break;
        case 'generateRag':
          response = await _handleGenerateRag(request);
          response['requestId'] = requestId;
          break;
        case 'addKnowledgeFromUserText':
          response = await _handleAddKnowledgeFromUserText(request);
          response['requestId'] = requestId;
          break;
        case 'unload':
          await _handleUnload();
          response = {'requestId': requestId, 'success': true};
          break;
        case 'seedBaseKnowledge':
          response = await _handleSeedBaseKnowledge();
          response['requestId'] = requestId;
          break;
        case 'clearKnowledge':
          response = await _handleClearKnowledge();
          response['requestId'] = requestId;
          break;
        default:
          response = {
            'requestId': requestId,
            'error': 'Unknown request type: $type',
          };
      }

      sw.stop();
      _log(
        '[WORKER][$requestId] done type=$type elapsedMs=${sw.elapsedMilliseconds}',
      );
      _mainSendPort.send(response);
    } catch (e) {
      _log('[WORKER][$requestId] error type=$type err=$e');
      _mainSendPort.send({'requestId': requestId, 'error': e.toString()});
    }
  }

  /// モデルをロード
  Future<void> _handleLoad(Map<String, Object?> request) async {
    final llmModelPath = request['llmModelPath'] as String;
    final embeddingModelPath = request['embeddingModelPath'] as String;
    final knowledgeDbDir = request['knowledgeDbDir'] as String;

    // 既存のモデルがあれば解放
    await _handleUnload();

    // LLMモデルをロード
    _log('[WORKER] loading llm: $llmModelPath');
    _llmModel = await LlamaModel.load(llmModelPath);

    // Embeddingモデルをロード
    _log('[WORKER] loading embedding: $embeddingModelPath');
    _embeddingModel = await LlamaEmbeddingModel.load(embeddingModelPath);

    // Embedding次元チェック
    if (_embeddingModel!.embeddingDim != 768) {
      await _handleUnload();
      throw Exception(
        'Embedding次元が一致しません。期待値: 768, 実際: ${_embeddingModel!.embeddingDim}',
      );
    }

    // ObjectBox Storeを開く
    _log('[WORKER] opening objectbox store: $knowledgeDbDir');
    _store = await openStore(directory: knowledgeDbDir);
    _knowledgeBox = Box<Knowledge>(_store!);
    _log('[WORKER] load completed');
  }

  /// RAGで応答を生成
  Future<Map<String, Object?>> _handleGenerateRag(
    Map<String, Object?> request,
  ) async {
    if (_llmModel == null || _embeddingModel == null || _knowledgeBox == null) {
      throw StateError('Models not loaded');
    }

    final userText = request['userText'] as String;
    final historyRaw =
        (request['history'] as List<dynamic>?)
            ?.map((e) => e as Map<String, String>)
            .toList() ??
        [];

    // 履歴が長すぎる場合の安全策: 最大10ターン（5往復）に制限
    // これによりプロンプトが長くなりすぎてn_batch超過を防ぐ
    final maxHistoryTurns = 10;
    final history = historyRaw.length > maxHistoryTurns
        ? historyRaw.sublist(historyRaw.length - maxHistoryTurns)
        : historyRaw;

    if (historyRaw.length > maxHistoryTurns) {
      _log(
        '[WORKER] history truncated: ${historyRaw.length} -> ${history.length} turns',
      );
    }

    final k = request['k'] as int? ?? 3;
    final maxTokens = request['maxTokens'] as int? ?? 256;

    // 1. 埋め込み生成
    final swEmbed = Stopwatch()..start();
    _log('[WORKER] embed start len=${userText.length}');
    final embedding = await _embeddingModel!.embed(userText);
    swEmbed.stop();
    _log(
      '[WORKER] embed done ms=${swEmbed.elapsedMilliseconds} dim=${embedding.length}',
    );

    // 2. ベクトル検索
    final swSearch = Stopwatch()..start();
    _log('[WORKER] search start k=$k');
    final q = _knowledgeBox!
        .query(Knowledge_.embedding.nearestNeighborsF32(embedding, k))
        .build();
    final searchResults = q.findWithScores();
    q.close();
    swSearch.stop();
    _log(
      '[WORKER] search done ms=${swSearch.elapsedMilliseconds} hits=${searchResults.length}',
    );

    // 3. RAGプロンプトを構築
    final prompt = _buildRagPrompt(userText, history, searchResults);
    _log('[WORKER] prompt: $prompt');

    // 4. テキスト生成
    final swGen = Stopwatch()..start();
    _log(
      '[WORKER] generate start maxTokens=$maxTokens promptLen=${prompt.length}',
    );
    final rawReplyText = await _llmModel!.generate(
      prompt,
      maxTokens: maxTokens,
    );
    final replyText = _extractResponseText(rawReplyText);
    swGen.stop();
    _log(
      '[WORKER] generate done ms=${swGen.elapsedMilliseconds} rawReplyLen=${rawReplyText.length} replyLen=${replyText.length}',
    );

    // 5. 結果を返す
    final contexts = searchResults.map((r) => r.object.text).toList();
    final scores = searchResults.map((r) => r.score).toList();

    return {
      'replyText': replyText,
      'rawReplyText': rawReplyText,
      'contexts': contexts,
      'scores': scores,
      'prompt': prompt, // RAGプロンプト文字列を追加
    };
  }

  /// ユーザー入力から知識を生成して追加
  Future<Map<String, Object?>> _handleAddKnowledgeFromUserText(
    Map<String, Object?> request,
  ) async {
    if (_llmModel == null || _embeddingModel == null || _knowledgeBox == null) {
      throw StateError('Models not loaded');
    }

    final userText = request['userText'] as String;

    // 1. LLMで知識文を生成
    final swGen = Stopwatch()..start();
    _log('[WORKER] generating knowledge text from: $userText');
    final knowledgePrompt = _buildKnowledgeGenerationPrompt(userText);
    final knowledgeText = await _llmModel!.generate(
      knowledgePrompt,
      maxTokens: 128,
    );
    swGen.stop();
    _log(
      '[WORKER] knowledge text generated ms=${swGen.elapsedMilliseconds} text=$knowledgeText',
    );

    // 2. 知識文をembedding
    final swEmbed = Stopwatch()..start();
    final embedding = await _embeddingModel!.embed(knowledgeText);
    swEmbed.stop();
    _log(
      '[WORKER] knowledge embedded ms=${swEmbed.elapsedMilliseconds} dim=${embedding.length}',
    );

    // 3. Knowledgeオブジェクトを作成して保存
    final knowledge = Knowledge(
      id: 0, // ObjectBoxが自動採番
      text: knowledgeText,
      embedding: embedding,
    );
    _knowledgeBox!.put(knowledge);
    _log('[WORKER] knowledge saved id=${knowledge.id}');

    return {'savedText': knowledgeText, 'id': knowledge.id};
  }

  /// 知識生成用プロンプトを構築
  String _buildKnowledgeGenerationPrompt(String userText) {
    final buffer = StringBuffer();
    buffer.writeln('## タスク');
    buffer.writeln('ユーザーの入力から、知識として保存すべき要点を1〜2文で簡潔にまとめてください。');
    buffer.writeln();
    buffer.writeln('## ユーザー入力');
    buffer.writeln(userText);
    buffer.writeln();
    buffer.writeln('## 制約事項');
    buffer.writeln('・知識として保存する価値のある要点を抽出してください');
    buffer.writeln('・1〜2文で簡潔にまとめてください');
    buffer.writeln('・知識文のみを出力し、それ以外のメタ情報は一切出力しないでください');
    buffer.writeln();
    buffer.writeln('## 知識文');
    return buffer.toString();
  }

  /// RAGプロンプトを構築
  String _buildRagPrompt(
    String userText,
    List<Map<String, String>> history,
    List<ObjectWithScore<Knowledge>> searchResults,
  ) {
    final buffer = StringBuffer();
    // ユーザー入力
    buffer.writeln('<instruction>');
    buffer.writeln('ユーザのメッセージに対しての返信文章を日本語で生成せよ');
    buffer.writeln('user_input: ユーザからのメッセージ。あなたはこれに対しての応答を生成する');
    buffer.writeln('conversation_history: 会話履歴。あなたはこれを参考にして応答を生成する');
    buffer.writeln('references: 関連する可能性のある情報。あなたは応答の生成時にこれを参照しても良い');
    buffer.writeln('response: 応答文章。あなたはこれを生成する');
    buffer.writeln('constraints: 制約事項。あなたはこれに従って応答を生成する');
    buffer.writeln('</instruction>');

    buffer.writeln('<user_input>');
    buffer.writeln(userText);
    buffer.writeln('</user_input>');

    // 会話履歴
    if (history.isNotEmpty) {
      buffer.writeln('<conversation_history>');
      for (final chat in history) {
        final role = chat['role'] == 'user' ? 'ユーザー' : 'アシスタント';
        buffer.writeln('$role: 「${chat['content']}」');
      }
      buffer.writeln('</conversation_history>');
    }
    buffer.writeln();

    // 関連する可能性のある情報
    if (searchResults.isNotEmpty) {
      buffer.writeln('<references>');
      for (final result in searchResults) {
        buffer.writeln('- ${result.object.text}');
      }
      buffer.writeln('</references>');
    }

    // 制約事項
    buffer.writeln('<constraints>');
    buffer.writeln('・応答文章は日本語で生成せよ');
    buffer.writeln('・応答文章は<response>タグのみを生成せよ。');
    buffer.writeln('・<response>タグの中にはプレーンテキストのみを生成せよ。');
    buffer.writeln('・回答はプレーンテキストで生成せよ');
    buffer.writeln('・回答の中にマークダウン(Markdown)を使用してはならない');
    buffer.writeln('</constraints>');

    return buffer.toString();
  }

  /// ベース知識を挿入
  Future<Map<String, Object?>> _handleSeedBaseKnowledge() async {
    if (_embeddingModel == null || _knowledgeBox == null) {
      throw StateError('Models not loaded');
    }

    final count = await _seedKnowledge();
    return {'success': true, 'count': count};
  }

  /// 知識を全削除
  Future<Map<String, Object?>> _handleClearKnowledge() async {
    if (_knowledgeBox == null) {
      throw StateError('Models not loaded');
    }

    _log('[WORKER] clearing knowledge start');
    final sw = Stopwatch()..start();
    final removed = _knowledgeBox!.removeAll();
    sw.stop();
    _log(
      '[WORKER] clearing knowledge done ms=${sw.elapsedMilliseconds} count=$removed',
    );
    return {'success': true, 'count': removed};
  }

  /// 事前知識を10件追加
  Future<int> _seedKnowledge() async {
    if (_embeddingModel == null || _knowledgeBox == null) {
      throw StateError('Models not loaded');
    }

    _log('[WORKER] seeding knowledge start');
    final sw = Stopwatch()..start();

    // 固定10件の知識テキスト
    final knowledgeTexts = [
      '福大ピアプロは福岡大学に存在するプログラミング同好会です。',
      'ピアプロの学生の多くは電子情報工学科（TL)の学生です',
      '福岡大学は福岡市の城南区に存在します',
      'Q-PITは北海道化学大学発祥のICTを活用した新たな手法や企画を提案する団体です。',
      'Q-PIは学内向けのウェブアプリやモバイルアプリ開発をしています',
      '北海道には情報系の大学が多いです',
      'Tech.Uniは関西学院大学発祥のIT学生団体です。',
      'Tech.Uniは組織理念として「世の中に価値あるプロダクトを」「人から学び」「共に学ぶ」を掲げています',
      'ディップ株式会社は「バイトル」や「はたらこねっと」などの人材サービスを開発しています',
      'このLT大会は３つの学生団体とディップ株式会社によって開催されています。',
    ];

    // 各テキストをembeddingしてKnowledgeオブジェクトを作成
    final knowledgeList = <Knowledge>[];
    for (final text in knowledgeTexts) {
      final embedding = await _embeddingModel!.embed(text);
      knowledgeList.add(
        Knowledge(
          id: 0, // ObjectBoxが自動採番
          text: text,
          embedding: embedding,
        ),
      );
    }

    // 一括保存
    _knowledgeBox!.putMany(knowledgeList);
    sw.stop();
    _log(
      '[WORKER] seeding knowledge done ms=${sw.elapsedMilliseconds} count=${knowledgeList.length}',
    );
    return knowledgeList.length;
  }

  /// モデルをアンロード
  Future<void> _handleUnload() async {
    try {
      _log('[WORKER] unload start');
      await _llmModel?.dispose();
      await _embeddingModel?.dispose();
      _store?.close();
    } catch (e) {
      // エラーは無視（既に解放済みの可能性）
      print('Warning: Error during unload: $e');
    } finally {
      _llmModel = null;
      _embeddingModel = null;
      _store = null;
      _knowledgeBox = null;
      _log('[WORKER] unload done');
    }
  }
}

void _log(String message) {
  // isolate上でも確実に出る簡易ログ
  // ignore: avoid_print
  print('[LLM_WORKER] $message');
}
