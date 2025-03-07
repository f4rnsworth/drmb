// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VestingPool is Ownable, ReentrancyGuard {
    IERC20 public usdcToken;

    uint256 public roundStartDate;
    uint256 public dispersalDate;
    uint256 public constant APY = 6; // 6% Fixed APY
    uint256 public constant ONE_YEAR = 365 days;
    uint256 public dispersalFunds;

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

    mapping(address => bool) public allowList;

    event Deposited(address indexed user, uint256 amount);
    event FundsTransferredToOwner(uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event MembershipPaid(address indexed user, uint256 expiry);

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

    modifier onlyExistingMember() {
        require(memberDeposits[msg.sender].amount > 0, "Not a member");
        _;
    }

    // set msg.sender to owner
    constructor(
        address initialOwner,
        address _usdcToken,
        uint256 _roundStartDate
    ) Ownable(initialOwner) {
        usdcToken = IERC20(_usdcToken);
        roundStartDate = _roundStartDate;
        dispersalDate = _roundStartDate + ONE_YEAR;
    }

    // set the roundStartDate, allowing for follow on rounds
    // should not allow modification of an active round
    function setRoundStartDate(uint256 _newStartDate) external onlyOwner {
        // check roundStartDate is greater than current date
        require(block.timestamp < roundStartDate, "Cannot modify active round");
        // check _newStartDate is not in the past
        require(
            _newStartDate > block.timestamp,
            "start date must be in the future"
        );

        // set new roundStartDate
        roundStartDate = _newStartDate;
    }

    function addToAllowList(address _user) external onlyOwner {
        allowList[_user] = true;
    }

    function removeFromAllowList(address _user) external onlyOwner {
        allowList[_user] = false;
    }

    function isAllowed(address _user) external view returns (bool) {
        return allowList[_user];
    }

    // 2500 cap on total amount depositable
    function deposit(uint256 _amount) external onlyBeforeStart {
        // make sure address sending deposit is on the allow list
        require(allowList[msg.sender], "Not invited to this round");
        // check for membership before staking
        require(
            membershipExpiry[msg.sender] >= block.timestamp,
            "Membership expired"
        );
        require(_amount > 0, "Deposit must be greater than zero");
        require(
            memberDeposits[msg.sender].amount + _amount <= 2500,
            "Max balance 2500 usdc"
        );

        // transfer from user to contract
        usdcToken.transferFrom(msg.sender, address(this), _amount);

        //record wallet, deposit amount and withdrawl = false
        memberDeposits[msg.sender].amount += _amount;
        if (memberDeposits[msg.sender].amount == 0) {
            members.push(msg.sender);
        }
        totalDeposited += _amount;

        emit Deposited(msg.sender, _amount);
    }

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    // ensure membership is expired
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
        if (membershipExpiry[msg.sender] > block.timestamp) {
            membershipExpiry[msg.sender] += ONE_YEAR;
        } else {
            membershipExpiry[msg.sender] =
                max(membershipExpiry[msg.sender], block.timestamp) +
                ONE_YEAR;
        }
        emit MembershipPaid(msg.sender, membershipExpiry[msg.sender]);
    }

    // move the funds to the owners wallet after start date event
    function transferToOwner() external onlyAfterStart onlyOwner {
        // ensure funds present
        require(totalDeposited > 0, "No funds to transfer");

        //transfer balance to owner
        uint256 balance = usdcToken.balanceOf(address(this));
        usdcToken.transfer(owner(), balance);

        emit FundsTransferredToOwner(balance);
    }

    // allows owner to deposit funds 7 days before dispersalDate
    function depositForDispersal(uint256 _amount) external onlyOwner {
        require(
            block.timestamp >= dispersalDate - 7 days,
            "Cannot fund too early"
        );

        // transfer usdc from owner to contract
        usdcToken.transferFrom(msg.sender, address(this), _amount);
        dispersalFunds += _amount;
    }

    // allows member to withdraw funds after dispersalDate
    function withdraw()
        external
        onlyAfterDispersal
        nonReentrant
        onlyExistingMember
    {
        // also check thier membership before allowing withdrawls
        require(
            membershipExpiry[msg.sender] >= dispersalDate ||
                membershipExpiry[msg.sender] >= block.timestamp,
            "Membership expired"
        );

        // cheacks userDeposit to ensure wallet is owed funds and has not been withdrawn already
        UserDeposit storage userDeposit = memberDeposits[msg.sender];
        require(userDeposit.amount > 0, "No deposit found");
        require(!userDeposit.withdrawn, "Already withdrawn");

        // calculates interest accrued and totalReturn amount
        uint256 interest = (userDeposit.amount * APY * ONE_YEAR) /
            (100 * ONE_YEAR);
        uint256 totalReturn = userDeposit.amount + interest;

        // set userDeposit withdrawn bool to true and transfers funds from contract to member
        userDeposit.withdrawn = true;
        usdcToken.transfer(msg.sender, totalReturn);

        emit Withdrawn(msg.sender, totalReturn);
    }

    function recoverFunds(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(owner(), _amount);
    }
}
