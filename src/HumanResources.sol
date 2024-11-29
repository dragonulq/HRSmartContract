pragma solidity ^0.8.24;

import "./IHumanResources.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


contract HumanResources is IHumanResources {

    struct EmployeeData {
        uint256 weeklyUsdSalary;
        uint256 availableSalary;
        uint256 employeeSince;
        uint256 terminationTime;
        bool registrationStatus;
        bool preferesUsd;
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
    address public manager;
    mapping(address => EmployeeData) employeesData;
    address[] employees;
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
        if(employeeRegistered(employee)) {
            revert EmployeeAlreadyRegistered();
        }
        employeesData[employee].weeklyUsdSalary = weeklyUsdSalary;
        employees.push(employee);
        employeesData[employee].registrationStatus = true;
        activeEmployees++;
        employeesData[employee].employeeSince = block.timestamp;
        employeesData[employee].terminationTime = 0;
        employeesData[employee].preferesUsd = true; // TODO if he prefered ETH, got terminated and reregistered he should prefer ETH
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    function employeeRegistered(address employee) internal view returns (bool) {
        uint256 length = employees.length;
        for(uint256 i = 0;i < length;i++) {
            if(employees[i] == employee) {
                return true;
            }
        }
        return false;
    }

    function terminateEmployee(address employee) external override onlyManager {
        bool foundEmployee = false;
        for(uint256 i = 0;i < employees.length;i++) {
            if(employees[i] == employee) {
                foundEmployee = true;
                break;    
            }
        }
        if(!foundEmployee) {
            revert EmployeeNotRegistered();
        }
        activeEmployees--;
        employeesData[employee].registrationStatus = false;
        employeesData[employee].terminationTime = block.timestamp;
        emit EmployeeTerminated(employee);
    }

    function withdrawSalary() external override {
        address employee = msg.sender;
        uint256 savedSalary = employeesData[employee].availableSalary;
        employeesData[employee].availableSalary = 0;
        if(employeesData[employee].preferesUsd) {
            (bool sent, bytes memory data) = employee.call{value: savedSalary}(""); // TODO
            if(!sent) {

            }
        } else {
            address tokenIn = USDC_ADDRESS;
            address tokenOut = WETH_ADDRESS;
            uint24 fee = 3000;
            uint256 amountIn = savedSalary;
            address recipient = employee;
            uint256 minutesToWait = 5;
            uint256 deadline = block.timestamp + 60 * minutesToWait;
            uint160 sqrtPriceLimitX96 = 0;
            uint256 amountInAfterTax = (savedSalary * 997 / 1000); 
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
            uniswap.exactInputSingle(input);
            //uint256 amountOutMinimum = expectedAmountOut * 98 / 100;
            //catBagiInAMM = catVreiSaTrimiti * 1000 / 997;
        }
        emit SalaryWithdrawn(employee, !employeesData[employee].preferesUsd, savedSalary);
    }

    function switchCurrency() external override {
        //withdrawSalary(); //TODO withdraw somehow as mentioned in spec
        employeesData[msg.sender].preferesUsd = !employeesData[msg.sender].preferesUsd;
        emit CurrencySwitched(msg.sender, employeesData[msg.sender].preferesUsd);
    }

    function salaryAvailable(
        address employee
    ) external view override returns (uint256) {
        return employeesData[employee].availableSalary;
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
    
        if(!employeeRegistered(employee)) {
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

}