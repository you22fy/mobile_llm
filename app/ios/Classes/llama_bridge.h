#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// エラーコード定義
#define LLAMA_BRIDGE_SUCCESS 0
#define LLAMA_BRIDGE_ERROR_INVALID_MODEL_ID -1
#define LLAMA_BRIDGE_ERROR_MODEL_NOT_FOUND -2
#define LLAMA_BRIDGE_ERROR_BUFFER_TOO_SMALL -3
#define LLAMA_BRIDGE_ERROR_INVALID_PARAM -4
#define LLAMA_BRIDGE_ERROR_MODEL_LOAD_FAILED -5
#define LLAMA_BRIDGE_ERROR_DECODE_FAILED -6
#define LLAMA_BRIDGE_ERROR_EMBEDDING_FAILED -7

// モデルをロードする
// 入力: model_path - モデルファイルパス（UTF-8）、is_embedding - embedding用かどうか（1=embedding, 0=LLM）
// 出力: 正常時は model_id（>=1）、異常時は負のエラーコード
__attribute__((visibility("default"))) __attribute__((used))
int32_t llama_load_model(const char* model_path, int32_t is_embedding);

// モデルを解放する
// 入力: model_id - モデルID
// 出力: LLAMA_BRIDGE_SUCCESS またはエラーコード
__attribute__((visibility("default"))) __attribute__((used))
int32_t llama_unload_model(int32_t model_id);

// テキスト生成を行う
// 入力: model_id - モデルID、prompt - プロンプト（UTF-8）、out_buffer - 出力バッファ、out_buffer_size - バッファサイズ
// 出力: 書き込まれたバイト数（終端NULを含まない）、エラー時は負の値
__attribute__((visibility("default"))) __attribute__((used))
int32_t llama_generate_text(int32_t model_id, const char* prompt, char* out_buffer, int32_t out_buffer_size);

// Embeddingの次元数を取得する
// 入力: model_id - モデルID
// 出力: 次元数（正常時）、エラー時は負の値
__attribute__((visibility("default"))) __attribute__((used))
int32_t llama_get_embedding_dim(int32_t model_id);

// テキストの埋め込み表現を生成する
// 入力: model_id - モデルID、text - テキスト（UTF-8）、out_buffer - 出力バッファ（float配列）、max_tokens - 最大トークン数
// 出力: 実際に書き込んだfloatの個数、エラー時は負の値
__attribute__((visibility("default"))) __attribute__((used))
int32_t llama_embed_text(int32_t model_id, const char* text, float* out_buffer, int32_t max_tokens);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_BRIDGE_H
