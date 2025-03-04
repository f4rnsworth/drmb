// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VestingPool is Ownable {
    IERC20 public usdcToken;

    uint256 public roundStartDate;
    uint256 public dispersalDate;
    uint256 public constant APY = 6; // 8% Fixed APY
    uint256 public constant ONE_YEAR = 365 days;

    struct UserDeposit {
        uint256 amount;
        bool withdrawn;
    }

    mapping(address => UserDeposit) public memberDeposits;
    address[] public members;
    uint256 public totalDeposited;

    // add tracking structures for membership fee
    mapping(address => uint256) public membershipExpiry;
    uint256 public constant MEMBERSHIP_FEE = 25 * 10 ** 6; // 25 usdc

    event Deposited(address indexed user, uint256 amount);
    event FundsTransferredToOwner(uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    modifier onlyBeforeStart() {
        require(block.timestamp < roundStartDate, "Deposits closed");
        _;
    }

    modifier onlyAfterStart() {
        require(block.timestamp >= roundStartDate, "Not started yet");
        _;
    }

    modifier onlyAfterDispersal() {
        require(block.timestamp >= dispersalDate, "Funds not available yet");
        _;
    }

    constructor(
        address _usdcToken,
        uint256 _roundStartDate
    ) Ownable(msg.sender) {
        usdcToken = IERC20(_usdcToken);
        roundStartDate = _roundStartDate;
        dispersalDate = _roundStartDate + ONE_YEAR;
    }

    // 2500 cap on total amount depositable
    function deposit(uint256 _amount) external onlyBeforeStart {
        // check for membership before staking
        require(
            membershipExpiry[msg.sender] >= block.timestamp,
            "Membership expired"
        );
        require(_amount > 0, "Deposit must be greater than zero");
        require(memberDeposits[msg.sender].amount <= 2500, "Already deposited");

        usdcToken.transferFrom(msg.sender, address(this), _amount);

        memberDeposits[msg.sender] = UserDeposit(_amount, false);
        members.push(msg.sender);
        totalDeposited += _amount;

        emit Deposited(msg.sender, _amount);
    }

    function payMembership() external {
        require(
            membershipExpiry[msg.sender] < block.timestamp,
            "Membership active"
        );

        // Transfer 25 usdc from user to contract
        require(
            usdcToken.transferFrom(msg.sender, address(this), MEMBERSHIP_FEE),
            "USDC transfer failed"
        );

        // Extend Membership for one year
        membershipExpiry[msg.sender] = block.timestamp + ONE_YEAR;
    }

    // should move the funds to the owners wallet after start date event
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
        // also check thier membership before allowing withdrawls
        require(
            membershipExpiry[msg.sender] >= block.timestamp,
            "Membership expired"
        );
        UserDeposit storage userDeposit = memberDeposits[msg.sender];
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
