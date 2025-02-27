// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VestingPool is Ownable {
    IERC20 public usdcToken;

    uint256 public startDate;
    uint256 public dispersalDate;
    uint256 public constant APY = 8; // 8% Fixed APY
    uint256 public constant ONE_YEAR = 365 days;

    struct UserDeposit {
        uint256 amount;
        bool withdrawn;
    }

    mapping(address => UserDeposit) public deposits;
    address[] public depositors;
    uint256 public totalDeposited;

    event Deposited(address indexed user, uint256 amount);
    event FundsTransferredToOwner(uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    modifier onlyBeforeStart() {
        require(block.timestamp < startDate, "Deposits closed");
        _;
    }

    modifier onlyAfterStart() {
        require(block.timestamp >= startDate, "Not started yet");
        _;
    }

    modifier onlyAfterDispersal() {
        require(block.timestamp >= dispersalDate, "Funds not available yet");
        _;
    }

    constructor(address _usdcToken, uint256 _startDate) Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
        startDate = _startDate;
        dispersalDate = _startDate + ONE_YEAR;
    }

    function deposit(uint256 _amount) external onlyBeforeStart {
        require(_amount > 0, "Deposit must be greater than zero");
        require(deposits[msg.sender].amount == 0, "Already deposited");

        usdcToken.transferFrom(msg.sender, address(this), _amount);

        deposits[msg.sender] = UserDeposit(_amount, false);
        depositors.push(msg.sender);
        totalDeposited += _amount;

        emit Deposited(msg.sender, _amount);
    }

    function transferToOwner() external onlyAfterStart onlyOwner {
        require(totalDeposited > 0, "No funds to transfer");

        uint256 balance = usdcToken.balanceOf(address(this));
        usdcToken.transfer(owner(), balance);

        emit FundsTransferredToOwner(balance);
    }

    function depositForDispersal(uint256 _amount) external onlyOwner {
        require(
            block.timestamp >= dispersalDate - 7 days,
            "Cannot fund too early"
        );
        usdcToken.transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw() external onlyAfterDispersal {
        UserDeposit storage userDeposit = deposits[msg.sender];
        require(userDeposit.amount > 0, "No deposit found");
        require(!userDeposit.withdrawn, "Already withdrawn");

        uint256 interest = (userDeposit.amount * APY * ONE_YEAR) /
            (100 * ONE_YEAR);
        uint256 totalReturn = userDeposit.amount + interest;

        userDeposit.withdrawn = true;
        usdcToken.transfer(msg.sender, totalReturn);

        emit Withdrawn(msg.sender, totalReturn);
    }
}
