# RUN 结果汇总

> ⚠️ 部分数据的 token 计数为估算值（token_source: estimated），decode_tok_s 等指标可能存在偏差。


## A1-single-short

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 1573ms | N/A | N/A | 2688ms | 19239MB |
| ollama |  | 9 | 133ms | 66.09 | 0.29 | 1662ms | 21504MB |
| omlx |  | 9 | 87ms | N/A | N/A | 1795ms | 21697MB |

## A2-single-code

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 1624ms | N/A | N/A | 12941ms | 19236MB |
| ollama |  | 9 | 199ms | 66.1 | 0.27 | 15699ms | 21504MB |
| omlx |  | 9 | 140ms | N/A | N/A | 16109ms | 21157MB |

## A3-single-long

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| mlx-lm |  | 9 | 2806ms | N/A | N/A | 4199ms | 19240MB |
| ollama |  | 9 | 1455ms | 65.46 | 0.3 | 3282ms | 21504MB |
| omlx |  | 9 | 1317ms | N/A | N/A | 3078ms | 21155MB |

## E1-gemma4-cross

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| ollama |  | 9 | 316ms | 46.66 | 0.65 | 2512ms | 23552MB |
| omlx |  | 9 | 116ms | N/A | N/A | 1706ms | 18828MB |

## E2-gemma4-long

| Provider | Prompt | Rounds | TTFT (median) | tok/s (median) | tok/s (stdev) | 总耗时 (median) | 峰值内存 |
|----------|--------|--------|--------------|---------------|--------------|----------------|---------|
| ollama |  | 9 | 2655ms | 40.68 | 1.4 | 7659ms | 23552MB |
| omlx |  | 9 | 408ms | N/A | N/A | 3740ms | 18491MB |

## B1-multi-turn — 多轮缓存分析

| Provider | Turn | Rounds | TTFT (median) | TTFT stdev | tok/s (median) | Cache Speedup |
|----------|------|--------|--------------|-----------|---------------|--------------|
| mlx-lm | T1 | 9 | 1662ms | 49.13 | N/A | — |
| mlx-lm | T2 | 9 | 420ms | 7.3 | N/A | 3.96x |
| ollama | T1 | 9 | 133ms | 3.91 | 66.29 | — |
| ollama | T2 | 9 | 356ms | 6.19 | 66.3 | 0.37x |
| omlx | T1 | 9 | 89ms | 3.61 | N/A | — |
| omlx | T2 | 9 | 304ms | 17.6 | N/A | 0.29x |
