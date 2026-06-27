# JMeter Load Testing

**Source branch:** `refactoer-and-redy-to-module`
**Purpose:** document the realistic-traffic JMeter test plan used against the local environment, the baseline results, the cart-write bottleneck it exposed, and the index cleanup that followed.

## Why Load Test

The storefront read paths (homepage, product detail, search, store pages) are cache-backed and expected to scale easily. The cart write path is not: every `add-to-cart` call touches `carts`, `cart_items`, and `cart_item_selections` under a row lock, so it is the part of the system most likely to degrade under concurrency. The goal of this test plan was to validate that assumption with real numbers instead of guessing, and to find out which indexes on the cart tables were actually load-bearing versus pure write overhead.

## Test Plan

File: `load-testing/realistic-commerce-local-seed.jmx`

A single thread group (`Bun Commerce - load test`) drives a weighted traffic mix intended to resemble real storefront behavior rather than hammering one endpoint:

| Flow | Share | Endpoint |
| --- | --- | --- |
| Homepage | 35% | `GET /api/public/home` |
| Product Detail | 25% | `GET /api/public/products/{productId}` |
| Product Search | 18% | `GET /api/public/products/search` |
| Unified Search | 10% | `GET /api/public/search` |
| Store Pages | 7% | `GET /api/stores/{slug}` |
| Cart Session | 2.4% of sessions | add → optional view/reconcile/checkout |

The cart session branch fans out into a realistic sub-mix instead of one flat request:

- cart size: 80% add one product, 15% add two, 5% add three (`POST /api/cart/add`, cart id captured from the response for follow-up calls);
- follow-up: none, `GET /api/cart/my/cart/{cartId}`, `POST /api/cart/{cartId}/reconcile`, or `POST /api/customer/orders/from-cart/whatsapp`, at roughly 1% view / 0.7% reconcile / 0.3% checkout of all sessions.

Traffic is data-driven rather than fixed IDs: product and store IDs are read directly from the raw seed export (`product_definitions.csv`, `stores.csv`) so they always match whatever is actually loaded in the target database, while search keywords, devices, and cart sessions come from `load-testing/data/` (`search_keywords.csv`, `devices.csv`, `cart_sessions.csv` — local-seed has no equivalent for these). A 100–300ms think time runs between requests per thread. Threads, ramp-up, and loop count are externalized as JMeter properties (`threads`, `rampup`, `loops`, default 1000 / 60s / 100) so the same plan can be re-run at different scale without editing the test.

Every sampler asserts on HTTP 200 and valid JSON, so latency numbers below are all from successful requests — none of the runs produced a request error.

## Runs

Three runs against a locally seeded database, ~99,800 samples each:

| Run | Report | Cart indexes |
| --- | --- | --- |
| Baseline | `local-seed-report16` | pre-cleanup (5 indexes on `carts`/`cart_items`/`cart_item_selections`, several unused) |
| After cleanup, run 1 | `report-1000-sustained2` | post `V14`/`V15` migrations |
| After cleanup, run 2 | `report-1000-sustained4` | post `V14`/`V15` migrations |

### Read paths (cache-backed, as expected)

| Endpoint | Samples | Mean (ms) | p90 (ms) | Throughput (req/s) |
| --- | --- | --- | --- | --- |
| Homepage | 35,000 | 90–104 | 219–223 | 390–405 |
| Product Detail | 25,000 | 89–102 | 207–223 | 278–288 |
| Product Search | 18,000 | 94–166 | 199–396 | 203–211 |
| Unified Search | 10,000 | 143–227 | 282–506 | 112–116 |
| Store Page | 7,000 | 90–101 | 194–208 | 79–82 |

These hold steady across all three runs — the read model is not where the bottleneck lives.

### Cart write path (the bottleneck)

| Endpoint | Baseline mean (ms) | After cleanup mean (ms) | Improvement |
| --- | --- | --- | --- |
| `POST /api/cart/add` (1 product) | 1,257 | 502–640 | ~2–2.5x |
| `POST /api/cart/{cartId}/reconcile` | 839 | 416–490 | ~1.7–2x |
| `GET /api/cart/my/cart/{cartId}` | 411 | 273–325 | ~1.3–1.5x |
| `POST .../orders/from-cart/whatsapp` | 847 | 466–559 | ~1.5–1.8x |

