// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

//import "forge-std/Script.sol";
import "./HumanResources.sol";
import "../lib/forge-std/src/console.sol";
import "../lib/forge-std/src/Script.sol";

contract LocalDeployScript is Script {
    function run() external {
        vm.startBroadcast();
        
        // Deploy your contract
        HumanResources humanResources = new HumanResources();

        console.log("Contract deployed at:", address(humanResources));
        
        vm.stopBroadcast();
    }
}
