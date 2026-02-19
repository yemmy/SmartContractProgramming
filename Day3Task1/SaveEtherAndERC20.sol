// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Minimal ERC20 interface
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Vault for saving ETH and ERC20 per user
contract SaveEtherAndERC20 {
    // Reentrancy guard
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrancy");
        _locked = 2;
        _;
        _locked = 1;
    }

    // User ETH balances
    mapping(address => uint256) private _ethBalance;

    // User token balances
    mapping(address => mapping(address => uint256)) private _tokenBalance;

    // Events
    event EthDeposited(address indexed user, uint256 amount);
    event EthWithdrawn(address indexed user, uint256 amount);
    event TokenDeposited(address indexed user, address indexed token, uint256 amount);
    event TokenWithdrawn(address indexed user, address indexed token, uint256 amount);

    // View ETH balance
    function ethBalanceOf(address user) external view returns (uint256) {
        return _ethBalance[user];
    }

    // View token balance
    function tokenBalanceOf(address user, address token) external view returns (uint256) {
        return _tokenBalance[user][token];
    }

    // Deposit ETH
    function depositEth() external payable {
        require(msg.value > 0, "No ETH");
        _ethBalance[msg.sender] += msg.value;
        emit EthDeposited(msg.sender, msg.value);
    }

    // Receive ETH directly
    receive() external payable {
        require(msg.value > 0, "No ETH");
        _ethBalance[msg.sender] += msg.value;
        emit EthDeposited(msg.sender, msg.value);
    }

    // Withdraw ETH
    function withdrawEth(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero");
        uint256 bal = _ethBalance[msg.sender];
        require(bal >= amount, "Insufficient");

        _ethBalance[msg.sender] = bal - amount;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Transfer failed");

        emit EthWithdrawn(msg.sender, amount);
    }

    // Deposit ERC20 (requires approve)
    function depositToken(address token, uint256 amount) external {
        require(token != address(0), "Zero token");
        require(amount > 0, "Zero");

        bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom failed");

        _tokenBalance[msg.sender][token] += amount;
        emit TokenDeposited(msg.sender, token, amount);
    }

    // Withdraw ERC20
    function withdrawToken(address token, uint256 amount) external nonReentrant {
        require(token != address(0), "Zero token");
        require(amount > 0, "Zero");

        uint256 bal = _tokenBalance[msg.sender][token];
        require(bal >= amount, "Insufficient");

        _tokenBalance[msg.sender][token] = bal - amount;

        bool ok = IERC20(token).transfer(msg.sender, amount);
        require(ok, "Transfer failed");

        emit TokenWithdrawn(msg.sender, token, amount);
    }

    // Withdraw all ETH
    function withdrawAllEth() external nonReentrant {
        uint256 amount = _ethBalance[msg.sender];
        require(amount > 0, "No balance");

        _ethBalance[msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Transfer failed");

        emit EthWithdrawn(msg.sender, amount);
    }

    // Withdraw all of a token
    function withdrawAllToken(address token) external nonReentrant {
        require(token != address(0), "Zero token");

        uint256 amount = _tokenBalance[msg.sender][token];
        require(amount > 0, "No balance");

        _tokenBalance[msg.sender][token] = 0;

        bool ok = IERC20(token).transfer(msg.sender, amount);
        require(ok, "Transfer failed");

        emit TokenWithdrawn(msg.sender, token, amount);
    }
}
