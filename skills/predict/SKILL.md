---
name: predict
description: >-
  Trade prediction markets on hermestrade.xyz with the predict-cli binary:
  install the CLI, set up a wallet and L2 API key, discover
  markets, read orderbooks, place and cancel limit/market orders, track positions
  and PnL, split/merge/redeem conditional tokens, and stream live WebSocket
  updates. Use this skill whenever the user mentions predict-cli, predict-rs,
  hermestrade, prediction markets, outcome shares, YES/NO tokens,
  CLOB orders, or conditional tokens (CTF) — even if they don't name the tool
  explicitly, and even for read-only questions like "what's the midpoint" or
  "show my positions".
---

# Trading prediction markets with predict-cli

`predict-cli` is the terminal client for the HermesTrade prediction-market
CLOB exchange.
Every command supports `-o json` for machine-readable output — prefer it when you
need to parse results (pipe to `jq`).

## 0. Get the CLI

Run `scripts/ensure-cli.sh` first. It is idempotent: if `predict-cli` is already
on PATH it does nothing; otherwise it installs the latest release via the
official installer (which verifies the sha256 checksum before installing):

```bash
curl -sSfL https://raw.githubusercontent.com/chainupcloud/predict-rs/main/install.sh | sh
```

If you are working inside a `predict-rs` checkout, `cargo build --release` and
`target/release/predict-cli` works too.

## 1. Connect to HermesTrade

Every command targets **hermestrade.xyz**. Export it once as the default and each
command — and the helper scripts — pick it up; the CLI derives the CLOB / Gamma /
WebSocket endpoints from the host automatically (`clob-api.hermestrade.xyz`,
`gamma-api.hermestrade.xyz`, `wss://clob-ws.hermestrade.xyz`):

```bash
export PM_TENANT=hermestrade.xyz   # default target for the session

predict-cli ok          # health check
predict-cli endpoints   # show the resolved URLs + chain id
```

`PM_TENANT` backs the global `--tenant` flag, so once it's exported you never repeat it;
a one-off `predict-cli --tenant hermestrade.xyz <cmd>` is the equivalent when you haven't.

## 2. Wallet & auth (one-time)

For first-time setup prefer the guided wizard — it walks through wallet, Safe
detection, and L2 API-key creation in one pass (it reads the target host from
`PM_TENANT`):

```bash
predict-cli setup
```

Manual equivalent:

```bash
predict-cli wallet create                 # fresh EOA, stored 0600 in <config-dir>/config.toml
predict-cli wallet import 0xYOURKEY       # or import an existing key
predict-cli auth create-key               # L2 API key (or derive-key to recover an existing one)
predict-cli wallet set-safe 0xSAFE        # persist the funded Safe address
predict-cli wallet show                   # address + Safe + signature type + config source
```

> **Careful with `wallet detect-safe`.** It reads the server's `proxy_wallet`
> field and **unconditionally overwrites** the stored Safe address — there is no
> check against what's already configured. Verify the result before trading: the
> address should hold the USDW balance (`balance --asset-type collateral`) and
> have contract code deployed. When in doubt, `wallet set-safe` the known-funded
> address instead.

Key facts that prevent confusion later:

- **Default signature type is `gnosis-safe`**: the EOA only signs; a 1-of-1
  Safe holds the USDW and outcome tokens and is the order `maker`. Balances and
  positions belong to the **Safe address**, not the EOA.
- Config lives in `~/.config/pm/config.toml` (Linux) or
  `~/Library/Application Support/pm` (macOS).
- Prefer `PM_PRIVATE_KEY` env over `--private-key` — flags leak into shell history.

Before a trading session, sanity-check with `predict-cli ok`,
`predict-cli wallet show`, and `predict-cli balance --asset-type collateral`.

## 3. Safety rules (real funds)

Orders and CTF operations move real money. Hold to these:

- **Confirm before committing funds.** Before any `order create` / `order market`
  / `ctf … --execute` / `approve set --execute`, state the market, side, price,
  size, and resulting notional, and get the operator's explicit go-ahead —
  unless they have already given you a standing budget and instruction.
- **Dry-run first on new flows.** `order create --dry-run` prints the signed
  envelope without posting; `ctf`/`approve` writes default to dry-run and only
  submit with `--execute`. Inspect, then re-run for real.
- **Never print private keys.** `wallet show` is safe (it never echoes the key);
  `config.toml` contents are not — don't cat it.
- **Stay inside any budget the operator set**, and stop and report rather than
  retry when a money-moving call fails in an unexpected way.

## 4. Discover markets

```bash
predict-cli gamma search "fed rate cuts" --limit-per-type 5
predict-cli gamma events list --limit 10
predict-cli gamma events get <slug>                 # e.g. how-many-fed-rate-cuts-in-2026-pm-406282
predict-cli gamma markets get <slug-or-condition-id>
```

