# Cart Index Benchmark Summary

Generated from direct PostgreSQL benchmark CSV output.

## Read Latency

| Rows | Scenario | Before avg ms/op | After avg ms/op | Delta |
| --- | --- | --- | --- | --- |
| 10,000 | Open cart by customer/store | 0.046 | 0.041 | -11.2% |
| 10,000 | Open carts by customer | 0.041 | 0.036 | -12.2% |
| 10,000 | Cart with items | 0.106 | 0.077 | -27.1% |
| 10,000 | Cart items by cart | 0.040 | 0.031 | -23.3% |
| 50,000 | Open cart by customer/store | 0.090 | 0.079 | -12.4% |
| 50,000 | Open carts by customer | 0.078 | 0.073 | -6.1% |
| 50,000 | Cart with items | 0.148 | 0.123 | -16.7% |
| 50,000 | Cart items by cart | 0.079 | 0.054 | -31.9% |
| 100,000 | Open cart by customer/store | 0.130 | 0.079 | -39.1% |
| 100,000 | Open carts by customer | 0.070 | 0.047 | -32.3% |
| 100,000 | Cart with items | 0.156 | 0.143 | -8.1% |
| 100,000 | Cart items by cart | 0.052 | 0.047 | -10.7% |

## Write Latency

| Rows | Scenario | Before total ms | After total ms | Delta |
| --- | --- | --- | --- | --- |
| 10,000 | Insert 1k cart items | 20.001 | 15.584 | -22.1% |
| 10,000 | Update 1k item statuses | 27.364 | 19.583 | -28.4% |
| 10,000 | Close 1k carts | 18.445 | 19.346 | +4.9% |
| 10,000 | Insert 1k selections | 12.687 | 11.935 | -5.9% |
| 50,000 | Insert 1k cart items | 38.053 | 19.153 | -49.7% |
| 50,000 | Update 1k item statuses | 56.971 | 49.806 | -12.6% |
| 50,000 | Close 1k carts | 50.207 | 26.108 | -48.0% |
| 50,000 | Insert 1k selections | 23.149 | 15.231 | -34.2% |
| 100,000 | Insert 1k cart items | 32.208 | 19.920 | -38.2% |
| 100,000 | Update 1k item statuses | 65.712 | 49.024 | -25.4% |
| 100,000 | Close 1k carts | 44.042 | 39.648 | -10.0% |
| 100,000 | Insert 1k selections | 32.858 | 16.367 | -50.2% |

## Index Size

| Rows | Before MB | After MB | Delta |
| --- | --- | --- | --- |
| 10,000 | 3.336 | 2.336 | -30.0% |
| 50,000 | 18.258 | 12.516 | -31.5% |
| 100,000 | 44.820 | 33.125 | -26.1% |
