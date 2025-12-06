import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ネイティブライブラリをロード
final DynamicLibrary _nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libnative_add.so')
    : DynamicLibrary.process();

// FFI関数シグネチャの定義
typedef LlamaLoadModelNative =
    Int32 Function(Pointer<Utf8> modelPath, Int32 isEmbedding);
typedef LlamaLoadModelDart =
    int Function(Pointer<Utf8> modelPath, int isEmbedding);

typedef LlamaUnloadModelNative = Int32 Function(Int32 modelId);
typedef LlamaUnloadModelDart = int Function(int modelId);

typedef LlamaGenerateTextNative =
    Int32 Function(
      Int32 modelId,
      Pointer<Utf8> prompt,
      Pointer<Utf8> outBuffer,
      Int32 outBufferSize,
    );
typedef LlamaGenerateTextDart =
    int Function(
      int modelId,
      Pointer<Utf8> prompt,
      Pointer<Utf8> outBuffer,
      int outBufferSize,
    );

typedef LlamaGetEmbeddingDimNative = Int32 Function(Int32 modelId);
typedef LlamaGetEmbeddingDimDart = int Function(int modelId);

typedef LlamaEmbedTextNative =
    Int32 Function(
      Int32 modelId,
      Pointer<Utf8> text,
      Pointer<Float> outBuffer,
      Int32 maxTokens,
    );
typedef LlamaEmbedTextDart =
    int Function(
      int modelId,
      Pointer<Utf8> text,
      Pointer<Float> outBuffer,
      int maxTokens,
    );

// ネイティブ関数の取得
final LlamaLoadModelDart _llamaLoadModel = _nativeLib
    .lookup<NativeFunction<LlamaLoadModelNative>>('llama_load_model')
    .asFunction();

final LlamaUnloadModelDart _llamaUnloadModel = _nativeLib
    .lookup<NativeFunction<LlamaUnloadModelNative>>('llama_unload_model')
    .asFunction();

final LlamaGenerateTextDart _llamaGenerateText = _nativeLib
    .lookup<NativeFunction<LlamaGenerateTextNative>>('llama_generate_text')
    .asFunction();

final LlamaGetEmbeddingDimDart _llamaGetEmbeddingDim = _nativeLib
    .lookup<NativeFunction<LlamaGetEmbeddingDimNative>>(
      'llama_get_embedding_dim',
    )
    .asFunction();

final LlamaEmbedTextDart _llamaEmbedText = _nativeLib
    .lookup<NativeFunction<LlamaEmbedTextNative>>('llama_embed_text')
    .asFunction();

class LlamaError {
  static const int success = 0;
  static const int invalidModelId = -1;
  static const int modelNotFound = -2;
  static const int bufferTooSmall = -3;
  static const int invalidParam = -4;
  static const int modelLoadFailed = -5;
  static const int decodeFailed = -6;
  static const int embeddingFailed = -7;

  static String getMessage(int errorCode) {
    switch (errorCode) {
      case invalidModelId:
        return 'Invalid model ID';
      case modelNotFound:
        return 'Model not found';
      case bufferTooSmall:
        return 'Buffer too small';
      case invalidParam:
        return 'Invalid parameter';
      case modelLoadFailed:
        return 'Model load failed';
      case decodeFailed:
        return 'Decode failed';
      case embeddingFailed:
        return 'Embedding failed';
      default:
        return 'Unknown error: $errorCode';
    }
  }
}

// LLMモデルクラス
class LlamaModel {
  final int id;
  final String path;
  bool _disposed = false;

  LlamaModel._(this.id, this.path);

  /// モデルをロードする
  static Future<LlamaModel> load(
    String modelPath, {
    bool isEmbedding = false,
  }) async {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final modelId = _llamaLoadModel(pathPtr, isEmbedding ? 1 : 0);
      if (modelId < 0) {
        throw Exception(
          'Failed to load model: ${LlamaError.getMessage(modelId)}',
        );
      }
      return LlamaModel._(modelId, modelPath);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// テキスト生成を行う
  Future<String> generate(String prompt, {int maxTokens = 128}) async {
    if (_disposed) {
      throw StateError('Model has been disposed');
    }

    final promptPtr = prompt.toNativeUtf8();
    final bufferSize = maxTokens * 10;
    final outBuffer = malloc.allocate<Uint8>(
      bufferSize + 1,
    );

    try {
      final result = _llamaGenerateText(
        id,
        promptPtr,
        outBuffer.cast<Utf8>(),
        bufferSize,
      );
      if (result < 0) {
        throw Exception(
          'Failed to generate text: ${LlamaError.getMessage(result)}',
        );
      }
      outBuffer[result] = 0;
      return outBuffer.cast<Utf8>().toDartString(length: result);
    } finally {
      malloc.free(promptPtr);
      malloc.free(outBuffer);
    }
  }

  /// モデルを解放する
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final result = _llamaUnloadModel(id);
    if (result != LlamaError.success) {
      throw Exception(
        'Failed to unload model: ${LlamaError.getMessage(result)}',
      );
    }
  }
}

// Embeddingモデルクラス
class LlamaEmbeddingModel {
  final int id;
  final String path;
  int? _embeddingDim;
  bool _disposed = false;

  LlamaEmbeddingModel._(this.id, this.path);

  /// Embeddingモデルをロードする
  static Future<LlamaEmbeddingModel> load(String modelPath) async {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final modelId = _llamaLoadModel(pathPtr, 1);
      if (modelId < 0) {
        throw Exception(
          'Failed to load embedding model: ${LlamaError.getMessage(modelId)}',
        );
      }
      final model = LlamaEmbeddingModel._(modelId, modelPath);
      model._embeddingDim = _llamaGetEmbeddingDim(modelId);
      if (model._embeddingDim! < 0) {
        throw Exception(
          'Failed to get embedding dimension: ${LlamaError.getMessage(model._embeddingDim!)}',
        );
      }
      return model;
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// 埋め込み次元数を取得する
  int get embeddingDim {
    if (_embeddingDim == null) {
      final dim = _llamaGetEmbeddingDim(id);
      if (dim < 0) {
        throw Exception(
          'Failed to get embedding dimension: ${LlamaError.getMessage(dim)}',
        );
      }
      _embeddingDim = dim;
    }
    return _embeddingDim!;
  }

  /// テキストの埋め込み表現を生成する
  Future<List<double>> embed(String text, {int maxTokens = 512}) async {
    if (_disposed) {
      throw StateError('Model has been disposed');
    }

    final textPtr = text.toNativeUtf8();
    final dim = embeddingDim;
    final outBuffer = malloc<Float>(dim);

    try {
      final result = _llamaEmbedText(id, textPtr, outBuffer, maxTokens);
      if (result < 0) {
        throw Exception(
          'Failed to embed text: ${LlamaError.getMessage(result)}',
        );
      }
      if (result != dim) {
        throw Exception(
          'Unexpected embedding dimension: expected $dim, got $result',
        );
      }

      // Float配列をList<double>に変換
      final embeddings = <double>[];
      for (int i = 0; i < dim; i++) {
        embeddings.add(outBuffer[i]);
      }
      return embeddings;
    } finally {
      malloc.free(textPtr);
      malloc.free(outBuffer);
    }
  }

  /// モデルを解放する
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final result = _llamaUnloadModel(id);
    if (result != LlamaError.success) {
      throw Exception(
        'Failed to unload model: ${LlamaError.getMessage(result)}',
      );
    }
  }
}
