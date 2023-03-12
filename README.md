# uniswap-v3-oracles

Trustless oracle of historical Uniswap v3 TWAP using ZK

## Setup

### Circuit

Optional: symlink existing `params` folder to `circuits/params` to avoid regenerating NOT FOR PRODUCTION trusted setup files. (It's fine to ignore this if you don't know what it means.)

### RPC URL

```bash
cp .env.example .env
```

Fill in `.env` with your `INFURA_ID`. In order for Forge to access `ETH_RPC_URL` for testing, we need to export `.env`:

```bash
set -a
source .env
set +a
```
