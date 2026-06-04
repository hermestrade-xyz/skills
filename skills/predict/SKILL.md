---
name: predict
description: >-
  Trade prediction markets on hermestrade.xyz with the predict-cli binary:
  install the CLI, set up a wallet and L2 API key, discover markets, read
  orderbooks, place and cancel limit/market orders, track positions and PnL,
  split/merge/redeem conditional tokens, and stream live WebSocket updates. Use
  this skill whenever the user mentions predict-cli, predict-rs, hermestrade,
  prediction markets, outcome shares, YES/NO tokens, CLOB orders, or conditional
  tokens (CTF) — even if they don't name the tool explicitly, and even for
  read-only questions like "what's the midpoint" or "show my positions".
---

# Trading prediction markets with predict-cli

`predict-cli` is the terminal client for the HermesTrade prediction-market CLOB
exchange. Out of the box it targets the built-in **`monad`** network (tenant
`hermestrade.xyz`): the chain id, endpoints, exchange, and every contract address
are compiled into the binary, so reads and trades need **no connection flags and
no environment variables**. Everything that has to persist — your key, Safe, and
identity — lives in one file, `config.toml`.

Every command supports `-o json` for machine-readable output — prefer it when you
need to parse results (pipe to `jq`).

## 0. Get the CLI

Run `scripts/ensure-cli.sh` first. It is idempotent: if `predict-cli` is already
on PATH it does nothing; otherwise it installs the latest release via the official
installer (statically linked musl binary on Linux, sha256-verified):

```bash
curl -sSfL https://raw.githubusercontent.com/chainupcloud/predict-rs/main/install.sh | sh
```

Inside a `predict-rs` checkout, `cargo build --release` →
`target/release/predict-cli` works too.

This skill targets **predict-cli 0.2.0+** — the built-in network registry and the
config.toml-first model described below are 0.2.0 features (0.1.x used environment
variables and a `~/.config/pm` config dir). Confirm with `predict-cli --version`.

## 1. Connect (nothing to configure)

The default `monad` network supplies the tenant, chain id (143), the CLOB / Gamma /
WebSocket / Data / relayer endpoints, the exchange, and all contract addresses.
Read-only commands work immediately:

```bash
predict-cli ok          # server health
predict-cli endpoints   # resolved network / tenant / clob / gamma / ws / chain_id / exchange
```

`endpoints` is the pre-trade sanity check: it prints exactly which network, chain,
and **exchange (EIP-712 `verifyingContract`)** the order signer will bind to.

Override only for non-default cases — you rarely need any of these:

```bash
predict-cli --tenant hermestrade.xyz ok          # same network, pin the host
predict-cli --clob-endpoint https://clob-api.hermestrade.xyz ok   # target the CLOB host directly
```

## 2. Wallet & auth (one-time)

Prefer the guided wizard. It walks through wallet → tenant identity (chain +
**scopeId** + signature type) → Safe address → L2 API key, and writes everything to
`config.toml`:

```bash
predict-cli setup
```

Manual equivalent — the individual subcommands edit the same `config.toml`:

```bash
predict-cli wallet create                 # fresh EOA → config.toml (mode 0600); --force to overwrite
predict-cli wallet import 0xYOURKEY       # or import an existing key
predict-cli wallet set-safe 0xSAFE        # persist the funded Safe address
predict-cli auth create-key               # mint an L2 API key (or derive-key to recover one)
predict-cli wallet show                   # EOA + Safe + signature type + config source (never echoes the key)
```

> **Careful with `wallet detect-safe`.** It reads the server's `proxy_wallet`
> field (via `GET /auth/api-keys`) and **unconditionally overwrites** the stored
> Safe address — no check against what's already configured. Verify before
> trading: the address should hold the USDW balance
> (`balance --asset-type collateral`) and have contract code deployed. When in
> doubt, `wallet set-safe` the known-funded address instead.

Key facts that prevent confusion later:

- **Default signature type is `gnosis-safe`.** The EOA only signs; a 1-of-1 Safe
  holds the USDW and outcome tokens and is the order `maker`. Balances and
  positions belong to the **Safe address**, not the EOA.
- **`scopeId`** is the tenant isolation key (`bytes32`) baked into every signed
  `ClobAuth` and order; the wrong scope derives a different L2 key and different
  order state. `setup` prompts for it; the canonical hermestrade value lives in
  `examples/config.toml` in predict-rs. The network does *not* supply it.
- **The private key is read only from `--private-key` or `config.toml`** — there
  is **no `PM_PRIVATE_KEY` env var** (a key in the environment leaks via
  `/proc/<pid>/environ`). Prefer the config file over the flag (flags leak into
  shell history).
