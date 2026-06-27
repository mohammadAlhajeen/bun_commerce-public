# JMeter Load Testing

**Source branch:** `refactoer-and-redy-to-module`
**Tooling:** Apache JMeter 5.6.3, PostgreSQL, Spring Boot, run on a local developer machine (not isolated benchmark hardware — absolute numbers are indicative, not a production SLA).
**Purpose:** document the realistic-traffic JMeter test plan used against the local environment, the full results of three runs, the cart-write latency this surfaced, every change made between runs, and — explicitly — what can and cannot be concluded from the data as it currently exists.

## Executive Summary

Three 99,800-sample runs of a weighted, realistic traffic mix against a 7,201-product seeded catalog produced zero request errors and stable read-path latency throughout. Cart write endpoints (`add-to-cart`, `reconcile`, `cart view`, `WhatsApp checkout`) were 2–3x slower than the read paths in every run, consistent with them being the only endpoints that mutate `carts`/`cart_items`/`cart_item_selections` under a row lock. Between the first run and the next two, two independent changes landed at the same time: a cart-table index cleanup (`V14`/`V15` migrations) and disabling SQL/format logging plus `open-in-view`. Cart write latency dropped by roughly half across that boundary. **This setup cannot cleanly isolate which change caused the improvement** — see [What Changed Between Runs](#what-changed-between-runs) and [What This Does And Does Not Prove](#what-this-does-and-does-not-prove). A controlled re-test (one variable at a time) would be required to attribute the improvement to a specific cause.

## Why Load Test

The storefront read paths (homepage, product detail, search, store pages) are cache-backed and expected to scale easily. The cart write path is not: every `add-to-cart` call touches `carts`, `cart_items`, and `cart_item_selections` under a row lock, so it is the part of the system most likely to degrade under concurrency. The goal of this test plan was to check that assumption with real numbers instead of guessing.

## Test Plan

File: `load-testing/realistic-commerce-local-seed.jmx` (JMeter 5.6.3 format).

A single thread group (`Bun Commerce - load test`) drives a weighted traffic mix intended to resemble real storefront behavior rather than hammering one endpoint. Thread count, ramp-up time, and loop count are externalized as JMeter properties (`threads`, `rampup`, `loops`; defaults 1000 / 60s / 100), so the same plan can be re-run at different scale without editing the test. A 100–300ms think time runs between requests per thread. Every sampler carries a response assertion (HTTP 200) and a JSON-syntax assertion.

### Traffic mix

| Flow | Share | Endpoint |
| --- | --- | --- |
| Homepage | 35% | `GET /api/public/home` |
| Product Detail | 25% | `GET /api/public/products/{productId}` |
| Product Search | 18% | `GET /api/public/products/search?q={keyword}&page=0&size=S` |
| Unified Search | 10% | `GET /api/public/search?q={keyword}&page=0&size=12` |
| Store Pages | 7% | `GET /api/stores/{storeSlug}?page=0&size=24&sort=newest` |
| Cart Session | 2.4% of sessions | add → optional view/reconcile/checkout |

The cart session branch fans out into a realistic sub-mix instead of one flat request:

- **cart size**: 80% add one product, 15% add two, 5% add three — each `POST /api/cart/add`, with the resulting `cartId` extracted from the response (regex post-processor) for follow-up calls;
- **follow-up**, applied per session after the add(s) complete: none, `GET /api/cart/my/cart/{cartId}`, `POST /api/cart/{cartId}/reconcile`, or `POST /api/customer/orders/from-cart/whatsapp` — roughly 1% view / 0.7% reconcile / 0.3% checkout of *all* sessions (not just cart sessions).

### Data sources

Traffic is data-driven rather than fixed IDs:

| CSV | Drives | Columns used |
| --- | --- | --- |
| `product_definitions.csv` (raw seed export) | product detail / search target IDs | `productId`, `productStoreId`, … (17 columns from the seed table, only a few read) |
| `stores.csv` (raw seed export) | store-page slugs | `storeId`, `storeSlug`, … |
| `load-testing/data/search_keywords.csv` | Product/Unified Search `q=` | keyword list |
| `load-testing/data/cart_sessions.csv` | which sessions run a cart flow at all | session weighting |
| `load-testing/data/devices.csv` | device header on cart requests | device ids |

Per the `.jmx`'s own `TestPlan.comments`: products/stores are read **directly from the raw DB seed export** so IDs always match whatever is actually loaded in the target database — this test plan deliberately does not use the curated `weighted_products.csv` / `weighted_stores.csv` / `variants.csv` files that a sibling plan (`production-realistic-commerce.jmx`, not included here) uses; local-seed has no equivalent for cart sessions/devices/keywords, which is why those three still come from `load-testing/data/`.

## Runs

Three runs, same `.jmx`, same property values (`threads=1000`, `rampup=60`, `loops=100`), same seeded catalog, 99,800 samples each, **zero request errors in all three**:

| Run | Report | When | DB/app state |
| --- | --- | --- | --- |
| Baseline | `local-seed-report16` | 2026-06-25 18:18 | original 5 indexes on `carts`/`cart_items`/`cart_item_selections`; SQL logging on; `open-in-view=true` |
| After, run 1 | `report-1000-sustained2` | 2026-06-26 01:36 | `V14`/`V15` applied; SQL logging off; `open-in-view=false` |
| After, run 2 | `report-1000-sustained4` | 2026-06-26 02:10 | same as run 1 |

### Full per-endpoint results

Mean / median / p90 / p95 / p99 in ms, throughput in req/s:

**Baseline (`local-seed-report16`)**

| Endpoint | Samples | Mean | Median | p90 | p95 | p99 | Throughput |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GET Homepage | 35,000 | 104.2 | 77.0 | 219.0 | 301.0 | 1186.0 | 390.9 |
| GET Product Detail | 25,000 | 101.8 | 83.0 | 223.0 | 299.0 | 1027.0 | 278.6 |
| GET Product Search | 18,000 | 166.0 | 97.0 | 396.0 | 635.0 | 1138.0 | 202.1 |
| GET Unified Search | 10,000 | 226.7 | 170.0 | 506.0 | 704.0 | 1230.0 | 112.0 |
| GET Store Page | 7,000 | 100.7 | 63.0 | 203.0 | 267.0 | 866.0 | 79.1 |
| POST Add To Cart 1 Product | 1,886 | 1256.9 | 1151.0 | 2552.3 | 3099.3 | 4083.4 | 21.6 |
| POST Add To Cart Product 1 (of 2/3) | 390 | 1335.5 | 1215.0 | 2598.9 | 3266.3 | 3994.7 | 4.7 |
| POST Add To Cart Product 2 (of 2/3) | 124 | 1262.7 | 1157.5 | 2532.0 | 3320.8 | 4072.0 | 1.5 |
| GET Cart View | 1,320 | 410.5 | 331.5 | 902.8 | 1059.9 | 1421.9 | 15.1 |
| POST Cart Reconcile | 739 | 838.8 | 725.0 | 1712.0 | 2211.0 | 3165.2 | 8.7 |
| POST WhatsApp Checkout From Cart | 341 | 847.0 | 834.0 | 1652.0 | 1818.8 | 2163.7 | 4.1 |
| **Total** | **99,800** | **166.8** | 21.0 | 117.0 | 162.0 | 595.0 | **1111.3** |

**After, run 1 (`report-1000-sustained2`)**

| Endpoint | Samples | Mean | Median | p90 | p95 | p99 | Throughput |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GET Homepage | 35,000 | 90.6 | 74.0 | 220.0 | 286.0 | 836.0 | 405.1 |
| GET Product Detail | 25,000 | 89.1 | 73.0 | 207.0 | 272.0 | 868.0 | 288.3 |
| GET Product Search | 18,000 | 94.4 | 56.0 | 199.0 | 265.0 | 853.0 | 210.7 |
| GET Unified Search | 10,000 | 143.0 | 113.0 | 282.0 | 365.0 | 851.0 | 116.4 |
| GET Store Page | 7,000 | 90.4 | 53.0 | 194.9 | 245.0 | 822.0 | 82.4 |
| POST Add To Cart 1 Product | 1,934 | 501.9 | 464.0 | 1002.0 | 1185.0 | 1537.6 | 23.2 |
| POST Add To Cart Product 1 (of 2/3) | 360 | 495.0 | 475.5 | 1002.1 | 1152.6 | 1545.1 | 4.5 |
| POST Add To Cart Product 2 (of 2/3) | 106 | 511.9 | 447.5 | 1010.5 | 1215.6 | 1690.0 | 1.4 |
| GET Cart View | 1,298 | 272.8 | 233.0 | 566.1 | 759.2 | 1112.1 | 15.7 |
| POST Cart Reconcile | 731 | 415.6 | 358.0 | 886.8 | 1048.8 | 1445.2 | 8.9 |
| POST WhatsApp Checkout From Cart | 371 | 465.5 | 414.0 | 913.2 | 1230.2 | 1551.1 | 4.7 |
| **Total** | **99,800** | **112.2** | 11.0 | 75.0 | 110.0 | 375.0 | **1151.0** |

**After, run 2 (`report-1000-sustained4`)**

| Endpoint | Samples | Mean | Median | p90 | p95 | p99 | Throughput |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GET Homepage | 35,000 | 97.8 | 101.0 | 223.0 | 254.0 | 650.0 | 394.1 |
| GET Product Detail | 25,000 | 97.2 | 98.0 | 218.0 | 248.0 | 689.0 | 281.2 |
| GET Product Search | 18,000 | 104.1 | 70.0 | 215.0 | 249.0 | 647.0 | 203.6 |
| GET Unified Search | 10,000 | 167.3 | 152.0 | 309.0 | 382.0 | 693.0 | 113.4 |
| GET Store Page | 7,000 | 99.1 | 67.0 | 208.0 | 240.0 | 580.0 | 79.8 |
| POST Add To Cart 1 Product | 1,899 | 639.6 | 544.0 | 1278.0 | 1425.0 | 1933.0 | 22.5 |
| POST Add To Cart Product 1 (of 2/3) | 380 | 628.0 | 510.5 | 1298.1 | 1477.5 | 2094.0 | 4.7 |
| POST Add To Cart Product 2 (of 2/3) | 121 | 563.1 | 486.0 | 1241.2 | 1324.6 | 2489.2 | 1.4 |
| GET Cart View | 1,278 | 325.3 | 282.0 | 691.1 | 854.2 | 1070.6 | 15.0 |
| POST Cart Reconcile | 761 | 490.0 | 411.0 | 1035.0 | 1184.8 | 1649.3 | 9.0 |
| POST WhatsApp Checkout From Cart | 361 | 558.8 | 488.0 | 1184.4 | 1291.4 | 1634.0 | 4.3 |
| **Total** | **99,800** | **126.3** | 21.0 | 123.0 | 152.0 | 544.0 | **1121.5** |

### Observations

- **Read paths are flat across all three runs** (homepage/product-detail/search/store-page means all sit within ~90–230ms regardless of run) — the cache-backed read model absorbed identical load before and after, with no measurable regression or improvement either way.
- **Cart write endpoints moved together**: every cart-touching endpoint (`add`, `view`, `reconcile`, `whatsapp checkout`) dropped by roughly the same proportion between baseline and the two after-runs, which is consistent with a shared bottleneck (e.g. connection contention or lock wait) rather than per-endpoint logic changes.
- **Total throughput barely moved** (1111 → 1151 → 1121 req/s) — the system wasn't saturated in any run; the difference shows up in *latency*, not in how much traffic it could absorb.
- Run 1 and run 2 ("after") differ slightly from each other (e.g. add-to-cart mean 502ms vs 640ms) despite identical config — that spread is a useful sanity check on run-to-run noise on this hardware, and it's roughly a third of the baseline-to-after gap, so the baseline-to-after difference is not just noise.

## What Changed Between Runs

This is the part that matters for honesty about what the numbers prove. Reconstructing the timeline from file modification times and commit history (everything ended up bundled into one later commit, `164369b "add load testing"`, made on 2026-06-28 — after all three runs had already been captured, so git history alone can't disambiguate "what was running when"; mtimes are the best available evidence):

| When | Change |
| --- | --- |
| 2026-06-22 23:26 | `V14__unique_open_cart_index.sql` written |
| 2026-06-25 18:18 | **Baseline run** |
| 2026-06-26 00:14 | `V15__drop_redundant_cart_indexes.sql` written |
| 2026-06-26 01:28 | `application-local.properties` edited: `spring.jpa.show-sql`/`format_sql`/`use_sql_comments` true → false, `spring.jpa.open-in-view` true → false |
| 2026-06-26 01:36 | **After run 1** |
| 2026-06-26 02:10 | **After run 2** |

Two independent changes landed in the window between the baseline run and the two after-runs:

1. **Index cleanup** ([details below](#root-cause-candidate-redundant-indexes-on-a-write-heavy-table)) — drops 5 indexes that cost a write on every cart mutation without serving any read.
2. **SQL/format logging and `open-in-view` disabled** — removes Hibernate's per-statement logging/formatting overhead and changes transaction/session-boundary behavior (`open-in-view=false` closes the Hibernate session at the controller boundary instead of holding it open through view rendering). A plausible, smaller contributor to latency under load on top of the index change.

Cart code itself (`Cart.java`, `CartRepository.java`, `CartService.java`, `CartValidationService.java`) also differs between the committed baseline tag and the final committed state — but those files' last-modified timestamps (2026-06-21 to 2026-06-24) predate the baseline run (06-25 18:18), so on the mtime evidence available, the cart-code changes were already present for *all three* runs and are not a confound between baseline and after. This can't be confirmed with certainty (mtimes reflect last edit, not which build was deployed for each run), but it's the best evidence available.

## Root Cause Candidate: Redundant Indexes On A Write-Heavy Table

Independent of whether they're the dominant cause of the measured latency drop, these indexes are a legitimate finding: `carts`, `cart_items`, and `cart_item_selections` are updated on every `add-to-cart` call, inside a row lock (see [Cart Validation Engine](cart/03-validation-engine.md)). The baseline schema maintained five indexes that no query actually read:

- `idx_cart_customer_open` on `carts` — fully subsumed by the composite index's leading column;
- `idx_cart_item_status`, `idx_cart_item_cart_status`, `idx_cart_item_cart_active` on `cart_items` — no query filters by status; `cart_id` alone already covers the FK-cascade and hot-path lookups;
- `idx_cart_item_selection_active` on `cart_item_selections` — an exact duplicate of `idx_cart_item_selection_cart_item`.

Each of these costs a B-tree maintenance write on every insert/update without paying for itself on any read. Dropping unused indexes on a write-heavy table is correct regardless of how much of the measured latency drop it's actually responsible for.

### The fix

Two migrations, applied together:

- **`V14__unique_open_cart_index.sql`** — replaces the ad-hoc open-cart lookup index with a single unique partial index, `idx_cart_customer_store_open ON carts(customer_id, store_id) WHERE closed = false`. This both enforces "one open cart per customer per store" at the database level and serves as the one composite index the hot path needs.
- **`V15__drop_redundant_cart_indexes.sql`** — drops the five indexes listed above, keeping only FK-cascade-supporting indexes and the new composite index.

## What This Does And Does Not Prove

**Does show, with reasonable confidence:**

- the cart write path (`add`, `view`, `reconcile`, `checkout`) is meaningfully slower than the cache-backed read paths under load, by design (row locks, no caching) — true in every run regardless of the confound;
- the system handled ~1,100–1,150 req/s sustained with zero errors across 299,400 logged requests (3 runs × 99,800 samples), in every configuration tested;
- dropping the five unused indexes is a correct, low-risk change on its own engineering merits (no query plan depends on them).

**Does not show:**

- that the index cleanup specifically, in isolation, caused the ~2x latency improvement on cart endpoints. The SQL-logging/`open-in-view` change landed in the same window and is a real, if likely smaller, contributor. The current data cannot fully separate the two effects.

**To actually attribute the improvement**, a controlled re-test is needed: hold the logging/session settings fixed at the "after" values, and toggle only the indexes (drop V14/V15's effect, rerun, reapply, rerun). That test has not been run yet. Until it is, claims about this load test should describe the *combined* effect of the index cleanup and the logging/session change, not credit the index migration alone.

## Verification

The numbers above are not hand-typed estimates — they come from JMeter's own per-sample log, cross-checked against the seed data:

- each run's raw `.jtl` file contains exactly 99,800 sample rows with real Unix timestamps, per-thread names, and request URLs, matching `statistics.json`'s `sampleCount` for that run exactly;
- every row in every run has `success=true` and HTTP `200`, matching the `errorCount: 0` reported for every transaction;
- request URLs reference real seeded entity IDs (e.g. `/api/public/products/2399`, `/api/public/products/402`, `/api/public/products/1899`) that resolve back to matching rows — same ID, same store — in `product_definitions.csv`, the exact file the `.jmx`'s "Local Seed Products CSV" element reads, confirming traffic was driven by the actual seed dataset rather than fixed/fake IDs;
- `product_definitions.csv` and `stores.csv` are full exports of the seeded catalog (7,201 products), not a handful of fixtures.

## Reproducing

```bash
jmeter -n -t load-testing/realistic-commerce-local-seed.jmx \
  -Jthreads=1000 -Jrampup=60 -Jloops=100 \
  -l load-testing/result.jtl -e -o load-testing/report
```

Product/store IDs come from `product_definitions.csv` and `stores.csv` in the application's seed export; search keywords, devices, and cart sessions come from `load-testing/data/`. The `.jmx`'s `localSeedDir` property defaults to `../src/main/resources/db/local-seed` (the private application source tree); in this docs-only snapshot the same two files are published flat under `load-testing/local-seed/` instead, alongside the `.jmx`, the three raw `.jtl` logs, and the `statistics.json` for each run — so the numbers above can be checked against the actual per-request log rather than taken on faith. The generated HTML dashboards are not included since they add no signal beyond `statistics.json`.

## Limitations And Future Work

- **No controlled A/B.** As covered above, this is the single biggest gap — re-run with one variable isolated at a time (indexes only, logging/session settings only) to get a defensible attribution.
- **Single machine, not isolated hardware.** JMeter and the application under test ran on the same developer machine; JMeter's own CPU/thread usage can compete with the server under test. A dedicated load generator would remove that noise.
- **No DB-side instrumentation.** `pg_stat_statements` / `EXPLAIN (ANALYZE, BUFFERS)` on the cart write queries, or connection-pool wait metrics, during each run would directly show whether the bottleneck was lock contention, index maintenance, or connection queueing — instead of inferring it from endpoint latency alone.
- **Ramp-up and steady-state aren't separated in the published stats.** `statistics.json` aggregates the whole run; a time-series view (the `.jtl` has per-sample timestamps) would show whether latency was driven by the ramp-up window specifically.

## Takeaways

- Read paths (homepage, product detail, search, store pages) held flat under load regardless of configuration — the cache-backed read model is not where this system's risk lives.
- The cart write path is the one place where backend configuration visibly shows up in p50/p95 latency, because every cart mutation runs under a row lock and touches the database directly.
- Changing more than one variable between "before" and "after" measurements — even with good intentions — destroys the ability to attribute the result to any one of them. That's a process lesson as much as a performance one.
- Dropping indexes that no query plan uses is correct on its own merits for a write-heavy table, independent of how much of the measured latency drop is actually attributable to it.
