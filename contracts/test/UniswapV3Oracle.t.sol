// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../lib/YulDeployer.sol";
import "../src/IAxiomV0.sol";
import "../src/UniswapV3Oracle.sol";
import "../src/Oracle.sol";

// import "./AxiomTest.t.sol";

contract UniswapTwapTest is Test {
    using Oracle for Oracle.Observation;

    YulDeployer yulDeployer;
    UniswapV3Oracle oracle;
    address verifierAddress;
    address AXIOM_ADDRESS = 0x01d5b501C1fc0121e1411970fb79c322737025c2;
    uint256 mainnetForkId;

    function setUp() public {
        yulDeployer = new YulDeployer();
        verifierAddress = address(yulDeployer.deployContract("../circuits/data/mainnet_evm"));
        oracle = new UniswapV3Oracle(AXIOM_ADDRESS, verifierAddress);
        mainnetForkId = vm.createFork("mainnet", 16_800_000);
        vm.makePersistent(verifierAddress);
        vm.makePersistent(address(oracle));
    }

    function testVerifyUniswapV3TWAP() public {
        vm.selectFork(mainnetForkId);
        // Import test proof and instance calldata
        string[] memory inputs = new string[](2);
        inputs[0] = "cat";
        inputs[1] = "../circuits/data/mainnet_0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640_bcda99_fa7fae_evm.calldata";
        bytes memory proof = vm.ffi(inputs);

        // Prepare witness data for Uniswap TWAP proof.
        // In `circuits` directory, run `cargo run --bin get_blockhash_witness -- --block-number 0xbcda99`
        IAxiomV0.BlockHashWitness memory startBlock = IAxiomV0.BlockHashWitness({
            blockNumber: 12376729,
            claimedBlockHash: bytes32(0x3496d03e6efd9a02417c713fa0de00915b78581a2eaf0e8b3fce435a96ab02c7),
            prevHash: bytes32(0xc1178c380f70527dd57594b51153132cc909f4005ea2e9c876c8a8684a8fd2b5),
            numFinal: 1024,
            merkleProof: [
                bytes32(0x1f913051374db4635e3d35470f11a95713e805a4f12597e6e13a249237b0c051),
                bytes32(0x0fdb37c72bfd47fcee290b111bbace4d320705cbb01477b3d2b33b0ba76af845),
                bytes32(0x4c2d6dd6e0a4c9f49285b42d985d1d09d39b0b8635d7ec131216fcacf320658d),
                bytes32(0x34ba56d950e2ac84aaa4aacd902c6e5b2d427be3f521868ed4d6eeca0b4f9814),
                bytes32(0x0fffb49026ec1f78dce49978022746d343573d8c6d31cba7fdefbe776bada8f4),
                bytes32(0xdb900bf3953ff846e7cc03fc2aa31e2820a51cb3a3e2f531b9b412f42a8e2f8c),
                bytes32(0x6d52dc6d64a018d37cb4c02c6a3e021dcd5eed6d4f06c8f99d87a0803d6de163),
                bytes32(0x9bc277fc6241d750a7c859ffec6a06f62f4c4f1e80ec0c26d978f921302fe312),
                bytes32(0x649496eb9718584e6ceb7c5cc2cd25dd269c5f7ee9e92b7650e6019ea0c6b1d0),
                bytes32(0x4ed4293f47ac3367740eeb2fe2a94a6a2e01b4cb15c9c6de5d5b6b7978607ee9)
            ]
        });
        // In `circuits` directory, run `cargo run --bin get_blockhash_witness -- --block-number 0xfa7fae`
        IAxiomV0.BlockHashWitness memory endBlock = IAxiomV0.BlockHashWitness({
            blockNumber: 16416686,
            claimedBlockHash: bytes32(0x6f8054dfd7dd8c837431b7ec5e2d595e639bcab1eaabb59775ea70fe2b0a6211),
            prevHash: bytes32(0xf88aad05419f10b5b03574ebab919a5a964706c28b1d149b2aab774420aa0706),
            numFinal: 1024,
            merkleProof: [
                bytes32(0x4ab44c5d0dd4724b0637ee2ad4d64848fa71a060783437a6671d1b1b06206614),
                bytes32(0x73a05e8942cdcad710798edf942948924bd4ba44c952e1170dfa3b80a571ba7a),
                bytes32(0x938eda5513c6629c23617e4a8b84f193494bd03e410f8e3fd4b6dbaa1ed4e587),
                bytes32(0xb69a70e148bfcafef4053e2a650fb7e4e504c2c6e4fa93cdb0990f8b6ba3ee26),
                bytes32(0x0afb22c5c9a437e08212bd10a91ffcb5d7e7fb6f6411fed58fe680ddbcb3644e),
                bytes32(0x066d30c6880001e9a3d4133a993cc653ee05fbb6b4fd5cc48dfeb7ed7ae79ea7),
                bytes32(0x4af518c22470563f5d190c5ec4dbaf2a67b3b61f3f4449d87ea0aeb39690aa20),
                bytes32(0x0f90276e97536890bcdeb5497489ecb775e3e77fd7a5332bb43616df22f9a7ce),
                bytes32(0xc8be8451874f7f80c5fc117278c4b60ae51eac27ddd619fc3aca76d612f6f523),
                bytes32(0xc446d346a6047db65f23bd4febbcbc9241e36d7adf510ee11e2579a0c7154e4c)
            ]
        });

        (
            int56 twaTick,
            uint160 twaLiquidity,
            Oracle.Observation memory startObservation,
            Oracle.Observation memory endObservation
        ) = oracle.verifyUniswapV3TWAP(startBlock, endBlock, proof);
        emit log_int(twaTick);
        emit log_uint(twaLiquidity);
        startObservation.initialized = false;
        endObservation.initialized = false;
        emit log_bytes32(startObservation.pack());
        emit log_bytes32(endObservation.pack());
        require(oracle.twapObservations(bytes28(abi.encodePacked(address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640), startBlock.blockNumber, endBlock.blockNumber)))
        == keccak256(abi.encodePacked(startObservation.pack(), endObservation.pack())));
    }
}