- Config lives in `~/.config/predict/config.toml` (Linux, dir mode 0700, file
  mode 0600) or `~/Library/Application Support/predict` (macOS). `config.toml`
  persists `private_key`, `safe_address`, `scope_id`, `signature_type`, and
  optional `network` / `chain_id` / `tenant` overrides. Only `private_key` is
  required for signing; the network provides the rest.

Before a trading session, sanity-check with `predict-cli endpoints`,
`predict-cli wallet show`, and `predict-cli balance --asset-type collateral`.

## 3. Safety rules (real funds)

Orders and CTF operations move real money. Hold to these:

- **Confirm before committing funds.** Before any `order create` / `order market`
  / `ctf … --execute` / `approve set --execute`, state the market, side, price,
  size, and resulting notional, and get the operator's explicit go-ahead — unless
  they have already given you a standing budget and instruction.
- **Dry-run first on new flows.** `order create --dry-run` prints the signed
  envelope without posting; `ctf` / `approve` writes default to dry-run and only
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
- `clobTokenIds` — the YES/NO outcome token ids (uint256 decimals). Orders, books,
  and prices are all per **token id**.

## 5. Read the market

Pull these before quoting a price:

```bash
predict-cli tick-size <TOKEN_ID>     # price granularity — orders must respect it
predict-cli fee-rate <TOKEN_ID>      # feeRateBps — required on every order
predict-cli midpoint <TOKEN_ID>
predict-cli book <TOKEN_ID>
predict-cli price <TOKEN_ID> --side buy
```

Batch variants: `midpoints` / `spreads` / `last-trades` take bare ids
(`last-trades` is server-capped at 500); `prices` / `books` take `<id>:<side>`
entries, e.g. `predict-cli prices 123:buy 456:sell`.

## 6. Place orders

The order signature embeds the EOA key, the chain id, and the **exchange the
market settles on** (EIP-712 `verifyingContract`). All three resolve
automatically from `config.toml` + the `monad` network — there is nothing to
export:

- **Binary (YES/NO) markets** sign against the network's **CTF Exchange**
  (`0x017641abFa4264121237023f9Fe678BF00F60De8`) — the default, zero config.
- **Sports / multi-outcome families** settle on the **Neg Risk CTF Exchange**
  (`0x50b7B00EE75F8bFb5cDa892883aFb3867851c738`). Gamma doesn't expose a per-market
  neg-risk flag, so if a correctly-keyed order is rejected with
  `EXECUTION_ERROR: INVALID_SIGNATURE: signer mismatch`, re-sign against it:
  `--exchange-address 0x50b7B00EE75F8bFb5cDa892883aFb3867851c738`.

`predict-cli endpoints` shows the bound exchange; both addresses also come from
`predict-cli gamma public-info`.

Always fetch `fee-rate` and `tick-size` for the token first; the server rejects
orders that miss the fee or violate price granularity. In the default Safe mode
`--maker` is **optional** — it falls back to the `safe_address` in `config.toml`
(`wallet set-safe` / `setup`); pass `--maker <SAFE>` only to override it.

```bash
predict-cli order create \
  --token <TOKEN_ID> --side buy --price 0.34 --size 100 \
  --fee-rate-bps <FROM_FEE_RATE> \
  --dry-run          # drop after inspecting the envelope; maker = stored Safe
```

Market order — `order market` is the slim alias for `order create --market` (FAK by
default). `--amount` is USDC notional (**BUY only**); `--size` is share-denominated
(SELL must use `--size`). A `--price` anchor is still required on the wire:

```bash
predict-cli order market --token <TOKEN_ID> --side buy --amount 25 --price 0.34 \
  --fee-rate-bps <BPS>
```

Rules the exchange enforces:

- **Minimum order size: 5 shares.** Smaller is rejected with
  `ORDER_SIZE_TOO_SMALL: limit order requires share >= 5`, even at a low price.
- **Lot size 0.01.** `size` rounds to 0.01; for a market order, `amount / price`
  must round to a multiple of 0.01 (else `… has N decimals; lot size is 2`).
- `price` ∈ (0, 1), decimals capped by tick size (0.01 → 2 dp, 0.001 → 3 dp,
  0.0001 → 4 dp), enforced **server-side**. Amounts floor-truncate to 6 decimals.
- **Fees are charged in shares on the receiving side**, not in USDW. A BUY of 5 @
  0.09 with `--fee-rate-bps 20` spends exactly 0.45 USDW but credits 4.99 tokens.
  (SELL fees come out in USDW.)
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
predict-cli order post-batch --tokens t1,t2 --prices 0.10,0.05 --sizes 5,5 \
  --side buy --fee-rate-bps 20               # ≤ 15 orders, shared side/fee/maker
