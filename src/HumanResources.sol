pragma solidity ^0.8.24;

import "./IHumanResources.sol";

contract HumanResources is IHumanResources {

    address public manager;
    mapping(address => uint256) weeklyUsdSalaries;
    mapping(address => uint256) availableSalaries;
    mapping(address => uint256) employeeSince;
    mapping(address => uint256) terminationTimes;
    
    address[] employees;
    bool[] registrationStatus;
    uint256 activeEmployees;

    constructor() {
        manager = msg.sender;
        activeEmployees = 0;
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
        if(employeeAlreadyRegistered(employee)) {
            revert EmployeeAlreadyRegistered();
        }
        weeklyUsdSalaries[employee] = scale(weeklyUsdSalary);
        employees.push(employee);
        registrationStatus.push(true);
        activeEmployees++;
        employeeSince[employee] = block.timestamp;
        terminationTimes[employee] = 0;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    function employeeAlreadyRegistered(address employee) internal view returns (bool) {
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
        uint256 employeeIndex;
        for(uint256 i = 0;i < employees.length;i++) {
            if(employees[i] == employee) {
                foundEmployee = true;
                employeeIndex = i;
                break;    
            }
        }
        if(!foundEmployee) {
            revert EmployeeNotRegistered();
        }
        activeEmployees--;
        registrationStatus[employeeIndex] = false;
        terminationTimes[employee] = block.timestamp;
        emit EmployeeTerminated(employee);
    }

    function withdrawSalary() external override {}

    function switchCurrency() external override {}

    function salaryAvailable(
        address employee
    ) external view override returns (uint256) {
        return fromScale(availableSalaries[employee]);
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
        bool foundEmployee = false;
        for(uint256 i = 0;i < employees.length;i++) {
            if(employees[i] == employee) {
                foundEmployee = true;
                break;
            }
        }
        if(!foundEmployee) {
            return (0, 0, 0);
        }
        return (weeklyUsdSalaries[employee], employeeSince[employee], terminationTimes[employee]);
    }

    function scale(uint256 value) internal pure returns (uint256) {
        return value * 1e18;
    }

    function fromScale(uint256 value) internal pure returns (uint256) {
        return value / 1e18;
    }

}