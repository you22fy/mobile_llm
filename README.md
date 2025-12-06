# mobile_llm

## GGUFモデルの作成
 - HFからモデルのリポジトリをクローン
 - config.jsonのdtypeを確認
 - llama.cppをクローンしてきて `convert_hf_to_gguf.py` を実行
   - 実行時に `--outtype`にdtypeを指定(bf16など)
