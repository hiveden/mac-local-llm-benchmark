# RUN 结果汇总

> ⚠️ 部分数据的 token 计数为估算值（token_source: estimated），decode_tok_s 等指标可能存在偏差。


## A1-single-short

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 172ms | N/A | N/A | 1298ms | 19237MB |
| ollama |  | 9 | 150ms | 65.58 | 0.83 | 1877ms | 21504MB |
| omlx |  | 9 | 88ms | N/A | N/A | 1877ms | 21243MB |

## A2-single-code

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 175ms | N/A | N/A | 12010ms | 19293MB |
| ollama |  | 9 | 216ms | 64.62 | 0.38 | 16062ms | 21504MB |
| omlx |  | 9 | 141ms | N/A | N/A | 16528ms | 21251MB |

## A3-single-long

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 176ms | N/A | N/A | 1598ms | 19260MB |
| ollama |  | 9 | 1523ms | 64.16 | 0.4 | 3453ms | 21504MB |
| omlx |  | 9 | 1332ms | N/A | N/A | 3205ms | 21262MB |

## E1-gemma4-cross

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| ollama |  | 9 | 313ms | 45.71 | 0.7 | 2634ms | 23552MB |
| omlx |  | 9 | 116ms | N/A | N/A | 1662ms | 18988MB |

## E2-gemma4-long

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| ollama |  | 9 | 2693ms | 40.3 | 0.79 | 7732ms | 23552MB |
| omlx |  | 9 | 411ms | N/A | N/A | 3688ms | 19073MB |

## B1-multi-turn — 多轮缓存分析

| Provider | Turn | Rounds | TTFT (median) | TTFT stdev | tok/s (median) | Cache Speedup |
|----------|------|--------|--------------|-----------|---------------|--------------|
| mlx-lm | T1 | 9 | 158ms | 3.97 | N/A | — |
| mlx-lm | T2 | 9 | 157ms | 3.21 | N/A | 1.01x |
| ollama | T1 | 9 | 150ms | 6.2 | 65.6 | — |
| ollama | T2 | 9 | 359ms | 4.93 | 65.47 | 0.42x |
| omlx | T1 | 9 | 88ms | 0.78 | N/A | — |
| omlx | T2 | 9 | 330ms | 12.35 | N/A | 0.27x |
