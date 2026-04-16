# SKILL.md — Zama fhEVM Development for AI Coding Agents

> Drop this file into Claude Code, Cursor, Windsurf, or any AI coding environment.
> When a developer asks you to build a confidential smart contract using Zama fhEVM,
> follow every rule in this file exactly. Do not guess. Do not use deprecated APIs.

---

## 1. What Is fhEVM?

Zama's fhEVM is a coprocessor that brings Fully Homomorphic Encryption (FHE) to EVM chains. It lets smart contracts perform arithmetic and comparisons on **encrypted values without ever decrypting them**. The result stays encrypted on-chain. Only the authorized user can decrypt their own data.

Architecture:
- **On-chain**: Solidity contracts store encrypted handles (`euint64`, `ebool`, etc.) — these are pointers, not values
- **Off-chain coprocessors**: Zama nodes perform the actual FHE computation
- **Gateway**: Coordinates coprocessors, manages access control (ACL), handles decryption requests
- **KMS (Key Management System)**: Threshold system — no single party can decrypt user data

---

## 2. Environment Setup

### Prerequisites
- Node.js v22+ (REQUIRED — v18/v20 will cause `EBADENGINE` errors)
- npm

### Always start from the official template
```bash
git clone https://github.com/zama-ai/fhevm-hardhat-template
cd fhevm-hardhat-template
npm install
```

### Required packages
```bash
npm install @openzeppelin/confidential-contracts  # for ERC-7984
```

### Environment variables
```bash
npx hardhat vars set MNEMONIC        # your wallet mnemonic
npx hardhat vars set INFURA_API_KEY  # for Sepolia deployment
```

---

## 3. CRITICAL: API Version Rules

### ❌ DEPRECATED — Never use these
```solidity
import "fhevm/lib/TFHE.sol";                          // deprecated package
import "fhevm/abstracts/EIP712WithModifier.sol";       // deprecated
TFHE.setCoprocessor(CoprocessorSetup.defaultConfig()); // does not exist in v0.11
TFHE.add(), TFHE.sub(), TFHE.mul()                    // old namespace
TFHE.isSenderAllowed(amount)                           // replaced
bytes32 encryptedAmount                               // old input type
TFHE.asEuint64(encryptedAmount)                       // old conversion
```

### ✅ CORRECT — Always use these (@fhevm/solidity v0.11+)
```solidity
import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract MyContract is ZamaEthereumConfig {  // replaces constructor setup
    // ZamaEthereumConfig handles coprocessor config automatically
}
```

### API Migration Table
| Deprecated | Current v0.11 |
|---|---|
| `TFHE.add(a, b)` | `FHE.add(a, b)` |
| `TFHE.sub(a, b)` | `FHE.sub(a, b)` |
| `TFHE.mul(a, b)` | `FHE.mul(a, b)` |
| `TFHE.le(a, b)` | `FHE.le(a, b)` |
| `TFHE.select(c, a, b)` | `FHE.select(c, a, b)` |
| `TFHE.allowThis(v)` | `FHE.allowThis(v)` |
| `TFHE.allow(v, addr)` | `FHE.allow(v, addr)` |
| `bytes32 encryptedInput` | `externalEuint64 encryptedInput` |
| `TFHE.asEuint64(input)` | `FHE.fromExternal(input, proof)` |
| `TFHE.isSenderAllowed(v)` | Handled internally by `FHE.fromExternal()` |
| `EIP712WithModifier` base | `ZamaEthereumConfig` base |

---

## 4. Encrypted Types

```solidity
// Encrypted integers (stored on-chain as handles)
ebool    // encrypted boolean
euint8   // encrypted 8-bit uint
euint16  // encrypted 16-bit uint
euint32  // encrypted 32-bit uint
euint64  // encrypted 64-bit uint  ← USE THIS for token balances
euint128 // encrypted 128-bit uint
euint256 // encrypted 256-bit uint
eaddress // encrypted address

// External input types (for function parameters from users)
externalEuint8, externalEuint16, externalEuint32, externalEuint64
externalEuint128, externalEuint256, externalEbool, externalEaddress
```

