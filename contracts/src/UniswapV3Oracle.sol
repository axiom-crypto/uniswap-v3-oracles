// SPDX-License-Identifier: MIT
// WARNING! This smart contract and the associated zk-SNARK verifiers have not been audited.
// DO NOT USE THIS CONTRACT FOR PRODUCTION
pragma solidity >=0.8.0 <0.9.0;

import "./IAxiomV0.sol";
import "./Oracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV3Oracle} from "./IUniswapV3Oracle.sol";

contract UniswapV3Oracle is Ownable, IUniswapV3Oracle {
    uint256 public constant VERSION = 0;

    // The public inputs and outputs of the ZK proof
    struct Instance {
        address poolAddress;
        uint32 startBlockNumber;
        uint32 endBlockNumber;
        bytes32 startBlockHash;
        bytes32 endBlockHash;
        Oracle.Observation startObservation;
        Oracle.Observation endObservation;
    }

    address private axiomAddress;
    address private verifierAddress;

    /// @notice Mapping between abi.encodePacked(address poolAddress, uint32 startBlockNumber, uint32 endBlockNumber)
    ///         => keccak(abi.encodePacked(bytes32 startObservationPacked, bytes32 endObservationPacked)) where observationPacked
    ///         is the packing of Oracle.Observation observation into 32 bytes:
    ///         bytes32(bytes1(0x0) . secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp)
    /// @dev    This is the same as how Oracle.Observation is laid out in EVM storage EXCEPT that we set initialized = false (for some gas optimization reasons)
    mapping(bytes28 => bytes32) public twapObservations;

    event UpdateAxiomAddress(address newAddress);
    event UpdateSnarkVerifierAddress(address newAddress);

    constructor(address _axiomAddress, address _verifierAddress) {
        axiomAddress = _axiomAddress;
        verifierAddress = _verifierAddress;
    }

    function updateAxiomAddress(address _axiomAddress) external onlyOwner {
        axiomAddress = _axiomAddress;
        emit UpdateAxiomAddress(_axiomAddress);
    }

    function updateSnarkVerifierAddress(address _verifierAddress) external onlyOwner {
        verifierAddress = _verifierAddress;
        emit UpdateSnarkVerifierAddress(_verifierAddress);
    }

    function unpackObservation(uint256 observation) internal pure returns (Oracle.Observation memory) {
        // observation` (31 bytes) is single field element, concatenation of `secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        return Oracle.Observation({
            blockTimestamp: uint32(observation),
            tickCumulative: int56(uint56(observation >> 32)),
            secondsPerLiquidityCumulativeX128: uint160(observation >> 88),
            initialized: true
        });
    }

    function getProofInstance(bytes calldata proof)
        internal
        pure
        returns (Instance memory instance, bytes32 startObservationPacked, bytes32 endObservationPacked)
    {
        // Public instances: total 7 field elements
        // 0: `pool_address . start_block_number . end_block_number` is `20 + 4 + 4 = 28` bytes, packed into a single field element
        // 1..3: `start_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
        // 3..5: `end_block_hash` (32 bytes) is split into two field elements (hi, lo u128)
        // 5: `start_observation` (31 bytes) is single field element, concatenation of `secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        // 6: `end_observation` (31 bytes) is single field element, concatenation of `secondsPerLiquidityCumulativeX128 . tickCumulative . blockTimestamp`
        bytes32[7] memory fieldElements;
        // The first 4 * 3 * 32 bytes give two elliptic curve points for internal pairing check
        uint256 start = 384;
        for (uint256 i = 0; i < 7; i++) {
            fieldElements[i] = bytes32(proof[start:start + 32]);
            start += 32;
        }
        instance.poolAddress = address(bytes20(fieldElements[0] << 32)); // 4 * 8, bytes is right padded so conversion is from left
        instance.startBlockNumber = uint32(bytes4(fieldElements[0] << 192)); // 24 * 8
        instance.endBlockNumber = uint32(bytes4(fieldElements[0] << 224)); // 28 * 8
        instance.startBlockHash = bytes32((uint256(fieldElements[1]) << 128) | uint128(uint256(fieldElements[2])));
        instance.endBlockHash = bytes32((uint256(fieldElements[3]) << 128) | uint128(uint256(fieldElements[4])));
        instance.startObservation = unpackObservation(uint256(fieldElements[5]));
        instance.endObservation = unpackObservation(uint256(fieldElements[6]));
        startObservationPacked = fieldElements[5];
        endObservationPacked = fieldElements[6];
    }

    function validateBlockHash(IAxiomV0.BlockHashWitness calldata witness) internal view {
        if (block.number - witness.blockNumber <= 256) {
            if (!IAxiomV0(axiomAddress).isRecentBlockHashValid(witness.blockNumber, witness.claimedBlockHash)) {
                revert("BlockHashWitness is not validated by Axiom");
            }
        } else {
            if (!IAxiomV0(axiomAddress).isBlockHashValid(witness)) {
                revert("BlockHashWitness is not validated by Axiom");
            }
        }
    }

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
        )
    {
        (Instance memory instance, bytes32 startObservationPacked, bytes32 endObservationPacked) =
            getProofInstance(proof);
        // compare calldata vs proof instances:
        if (instance.startBlockNumber > instance.endBlockNumber) {
            revert("startBlockNumber <= endBlockNumber");
        }
        if (instance.startBlockNumber != startBlock.blockNumber) {
            revert("instance.startBlockNumber != startBlock.blockNumber");
        }
        if (instance.endBlockNumber != endBlock.blockNumber) {
            revert("instance.endBlockNumber != endBlock.blockNumber");
        }
        if (instance.startBlockHash != startBlock.claimedBlockHash) {
            revert("instance.startBlockHash != startBlock.claimedBlockHash");
        }
        if (instance.endBlockHash != endBlock.claimedBlockHash) {
            revert("instance.endBlockHash != endBlock.claimedBlockHash");
        }
        // Use Axiom to validate block hashes
        validateBlockHash(startBlock);
        validateBlockHash(endBlock);

        (bool success,) = verifierAddress.call(proof);
        if (!success) {
            revert("Proof verification failed");
        }
        startObservation = instance.startObservation;
        endObservation = instance.endObservation;

        twapObservations[bytes28(
            abi.encodePacked(instance.poolAddress, instance.startBlockNumber, instance.endBlockNumber)
        )] = keccak256(abi.encodePacked(startObservationPacked, endObservationPacked));

        emit UniswapV3TwapProof(
            instance.poolAddress, instance.startBlockNumber, instance.endBlockNumber, startObservation, endObservation
        );

        uint32 secondsElapsed = endObservation.blockTimestamp - startObservation.blockTimestamp;
        // floor division
        twaTick = (endObservation.tickCumulative - startObservation.tickCumulative) / int56(uint56(secondsElapsed));
        // floor division
        twaLiquidity = ((uint160(1) << 128) * secondsElapsed)
            / (endObservation.secondsPerLiquidityCumulativeX128 - startObservation.secondsPerLiquidityCumulativeX128);
    }
}
