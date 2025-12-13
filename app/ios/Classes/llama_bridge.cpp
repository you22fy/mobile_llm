#include "llama_bridge.h"
#include "llama.h"
#include <unordered_map>
#include <mutex>
#include <string>
#include <cstring>
#include <vector>
#include <cstdio>

// モデルコンテキストを保持する構造体
struct ModelContext
{
    llama_model *model;
    llama_context *ctx;
    bool is_embedding;

    ModelContext() : model(nullptr), ctx(nullptr), is_embedding(false) {}
};

// モデルIDとコンテキストのマップ（スレッドセーフのためmutexで保護）
static std::mutex g_models_mutex;
static std::unordered_map<int32_t, ModelContext> g_models;
static int32_t g_next_model_id = 1;

// llama.cpp のログを Xcode コンソールに流すコールバック
static void llama_log_callback(ggml_log_level level, const char *text, void *user_data)
{
    (void)level;
    (void)user_data;
    // llama.cpp 側のログをそのまま標準エラーに出力
    fprintf(stderr, "[llama] %s", text);
}

// エラーコードを返すヘルパー関数
static int32_t return_error(int32_t error_code)
{
    return error_code;
}

// モデルをロードする
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
llama_load_model(const char *model_path, int32_t is_embedding)
{
    if (!model_path)
    {
        return LLAMA_BRIDGE_ERROR_INVALID_PARAM;
    }

    // ログコールバックを設定
    llama_log_set(llama_log_callback, nullptr);

    fprintf(stderr, "[llama_bridge] llama_load_model: path=%s, is_embedding=%d\n",
            model_path, is_embedding);

    // llama.cppのバックエンドを初期化
    llama_backend_init();
    fprintf(stderr, "[llama_bridge] llama_backend_init done\n");

    // モデルパラメータを設定
    llama_model_params model_params = llama_model_default_params();
    fprintf(stderr, "[llama_bridge] llama_model_default_params done\n");

    // モデルをロード
    llama_model *model = llama_model_load_from_file(model_path, model_params);
    if (!model)
    {
        fprintf(stderr, "[llama_bridge] llama_model_load_from_file FAILED\n");
        llama_backend_free();
        return LLAMA_BRIDGE_ERROR_MODEL_LOAD_FAILED;
    }
    fprintf(stderr, "[llama_bridge] llama_model_load_from_file OK\n");

    // コンテキストパラメータを設定
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.embeddings = (is_embedding != 0);
    if (is_embedding)
    {
        ctx_params.n_ctx = 32;
        ctx_params.n_batch = 128;
        ctx_params.n_ubatch = 128; // NOTE: n_ubatch > (入力トークン数)じゃないとエラーになる
        ctx_params.n_threads = 4;
        ctx_params.n_threads_batch = 4;
    }
    else
    {
        // 生成ではプロンプト＋生成トークン数を収容できるだけのコンテキスト長が必要。
        // n_ctx が小さすぎると decode が失敗したり、実装によってはabortする可能性がある。
        ctx_params.n_ctx = 2048;
        ctx_params.n_batch = 256;
        ctx_params.n_ubatch = 256;
        ctx_params.n_threads = 8;
        ctx_params.n_threads_batch = 8;
    }

    fprintf(stderr,
            "[llama_bridge] llama_context_default_params: embeddings=%d, n_ctx=%d, n_batch=%d\n",
            ctx_params.embeddings ? 1 : 0, ctx_params.n_ctx, ctx_params.n_batch);

    // コンテキストを作成
    llama_context *ctx = llama_init_from_model(model, ctx_params);
    if (!ctx)
    {
        fprintf(stderr, "[llama_bridge] llama_init_from_model FAILED\n");
        llama_model_free(model);
        llama_backend_free();
        return LLAMA_BRIDGE_ERROR_MODEL_LOAD_FAILED;
    }
    fprintf(stderr, "[llama_bridge] llama_init_from_model OK\n");

    // モデルコンテキストを作成してマップに追加
    std::lock_guard<std::mutex> lock(g_models_mutex);
    int32_t model_id = g_next_model_id++;
    ModelContext model_ctx;
    model_ctx.model = model;
    model_ctx.ctx = ctx;
    model_ctx.is_embedding = (is_embedding != 0);
    g_models[model_id] = model_ctx;

    fprintf(stderr, "[llama_bridge] llama_load_model SUCCESS, model_id=%d\n", model_id);

    return model_id;
}

