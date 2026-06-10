---
name: predict
description: >-
  Trade prediction markets on hermestrade.xyz with the predict-cli binary:
  install the CLI, set up a wallet and L2 API key, create a Safe, deposit and
  withdraw collateral (USDC↔USDW), discover markets, read orderbooks, place and
  cancel limit/market orders, track positions and PnL, split/merge/redeem
  conditional tokens, stream live WebSocket updates, and run several trading
  accounts side by side (--slug). Use this skill whenever the user mentions
  predict-cli, predict-rs, hermestrade, prediction markets, outcome shares,
  YES/NO tokens, CLOB orders, conditional tokens (CTF), depositing /
  withdrawing / funding the Safe, or switching between multiple trading
  accounts — even if they don't name the tool explicitly, and even for
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

The installer defaults to `/usr/local/bin` (uses `sudo` when that isn't
writable); set `INSTALL_DIR` to install somewhere user-writable without sudo:

```bash
curl -sSfL https://raw.githubusercontent.com/chainupcloud/predict-rs/main/install.sh \
  | INSTALL_DIR=~/.local/bin sh
```

Inside a `predict-rs` checkout, `cargo build --release` →
`target/release/predict-cli` works too.

This skill tracks the **latest** predict-cli release — what the installer above
fetches. If a command or flag here doesn't match your binary, re-run the installer
to update (`predict-cli --version` shows what you have).

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

> **After setting up the wallet, tell the user where the key lives and to back it
> up.** A freshly created EOA exists only in `<config-dir>/config.toml` (Linux:
> `~/.config/predict/config.toml`; macOS: `~/Library/Application Support/predict/config.toml`;
> with `--slug <name>`: `…/predict/<name>/config.toml`) — lose that file and the
> funds are unrecoverable. Surface the exact path
> (`predict-cli wallet show` prints `config path`) and remind the user to back it
> up somewhere safe. Backing up means the user copying the file themselves — don't
> print the key.

**No Safe yet?** `predict-cli wallet deploy-safe` creates the EOA's Gnosis Safe
on-chain via the relayer's SAFE-CREATE — **gasless** (the relayer pays), with a
**deterministic** address derived from your EOA + `scopeId`, and **one-shot** per
`(EOA, scopeId)` (rejected once code exists there). It needs a `scope_id`
configured, and on success saves the deployed address to `config.toml` (`--save`,
on by default). Use it when the EOA has no Safe; if you already control a funded
Safe, `wallet set-safe <addr>` instead. It **submits by default** — add `--dry-run`
to only predict + sign the address.

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
  mode 0600) or `~/Library/Application Support/predict` (macOS); with
  `--slug <name>` it nests to `~/.config/predict/<name>/config.toml` (next
  subsection). `config.toml` persists `private_key`, `safe_address`,
  `scope_id`, `signature_type`, and optional `network` / `chain_id` / `tenant`
  overrides. Only `private_key` is required for signing; the network provides
  the rest.

### Multiple accounts — `--slug` / `-s`

