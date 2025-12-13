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
    final replyText = await _llmModel!.generate(prompt, maxTokens: maxTokens);
    swGen.stop();
    _log(
      '[WORKER] generate done ms=${swGen.elapsedMilliseconds} replyLen=${replyText.length}',
    );

    // 5. 結果を返す
    final contexts = searchResults.map((r) => r.object.text).toList();
    final scores = searchResults.map((r) => r.score).toList();

    return {
      'replyText': replyText,
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
    buffer.writeln('User input:');
    buffer.writeln(userText);

    // 会話履歴
    buffer.writeln('Conversation history:');
    if (history.isNotEmpty) {
      for (final chat in history) {
        final role = chat['role'] == 'user' ? 'ユーザー' : 'アシスタント';
        buffer.writeln('$role: 「${chat['content']}」');
      }
    }
    buffer.writeln();

    buffer.writeln('# Constraints:');
    buffer.writeln('1. Generate a response only for the user input.');
    buffer.writeln('2. Generate only the response text, no other metadata.');
    buffer.writeln('3. Do not generate any other information.');
    buffer.writeln('4. You must response in Japanese.');
    buffer.writeln(
      '5. If the following information is needed in the conversation, use it to generate the response.',
    );
    if (searchResults.isNotEmpty) {
      for (final result in searchResults) {
        buffer.writeln('- ${result.object.text}');
      }
    }

    buffer.writeln('Response:');

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

  /// 事前知識を10件追加
  Future<int> _seedKnowledge() async {
    if (_embeddingModel == null || _knowledgeBox == null) {
      throw StateError('Models not loaded');
    }

    _log('[WORKER] seeding knowledge start');
    final sw = Stopwatch()..start();

    // 固定10件の知識テキスト
    final knowledgeTexts = [
      'FlutterはGoogleが開発したモバイルアプリケーション開発フレームワークです。',
      'DartはFlutterで使用されるプログラミング言語で、オブジェクト指向言語です。',
      'ObjectBoxは高速なオブジェクトデータベースで、モバイルアプリに適しています。',
      'RAG（Retrieval-Augmented Generation）は検索と生成を組み合わせたAI技術です。',
      'ベクトル検索は意味的に類似した文書を見つけるための技術です。',
      '埋め込み（Embedding）はテキストを数値ベクトルに変換する技術です。',
      'LLM（Large Language Model）は大規模な言語モデルで、テキスト生成が可能です。',
      'IsolateはDartで並行処理を実現するための軽量スレッドです。',
      'ネイティブコードはプラットフォーム固有のコードで、高速な処理が可能です。',
      'モバイルアプリ開発では、パフォーマンスとユーザー体験が重要です。',
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
