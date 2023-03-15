/// FOR REFERENCE ONLY; TOO SLOW FOR USE
/// @notice Helper functions for testing with AxiomV0 smart contract.
///         In particular calculates the correct merkle proof for a historical block hash.
/// @dev This is super slow, unusable.
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import "../src/IAxiomV0.sol";

uint8 constant TREE_DEPTH = 10;

contract AxiomTest is Test {
    function getBlockHash(uint32 blockNumber) public returns (bytes32 blockHash) {
        string[] memory castCommand = new string[](4);
        castCommand[0] = "cast";
        castCommand[1] = "block";
        castCommand[2] = vm.toString(blockNumber);
        castCommand[3] = "hash";
        bytes memory hashString = vm.ffi(castCommand);
        blockHash = vm.parseBytes32(vm.toString(hashString));
    }

    function getBlockHashWitness(uint32 blockNumber) public returns (IAxiomV0.BlockHashWitness memory witness) {
        require(
            blockNumber - (blockNumber % 1024) + 1024 <= block.number,
            "For recent block hashes need to watch event logs"
        );
        uint32 startBlockNumber = blockNumber - (blockNumber % 1024);

        bytes32[][] memory merkleRoots = new bytes32[][](TREE_DEPTH + 1);
        merkleRoots[0] = new bytes32[](2 ** TREE_DEPTH);
        for (uint32 i = 0; i < 2 ** TREE_DEPTH; i++) {
            merkleRoots[0][i] = getBlockHash(startBlockNumber + i);
        }
        emit log_string("got block hashes");
        for (uint256 depth = 0; depth < TREE_DEPTH; depth++) {
            merkleRoots[depth + 1] = new bytes32[](2 ** (TREE_DEPTH - depth - 1));
            for (uint256 i = 0; i < 2 ** (TREE_DEPTH - depth - 1); i++) {
                merkleRoots[depth + 1][i] =
                    keccak256(abi.encodePacked(merkleRoots[depth][2 * i], merkleRoots[depth][2 * i + 1]));
            }
        }

        uint256 side = blockNumber % 1024;
        for (uint8 depth = 0; depth < TREE_DEPTH; depth++) {
            witness.merkleProof[depth] = merkleRoots[depth][(side >> depth) ^ 1];
        }

        witness.blockNumber = blockNumber;
        witness.claimedBlockHash = merkleRoots[0][side];
        witness.prevHash = getBlockHash(startBlockNumber - 1);
        witness.numFinal = 1024;
    }
}