```

## 7. Track fills and balances

```bash
predict-cli trade --asset-id <TOKEN_ID> --limit 50   # trade history (L2-auth)
predict-cli balance --asset-type collateral          # USDW
predict-cli balance --asset-type conditional --token <TOKEN_ID>
```

`balance --update` forces a subgraph refresh; plain `balance` returns the cached
value. Cross-check on-chain when a balance is load-bearing.

On `/ws/user` (and in `trade` output) the trade `status` field takes the uppercase
`TradeStatus` values `MATCHED` / `MINED` / `CONFIRMED` / `RETRYING` / `FAILED`.
Treat a fill as final only at `CONFIRMED`; `MATCHED` means the engine matched it
but settlement is still pending. The `match_type` field is `MATCH` (bilateral
fill), `MINT` (mints the complementary token — neg-risk maker side), or `MERGE`
(burns a complementary pair). `data activity` rows carry an `activity_type` of
`TRADE` / `SPLIT` / `MERGE` / `REDEEM` / `REWARD` / `CONVERSION`.

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
the default `gnosis-safe` signature type plus a stored Safe address. They run
against the built-in network (chain id, RPC, relayer, and contract addresses come
from `monad` — there is **no `--network-config` flag**), and default to **dry-run**:

```bash
# One-time approvals. approve check uses the stored Safe (or --address <SAFE>).
# approve set defaults to --asset all over the three exchange targets via MultiSend.
predict-cli approve check
predict-cli approve set   --execute

# split / merge call ConditionalTokens directly, which is NOT in the default
# approve targets — approve USDW for it once before your first split:
predict-cli approve set --asset usdw \
  --spender 0xd77d550092aB455bd1b9071E4185eCbB6E8d6a2A --execute

# --amount is RAW 6-decimal units: 1000000 = 1 USDW. Run without --execute first
# and read back the dry-run plan's amount before submitting.
predict-cli ctf split  --condition-id 0x… --partition 1,2 --amount 1000000 --execute
predict-cli ctf merge  --condition-id 0x… --partition 1,2 --amount 1000000 --execute
predict-cli ctf redeem --condition-id 0x… --index-sets 1,2 --execute   # only after resolution
```

For **neg-risk** markets the write target is the Neg Risk Adapter, not the default
ConditionalTokens contract — pass
`--contract 0x4c3Ba1A5A6BEaF4CDA6E1Dca75fF9e889A076bE8`. `redeem` succeeds only
once the condition is resolved on-chain (non-zero `payoutNumerators`).
`ctf condition-id` / `position-id` compute identifiers locally with no RPC;
`ctf collection-id` reads `getCollectionId` on-chain (RPC from the network, override
with `--rpc-url`) but submits no transaction.

## 10. Watch live

```bash
predict-cli ws ping                                   # connectivity check
predict-cli ws book <TOKEN_ID> --count 5              # N frames, then exit
predict-cli ws book-watch <TOKEN_ID>                  # stream until Ctrl-C (--print-as-json for jq)
predict-cli ws user --market <CONDITION_ID>           # own orders + trades; repeat --market to add ids
```

For one-shot checks prefer REST reads; use `ws` when the user wants continuous
monitoring or to wait for a fill.

## 11. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `private key required` / `no private key configured` | `predict-cli wallet create` / `import`, or pass `--private-key` (no env var) |
| 401 / `authentication failed` | `predict-cli auth derive-key` (existing key) or `auth create-key` |
| `no maker for signature_type=gnosis-safe` | store the Safe with `predict-cli wallet set-safe <addr>` (or `setup`), pass `--maker <SAFE>`, or use `--signature-type eoa` |
| `INVALID_SIGNATURE: signer mismatch` on `POST /order` | neg-risk market — re-sign with `--exchange-address 0x50b7B00EE75F8bFb5cDa892883aFb3867851c738` (see §6) |
| `ORDER_SIZE_TOO_SMALL: … requires share >= 5` | raise size to ≥ 5 shares |
| `… has N decimals; lot size is 2` | round `size` (or market `amount / price`) to a multiple of 0.01 |
| price rejected | re-check `tick-size` — too many decimals for this market |
| allowance / transfer failures on split or first order | `approve check`, then `approve set --execute` (and the ConditionalTokens approval in §9 for split/merge) |
| `next_cursor: "LTE="` in paginated output | end of stream — stop paging |

Deeper reference: `docs/orders.md`, `docs/ws.md`, `docs/wallet.md`,
`docs/auth-flow.md`, `docs/gamma.md`, and `cli/README.md` in the
[predict-rs repo](https://github.com/chainupcloud/predict-rs).
