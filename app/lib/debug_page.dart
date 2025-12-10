import 'dart:io';

import 'package:app/debug_box.dart';
import 'package:app/entity/debug.dart';
import 'package:app/llm.dart';
import 'package:app/natives/llama.dart';
import 'package:app/natives/native_add.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key, required this.title});
  final String title;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  int _nativeAddResult = 0;
  String _llmOutput = '';
  String _embeddingPreview = '';
  String _debugSearchResult = '';
  Llm _currentLlm = Llm.gemma3_270m;
  EmbeddingModel _currentEmbeddingModel = EmbeddingModel.gemma300mQ4KM;

  final TextEditingController _llmInputController = TextEditingController();
  final TextEditingController _embeddingInputController =
      TextEditingController();

  final DebugBox _debugBox = DebugBox();

  Future<void> _runDebugSearch() async {
    await _debugBox.init();
    await _debugBox.insertSampleData();

    try {
      setState(() {
        _debugSearchResult = 'Running ObjectBox debug search...';
      });

      // デモ用のクエリベクトル（[1.0, 2.0, 3.0] に近い点を検索）
      final query = Debug(id: 1, text: 'query', embedding: [1.0, 1.0, 1.0]);

      final results = await _debugBox.search(query: query, k: 2);

      if (results.isEmpty) {
        setState(() {
          _debugSearchResult = 'No results.';
        });
        return;
      }

      final buffer = StringBuffer();
      for (final r in results) {
        buffer.writeln(
          'id=${r.object.id}, text=${r.object.text}, score=${r.score.toStringAsFixed(4)}',
        );
      }

      setState(() {
        _debugSearchResult = buffer.toString();
      });
    } catch (e) {
      setState(() {
        _debugSearchResult = 'Debug search error: $e';
      });
    }
  }

  void _nativeAdd(int a, int b) {
    setState(() {
      _nativeAddResult = nativeAdd(a, b);
    });
  }

  void _reset() {
    setState(() {
      _nativeAddResult = 0;
      _llmOutput = '';
      _embeddingPreview = '';
      _debugSearchResult = '';
    });
  }

  Future<String> _ensureModelCopied(
    String assetPath,
    String fileName, {
    bool needOverwrite = false,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    if (!needOverwrite && await file.exists()) {
      return file.path;
    }

    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  void _setLlm(Llm llm) {
    setState(() {
      _currentLlm = llm;
    });
  }

  void _setEmbeddingModel(EmbeddingModel embeddingModel) {
    setState(() {
      _currentEmbeddingModel = embeddingModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _reset, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // ---- native_add の確認 ----
              Text('Native add result: $_nativeAddResult'),
              ElevatedButton(
                onPressed: () => _nativeAdd(1, 2),
                child: const Text('Native Add'),
              ),
              const Divider(height: 32),
              DropdownButton<Llm>(
                value: _currentLlm,
                onChanged: (Llm? llm) => _setLlm(llm ?? Llm.gemma3_270m),
                items: Llm.values
                    .map(
                      (Llm llm) => DropdownMenuItem(
                        value: llm,
                        child: Text(llm.displayName),
                      ),
                    )
                    .toList(),
              ),

              // ---- LLM 実行 ----
              TextField(
                controller: _llmInputController,
                decoration: const InputDecoration(hintText: 'Enter prompt'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    setState(() {
                      _llmOutput = 'Running LLM...';
                    });

                    final modelPath = await _ensureModelCopied(
                      _currentLlm.assetPath,
                      '${_currentLlm.displayName}.gguf',
                    );

                    final model = await LlamaModel.load(modelPath);
                    final result = await model.generate(
                      _llmInputController.text,
                      maxTokens: 64,
                    );
                    await model.dispose();

                    setState(() {
                      _llmOutput = result;
                    });
                  } catch (e) {
                    setState(() {
                      _llmOutput = 'LLM error: $e';
                    });
                  }
                },
                child: const Text('Run LLM'),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _llmOutput.isEmpty
                      ? 'LLM output will appear here.'
                      : _llmOutput,
                  textAlign: TextAlign.center,
                ),
              ),

              const Divider(height: 32),

              // ---- Embedding 実行 ----
              DropdownButton<EmbeddingModel>(
                value: _currentEmbeddingModel,
                onChanged: (EmbeddingModel? embeddingModel) =>
                    _setEmbeddingModel(
                      embeddingModel ?? EmbeddingModel.gemma300mQ4KM,
                    ),
                items: EmbeddingModel.values
                    .map(
                      (EmbeddingModel embeddingModel) => DropdownMenuItem(
                        value: embeddingModel,
                        child: Text(embeddingModel.displayName),
                      ),
                    )
                    .toList(),
              ),
              TextField(
                controller: _embeddingInputController,
                decoration: const InputDecoration(hintText: 'Enter text'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    setState(() {
                      _embeddingPreview = 'Computing embedding...';
                    });

                    final modelPath = await _ensureModelCopied(
                      _currentEmbeddingModel.assetPath,
                      '${_currentEmbeddingModel.displayName}.gguf',
                    );

                    final embModel = await LlamaEmbeddingModel.load(modelPath);
                    final emb = await embModel.embed(
                      _embeddingInputController.text,
                    );
                    await embModel.dispose();

                    final preview = emb
                        .take(100)
                        .map((v) => v.toStringAsFixed(10))
                        .join(', ');

                    setState(() {
                      _embeddingPreview = preview;
                    });
                  } catch (e) {
                    setState(() {
                      _embeddingPreview = 'Embedding error: $e';
                    });
                  }
                },
                child: const Text('Compute Embedding'),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _embeddingPreview.isEmpty
                      ? 'Embedding preview will appear here.'
                      : _embeddingPreview,
                  textAlign: TextAlign.center,
                ),
              ),

              const Divider(height: 32),

              // ---- ObjectBox Debug 検索デモ ----
              ElevatedButton(
                onPressed: _runDebugSearch,
                child: const Text('Run ObjectBox Debug Search (top 2)'),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _debugSearchResult.isEmpty
                      ? 'Debug search results will appear here.'
                      : _debugSearchResult,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