**Rule**: User-facing function parameters that accept encrypted values from outside the contract MUST use `externalEuintXX` types, not `euintXX`. Convert with `FHE.fromExternal()`.

---

## 5. FHE Operations Reference

### Arithmetic (all return encrypted results)
```solidity
FHE.add(euint64 a, euint64 b) returns (euint64)
FHE.sub(euint64 a, euint64 b) returns (euint64)
FHE.mul(euint64 a, euint64 b) returns (euint64)
// ⚠️ FHE.div() does NOT exist — see workaround below
```

### Comparison (return ebool)
```solidity
FHE.eq(a, b)   // equal
FHE.ne(a, b)   // not equal
FHE.lt(a, b)   // less than
FHE.le(a, b)   // less than or equal
FHE.gt(a, b)   // greater than
FHE.ge(a, b)   // greater than or equal
```

### Conditional (encrypted if/else)
```solidity
FHE.select(ebool condition, euint64 ifTrue, euint64 ifFalse) returns (euint64)
```

### Bitwise
```solidity
FHE.and(a, b)
FHE.or(a, b)
FHE.xor(a, b)
```

### Type conversion
```solidity
FHE.asEuint64(uint64 plainValue)         // plaintext → encrypted
FHE.fromExternal(externalEuint64, proof) // user input → encrypted (validates proof)
```

### State checks
```solidity
FHE.isInitialized(euint64 v) returns (bool)  // check if handle is non-zero
```

---

## 6. Access Control (ACL) — Most Common Source of Bugs

Every encrypted value stored on-chain needs explicit permission grants or **users cannot decrypt their own data**.

### Rules
```solidity
// After EVERY state-changing operation that produces a new encrypted value:
FHE.allowThis(newEncryptedValue);        // allow the contract itself to use it
FHE.allow(newEncryptedValue, userAddr);  // allow a specific user to decrypt it

// For transient (temporary) access within a transaction:
FHE.allowTransient(value, address);
```

### ❌ Bug: Missing ACL after subtraction
```solidity
// WRONG — newBalance is inaccessible after this
euint64 newBalance = FHE.sub(balances[msg.sender], amount);
balances[msg.sender] = newBalance;

// CORRECT
euint64 newBalance = FHE.sub(balances[msg.sender], amount);
balances[msg.sender] = newBalance;
FHE.allowThis(newBalance);              // ← required
FHE.allow(newBalance, msg.sender);      // ← required
```

---

## 7. Input Proofs — What They Are and Why They're Needed

When a user sends an encrypted value to a contract, they must also send an **input proof** — a zero-knowledge proof that:
1. The encrypted value was correctly formed
2. The user actually knows the plaintext value
3. The value is within the valid range

Without the proof, the contract cannot safely use the input.

### Contract side
```solidity
function deposit(
    externalEuint64 encryptedAmount,  // the encrypted value handle
    bytes calldata inputProof         // the ZK proof
) public {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
    // amount is now safe to use
}
```

### Client side (TypeScript/JavaScript)
```typescript
import { ethers, fhevm } from "hardhat"; // in tests
// or
import { createFhevmInstance } from "fhevmjs"; // in frontend

// Create encrypted input with proof
const encryptedInput = await fhevm
  .createEncryptedInput(contractAddress, userAddress)
  .add64(1000)   // the plaintext value to encrypt
  .encrypt();

// encryptedInput.handles[0] = the encrypted handle (externalEuint64)
// encryptedInput.inputProof = the ZK proof (bytes)

await contract.deposit(encryptedInput.handles[0], encryptedInput.inputProof);
```

---

## 8. User Decryption (Reading Your Own Encrypted Balance)

Users decrypt their own data via EIP-712 signing — they sign a request off-chain, which is verified by Zama's Gateway KMS, which returns the decrypted value only to them.

### In Hardhat tests
```typescript
import { FhevmType } from "@fhevm/hardhat-plugin";

const encryptedBalance = await contract.getEncryptedBalance(user.address);

const clearBalance = await fhevm.userDecryptEuint(
  FhevmType.euint64,       // the encrypted type
  encryptedBalance,         // the handle
  contractAddress,          // contract that owns the value
  user,                     // the signer (must match who was FHE.allow'd)
);

console.log(clearBalance); // the actual number
```

