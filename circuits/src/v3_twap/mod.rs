use std::{env::set_var, iter};

use axiom_scaffold::{
    axiom_eth::{
        rlp::builder::{RlcThreadBreakPoints, RlcThreadBuilder},
        storage::EIP1186ResponseDigest,
        util::{
            circuit::{PinnableCircuit, PreCircuit},
            EthConfigPinning,
        },
        Field,
    },
    halo2_base::gates::GateInstructions,
    halo2_base::{
        gates::{builder::CircuitBuilderStage, RangeInstructions},
        halo2_proofs::{
            halo2curves::bn256::{Bn256, Fr},
            poly::{commitment::Params, kzg::commitment::ParamsKZG},
        },
        AssignedValue,
        QuantumCell::Constant,
    },
    scaffold::AxiomChip,
};
use ethers_core::types::{Address, H256};
use ethers_providers::{Http, Provider};

/// Found with `forge inspect UniswapV3Pool storage-layout --pretty`
const UNISWAP_V3_POOL_OBSERVATION0_SLOT: u64 = 8;

pub mod helpers;
#[cfg(test)]
mod tests;

#[derive(Clone, Copy, Debug)]
pub struct OracleObservation<F: Field> {
    pub block_hash: [AssignedValue<F>; 2],
    pub block_number: AssignedValue<F>,
    pub pool_address: AssignedValue<F>,
    /// This is the concatenated packing of `secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp` as `20 + 7 + 4 = 31` bytes (248 bits), which fits in a single bn254::Fr field element
    pub observation: AssignedValue<F>,
}

pub trait UniswapV3TwapOracle<F: Field> {
    /// See https://docs.uniswap.org/contracts/v3/reference/core/UniswapV3Pool#observe
    ///
    /// We essentially read the output of the UniswapV3Pool `observe` function as the "current" timestamp (`secondsAgo = [0]`) at a specific block.
    /// This returns the accumulator values at block.timestamp.
    fn observe_single(
        &mut self,
        provider: &Provider<Http>,
        pool_address: Address,
        block_number: u32,
    ) -> OracleObservation<F>;

    /// Calls `observe_single` for each block number in `block_numbers`.
    ///
    /// To compute the TWAP between `start_block_number` and `end_block_number`, we call `observe` on `[start_block_number, end_block_number]`
    /// and use the returned observations.
    fn observe(
        &mut self,
        provider: &Provider<Http>,
        pool_address: Address,
        block_numbers: &[u32],
    ) -> Vec<OracleObservation<F>>;
}

impl<F: Field> UniswapV3TwapOracle<F> for AxiomChip<F> {
    fn observe_single(
        &mut self,
        provider: &Provider<Http>,
        pool_address: Address,
        block_number: u32,
    ) -> OracleObservation<F> {
        assert!(F::CAPACITY >= 248, "Field needs to have at least 248 bits capacity");
        let slot = H256::from_low_u64_be(UNISWAP_V3_POOL_OBSERVATION0_SLOT);
        let EIP1186ResponseDigest { block_hash, block_number, address, mut slots_values } =
            self.eth_getProof(provider, pool_address, vec![slot], block_number);
        assert_eq!(slots_values.len(), 1);
        let (slot, value) = slots_values.pop().unwrap();
        let ctx = &mut self.ctx();
        // slot should equal H256(UNISWAP_V3_POOL_OBSERVATIONS_SLOT)
        self.gate().assert_is_const(ctx, &slot[0], &F::zero());
        self.gate().assert_is_const(ctx, &slot[1], &F::from(UNISWAP_V3_POOL_OBSERVATION0_SLOT));

        // value is 256 bits representing concatenation `initialized . secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        let [hi, lo] = value;
        // We want `hi` to be `uint128` with first byte equal to `0x1` (for `initialized = true`)
        let hi120 = self.gate().sub(ctx, hi, Constant(self.gate().pow_of_two()[120]));
        self.range().range_check(ctx, hi120, 120);
        // `observation = secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        let observation =
            self.gate().mul_add(ctx, hi120, Constant(self.gate().pow_of_two()[128]), lo);
        OracleObservation { block_hash, block_number, pool_address: address, observation }
    }

    fn observe(
        &mut self,
        provider: &Provider<Http>,
        pool_address: Address,
        block_numbers: &[u32],
    ) -> Vec<OracleObservation<F>> {
        assert!(!block_numbers.is_empty());
        let obs: Vec<_> = block_numbers
            .iter()
            .map(|&num| self.observe_single(provider, pool_address, num))
            .collect();
        for ob in obs.iter().skip(1) {
            self.ctx().constrain_equal(&ob.pool_address, &obs[0].pool_address);
        }
        obs
    }
}

#[derive(Clone, Debug)]
pub struct UniswapV3TwapCircuit {
    pub provider: Provider<Http>,
    pub pool_address: Address,
    pub start_block_number: u32,
    pub end_block_number: u32,
}

impl UniswapV3TwapCircuit {
    pub fn create<F: Field>(
        self,
        builder: RlcThreadBuilder<F>,
        break_points: Option<RlcThreadBreakPoints>,
    ) -> impl PinnableCircuit<F> {
        let mut axiom = AxiomChip::new(builder);
        let [start_obs, end_obs]: [_; 2] = axiom
            .observe(
                &self.provider,
                self.pool_address,
                &[self.start_block_number, self.end_block_number],
            )
            .try_into()
            .unwrap();
        // Public instances: total 7 field elements
        // 0: `pool_address . start_block_number . end_block_number` is `20 + 4 + 4 = 28` bytes, packed into a single field element
        // 1..3: `start_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
        // 3..5: `end_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
        // 5: `start_observation` (31 bytes) is single field element, concatenation of `secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        // 6: `end_observation` (31 bytes) is single field element, concatenation of `secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        assert!(F::CAPACITY >= 248, "Field needs to have at least 248 bits capacity");
        let mut aux = axiom.ctx();
        let ctx = &mut aux;
        let gate = axiom.gate();
        let pow2 = gate.pow_of_two();
        let mut packed =
            gate.mul_add(ctx, start_obs.block_number, Constant(pow2[4]), end_obs.block_number);
        packed = gate.mul_add(ctx, start_obs.pool_address, Constant(pow2[8]), packed);
        drop(aux);

        for elt in iter::once(packed)
            .chain(start_obs.block_hash)
            .chain(end_obs.block_hash)
            .chain(iter::once(start_obs.observation))
            .chain(iter::once(end_obs.observation))
        {
            axiom.expose_public(elt);
        }

        axiom.create(break_points)
    }
}

impl PreCircuit for UniswapV3TwapCircuit {
    type Pinning = EthConfigPinning;

    fn create_circuit(
        self,
        stage: CircuitBuilderStage,
        pinning: Option<Self::Pinning>,
        params: &ParamsKZG<Bn256>,
    ) -> impl PinnableCircuit<Fr> {
        let builder = match stage {
            CircuitBuilderStage::Prover => RlcThreadBuilder::new(true),
            _ => RlcThreadBuilder::new(false),
        };
        let break_points = pinning.map(|p| p.break_points);
        set_var("DEGREE", params.k().to_string());
        self.create::<Fr>(builder, break_points)
    }
}