Total throughput across all endpoints was unaffected (~1,100–1,150 req/s, 0 errors in every run) — the read paths absorbed the load fine throughout. The cart write path was the only place where index overhead showed up as latency.

## Root Cause: Redundant Indexes On A Write-Heavy Table

`carts`, `cart_items`, and `cart_item_selections` are updated on every `add-to-cart` call, inside a row lock (see [Cart Validation Engine](cart/03-validation-engine.md)). At baseline, that write path was maintaining indexes that no query actually read:

- `idx_cart_customer_open` on `carts` — fully subsumed by the composite index's leading column;
- `idx_cart_item_status`, `idx_cart_item_cart_status`, `idx_cart_item_cart_active` on `cart_items` — no query filters by status; `cart_id` alone already covers the FK-cascade and hot-path lookups;
- `idx_cart_item_selection_active` on `cart_item_selections` — an exact duplicate of `idx_cart_item_selection_cart_item`.

Each of these costs a B-tree maintenance write on every insert/update without paying for itself on any read.

## Fix

Two migrations, applied together:

- **`V14__unique_open_cart_index.sql`** — replaces the ad-hoc open-cart lookup index with a single unique partial index, `idx_cart_customer_store_open ON carts(customer_id, store_id) WHERE closed = false`. This both enforces "one open cart per customer per store" at the database level and serves as the one composite index the hot path needs.
- **`V15__drop_redundant_cart_indexes.sql`** — drops the five indexes listed above, keeping only FK-cascade-supporting indexes and the new composite index.

The result is the "after cleanup" column above: cart write latency dropped by roughly half with the same traffic shape, same hardware, same data volume, and zero request errors before and after.

## Reproducing

```bash
jmeter -n -t load-testing/realistic-commerce-local-seed.jmx \
  -Jthreads=1000 -Jrampup=60 -Jloops=100 \
  -l load-testing/result.jtl -e -o load-testing/report
```

Product/store IDs come from `product_definitions.csv` and `stores.csv` in the application's seed export; search keywords, devices, and cart sessions come from `load-testing/data/`. The `.jmx`'s `localSeedDir` property defaults to `../src/main/resources/db/local-seed` (the private application source tree); in this docs-only snapshot the same two files are published flat under `load-testing/local-seed/` instead, alongside the `.jmx`, the three raw `.jtl` logs, and the `statistics.json` for each run — so the numbers above can be checked against the actual per-request log rather than taken on faith. The generated HTML dashboards are not included since they add no signal beyond `statistics.json`.

## Verification

The numbers above are not hand-typed estimates — they come from JMeter's own per-sample log, cross-checked against the seed data:

- each run's raw `.jtl` file contains exactly 99,800 sample rows with real Unix timestamps, per-thread names, and request URLs, matching `statistics.json`'s `sampleCount` for that run exactly;
- every row in every run has `success=true` and HTTP `200`, matching the `errorCount: 0` reported for every transaction;
- request URLs reference real seeded entity IDs (e.g. `/api/public/products/2399`, `/api/public/products/402`, `/api/public/products/1899`) that resolve back to matching rows — same ID, same store — in `product_definitions.csv`, the exact file the `.jmx`'s "Local Seed Products CSV" element reads, confirming traffic was driven by the actual seed dataset rather than fixed/fake IDs;
- `product_definitions.csv` and `stores.csv` are full exports of the seeded catalog (7,201 products), not a handful of fixtures.

## Takeaways

- Read paths (homepage, product detail, search, store pages) scaled linearly with no tuning — the cache-backed read model held up under the same load that exposed the cart bottleneck.
- The cart write path is the one place in the system where index choice directly shows up in p50/p90 latency, because every cart mutation runs under a row lock.
- "Add an index" is not free on a write-heavy table — auditing which indexes are actually used and dropping the rest was a bigger win than any code-level optimization would have been here.
- Load testing against realistic, weighted traffic (rather than a single hammered endpoint) was what surfaced this — a flat add-to-cart benchmark would have shown the same regression, but the weighted mix confirmed it wasn't drowning out the read paths.