### In frontend (fhevmjs)
```typescript
import { createFhevmInstance } from "fhevmjs";

const fhevmInstance = await createFhevmInstance({
  kmsContractAddress: "0x...",
  aclContractAddress: "0x...",
  network: window.ethereum,
});

// Generate EIP-712 keypair for this session
const { publicKey, privateKey } = fhevmInstance.generateKeypair();
const eip712 = fhevmInstance.createEIP712(publicKey, contractAddress);
const signature = await signer.signTypedData(eip712.domain, eip712.types, eip712.message);

// Re-encrypt (gateway decrypts and re-encrypts with user's public key)
const encryptedBalance = await contract.getEncryptedBalance(userAddress);
const decryptedBalance = fhevmInstance.decrypt(contractAddress, encryptedBalance);
```

---

## 9. Public Decryption (Gateway Callback Pattern)

For values that need to be revealed publicly (e.g. auction results), use the Gateway callback pattern:

```solidity
import {GatewayCaller} from "@fhevm/solidity/lib/GatewayCaller.sol";
import {Gateway} from "@fhevm/solidity/lib/Gateway.sol";

contract AuctionResult is GatewayCaller {
    uint256 public revealedWinningBid;

    function requestReveal(euint64 encryptedBid) public {
        uint256[] memory handles = new uint256[](1);
        handles[0] = uint256(euint64.unwrap(encryptedBid));
        Gateway.requestDecryption(handles, this.receiveResult.selector, 0, block.timestamp + 100, false);
    }

    function receiveResult(uint256 requestId, uint64 result) public onlyGateway {
        revealedWinningBid = result;
    }
}
```

---

## 10. Complete Contract Pattern: Encrypted Banking

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialBank is ZamaEthereumConfig {
    mapping(address => euint64) private balances;

    function deposit(externalEuint64 encryptedAmount, bytes calldata inputProof) public {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 newBalance = FHE.add(balances[msg.sender], amount);
        balances[msg.sender] = newBalance;
        FHE.allowThis(newBalance);
        FHE.allow(newBalance, msg.sender);
    }

    function withdraw(externalEuint64 encryptedAmount, bytes calldata inputProof) public {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 currentBalance = balances[msg.sender];

        // Encrypted overdraft protection — no plaintext comparison needed
        ebool hasFunds = FHE.le(amount, currentBalance);
        euint64 safeAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));

        euint64 newBalance = FHE.sub(currentBalance, safeAmount);
        balances[msg.sender] = newBalance;
        FHE.allowThis(newBalance);
        FHE.allow(newBalance, msg.sender);
    }

    function transfer(address to, externalEuint64 encryptedAmount, bytes calldata inputProof) public {
        require(to != address(0) && to != msg.sender, "Invalid recipient");
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        ebool canTransfer = FHE.le(amount, balances[msg.sender]);
        euint64 actualAmount = FHE.select(canTransfer, amount, FHE.asEuint64(0));

        euint64 newSenderBalance = FHE.sub(balances[msg.sender], actualAmount);
        balances[msg.sender] = newSenderBalance;
        FHE.allowThis(newSenderBalance);
        FHE.allow(newSenderBalance, msg.sender);

        euint64 newRecipientBalance = FHE.add(balances[to], actualAmount);
        balances[to] = newRecipientBalance;
        FHE.allowThis(newRecipientBalance);
        FHE.allow(newRecipientBalance, to);
    }

    function getBalance(address account) public view returns (euint64) {
        return balances[account];
    }
}
```

---

## 11. ERC-7984: Confidential Token Standard

ERC-7984 is similar to ERC-20, but built from the ground up with confidentiality in mind. All balance and transfer amounts are represented as ciphertext handles, ensuring no data is leaked publicly.

### Minimal ERC-7984 token
```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ERC7984} from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";

