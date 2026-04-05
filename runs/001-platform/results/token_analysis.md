# T1: 非流式精确 Token 计数

> 独立场景，用非流式请求采集精确 completion_tokens。

## 数据

| Provider | Rounds | Tokens (median) | Tokens (stdev) | 非流式总耗时 (median) |
|----------|--------|----------------|----------------|---------------------|
| mlx-lm | 9 | 100 | 0.0 | 1277ms |
| ollama | 9 | 100 | 14.54 | 1602ms |
| omlx | 9 | 118 | 11.97 | 1959ms |

## 适用范围

- T1 prompt 与 A1 相同（"用一段话解释 RAG 的工作原理"）
- T1 数据**仅可参考对比 A1 场景**的 token 量级
- A2/A3/E1/E2 的 prompt 不同，T1 数据**不适用于修正**这些场景的 tok/s
- 如需其他场景的精确 token 数，应新建对应的 T 场景独立采集
