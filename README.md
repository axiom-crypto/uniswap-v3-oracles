# Trustless Uniswap V3 Oracles via ZK (Axiom)

Trustless oracle of historical Uniswap v3 TWAP using ZK

## Setup

Clone this repository (and git submodule dependencies) with

```bash
git clone --recurse-submodules -j8 https://github.com/axiom-crypto/uniswap-v3-oracles.git
cd uniswap-v3-oracles
```

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

## ZK Proving

In the `circuits` directory, run:

```bash
cargo run --bin twap_proof --release -- --pool <UNISWAP V3 POOL ADDRESS> --start <TWAP START BLOCK NUMBER> --end <TWAP END BLOCK NUMBER>
```

If this is the first time running, it will generate proving keys (and trusted setup files if they don't exist already).

The proof calldata is written as a hex string to `circuits/data/mainnet_*_*_*_evm.calldata`.

**Note:** The proof generation requires up to 40GB of RAM to complete. If you do not have enough RAM, you can [set up swap](https://www.digitalocean.com/community/tutorials/how-to-add-swap-space-on-ubuntu-20-04) to compensate (this is done automatically on Macs) at the tradeoff of slower runtimes.

For a technical overview of what the circuit is doing, see [here](https://hackmd.io/@jpw/BJEYSD8k2).

## Smart Contract Testing

We use [foundry](https://book.getfoundry.sh/) for smart contract development and testing. You can follow these [instructions](https://book.getfoundry.sh/getting-started/installation) to install it.
We fork mainnet for tests, so make sure that `.env` variables have been [exported](#rpc-url).

After installing `foundry`, in the `contracts` directory, run:

```bash
forge install
forge test
```

For verbose logging of events and gas tracking, run

```bash
forge test -vvvv
```
