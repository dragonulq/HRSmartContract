pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import "forge-std/console.sol";

import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract PrintTest is Test {

    constructor() {

    }

    function testPrint() external {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
       
       console.log(priceFeed.description());
        assert(1 == 1);
    }

}