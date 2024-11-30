pragma solidity ^0.8.24;

import "./IHumanResources.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./IWETH.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract HumanResources is IHumanResources {

    struct EmployeeData {
        uint256 weeklyUsdSalary;
        uint256 employeeSince;
        uint256 terminationTime;
        bool preferesUsd;
        uint256 lastWithdrawalTime;
        bool wasEverRegistered;
        uint256 accumulatedUntilTermination;
    }
    /**
     * swap from usdc to WETH and then just transfer WETH which gets converted
     * no debt
     * 3 pool fees take one from the first 2 when swapping USDC
     * ExactSingleInputParams from that interface to create
     * need to import that interface from github
     * salary available probably needs scaling down
     * oracle gets some off chain data so its fine
     * call/send/transfer should not infinitely fail
     * scale the scaled by 6 usdc to 18 decimals 
     */
    address manager;
    mapping(address => EmployeeData) employeesData;
    mapping(address => bool) registrationStatus;
    uint256 activeEmployees;
    address USDC_ADDRESS = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    AggregatorV3Interface priceFeed;
    uint256 decimals = 18;
    
    constructor() {
        manager = msg.sender;
        activeEmployees = 0;
        priceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
    }

    modifier onlyManager {
        if(msg.sender != manager) {
            revert NotAuthorized();
        }
        _;
    }

    function registerEmployee(
        address employee,
        uint256 weeklyUsdSalary
    ) external override {
        if(registrationStatus[employee]) {
            revert EmployeeAlreadyRegistered();
        }
        employeesData[employee].weeklyUsdSalary = weeklyUsdSalary;
        registrationStatus[employee] = true;
        activeEmployees++;
        employeesData[employee].employeeSince = block.timestamp; // multiple potential employeeSince
        employeesData[employee].terminationTime = 0;
        employeesData[employee].preferesUsd = true; 
        employeesData[employee].lastWithdrawalTime = block.timestamp;
        employeesData[employee].wasEverRegistered = true;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    function terminateEmployee(address employee) external override onlyManager {
       
        if(!registrationStatus[employee]) {
            revert EmployeeNotRegistered();
        }
        activeEmployees--;
        registrationStatus[employee] = false;
        employeesData[employee].terminationTime = block.timestamp;
        employeesData[employee].accumulatedUntilTermination += lastActivePeriod(employee);
        emit EmployeeTerminated(employee);
    }

    function calculateAvailableSalary(address employee) view internal returns (uint256) {
        uint256 accumulated = employeesData[employee].accumulatedUntilTermination;
        if(!registrationStatus[employee]) {
            return accumulated;
        }
        return accumulated + lastActivePeriod(employee);
    }

    function lastActivePeriod(address employee) view internal returns (uint256) {
        uint256 currentTime = block.timestamp;
        uint256 timePassed = currentTime - employeesData[employee].lastWithdrawalTime;
        uint256 secondsPerWeek = 60 * 60 * 24 * 7;
        return employeesData[employee].weeklyUsdSalary * timePassed / secondsPerWeek;
    }

    function withdrawSalary() public override {
        address employee = msg.sender;
        if(!employeesData[employee].wasEverRegistered) {
            revert NotAuthorized();
        }
        uint256 availableSalary = calculateAvailableSalary(employee);
        employeesData[employee].accumulatedUntilTermination = 0;

        //uint256 lastWithdrawalTime = employeesData[employee].lastWithdrawalTime;
        employeesData[employee].lastWithdrawalTime = block.timestamp;

        if(employeesData[employee].preferesUsd) {
            IERC20 usdc = IERC20(USDC_ADDRESS);
            usdc.transfer(employee, usdToUsdc(availableSalary)); // TODO maybe see if fails what to do
        
        } else {
            address tokenIn = USDC_ADDRESS;
            address tokenOut = WETH_ADDRESS;
            uint24 fee = 3000;
            uint256 amountIn = usdToUsdc(availableSalary);
            address recipient = employee;
            uint256 minutesToWait = 5;
            uint256 deadline = block.timestamp + 60 * minutesToWait;
            uint160 sqrtPriceLimitX96 = 0;
            uint256 amountInAfterTax = (availableSalary * 997 / 1000); 
            uint256 oracleDecimals = priceFeed.decimals();
            int256 answer;
            (, answer, , , ) = priceFeed.latestRoundData();
            uint256 expectedAmountOut;
            if(decimals > oracleDecimals) {
                expectedAmountOut = amountInAfterTax * (uint256(answer) * (10 ** (decimals - oracleDecimals)));
            } else {
                expectedAmountOut = amountInAfterTax * uint256(answer) / (10 ** (oracleDecimals - decimals));   
            }

            uint256 amountOutMinimum = expectedAmountOut * 98 / 100;

            ISwapRouter.ExactInputSingleParams memory input = ISwapRouter.ExactInputSingleParams(tokenIn, tokenOut, fee, recipient, deadline, amountIn, amountOutMinimum, sqrtPriceLimitX96);
            ISwapRouter uniswap = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
            uint256 amountOut = uniswap.exactInputSingle(input);
            IWETH(0x4200000000000000000000000000000000000006).withdraw(amountOut);
        }
        emit SalaryWithdrawn(employee, !employeesData[employee].preferesUsd, availableSalary);
    }

    function switchCurrency() external override {
        if(!registrationStatus[msg.sender]) {
            revert NotAuthorized();
        }
        withdrawSalary();
        employeesData[msg.sender].preferesUsd = !employeesData[msg.sender].preferesUsd;
        emit CurrencySwitched(msg.sender, employeesData[msg.sender].preferesUsd);
    }

    function salaryAvailable(
        address employee
    ) external view override returns (uint256) {
        if(!employeesData[employee].wasEverRegistered) {
            revert NotAuthorized();
        }
        uint256 availableSalaryUsd = calculateAvailableSalary(employee);
        uint256 availableSalaryUsdc = usdToUsdc(availableSalaryUsd);
        if(employeesData[employee].preferesUsd) {
            return availableSalaryUsdc;
        }
        uint256 oracleDecimals = priceFeed.decimals();
        int256 answer;
        (, answer, , , ) = priceFeed.latestRoundData();
        uint256 availableEth;
        if(decimals > oracleDecimals) {
            availableEth = availableSalaryUsd * (uint256(answer) * (10 ** (decimals - oracleDecimals)));
        } else {
            availableEth = availableSalaryUsd * uint256(answer) / (10 ** (oracleDecimals - decimals));   
        }
        return availableEth;
    }

    function hrManager() external view override returns (address) {
        return manager;
    }

    function getActiveEmployeeCount()
        external
        view
        override
        returns (uint256)
    {
        return activeEmployees;
    }

    function getEmployeeInfo(
        address employee
    )
        external
        view
        override
        returns (
            uint256 weeklyUsdSalary,
            uint256 employedSince,
            uint256 terminatedAt
        )
    {
    
        if(!registrationStatus[employee]) {
            return (0, 0, 0);
        }
        return (employeesData[employee].weeklyUsdSalary, employeesData[employee].employeeSince, employeesData[employee].terminationTime);
    }

    function scale(uint256 value) internal pure returns (uint256) {
        return value * 1e18;
    }

    function fromScale(uint256 value) internal pure returns (uint256) {
        return value / 1e18;
    }

    function usdToUsdc(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

}