// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract MinimalExample is ZamaEthereumConfig {
    mapping(address => euint64) private balances;

    function withdrawEncrypted(externalEuint64 encryptedAmount, bytes calldata inputProof) public {
        euint64 eamount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 newBalance = FHE.sub(balances[msg.sender], eamount);
        balances[msg.sender] = newBalance;
        FHE.allowThis(newBalance);
        FHE.allow(newBalance, msg.sender);
    }

    function balanceOf(address account) public view returns (euint64) {
        return balances[account];
    }
}
