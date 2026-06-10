# HermesTrade Predict Skills

Agent skills for trading prediction markets on [hermestrade.xyz](https://hermestrade.xyz)
through the `predict-cli` binary — discover markets, read order books, place and manage
orders, track positions and PnL, settle conditional tokens, and stream live updates, all in
natural language.

## Install

```bash
npx skills add https://github.com/hermestrade-xyz/skills
```

Or clone it into your agent's skills directory:

```bash
git clone https://github.com/hermestrade-xyz/skills.git
```

The skill installs `predict-cli` on first use (`scripts/ensure-cli.sh`, idempotent).

## The skill

| Skill | What it does |
|-------|--------------|
| [`predict`](skills/predict/SKILL.md) | Install the CLI; set up a wallet + L2 API key; create a Safe; deposit / withdraw collateral (USDC↔USDW); discover markets; read tick size / fee / book / midpoint; place and cancel limit & market orders; track fills, balances, positions and PnL; split / merge / redeem conditional tokens; stream live order-book and user feeds; run multiple accounts side by side (`--slug`). |

It triggers on any mention of `predict-cli`, HermesTrade, prediction markets, YES/NO tokens,
CLOB orders, conditional tokens (CTF), or switching between trading accounts — including
read-only questions like *"what's the midpoint"* or *"show my positions"*.

## Quickstart

```bash
# 1. Read-only works out of the box — the built-in `monad` network targets hermestrade.xyz
predict-cli ok
predict-cli endpoints           # network / endpoints / chain id / bound exchange

# 2. One-time wallet + Safe + L2 key, all saved to config.toml
predict-cli setup

# 3. Read a market, then dry-run an order (maker = your stored Safe; exchange auto-binds)
predict-cli fee-rate <TOKEN_ID>
predict-cli book <TOKEN_ID>
predict-cli order create --token <TOKEN_ID> --side buy --price 0.34 --size 100 \
  --fee-rate-bps <FEE> --dry-run
```

No environment variables: the built-in `monad` network supplies the tenant, chain id,
endpoints, exchange, and contract addresses, and `config.toml` holds your key and Safe.
Several accounts side by side? Prefix any command with `-s <name>` — each slug gets its
own isolated config dir (`~/.config/predict/<name>/`), key, Safe, and L2 key.
Binary YES/NO markets sign against the CTF Exchange automatically; for sports /
multi-outcome markets add `--exchange-address <Neg Risk CTF Exchange>`. See
[`SKILL.md`](skills/predict/SKILL.md) for the full workflow.

## Safety

Orders and CTF operations move **real funds**. The skill confirms market / side / price /
size / notional before any money-moving call, dry-runs new flows first (`--dry-run`,
`--execute`), never prints private keys, and stops to report rather than blindly retry a
failed write.

## Repository layout

```
skills/predict/
├── SKILL.md                # the skill
└── scripts/ensure-cli.sh   # idempotent predict-cli installer
```

## Disclaimer

These skills drive live prediction-market and on-chain systems that move real funds. They are
tooling only, provided "as is" without warranty, and are not financial or investment advice.
You are solely responsible for verifying every transaction before authorizing it.

---

CLI source & deeper reference: [predict-rs](https://github.com/chainupcloud/predict-rs).