// モデルを解放する
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
llama_unload_model(int32_t model_id)
{
    std::lock_guard<std::mutex> lock(g_models_mutex);

    auto it = g_models.find(model_id);
    if (it == g_models.end())
    {
        return LLAMA_BRIDGE_ERROR_INVALID_MODEL_ID;
    }

    ModelContext &model_ctx = it->second;

    // コンテキストとモデルを解放
    if (model_ctx.ctx)
    {
        llama_free(model_ctx.ctx);
    }
    if (model_ctx.model)
    {
        llama_model_free(model_ctx.model);
    }

    g_models.erase(it);

    // 最後のモデルが解放されたらバックエンドも解放
    if (g_models.empty())
    {
        llama_backend_free();
    }

    return LLAMA_BRIDGE_SUCCESS;
}

// テキスト生成を行う
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
llama_generate_text(int32_t model_id, const char *prompt, char *out_buffer, int32_t out_buffer_size)
{
    if (!prompt || !out_buffer || out_buffer_size <= 0)
    {
        return LLAMA_BRIDGE_ERROR_INVALID_PARAM;
    }

    std::lock_guard<std::mutex> lock(g_models_mutex);

    auto it = g_models.find(model_id);
    if (it == g_models.end())
    {
        return LLAMA_BRIDGE_ERROR_INVALID_MODEL_ID;
    }

    ModelContext &model_ctx = it->second;

    if (model_ctx.is_embedding)
    {
        return LLAMA_BRIDGE_ERROR_INVALID_PARAM; // embeddingモデルでは生成不可
    }

    llama_context *ctx = model_ctx.ctx;
    const llama_vocab *vocab = llama_model_get_vocab(model_ctx.model);

    // 生成のたびにKVキャッシュをクリア（会話履歴はDart側でプロンプトに含めるため）
    // これをしないと前回推論の状態が残り、n_ctx超過や不正状態になり得る。
    llama_set_embeddings(ctx, false);
    llama_memory_clear(llama_get_memory(ctx), true);

    // プロンプトをトークナイズ（動的メモリ確保）
    const int32_t max_tokens = 512;
    std::vector<llama_token> tokens(max_tokens);
    int32_t n_tokens = llama_tokenize(vocab, prompt, strlen(prompt), tokens.data(), max_tokens, true, false);

    if (n_tokens < 0)
    {
        return LLAMA_BRIDGE_ERROR_DECODE_FAILED;
    }

    // バッチを作成してデコード
    llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);

    // デコード実行
    if (llama_decode(ctx, batch) < 0)
    {
        // llama_batch_free(batch);
        return LLAMA_BRIDGE_ERROR_DECODE_FAILED;
    }

    // llama_batch_free(batch);

    // 生成ループ（簡易版：固定パラメータ）
    std::string generated_text;
    const int32_t max_gen_tokens = 128;
    const float temp = 0.7f;
    const int32_t top_k = 40;
    const float top_p = 0.9f;
    const float min_p = 0.1f;
    const uint32_t seed = 0xFFFFFFFF; // LLAMA_DEFAULT_SEED

    // サンプラーチェーンを構築
    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    llama_sampler *sampler = llama_sampler_chain_init(chain_params);

    // サンプラーをチェーンに追加
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_min_p(min_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));

    for (int32_t i = 0; i < max_gen_tokens; i++)
    {
        // サンプリング
        llama_token new_token_id = llama_sampler_sample(sampler, ctx, -1);

        // EOSトークンの場合は終了
        if (llama_vocab_is_eog(vocab, new_token_id))
        {
            break;
        }

        // トークンをテキストに変換
        char token_text[256];
        int32_t token_len = llama_token_to_piece(vocab, new_token_id, token_text, sizeof(token_text), 0, false);
        if (token_len > 0)
        {
            generated_text.append(token_text, token_len);
        }

        // 次のトークンをデコード
        batch = llama_batch_get_one(&new_token_id, 1);
        if (llama_decode(ctx, batch) < 0)
        {
            // llama_batch_free(batch);
            break;
        }
        // llama_batch_free(batch);
    }

    llama_sampler_free(sampler);

    // 生成されたテキストをバッファにコピー
    int32_t text_len = generated_text.length();
    if (text_len >= out_buffer_size)
    {
        return LLAMA_BRIDGE_ERROR_BUFFER_TOO_SMALL;
    }

    memcpy(out_buffer, generated_text.c_str(), text_len);
    out_buffer[text_len] = '\0';

    return text_len;
}