contract ConfidentialToken is ZamaEthereumConfig, ERC7984, Ownable2Step {
    constructor(
        address owner,
        uint64 initialSupply,
        string memory name,
        string memory symbol,
        string memory uri
    ) ERC7984(name, symbol, uri) Ownable(owner) {
        euint64 encryptedAmount = FHE.asEuint64(initialSupply);
        _mint(owner, encryptedAmount);
    }

    function mint(address to, externalEuint64 amount, bytes memory inputProof) public onlyOwner {
        _mint(to, FHE.fromExternal(amount, inputProof));
    }
}
```

### Install OpenZeppelin confidential contracts
```bash
npm install @openzeppelin/confidential-contracts
```

### Key ERC-7984 functions
```solidity
confidentialBalanceOf(address account) → euint64
confidentialTransfer(address to, externalEuint64 amount, bytes inputProof) → euint64
confidentialTransferFrom(address from, address to, euint64 amount) → euint64
```

---

## 12. Testing Pattern

```typescript
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";
import { expect } from "chai";
import { FhevmType } from "@fhevm/hardhat-plugin";

describe("MyContract", function () {
  let contract: any;
  let contractAddress: string;
  let alice: HardhatEthersSigner;
  let bob: HardhatEthersSigner;

  beforeEach(async function () {
    // Skip if not running against mock FHE environment
    if (!fhevm.isMock) { this.skip(); }

    [, alice, bob] = await ethers.getSigners();
    const factory = await ethers.getContractFactory("MyContract");
    contract = await factory.deploy();
    contractAddress = await contract.getAddress();
  });

  it("should handle encrypted deposit", async function () {
    const amount = 1000;

    // Encrypt value + generate proof
    const encrypted = await fhevm
      .createEncryptedInput(contractAddress, alice.address)
      .add64(amount)
      .encrypt();

    // Send to contract
    const tx = await contract
      .connect(alice)
      .deposit(encrypted.handles[0], encrypted.inputProof);
    await tx.wait();

    // Read and decrypt result
    const encryptedBalance = await contract.getBalance(alice.address);
    const clearBalance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      encryptedBalance,
      contractAddress,
      alice,
    );

    expect(clearBalance).to.eq(amount);
  });
});
```

---

## 13. Deployment

### Local testing
```bash
# Terminal 1
npx hardhat node

# Terminal 2
npx hardhat test --network localhost
```

### Sepolia testnet
```bash
npx hardhat deploy --network sepolia
npx hardhat test --network sepolia
```

### hardhat.config.ts — Sepolia config is included in the template. Just set vars:
```bash
npx hardhat vars set MNEMONIC
npx hardhat vars set INFURA_API_KEY
```

---

## 14. Frontend Integration (React)

Fork the official React template: https://github.com/zama-ai/fhevm-react-template

### Key setup
```typescript
import { createFhevmInstance } from "fhevmjs";

const instance = await createFhevmInstance({
  kmsContractAddress: KMS_CONTRACT_ADDRESS,
  aclContractAddress: ACL_CONTRACT_ADDRESS,
  network: window.ethereum,
  gatewayUrl: "https://gateway.zama.ai",
});
```

### Encrypt and send
```typescript
const input = instance.createEncryptedInput(contractAddress, userAddress);
input.add64(transferAmount);
const encrypted = await input.encrypt();

await contract.transfer(
  recipientAddress,
  encrypted.handles[0],
  encrypted.inputProof
);
```

### Decrypt user's own balance
```typescript
const { publicKey, privateKey } = instance.generateKeypair();
const eip712 = instance.createEIP712(publicKey, contractAddress);
const signature = await signer.signTypedData(
  eip712.domain, eip712.types, eip712.message
);

const encryptedBalance = await contract.getBalance(userAddress);
const clearBalance = instance.decrypt(contractAddress, encryptedBalance);
```

---

## 15. Common Anti-Patterns and Fixes

### ❌ 1: `pure` function with FHE operations
```solidity
// WRONG — FHE operations modify state, cannot be pure
function subtract(euint64 a, euint64 b) private pure returns (euint64) {
    return FHE.sub(a, b);
}

// CORRECT
function subtract(euint64 a, euint64 b) private returns (euint64) {
    return FHE.sub(a, b);
}
```

### ❌ 2: Missing ACL after state change
```solidity
// WRONG — user can never read their balance
balances[msg.sender] = FHE.sub(balances[msg.sender], amount);

