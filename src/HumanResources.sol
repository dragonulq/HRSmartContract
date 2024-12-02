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
    
    address immutable manager;
    mapping(address => EmployeeData) employeesData;
    mapping(address => bool) registrationStatus;
    uint256 activeEmployees;
    address USDC_ADDRESS = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    AggregatorV3Interface priceFeed;
    uint256 decimals = 18;
    address employeeGettingPaid;
    bool enteredReceiveOnce;
    uint256 secondsPerWeek = 60 * 60 * 24 * 7;
    
    constructor() {
        manager = msg.sender;
        activeEmployees = 0;
        priceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
        enteredReceiveOnce = true;
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
    ) external override onlyManager {
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
        return employeesData[employee].weeklyUsdSalary * timePassed / secondsPerWeek;
    }

    function withdrawSalary() public override {
        address employee = msg.sender;
        if(!employeesData[employee].wasEverRegistered) {
            revert NotAuthorized();
        }
        uint256 availableSalary = calculateAvailableSalary(employee);
        employeesData[employee].accumulatedUntilTermination = 0;

        employeesData[employee].lastWithdrawalTime = block.timestamp;
        IERC20 usdc = IERC20(USDC_ADDRESS);
        if(employeesData[employee].preferesUsd) {
            
            usdc.transfer(employee, availableSalary / 1e12); // TODO maybe see if fails what to do
        
        } else {
            uint256 amountIn = availableSalary / 1e12;//usdToUsdc(availableSalary);
            uint256 deadline = block.timestamp + 60 * 5; //wait 5 minutes
            uint256 amountInAfterTax = (availableSalary * 997 / 1000); 
            uint256 oracleDecimals = priceFeed.decimals();
            int256 answer;
            (, answer, , , ) = priceFeed.latestRoundData();
            uint256 expectedAmountOut;
            uint256 ethPrice = uint256(answer) * 10 ** (decimals - oracleDecimals);
            expectedAmountOut = amountInAfterTax * 1e18 / ethPrice;    // in wei

            uint256 amountOutMinimum = expectedAmountOut * 98 / 100;
            
            ISwapRouter.ExactInputSingleParams memory input = ISwapRouter.ExactInputSingleParams(USDC_ADDRESS, WETH_ADDRESS, 3000, address(this), deadline, amountIn, amountOutMinimum, 0);
            ISwapRouter uniswap = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
            usdc.approve(address(uniswap), amountIn);
            uint256 amountOut = uniswap.exactInputSingle(input);
            employeeGettingPaid = employee;
            enteredReceiveOnce = false;
            IWETH(0x4200000000000000000000000000000000000006).withdraw(amountOut);
            employee.call{value: amountOut}("");
        }
        emit SalaryWithdrawn(employee, !employeesData[employee].preferesUsd, availableSalary);
    }

    receive() external payable {
    
    }

    fallback() external payable {
       
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
        uint256 availableSalaryUsdc = availableSalaryUsd / 1e12;//usdToUsdc(availableSalaryUsd);
        if(employeesData[employee].preferesUsd) {
            return availableSalaryUsdc;
        }
        uint256 oracleDecimals = priceFeed.decimals();
        int256 answer;
        (, answer, , , ) = priceFeed.latestRoundData();
        
        uint256 ethPrice = uint256(answer) * 10 ** (decimals - oracleDecimals);
    
        return availableSalaryUsd * 1e18 / ethPrice;  //return in wei
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

    function usdToUsdc(uint256 value) internal pure returns (uint256) {
        return value / 1e12;
    }

}