// Embeddingの次元数を取得する
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
llama_get_embedding_dim(int32_t model_id)
{
    std::lock_guard<std::mutex> lock(g_models_mutex);

    auto it = g_models.find(model_id);
    if (it == g_models.end())
    {
        return LLAMA_BRIDGE_ERROR_INVALID_MODEL_ID;
    }

    ModelContext &model_ctx = it->second;
    return llama_model_n_embd(model_ctx.model);
}

// テキストの埋め込み表現を生成する
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
llama_embed_text(int32_t model_id, const char *text, float *out_buffer, int32_t max_tokens)
{
    if (!text || !out_buffer || max_tokens <= 0)
    {
        return LLAMA_BRIDGE_ERROR_INVALID_PARAM;
    }

    std::lock_guard<std::mutex> lock(g_models_mutex);

    auto it = g_models.find(model_id);
    if (it == g_models.end())
    {
        return LLAMA_BRIDGE_ERROR_INVALID_MODEL_ID;
    }

    ModelContext &model_ctx = it->second;

    if (!model_ctx.is_embedding)
    {
        return LLAMA_BRIDGE_ERROR_INVALID_PARAM; // LLMモデルでは埋め込み不可
    }

    llama_context *ctx = model_ctx.ctx;
    llama_model *model = model_ctx.model;
    const llama_vocab *vocab = llama_model_get_vocab(model);

    // テキストをトークナイズ（動的メモリ確保）
    std::vector<llama_token> tokens(max_tokens);
    int32_t n_tokens = llama_tokenize(vocab, text, strlen(text), tokens.data(), max_tokens, true, false);

    if (n_tokens < 0)
    {
        return LLAMA_BRIDGE_ERROR_EMBEDDING_FAILED;
    }

    // バッチを作成
    llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);

    // 埋め込みを有効にする
    llama_set_embeddings(ctx, true);

    // 前回のKVキャッシュをクリア（埋め込み専用の推論なので毎回リセットしてOK）
    llama_memory_clear(llama_get_memory(ctx), true);

    // デコード実行
    if (llama_decode(ctx, batch) < 0)
    {
        // llama_batch_free(batch);
        return LLAMA_BRIDGE_ERROR_EMBEDDING_FAILED;
    }

    // llama_batch_free(batch);

    // プーリング方式に応じて埋め込みベクトルを取得
    float *embeddings = nullptr;
    enum llama_pooling_type pooling = llama_pooling_type(ctx);

    if (pooling == LLAMA_POOLING_TYPE_NONE)
    {
        // トークンごとの埋め込み: 最後のトークンの埋め込みを使う
        embeddings = llama_get_embeddings_ith(ctx, -1);
    }
    else
    {
        // プーリング済みのシーケンス埋め込み（mean / cls など）
        embeddings = llama_get_embeddings_seq(ctx, 0);
    }

    if (!embeddings)
    {
        return LLAMA_BRIDGE_ERROR_EMBEDDING_FAILED;
    }

    // 埋め込みの次元数を取得
    int32_t n_embd = llama_model_n_embd(model);

    // バッファにコピー
    memcpy(out_buffer, embeddings, n_embd * sizeof(float));

    return n_embd;
}
