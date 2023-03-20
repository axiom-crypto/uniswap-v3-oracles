// @notice This is a script can be used to TEST deploy UniswapV3Oracle contract and SNARK verifier.
//         We do not recommend using it for production deployment.
// SPDX-License-Identifier: MIT 
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import {UniswapV3Oracle} from "../src/UniswapV3Oracle.sol";

contract UniswapV3OracleScript is Script {
    UniswapV3Oracle oracle;
    function deployVerifier(string memory fileName) public returns (address) {
        string memory bashCommand = string.concat(
            'cast abi-encode "f(bytes)" $(solc --yul ', string.concat(fileName, ".yul --bin | tail -1)")
        );

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory bytecode = abi.decode(vm.ffi(inputs), (bytes));

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(deployedAddress != address(0), "Could not deploy Yul contract");

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ANVIL_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address AXIOM_ADDRESS = 0x01d5b501C1fc0121e1411970fb79c322737025c2;
        address verifierAddress = deployVerifier("../circuits/data/deployed_verifier");
        UniswapV3Oracle oracle = new UniswapV3Oracle(AXIOM_ADDRESS, verifierAddress);

        vm.stopBroadcast();
    }
}
