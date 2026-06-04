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
| [`predict`](skills/predict/SKILL.md) | Install the CLI; set up a wallet + L2 API key; discover markets; read tick size / fee / book / midpoint; place and cancel limit & market orders; track fills, balances, positions and PnL; split / merge / redeem conditional tokens; stream live order-book and user feeds. |

It triggers on any mention of `predict-cli`, HermesTrade, prediction markets, YES/NO tokens,
CLOB orders, or conditional tokens (CTF) — including read-only questions like *"what's the
midpoint"* or *"show my positions"*.

## Quickstart

```bash
# 1. Connect — read-only needs only the tenant
export PM_TENANT=hermestrade.xyz
predict-cli ok

# 2. One-time wallet + L2 key (stores your key, chain id, and Safe)
predict-cli setup

# 3. Trading also needs the exchange the market settles on
export PM_EXCHANGE_ADDRESS=0x017641abFa4264121237023f9Fe678BF00F60De8   # CTF Exchange (binary markets)

# 4. Read a market, then dry-run an order
predict-cli fee-rate <TOKEN_ID>
predict-cli book <TOKEN_ID>
predict-cli order create --token <TOKEN_ID> --side buy --price 0.34 --size 100 \
  --fee-rate-bps <FEE> --maker <SAFE_ADDRESS> --dry-run
```

`PM_EXCHANGE_ADDRESS` is required for every order and must match the market — CTF Exchange
for binary YES/NO markets, Neg Risk CTF Exchange for sports / multi-outcome. See
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