Run several wallets side by side by giving each its own config dir. `--slug
<name>` (short `-s`) nests one level under the base dir: the effective file
becomes `<config-dir>/<name>/config.toml` (default
`~/.config/predict/<name>/config.toml`). It is a **global flag** — put it
before or after any subcommand. `<name>` must be a single path segment (`/`,
`\`, `..`, `.` are rejected), so a slug can only ever name a direct child of
the config root. `--config-dir` still works and acts as the base:
`--config-dir /data/pm -s acctA` → `/data/pm/acctA/`.

```bash
# Set up two isolated accounts — each gets its own key / Safe / scope / L2 key
predict-cli -s acctA wallet create
predict-cli -s acctA wallet deploy-safe
predict-cli -s acctA auth create-key
predict-cli -s acctB wallet create        # lives in ~/.config/predict/acctB/

# Then prefix any command with the account
predict-cli -s acctA order list
predict-cli -s acctB balance --asset-type collateral
```

- Each invocation is an independent process reading only its own dir —
  accounts never share keys, Safes, or order state.
- `predict-cli -s acctA shell` scopes the whole REPL session: every line that
  doesn't pick an account itself runs as `acctA` (a line can still override
  with its own `-s` / `--config-dir`). The banner shows the bound account dir.
- **Always know which account a command acts on.** A bare `predict-cli` (no
  `-s`) is the *default* account — easy to hit by accident in a multi-account
  setup. Before anything money-moving, check the slug on the command line and
  name the account when asking the operator to confirm (§3);
  `predict-cli -s <name> wallet show` prints the config path it loaded.

Before a trading session, sanity-check with `predict-cli endpoints`,
`predict-cli wallet show`, and `predict-cli balance --asset-type collateral`
(each with the session's `-s <slug>` if you're using accounts).

## 3. Safety rules (real funds)

Orders and CTF operations move real money. Hold to these:

- **Confirm before committing funds.** Before any `order create` / `order market`
  / `deposit` / `withdraw` / `ctf … --execute` / `approve set --execute` /
  `wallet deploy-safe`, state the market, side, price, size, and resulting notional
  (or the amount moved) — plus **which account** (`-s <slug>`) when more than one
  is configured — and get the operator's explicit go-ahead, unless they have
  already given you a standing budget and instruction.
- **Dry-run first on new flows.** `order create --dry-run` prints the signed
  envelope without posting; `ctf` / `approve` writes default to dry-run and only
  submit with `--execute`. **`deposit` / `withdraw` / `wallet deploy-safe` are the
  exception — they broadcast by default; add `--dry-run` to preview.** Inspect,
  then re-run for real.
- **Never print private keys.** `wallet show` is safe (it never echoes the key);
  `config.toml` contents are not — don't cat it.
- **Stay inside any budget the operator set**, and stop and report rather than
  retry when a money-moving call fails in an unexpected way.

## 4. Fund the Safe — deposit & withdraw

Trading collateral is **USDW**, held by the Safe. Mint it by depositing **USDC**;
redeem it back to USDC by withdrawing. Both move real funds — the §3 rules apply,
and unlike `ctf` / `approve` these commands **broadcast by default** (`--dry-run`
previews).

### Deposit (USDC → USDW)

`predict-cli deposit` wraps the **EOA's USDC** into USDW and mints it straight to
the Safe. It is the one predict-cli flow that sends a **direct EOA transaction**
(the USDC lives in the EOA, so there is no Safe to route through), so the EOA needs
USDC **plus a little MON for gas**:

```bash
predict-cli deposit --amount 5            # wrap 5 USDC → 5 USDW into the Safe
predict-cli deposit --amount 5 --dry-run  # check balance + allowance, print the plan, don't broadcast
```

- `--amount` is whole units (`5`, `5.5`), scaled by the asset's on-chain decimals.
- `--to <addr>` overrides the mint recipient (defaults to the Safe in config).
- `--asset <addr>` overrides the underlying USDC (defaults to the network's
  `usdw_underlying` — `0x754704Bc059F8C67012fEd69BC8A327a5aafb603` on Monad: USDC,
  6 decimals, distinct from the `usdw` trading collateral).
- It auto-`approve`s USDC to the wrapper when the allowance is short, then calls
  `USDWrapper.wrap` (one immediate tx). It aborts if the EOA's USDC balance is below
  `--amount`.

### Withdraw (USDW → USDC) — two steps, with a delay

Withdraw is Safe-side and **two-step**, separated by the wrapper's on-chain
`unwrapDelay` (**~24h on Monad**, measured in real wall-clock time — fast block
production does *not* shorten it):

```bash
# 1. initiate — burn the Safe's USDW via the relayer (gasless), open a delayed
#    unwrap request, and print its requestId.
predict-cli withdraw initiate --amount 1
#    → request_id (this initiate): 3
#    → claimable in ~86400s (~24h) via: predict-cli withdraw claim --request-id 3

# 2. status — read the request's on-chain state any time
predict-cli withdraw status --request-id 3     # claimable_at (unix) / claimed / claimable_now

# 3. claim — after the delay, release the USDC to the Safe. Direct EOA tx
#    (permissionless), so the EOA again needs a little MON for gas.
predict-cli withdraw claim --request-id 3
```

- `initiate --amount` is USDW whole units (6 decimals); it must be ≥ the wrapper's
  `minUnwrapUsdw` and ≤ the Safe's USDW balance. `initiate` submits via the relayer
  by default; `--dry-run` signs without submitting.
- The pre-read requestId can race, so `initiate` re-confirms the real id from chain
  after submitting — claim with the **confirmed** id it prints.
- `claim` aborts if the request is not found, already claimed, or not yet claimable
  (`claimable_at` still in the future — check with `withdraw status`).
- All three accept `--rpc-url` to override the network RPC.

## 5. Discover markets

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

## 6. Read the market

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

## 7. Place orders

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

## 8. Track fills and balances

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

## 9. Positions & PnL

The Data API is keyed by **wallet address — use the Safe address**:

```bash
predict-cli data positions <SAFE_ADDRESS>
predict-cli data closed-positions <SAFE_ADDRESS>
predict-cli data trades <SAFE_ADDRESS>
predict-cli data activity <SAFE_ADDRESS>     # trades + splits + merges + redeems
predict-cli data user-pnl <SAFE_ADDRESS>
```

## 10. CTF operations (split / merge / redeem)

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

## 11. Watch live

```bash
predict-cli ws ping                                   # connectivity check
predict-cli ws book <TOKEN_ID> --count 5              # N frames, then exit
predict-cli ws book-watch <TOKEN_ID>                  # stream until Ctrl-C (--print-as-json for jq)
predict-cli ws user --market <CONDITION_ID>           # own orders + trades; repeat --market to add ids
```

For one-shot checks prefer REST reads; use `ws` when the user wants continuous
monitoring or to wait for a fill.

## 12. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `private key required` / `no private key configured` | `predict-cli wallet create` / `import`, or pass `--private-key` (no env var) |
| 401 / `authentication failed` | `predict-cli auth derive-key` (existing key) or `auth create-key` |
| `no maker for signature_type=gnosis-safe` | store the Safe with `predict-cli wallet set-safe <addr>` (or `setup`), pass `--maker <SAFE>`, or use `--signature-type eoa` |
| `INVALID_SIGNATURE: signer mismatch` on `POST /order` | neg-risk market — re-sign with `--exchange-address 0x50b7B00EE75F8bFb5cDa892883aFb3867851c738` (see §7) |
| `ORDER_SIZE_TOO_SMALL: … requires share >= 5` | raise size to ≥ 5 shares |
| `… has N decimals; lot size is 2` | round `size` (or market `amount / price`) to a multiple of 0.01 |
| price rejected | re-check `tick-size` — too many decimals for this market |
| allowance / transfer failures on split or first order | `approve check`, then `approve set --execute` (and the ConditionalTokens approval in §10 for split/merge) |
| `EOA … holds … but deposit needs …` | fund the EOA with USDC (plus a little MON for gas) before `deposit` |
| `amount … is below minUnwrapUsdw` | raise the `withdraw initiate` amount to the wrapper's minimum |
| `request … not claimable yet` | wait out `unwrapDelay` (~24h on Monad); poll `withdraw status` |
| `a Safe is already deployed … for this (EOA, scopeId)` | the Safe exists — `wallet set-safe` it; `deploy-safe` is one-shot |
| `SAFE-CREATE requires a scope_id` | set `scope_id` (via `setup` / config.toml / `--scope-id`) before `deploy-safe` |
| wrong account hit / balance unexpectedly empty in a multi-account setup | the `-s <slug>` was missing or wrong — every command needs it; `wallet show` prints the loaded config path; `shell` binds the launch-time account |
| `invalid --slug …: must be a single path segment` | slugs can't contain `/`, `\`, `..`, `.`; use a plain name (`acctA`) — for an arbitrary path use `--config-dir` instead |
| `next_cursor: "LTE="` in paginated output | end of stream — stop paging |

Deeper reference: `docs/orders.md`, `docs/ws.md`, `docs/wallet.md`,
`docs/auth-flow.md`, `docs/gamma.md`, and `cli/README.md` in the
[predict-rs repo](https://github.com/chainupcloud/predict-rs).
