use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use axiom_uniswap_oracles::v3_twap::helpers::{UniswapTwapTask, UniswapV3TwapScheduler};
use clap::Parser;
use clap_num::maybe_hex;
use ethers_core::types::Address;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)] // Read from `Cargo.toml`
/// Generates ZK SNARK that reads historical oracle observations from a Uniswap V3 Pool smart contract
/// for TWAP computations.
/// The output is the proof calldata to send to the EVM SNARK verifier or Axiom's specialized TWAP Oracle contract.
/// Optionally produces the EVM verifier contract Yul code.
struct Cli {
    #[arg(long, default_value_t = Network::Mainnet)]
    network: Network,
    #[arg(short, long = "pool")]
    pool_address: Address,
    #[arg(short, long = "start", value_parser=maybe_hex::<u32>)]
    start_block_number: u32,
    #[arg(short, long = "end", value_parser=maybe_hex::<u32>)]
    end_block_number: u32,
    #[arg(long = "create-contract")]
    create_contract: bool,
    #[arg(long = "readonly")]
    readonly: bool,
    #[arg(short, long = "config-path")]
    config_path: Option<PathBuf>,
    #[arg(short, long = "data-path")]
    data_path: Option<PathBuf>,
}

fn main() {
    let args = Cli::parse();
    #[cfg(feature = "production")]
    let production = true;
    #[cfg(not(feature = "production"))]
    let production = false;

    let oracle = UniswapV3TwapScheduler::new(
        args.network,
        production,
        args.readonly,
        args.config_path.unwrap_or_else(|| PathBuf::from("configs")),
        args.data_path.unwrap_or_else(|| PathBuf::from("data")),
    );

    assert!(
        args.start_block_number <= args.end_block_number,
        "start block number must be less than or equal to end block number"
    );
    // TODO: check that start block number is >= contract creation block number
    oracle.get_calldata(
        ForEvm(UniswapTwapTask::new(
            args.start_block_number,
            args.end_block_number,
            args.pool_address,
            args.network,
        )),
        args.create_contract,
    );
}
