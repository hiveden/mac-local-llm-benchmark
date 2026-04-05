# RUN 结果汇总

> ⚠️ 部分数据的 token 计数为估算值（token_source: estimated），decode_tok_s 等指标可能存在偏差。


## A1-single-short

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 154ms | N/A | N/A | 1230ms | 19235MB |
| ollama |  | 9 | 50ms | 66.56 | 0.21 | 1632ms | 21504MB |
| omlx |  | 9 | 101ms | N/A | N/A | 1771ms | 20136MB |

## A2-single-code

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 162ms | N/A | N/A | 11621ms | 19233MB |
| ollama |  | 9 | 56ms | 65.74 | 0.45 | 15656ms | 21504MB |
| omlx |  | 9 | 168ms | N/A | N/A | 16130ms | 20224MB |

## A3-single-long

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 165ms | N/A | N/A | 1553ms | 19256MB |
| ollama |  | 9 | 58ms | 64.78 | 0.37 | 1997ms | 21504MB |
| omlx |  | 9 | 1330ms | N/A | N/A | 3220ms | 19829MB |

## E1-gemma4-cross

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| ollama |  | 9 | 237ms | 47.23 | 0.92 | 2565ms | 23552MB |
| omlx |  | 9 | 146ms | N/A | N/A | 1661ms | 16108MB |

## E2-gemma4-long

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| ollama |  | 9 | 274ms | 39.41 | 0.74 | 5215ms | 23552MB |
| omlx |  | 9 | 447ms | N/A | N/A | 3854ms | 16898MB |

## B1-multi-turn — 多轮缓存分析

| Provider | Turn | Rounds | TTFT (median) | TTFT stdev | tok/s (median) | Cache Speedup |
|----------|------|--------|--------------|-----------|---------------|--------------|
| mlx-lm | T1 | 9 | 310ms | 10.77 | N/A | — |
| mlx-lm | T2 | 9 | 158ms | 2.92 | N/A | 1.96x |
| ollama | T1 | 9 | 133ms | 4.06 | 66.68 | — |
| ollama | T2 | 9 | 358ms | 18.55 | 66.52 | 0.37x |
| omlx | T1 | 9 | 87ms | 3.12 | N/A | — |
| omlx | T2 | 9 | 315ms | 14.74 | N/A | 0.28x |
