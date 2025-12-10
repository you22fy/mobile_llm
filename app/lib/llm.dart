enum Llm {
  gemma2,
  gemma3_1b,
  gemma3_270m,
  tinyswallow;

  get displayName => switch (this) {
    Llm.gemma2 => 'google/gemma2-2b-jpt-it',
    Llm.gemma3_1b => 'google/gemma3-1b-jpt-it',
    Llm.gemma3_270m => 'google/gemma3-270m-jpt-it',
    Llm.tinyswallow => 'SakanaAI/TinySwallow-1.5B',
  };

  get assetPath => switch (this) {
    Llm.gemma2 => 'assets/artifacts/gemma-2-2B-it-BF16-Q4_K_M.gguf',
    Llm.gemma3_1b => 'assets/artifacts/gemma-3-1B-it-BF16_Q4_K_M.gguf',
    Llm.gemma3_270m => 'assets/artifacts/gemma-3-270M-BF16-Q4_K_M.gguf',
    Llm.tinyswallow => 'assets/artifacts/Qwen2.5-1.5B-Instruct-BF16-Q4_K_M.gguf',
  };
}

// enum Llm {
//   gemma270m,
//   tinyswallow,
//   gemma270mQ4KM,
//   tinyswallowQ4KM,
//   qwen06bq8,
//   gemma3_1bit,
//   gemma3_1bitQ4KM,
//   gemma2_2BQ4KM;

//   get displayName => switch (this) {
//     Llm.gemma270m => 'Gemma 270M',
//     Llm.tinyswallow => 'TinySwallow 1.5B',
//     Llm.gemma270mQ4KM => 'Gemma 270M Q4KM',
//     Llm.tinyswallowQ4KM => 'TinyLlama 3.70B Q4KM',
//     Llm.qwen06bq8 => 'Qwen 0.6B Q8',
//     Llm.gemma3_1bit => 'Gemma 3 1B it',
//     Llm.gemma3_1bitQ4KM => 'Gemma 3 1B it Q4KM',
//     Llm.gemma2_2BQ4KM => 'Gemma 2 2B Q4KM',
//   };

//   get assetPath => switch (this) {
//     Llm.gemma270m => 'assets/artifacts/gemma-3-270M-BF16.gguf',
//     Llm.tinyswallow => 'assets/artifacts/Qwen2.5-1.5B-Instruct-BF16.gguf',
//     Llm.gemma270mQ4KM => 'assets/artifacts/gemma-3-270M-BF16-Q4_K_M.gguf',
//     Llm.tinyswallowQ4KM =>
//       'assets/artifacts/Qwen2.5-1.5B-Instruct-BF16-Q4_K_M.gguf',
//     Llm.qwen06bq8 => 'assets/artifacts/Qwen3-0.6B-Q8_0.gguf',
//     Llm.gemma3_1bit => 'assets/artifacts/gemma-3-1B-it-BF16.gguf',
//     Llm.gemma3_1bitQ4KM => 'assets/artifacts/gemma-3-1B-it-BF16_Q4_K_M.gguf',
//     Llm.gemma2_2BQ4KM => 'assets/artifacts/gemma-2-2B-it-BF16-Q4_K_M.gguf',
//   };
// }

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
