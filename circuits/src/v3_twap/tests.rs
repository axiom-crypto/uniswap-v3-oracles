use super::helpers::{UniswapTwapTask, UniswapV3TwapScheduler};
use axiom_scaffold::axiom_eth::{
    util::scheduler::{evm_wrapper::Wrapper::ForEvm, Scheduler},
    Network,
};
use ethers_core::types::Address;
use std::path::PathBuf;
use test_log::test;

#[test]
fn test_usdc_eth_5bps() {
    let network = Network::Mainnet;
    let oracle = UniswapV3TwapScheduler::new(
        network,
        false,
        false,
        PathBuf::from("configs"),
        PathBuf::from("data"),
    );
    // USDC / WETH pool with token0 = USDC, token1 = WETH with 5 bip fee per swap
    let pool_address = "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640".parse::<Address>().unwrap();
    // contract creation: https://etherscan.io/tx/0x125e0b641d4a4b08806bf52c0c6757648c9963bcda8681e4f996f09e00d4c2cc
    let contract_creation_block_number = 12376729;
    let start_block_number = 12376729;
    assert!(start_block_number >= contract_creation_block_number);
    oracle.get_calldata(
        ForEvm(UniswapTwapTask::new(start_block_number, 16416686, pool_address, network)),
        true,
    );
}
