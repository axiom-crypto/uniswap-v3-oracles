// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity >=0.8.0 <0.9.0;

import "./IAxiomV0.sol";
import {Oracle} from "./Oracle.sol";

interface IUniswapV3Oracle {
    /// @notice Mapping between abi.encodePacked(address poolAddress, uint32 startBlockNumber, uint32 endBlockNumber)
    ///         => keccak(abi.encodePacked(bytes32 startObservationPacked, bytes32 endObservationPacked)) where observationPacked
    ///         is the packing of Oracle.Observation observation into 32 bytes:
    ///         bytes32(bytes1(0x0) . secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp)
    /// @dev    This is the same as how Oracle.Observation is laid out in EVM storage EXCEPT that we set initialized = false (for some gas optimization reasons)
    function twapObservations(bytes28) external view returns (bytes32);

    event UniswapV3TwapProof(
        address poolAddress,
        uint32 startBlockNumber,
        uint32 endBlockNumber,
        Oracle.Observation startObservation,
        Oracle.Observation endObservation
    );

    /// @notice Verify a ZK proof of a Uniswap V3 TWAP oracle observation and verifies the validity of checkpoint blockhashes using Axiom.
    ///         Caches the [hash of] raw observations for future use.
    ///         Returns the time (seconds) weighted average tick (geometric mean) and the time (seconds) weight average liquidity (harmonic mean).
    /// @dev    We provide the time weighted average tick and time weighted average inverse liquidity for convenience, but return
    ///         the full Observations in case developers want more fine-grained calculations of the oracle observations.
    ///         For example the price can be calculated from the tick by P = 1.0001^tick
    function verifyUniswapV3TWAP(
        IAxiomV0.BlockHashWitness calldata startBlock,
        IAxiomV0.BlockHashWitness calldata endBlock,
        bytes calldata proof
    )
        external
        returns (
            int56 twaTick,
            uint160 twaLiquidity,
            Oracle.Observation memory startObservation,
            Oracle.Observation memory endObservation
        );
}
