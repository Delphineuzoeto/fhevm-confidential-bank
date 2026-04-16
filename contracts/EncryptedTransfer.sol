// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedTransfer is ZamaEthereumConfig {
    mapping(address => euint64) private balances;

    event TransferEvent(address indexed from, address indexed to);

    function initializeBalance(address account, euint64 initialBalance) public {
        balances[account] = initialBalance;
        FHE.allowThis(initialBalance);
        FHE.allow(initialBalance, account);
    }

    function subtractEncryptedBalance(euint64 ebalance, euint64 eamount) private returns (euint64) {
        return FHE.sub(ebalance, eamount);
    }

    function transfer(address to, externalEuint64 encryptedAmount, bytes calldata inputProof) public returns (bool) {
        require(to != address(0), "Cannot transfer to zero address");
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        address from = msg.sender;
        euint64 senderBalance = balances[from];
        ebool canTransfer = FHE.le(amount, senderBalance);
        euint64 amountToSubtract = FHE.select(canTransfer, amount, FHE.asEuint64(0));
        euint64 newSenderBalance = subtractEncryptedBalance(senderBalance, amountToSubtract);
        balances[from] = newSenderBalance;
        FHE.allowThis(newSenderBalance);
        FHE.allow(newSenderBalance, from);
        euint64 recipientBalance = balances[to];
        euint64 newRecipientBalance = FHE.add(recipientBalance, amountToSubtract);
        balances[to] = newRecipientBalance;
        FHE.allowThis(newRecipientBalance);
        FHE.allow(newRecipientBalance, to);
        emit TransferEvent(from, to);
        return true;
    }

    function subtractEncryptedBalanceOf(address account, externalEuint64 encryptedSubtractAmount, bytes calldata inputProof) public {
        require(account != address(0), "Invalid account address");
        euint64 amount = FHE.fromExternal(encryptedSubtractAmount, inputProof);
        euint64 currentBalance = balances[account];
        euint64 newBalance = subtractEncryptedBalance(currentBalance, amount);
        balances[account] = newBalance;
        FHE.allowThis(newBalance);
        FHE.allow(newBalance, account);
    }

    function balanceOf(address account) public view returns (euint64) {
        return balances[account];
    }
}