// CORRECT
euint64 newBalance = FHE.sub(balances[msg.sender], amount);
balances[msg.sender] = newBalance;
FHE.allowThis(newBalance);
FHE.allow(newBalance, msg.sender);
```

### ❌ 3: Using FHE.div() — it does not exist
```solidity
// WRONG — FHE.div() is not supported (too expensive in FHE)
euint64 fee = FHE.div(amount, FHE.asEuint64(100));

// CORRECT — use plaintext fee constants
uint64 constant FEE_BPS = 50; // 0.5% in basis points
// Apply fee logic using plaintext math off-chain or use FHE.mul with plaintext
euint64 fee = FHE.mul(amount, FHE.asEuint64(5));
// Note: can't divide — design around this constraint
```

### ❌ 4: Trying to use encrypted value in a `require`
```solidity
// WRONG — cannot use encrypted bool in require
require(FHE.le(amount, balance), "Insufficient funds");

// CORRECT — use FHE.select to safely handle the condition
ebool hasFunds = FHE.le(amount, balance);
euint64 safeAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));
```

### ❌ 5: Using old `bytes32` input type
```solidity
// WRONG
function deposit(bytes32 encryptedAmount, bytes calldata proof) public {
    euint64 amount = TFHE.asEuint64(encryptedAmount);

// CORRECT
function deposit(externalEuint64 encryptedAmount, bytes calldata inputProof) public {
    euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
```

### ❌ 6: Wrong Node.js version
```
Error: EBADENGINE — node >=20 required
```
Fix: `nvm install 22 && nvm use 22`

### ❌ 7: Comparing encrypted value to plaintext directly
```solidity
// WRONG
if (encryptedBalance > 1000) { ... }

// CORRECT
euint64 threshold = FHE.asEuint64(1000);
ebool isAbove = FHE.gt(encryptedBalance, threshold);
// isAbove is encrypted — use FHE.select() to branch
```

---

## 16. Validated Example Project

This SKILL.md was validated against a fully working project: **ConfidentialBank**

- Contracts: `ConfidentialBank.sol`, `EncryptedTransfer.sol`, `MinimalExample.sol`
- All migrated from deprecated `TFHE`/`fhevm` API to `FHE`/`@fhevm/solidity` v0.11
- Test results: **8/8 passing** on local fhEVM mock node

```
ConfidentialBank
  ✔ balance should be uninitialized after deployment
  ✔ alice can deposit an encrypted amount
  ✔ alice can withdraw an encrypted amount
  ✔ alice can transfer encrypted funds to bob
  ✔ withdraw should not go below zero (insufficient balance protection)
```

Source: https://github.com/Delphineuzoeto/fhevm-confidential-bank

---

## 17. Quick Reference Checklist

Before submitting any fhEVM contract:

- [ ] Using `@fhevm/solidity` not `fhevm`
- [ ] Contract inherits `ZamaEthereumConfig`
- [ ] All user inputs use `externalEuintXX` type
- [ ] All inputs converted with `FHE.fromExternal(input, proof)`
- [ ] `FHE.allowThis()` called after every state change
- [ ] `FHE.allow(value, user)` called for every authorized user
- [ ] No `FHE.div()` calls
- [ ] No `pure` modifier on functions that call FHE operations
- [ ] No `require()` on encrypted booleans — use `FHE.select()` instead
- [ ] Node.js v22+
- [ ] Tests run against `--network localhost` with `npx hardhat node` running

---

## Resources

- [Zama Protocol Docs](https://docs.zama.ai/protocol)
- [fhEVM GitHub](https://github.com/zama-ai/fhevm)
- [Hardhat Template](https://github.com/zama-ai/fhevm-hardhat-template)
- [React Template](https://github.com/zama-ai/fhevm-react-template)
- [OpenZeppelin Confidential Contracts](https://docs.openzeppelin.com/confidential-contracts)
- [ERC-7984 Standard](https://docs.openzeppelin.com/confidential-contracts/token)
- [Zama Discord](https://discord.gg/zama)
