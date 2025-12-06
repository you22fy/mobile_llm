import 'dart:io';

import 'package:app/natives/native_add.dart';
import 'package:app/natives/llama.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _nativeAddResult = 0;
  String _llmOutput = '';
  String _embeddingPreview = '';

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

              // ---- LLM 実行 ----
              ElevatedButton(
                onPressed: () async {
                  try {
                    setState(() {
                      _llmOutput = 'Running LLM...';
                    });

                    final modelPath = await _ensureModelCopied(
                      'assets/artifacts/gemma-3-270M-BF16.gguf',
                      'gemma-3-270M-BF16.gguf',
                    );

                    final model = await LlamaModel.load(modelPath);
                    final result = await model.generate(
                      'Hello from Flutter!',
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
                child: const Text('Run LLM (gemma-3-270M-BF16)'),
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
              ElevatedButton(
                onPressed: () async {
                  try {
                    setState(() {
                      _embeddingPreview = 'Computing embedding...';
                    });

                    final modelPath = await _ensureModelCopied(
                      'assets/artifacts/embeddinggemma-300M-F32.gguf',
                      'embeddinggemma-300M-F32.gguf',
                    );

                    final embModel = await LlamaEmbeddingModel.load(modelPath);
                    final emb = await embModel.embed(
                      'It is said that the world will end in 2025.',
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
                child: const Text('Compute Embedding (first 8 dims)'),
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
            ],
          ),
        ),
      ),
    );
  }
}
