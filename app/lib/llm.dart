enum Llm {
  gemma3_1b_Q4KM,
  gemma3_1b_Q5KM,
  gemma3_1b_Q8,
  gemma3_270m,
  tinyswallow;

  get displayName => switch (this) {
    Llm.gemma3_1b_Q4KM => 'gema3-1b-it-Q4_K_M',
    Llm.gemma3_1b_Q5KM => 'gema3-1b-it-Q5_K_M',
    Llm.gemma3_1b_Q8 => 'gema3-1b-it-Q8',
    Llm.gemma3_270m => 'gemma3-270m-it',
    Llm.tinyswallow => 'tinyswallow-1.5b',
  };

  get assetPath => switch (this) {
    Llm.gemma3_1b_Q4KM => 'assets/artifacts/gemma-3-1B-it-BF16_Q4_K_M.gguf',
    Llm.gemma3_1b_Q5KM => 'assets/artifacts/gemma-3-1B-it-BF16_Q5_K_M.gguf',
    Llm.gemma3_1b_Q8 => 'assets/artifacts/gemma-3-1B-it-BF16_Q8_0.gguf',
    Llm.gemma3_270m => 'assets/artifacts/gemma-3-270M-BF16-Q4_K_M.gguf',
    Llm.tinyswallow =>
      'assets/artifacts/Qwen2.5-1.5B-Instruct-BF16-Q4_K_M.gguf',
  };
}

enum EmbeddingModel {
  gemma300mQ4KM;

  get displayName => switch (this) {
    EmbeddingModel.gemma300mQ4KM => 'Gemma 300M Q4KM',
  };

  get assetPath => switch (this) {
    EmbeddingModel.gemma300mQ4KM =>
      'assets/artifacts/embeddinggemma-300M-F32-Q4_K_M.gguf',
  };
}
