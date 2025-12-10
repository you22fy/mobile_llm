enum Llm {
  gemma270m,
  tinyswallow,
  gemma270mQ4KM,
  tinyswallowQ4KM,
  qwen06bq8;

  get displayName => switch (this) {
    Llm.gemma270m => 'Gemma 270M',
    Llm.tinyswallow => 'TinySwallow 1.5B',
    Llm.gemma270mQ4KM => 'Gemma 270M Q4KM',
    Llm.tinyswallowQ4KM => 'TinyLlama 3.70B Q4KM',
    Llm.qwen06bq8 => 'Qwen 0.6B Q8',
  };

  get assetPath => switch (this) {
    Llm.gemma270m => 'assets/artifacts/gemma-3-270M-BF16.gguf',
    Llm.tinyswallow => 'assets/artifacts/Qwen2.5-1.5B-Instruct-BF16.gguf',
    Llm.gemma270mQ4KM => 'assets/artifacts/gemma-3-270M-BF16-Q4_K_M.gguf',
    Llm.tinyswallowQ4KM =>
      'assets/artifacts/Qwen2.5-1.5B-Instruct-BF16-Q4_K_M.gguf',
    Llm.qwen06bq8 => 'assets/artifacts/Qwen3-0.6B-Q8_0.gguf',
  };
}

enum EmbeddingModel {
  gemma300m,
  gemma300mQ4KM;

  get displayName => switch (this) {
    EmbeddingModel.gemma300m => 'Gemma 300M',
    EmbeddingModel.gemma300mQ4KM => 'Gemma 300M Q4KM',
  };

  get assetPath => switch (this) {
    EmbeddingModel.gemma300m => 'assets/artifacts/embeddinggemma-300M-F32.gguf',
    EmbeddingModel.gemma300mQ4KM =>
      'assets/artifacts/embeddinggemma-300M-F32-Q4_K_M.gguf',
  };
}
