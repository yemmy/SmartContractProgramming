// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SaveEtherAndERC20 {
    
    mapping(address => uint256) public ethBalances;
    mapping(address => mapping(address => uint256)) public tokenBalances;
    
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    
    // Deposit ETH
    function depositETH() external payable {
        require(msg.value > 0, "Amount must be > 0");
        ethBalances[msg.sender] += msg.value;
        emit Deposited(msg.sender, address(0), msg.value);
    }
    
    // Deposit ERC20
    function depositERC20(address token, uint256 amount) external {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount must be > 0");
        
        transferFrom(msg.sender, address(this), amount);
        tokenBalances[msg.sender][token] += amount;
        
        emit Deposited(msg.sender, token, amount);
    }
    
    // Withdraw ETH
    function withdrawETH(uint256 amount) external {
        require(ethBalances[msg.sender] >= amount, "Insufficient ETH");
        
        ethBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        
        emit Withdrawn(msg.sender, address(0), amount);
    }
    
    // Withdraw ERC20
    function withdrawERC20(address token, uint256 amount) external {
        require(tokenBalances[msg.sender][token] >= amount, "Insufficient tokens");
        
        tokenBalances[msg.sender][token] -= amount;
        transferFrom(address(this), msg.sender, amount);
        
        emit Withdrawn(msg.sender, token, amount);
    }
    
    // Check balances
    function getETHBalance(address user) external view returns (uint256) {
        return ethBalances[user];
    }
    
    function getTokenBalance(address user, address token) external view returns (uint256) {
        return tokenBalances[user][token];
    }

      function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        address spender = msg.sender;
        _transfer(from, to, amount);
        return true;
    }
    
    // Internal transfer function
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        require(to != address(this), "ERC20: transfer to contract itself");
        
        uint256 fromBalance = tokenBalances[from];
        require(fromBalance >= amount, "ERC20: insufficient balance");
        
        // Check for overflow (though Solidity 0.8+ automatically checks)
        require(tokenBalances[to] + amount >= tokenBalances[to], "ERC20: overflow");
        
        // Update balances
        tokenBalances[from] = fromBalance - amount;
        tokenBalances[to] += amount;
    }
    
    // Fallback
    receive() external payable {
    }
}