From a market object you need two identifiers:

- `conditionId` (`0x…` hex) — keys the market for `order cancel-market`,
  `ws user --market`, and CTF operations.
- `clobTokenIds` — the YES/NO outcome token ids (uint256 decimals). Orders,
  books, and prices are all per **token id**.

## 5. Read the market

Pull these before quoting a price:

```bash
predict-cli tick-size <TOKEN_ID>     # price granularity — orders must respect it
predict-cli fee-rate <TOKEN_ID>      # feeRateBps — required on every order
predict-cli midpoint <TOKEN_ID>
predict-cli book <TOKEN_ID>
predict-cli price <TOKEN_ID> --side buy
```

Batch variants take comma-separated ids: `midpoints` / `spreads` / `last-trades`
take bare ids (`last-trades` is capped at 500); `prices` / `books` take
`<id>:<side>` entries, e.g. `predict-cli prices 123:buy 456:sell`.

## 6. Place orders

Signing an order needs the EOA key, the chain id, and the **exchange the market
settles on** — all three are baked into the EIP-712 signature. `setup` already
stored your key and chain id (Monad, `143`); the one thing it does *not* store is
the exchange address, which you must set yourself:

```bash
export PM_EXCHANGE_ADDRESS=0x017641abFa4264121237023f9Fe678BF00F60De8   # CTF Exchange
```

**`PM_EXCHANGE_ADDRESS` is mandatory.** Order signing aborts before posting with
`exchange address required for sign_order` if it is unset, and it must match the
market type:

- **Binary (YES/NO) markets → CTF Exchange** `0x017641abFa4264121237023f9Fe678BF00F60De8`
- **Sports / multi-outcome families → Neg Risk CTF Exchange** `0x50b7B00EE75F8bFb5cDa892883aFb3867851c738`

Picking the wrong one is rejected server-side with
`EXECUTION_ERROR: INVALID_SIGNATURE: signer mismatch` — swap to the other address
(per-invocation override: `--exchange-address <addr>`). Both addresses come from
the `contracts` block of `examples/networks/monad-hermestrade.yaml` in predict-rs,
or `predict-cli gamma public-info`.

Always fetch `fee-rate` and `tick-size` for the token first; the server rejects
orders that miss the fee or violate price granularity (the CLI does not check tick
decimals locally). Limit order — default Safe mode, so `--maker` is **required**
and is the Safe address from `wallet show` (it is *not* auto-filled from config):

```bash
predict-cli order create \
  --token <TOKEN_ID> --side buy --price 0.34 --size 100 \
  --fee-rate-bps <FROM_FEE_RATE> \
  --maker <SAFE_ADDRESS> \
  --dry-run          # drop after inspecting the envelope
```

Market order (FAK by default; `--amount` is USDC notional, BUY only; `--size` is
share-denominated). A market order **still needs `--price`** — the limit/anchor the
signed amounts are pinned to:

```bash
predict-cli order market --token <TOKEN_ID> --side buy --amount 25 --price 0.34 \
  --fee-rate-bps <BPS> --maker <SAFE_ADDRESS>
```

Rules the exchange enforces:

- `price` ∈ (0, 1), decimals capped by tick size (tick 0.01 → 2 dp, 0.001 → 3 dp,
  0.0001 → 4 dp), enforced **server-side**. `size` max 2 decimals; amounts
  floor-truncate to 6 decimals.
- Per-event **minimum order size** — a too-small order is rejected server-side.
- Order types: `gtc` (default limit), `gtd` (requires `--expiration` unix-seconds),
  `fok` / `fak` (market). `--post-only` makes a limit order maker-only.
- EOA mode (`--signature-type eoa`): `--maker` defaults to the signer address.

Cancel / inspect:

```bash
predict-cli order list                       # open orders
predict-cli order get <ORDER_ID>
predict-cli order cancel <ORDER_ID>
predict-cli order cancel-many id1,id2,id3    # ≤ 3000
predict-cli order cancel-market --market 0xCONDITION_ID   # and/or --asset-id <TOKEN_ID>
predict-cli order cancel-all                 # everything for the API key — confirm first
predict-cli order replace --cancel id1 --orders-file new.json   # new.json from --dry-run output
predict-cli order post-batch …               # ≤ 15 orders, shared side/fee/maker
```

## 7. Track fills and balances

```bash
predict-cli trade --asset-id <TOKEN_ID> --limit 50   # trade history (L2-auth)
predict-cli balance --asset-type collateral          # USDW
predict-cli balance --asset-type conditional --token <TOKEN_ID>
```

(`balance --update` forces a subgraph refresh; plain `balance` returns the cached
value. Cross-check on-chain when a balance is load-bearing.)

