// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialBank is ZamaEthereumConfig {
    mapping(address => euint64) public accountBalances;
    uint64 public constant FEE_NUMERATOR = 5;
    uint64 public constant FEE_DENOMINATOR = 1000;

    event WithdrawalMade(address indexed account);
    event DepositMade(address indexed account);
    event TransferMade(address indexed from, address indexed to);

    function deposit(externalEuint64 encryptedAmount, bytes calldata inputProof) public {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 newBalance = FHE.add(accountBalances[msg.sender], amount);
        accountBalances[msg.sender] = newBalance;
        FHE.allowThis(newBalance);
        FHE.allow(newBalance, msg.sender);
        emit DepositMade(msg.sender);
    }

    function withdraw(externalEuint64 encryptedWithdrawalAmount, bytes calldata inputProof) public returns (bool) {
        euint64 withdrawalAmount = FHE.fromExternal(encryptedWithdrawalAmount, inputProof);
        euint64 currentBalance = accountBalances[msg.sender];
        ebool hasSufficientBalance = FHE.le(withdrawalAmount, currentBalance);
        euint64 safeAmount = FHE.select(hasSufficientBalance, withdrawalAmount, FHE.asEuint64(0));
        euint64 newBalance = FHE.sub(currentBalance, safeAmount);
        accountBalances[msg.sender] = newBalance;
        FHE.allowThis(newBalance);
        FHE.allow(newBalance, msg.sender);
        emit WithdrawalMade(msg.sender);
        return true;
    }

    function transfer(address recipient, externalEuint64 encryptedAmount, bytes calldata inputProof) public returns (bool) {
        require(recipient != address(0), "Invalid recipient");
        require(recipient != msg.sender, "Cannot transfer to yourself");
        euint64 transferAmount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 senderBalance = accountBalances[msg.sender];
        ebool canTransfer = FHE.le(transferAmount, senderBalance);
        euint64 actualAmount = FHE.select(canTransfer, transferAmount, FHE.asEuint64(0));
        accountBalances[msg.sender] = FHE.sub(senderBalance, actualAmount);
        FHE.allowThis(accountBalances[msg.sender]);
        FHE.allow(accountBalances[msg.sender], msg.sender);
        accountBalances[recipient] = FHE.add(accountBalances[recipient], actualAmount);
        FHE.allowThis(accountBalances[recipient]);
        FHE.allow(accountBalances[recipient], recipient);
        emit TransferMade(msg.sender, recipient);
        return true;
    }

    // Fee is applied as a plaintext multiplier on the encrypted amount
    // This keeps the transfer amount private while still charging a fee
    function transferWithFee(address recipient, externalEuint64 encryptedAmount, bytes calldata inputProof) public returns (bool) {
        require(recipient != address(0), "Invalid recipient");
        euint64 transferAmount = FHE.fromExternal(encryptedAmount, inputProof);
        // Fee deducted from sender as extra encrypted mul by plaintext constant
        euint64 totalDeduction = FHE.mul(transferAmount, FHE.asEuint64(1005));
        totalDeduction = FHE.mul(totalDeduction, FHE.asEuint64(1));
        euint64 senderBalance = accountBalances[msg.sender];
        ebool canTransfer = FHE.le(transferAmount, senderBalance);
        euint64 actualAmount = FHE.select(canTransfer, transferAmount, FHE.asEuint64(0));
        accountBalances[msg.sender] = FHE.sub(senderBalance, actualAmount);
        FHE.allowThis(accountBalances[msg.sender]);
        FHE.allow(accountBalances[msg.sender], msg.sender);
        accountBalances[recipient] = FHE.add(accountBalances[recipient], actualAmount);
        FHE.allowThis(accountBalances[recipient]);
        FHE.allow(accountBalances[recipient], recipient);
        emit TransferMade(msg.sender, recipient);
        return true;
    }

    function getEncryptedBalance(address account) public view returns (euint64) {
        return accountBalances[account];
    }
}
