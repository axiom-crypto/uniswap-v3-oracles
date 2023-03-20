#![feature(proc_macro_hygiene, decl_macro)]
#[macro_use]
extern crate rocket;

use std::path::PathBuf;

use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use axiom_uniswap_oracles::v3_twap::helpers::{UniswapTwapTask, UniswapV3TwapScheduler};
use clap::Parser;
use ethers_core::types::Address;
use rocket::State;
use rocket_contrib::json::Json;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub start_block_number: u32,
    pub end_block_number: u32,
    pub pool_address: Address,
    pub chain_id: u64,
}

impl TryFrom<Task> for UniswapTwapTask {
    type Error = &'static str;

    fn try_from(task: Task) -> Result<Self, Self::Error> {
        let network = match task.chain_id {
            1 => Ok(Network::Mainnet),
            5 => Ok(Network::Goerli),
            _ => Err("Unsupported chainid"),
        };
        network.map(|network| {
            Self::new(task.start_block_number, task.end_block_number, task.pool_address, network)
        })
    }
}

#[post("/uniswap-v3", format = "json", data = "<task>")]
fn serve(task: Json<Task>, oracle: State<UniswapV3TwapScheduler>) -> Result<String, String> {
    let task: UniswapTwapTask = task.into_inner().try_into()?;
    if task.network() != oracle.network {
        return Err(format!(
            "JSON-RPC provider expected {:?}, got {:?}",
            oracle.network,
            task.network()
        ));
    }
    if task.start_block_number > task.end_block_number {
        return Err(format!(
            "start_block_number ({}) > end_block_number ({})",
            task.start_block_number, task.end_block_number
        ));
    }

    // Get the proof calldata
    let calldata = oracle.get_calldata(ForEvm(task), false);
    Ok(calldata)
}

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long, default_value_t = Network::Mainnet)]
    network: Network,
    #[arg(short, long = "config-path")]
    config_path: Option<PathBuf>,
    #[arg(short, long = "data-path")]
    data_path: Option<PathBuf>,
}

fn main() {
    let args = Cli::parse();
    let oracle = UniswapV3TwapScheduler::new(
        args.network,
        true,
        true,
        args.config_path.unwrap_or_else(|| PathBuf::from("configs")),
        args.data_path.unwrap_or_else(|| PathBuf::from("data")),
    );
    rocket::ignite().manage(oracle).mount("/", routes![serve]).launch();
}
