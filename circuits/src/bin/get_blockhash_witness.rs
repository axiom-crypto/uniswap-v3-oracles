use axiom_scaffold::axiom_eth::providers::MAINNET_PROVIDER_URL;
use clap::Parser;
use ethers_core::{types::H256, utils::keccak256};
use ethers_providers::{Http, Middleware, Provider};
use std::env::var;

///! Aided tool for testing smart contracts
///! Gets the merkle proof to construct IAxiomV0.BlockHashWitness

#[derive(Parser, Debug)]
struct Cli {
    #[arg(long = "block-number")]
    block_number: String,
}

const DEPTH: usize = 10;
const NUM_LEAVES: usize = 1 << DEPTH;

#[tokio::main]
async fn main() {
    let args = Cli::parse();
    let block_number = if args.block_number.starts_with("0x") {
        usize::from_str_radix(&args.block_number[2..], 16).expect("Enter proper hex")
    } else {
        args.block_number
            .parse()
            .expect("Block number needs to be base 10 or in hex with 0x prefix")
    };

    let infura_id = var("INFURA_ID").expect("Infura ID not found");
    let provider_url = MAINNET_PROVIDER_URL;
    let provider = Provider::<Http>::try_from(format!("{provider_url}{infura_id}").as_str())
        .expect("could not instantiate HTTP Provider");

    let side = block_number % NUM_LEAVES;
    let start = block_number - side;
    let prev_hash = provider
        .get_block((start - 1) as u64)
        .await
        .expect("could not get block")
        .unwrap()
        .hash
        .unwrap();

    let mut nodes = vec![];
    let mut leaves = Vec::with_capacity(NUM_LEAVES);
    for i in 0..NUM_LEAVES {
        let block_hash = provider
            .get_block((start + i) as u64)
            .await
            .expect("could not get block")
            .unwrap()
            .hash
            .unwrap();
        leaves.push(block_hash);
    }
    nodes.push(leaves);
    for i in 0..DEPTH {
        let mut level = vec![];
        for j in 0..(NUM_LEAVES >> (i + 1)) {
            let left = nodes[i][2 * j];
            let right = nodes[i][2 * j + 1];
            let hash = keccak256([left.0, right.0].concat());
            level.push(H256(hash));
        }
        nodes.push(level);
    }
    let mut proof = "[\n".to_string();
    for i in 0..DEPTH {
        proof += &format!("bytes32({:?})", nodes[i][(side >> i) ^ 1]);
        if i != DEPTH - 1 {
            proof += ",\n";
        }
    }
    proof += "\n]";
    println!(
        "IAxiomV0.BlockHashWitness({{
            blockNumber: {block_number},
            claimedBlockHash: bytes32({:?}),
            prevHash: bytes32({prev_hash:?}),
            numFinal: 1024,
            merkleProof: {proof} 
        }});",
        nodes[0][side],
    );
}