On `/ws/user` (and in `trade` output) the trade `status` field takes the uppercase
values `MATCHED` / `MINED` / `CONFIRMED` / `RETRYING` / `FAILED` (the `TradeStatus`
enum). Treat a fill as final only at `CONFIRMED`; `MATCHED` means the engine matched
it but settlement is still pending. The `match_type` field is `MATCH` (bilateral
fill), `MINT` (mints the complementary token — neg-risk maker side), or `MERGE`
(burns a complementary pair). Per the fee formula in `docs/orders.md`, BUY fees are
charged **in outcome tokens** (you receive slightly fewer shares than `size`) and
SELL fees in USDC. `data activity` rows carry an `activity_type` of `TRADE` /
`SPLIT` / `MERGE` / `REDEEM` / `REWARD` / `CONVERSION`.

## 8. Positions & PnL

The Data API is keyed by **wallet address — use the Safe address**:

```bash
predict-cli data positions <SAFE_ADDRESS>
predict-cli data closed-positions <SAFE_ADDRESS>
predict-cli data trades <SAFE_ADDRESS>
predict-cli data activity <SAFE_ADDRESS>     # trades + splits + merges + redeems
predict-cli data user-pnl <SAFE_ADDRESS>
```

## 9. CTF operations (split / merge / redeem)

On-chain writes go through the relayer as Safe meta-transactions, so they require
the default `gnosis-safe` signature type plus a Safe address (`wallet set-safe`),
and a network-config YAML — use `examples/networks/monad-hermestrade.yaml` from
predict-rs (it carries chain id, RPC, the relayer endpoint, and contract
addresses). All writes default to **dry-run**:

```bash
# One-time prerequisite: USDW allowance + CTF setApprovalForAll.
# Pass --address <SAFE>: the EOA holds nothing, so its allowance is always zero.
predict-cli approve check --network-config <yaml> --address <SAFE_ADDRESS>
predict-cli approve set   --network-config <yaml> --execute

# --amount is RAW 6-decimal units: 1000000 = 1 USDW. Run without --execute
# first and read back the dry-run plan's amount before submitting.
predict-cli ctf split  --network-config <yaml> --condition-id 0x… --partition 1,2 --amount 1000000 --execute
predict-cli ctf merge  --network-config <yaml> --condition-id 0x… --partition 1,2 --amount 1000000 --execute
predict-cli ctf redeem --network-config <yaml> --condition-id 0x… --index-sets 1,2 --execute   # only after resolution
```

For **neg-risk** markets the write target is the Neg Risk Adapter, not the default
ConditionalTokens contract — pass `--contract <neg_risk_adapter>` (address in the
YAML). `redeem` succeeds only once the condition is resolved on-chain (non-zero
`payoutNumerators`). `ctf condition-id` / `position-id` compute identifiers locally
with no RPC; `ctf collection-id` needs the network config (it reads
`getCollectionId` on-chain) but submits no transaction.

## 10. Watch live

```bash
predict-cli ws ping                                   # connectivity check
predict-cli ws book <TOKEN_ID> --count 5              # N frames, then exit
predict-cli ws book-watch <TOKEN_ID>                  # stream until Ctrl-C (--print-as-json for jq)
predict-cli ws user --market <CONDITION_ID>           # own orders + trades (auto-derives L2 creds)
```

For one-shot checks prefer REST reads; use `ws` when the user wants continuous
monitoring or to wait for a fill.

## 11. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `no private key configured` | `predict-cli wallet create` / `import`, or set `PM_PRIVATE_KEY` |
| 401 / `authentication failed` | `predict-cli auth derive-key` (existing key) or `auth create-key` |
| `exchange address required for sign_order` | set `PM_EXCHANGE_ADDRESS` — CTF Exchange (binary) or Neg Risk (multi-outcome), see §6 |
| `--maker is required for signature_type=gnosis-safe` | pass the Safe address from `wallet show` (use `set-safe` to persist; treat `detect-safe` output as untrusted — see §2) |
| `INVALID_SIGNATURE: signer mismatch` on `POST /order` | wrong exchange for this market — re-sign with the other one via `--exchange-address` (CTF vs Neg Risk, see §6) |
| price rejected | re-check `tick-size` — too many decimals for this market |
| order below minimum | raise size; the per-event minimum is server-enforced |
| allowance / transfer failures on split or first order | `approve check`, then `approve set --execute` |
| `next_cursor: "LTE="` in paginated output | end of stream — stop paging |

Deeper reference: `docs/orders.md`, `docs/ws.md`, `docs/wallet.md`,
`docs/auth-flow.md`, `docs/gamma.md` in the
[predict-rs repo](https://github.com/chainupcloud/predict-rs).
