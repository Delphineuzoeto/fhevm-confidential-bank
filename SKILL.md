---
name: zama-fhevm
description: Use this skill whenever the user wants to build, modify, debug, test, or deploy a confidential smart contract on Zama fhEVM, any mention of FHE on Ethereum, encrypted state, confidential tokens, ERC-7984, fhevm, @fhevm/solidity, euint64, externalEuint64, ebool, FHE.add/sub/select, ZamaEthereumConfig, confidential voting, confidential banking, confidential auctions, private DeFi, or the Zama Developer Program. Covers correct v0.11 API usage, access control (FHE.allowThis / FHE.allow), input proofs, user decryption via userDecryptEuint in tests and via relayer-sdk in frontends, public decryption via the self-relaying flow (FHE.makePubliclyDecryptable + off-chain publicDecrypt + FHE.checkSignatures), ERC-7984 token creation, common anti-patterns to avoid (FHE.div does not exist, pure modifier on FHE functions, require() on encrypted bools, deprecated TFHE namespace, bytes32 inputs, number-vs-bigint comparisons in tests), and Hardhat + Sepolia deployment. Do NOT use this skill for generic Ethereum Solidity work that does not involve encrypted state.
---

# Zama fhEVM Development for AI Coding Agents

> Drop this file into Claude Code, Cursor, Windsurf, or any AI coding environment.
> When a developer asks you to build a confidential smart contract using Zama fhEVM,
> follow every rule in this file exactly. Do not guess. Do not use deprecated APIs.

---

## 1. What Is fhEVM?

Zama's fhEVM is a coprocessor that brings Fully Homomorphic Encryption (FHE) to EVM chains. It lets smart contracts perform arithmetic and comparisons on **encrypted values without ever decrypting them**. The result stays encrypted on-chain. Only the authorized user can decrypt their own data.

Architecture:
- **On-chain**: Solidity contracts store encrypted handles (`euint64`, `ebool`, etc.) — these are pointers, not values
- **Off-chain coprocessors**: Zama nodes perform the actual FHE computation
- **KMS (Key Management System)**: Threshold MPC system that holds the global decryption key — no single party can decrypt user data
- **Relayer SDK** (`@zama-fhe/relayer-sdk`): Client-side library used to produce input proofs, request user-decryption, and run public decryption (`publicDecrypt`) on handles that the contract has marked publicly decryptable

---

## 2. Environment Setup

### Prerequisites
- Node.js v20+ (the installed `@fhevm/solidity@0.11.x` declares `node >=20`). v22 is
  recommended because some tooling in the broader monorepo uses v22+ features; older
  versions like v18 will produce Hardhat unsupported-version warnings.
- npm or pnpm

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

When a user sends a **new** encrypted value to a contract for the first time, they
must also send an **input proof** — a zero-knowledge proof that:
1. The encrypted value was correctly formed
2. The user actually knows the plaintext value
3. The value is within the valid range

`FHE.fromExternal(handle, proof)` validates both the handle and the proof.

For handles that were already verified and allowed in an earlier transaction,
the library permits `FHE.fromExternal` to be called with an empty proof — the
ACL entry established on first use is sufficient. The default pattern, though,
is to always send a proof for every user-supplied encrypted input, which is
what all examples below assume.

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
import { createInstance } from "@zama-fhe/relayer-sdk"; // in frontend

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

Users decrypt their own data via EIP-712 signing — they sign a request off-chain that is verified by Zama's KMS, which then returns the decrypted value only to the signing user.

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

### In frontend (`@zama-fhe/relayer-sdk`)

> ⚠️ The older `fhevmjs` package was renamed to `@zama-fhe/relayer-sdk` in
> v0.9+. If you see tutorials using `createFhevmInstance` from `fhevmjs`,
> translate to the current SDK.

```typescript
import { createInstance } from "@zama-fhe/relayer-sdk";

const instance = await createInstance({
  network: window.ethereum,
  // On Sepolia the SDK auto-resolves KMS/ACL addresses from chainId.
  // For local dev you can supply them explicitly.
});

// Generate a per-session EIP-712 keypair for user decryption
const { publicKey, privateKey } = instance.generateKeypair();
const eip712 = instance.createEIP712(publicKey, contractAddress);
const signature = await signer.signTypedData(
  eip712.domain, eip712.types, eip712.message,
);

// User-decrypt your own balance
const encryptedBalance = await contract.getEncryptedBalance(userAddress);
const decryptedBalance = await instance.userDecrypt(
  contractAddress, encryptedBalance, privateKey, publicKey, signature,
);
```

---

## 9. Public Decryption (Self-Relaying Flow)

> ⚠️ **Breaking change in v0.9+**: the Zama Oracle and the `Gateway` /
> `GatewayCaller` / `FHE.requestDecryption` / `onlyGateway` pattern were
> **removed**. Any code using those imports will fail at compile time in
> current `@fhevm/solidity`. Use the self-relaying flow below instead.

For values that need to be revealed publicly (e.g. auction results, vote
tallies, game outcomes), the v0.11 flow is three steps:

1. **On-chain**: the contract marks the ciphertext as publicly decryptable
   via `FHE.makePubliclyDecryptable(handle)`.
2. **Off-chain**: any client (frontend, a bot, the user themselves) fetches
   the handle, calls `publicDecrypt(handle, contractAddress)` from
   `@zama-fhe/relayer-sdk`, and receives `{ cleartext, proof }` where the
   proof is a set of KMS signatures.
3. **On-chain callback**: the client submits the cleartext + proof to a
   normal function on the contract. Inside that function,
   `FHE.checkSignatures(cts, abi.encode(cleartext), proof)` verifies the
   KMS actually signed this cleartext for this handle. If signatures are
   invalid, `checkSignatures` reverts.

### Canonical pattern

```solidity
// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract AuctionResult is ZamaEthereumConfig {
    euint64 private encryptedWinningBid;
    uint64  public  revealedWinningBid;
    bool    public  revealed;

    function requestReveal() external {
        // Step 1 (on-chain): mark the handle publicly decryptable.
        // The KMS will now accept publicDecrypt() requests for this handle.
        FHE.makePubliclyDecryptable(encryptedWinningBid);
    }

    // Step 3 (on-chain): anyone can submit the cleartext + KMS proof
    // after they've run step 2 off-chain.
    function finalizeReveal(uint64 clearBid, bytes calldata decryptionProof) external {
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = euint64.unwrap(encryptedWinningBid);

        // Reverts if the KMS signatures don't match this handle + cleartext.
        FHE.checkSignatures(cts, abi.encode(clearBid), decryptionProof);

        revealedWinningBid = clearBid;
        revealed = true;
    }
}
```

### Off-chain client (step 2)

```typescript
// In a Hardhat task / test or a frontend:
import { publicDecrypt } from "@zama-fhe/relayer-sdk";

const handle = await contract.encryptedWinningBid();
const { cleartext, proof } = await publicDecrypt(handle, contractAddress);

await contract.finalizeReveal(cleartext, proof);
```

In Hardhat tests specifically, `@fhevm/hardhat-plugin` exposes the helper
as `fhevm.publicDecrypt(handle, contractAddress)` which returns the same
`{ cleartext, proof }` shape.

### Why this design?

- **No Oracle dependency** — the dApp client drives the off-chain decryption,
  so you are not relying on a Zama-run relayer service being up.
- **On-chain verification preserved** — the `FHE.checkSignatures` call inside
  `finalizeReveal` still guarantees the cleartext is authentic; a malicious
  client cannot submit a fake cleartext because they cannot forge KMS
  signatures.

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

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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

    // IMPORTANT: userDecryptEuint returns a bigint, not a number.
    // Compare with a bigint literal (1000n) or wrap the expected value:
    //   expect(clearBalance).to.eq(BigInt(amount))
    expect(clearBalance).to.eq(BigInt(amount));
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

The current client SDK is **`@zama-fhe/relayer-sdk`** (v0.3+), not the
older `fhevmjs` package.

### Key setup
```typescript
import { createInstance } from "@zama-fhe/relayer-sdk";

const instance = await createInstance({
  network: window.ethereum,
  // KMS/ACL addresses auto-resolve from chainId on known networks (Sepolia).
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
  encrypted.inputProof,
);
```

### Decrypt user's own balance
```typescript
const { publicKey, privateKey } = instance.generateKeypair();
const eip712 = instance.createEIP712(publicKey, contractAddress);
const signature = await signer.signTypedData(
  eip712.domain, eip712.types, eip712.message,
);

const encryptedBalance = await contract.getBalance(userAddress);
const clearBalance = await instance.userDecrypt(
  contractAddress, encryptedBalance, privateKey, publicKey, signature,
);
```

### Public decryption (step 2 of the section 9 flow)
```typescript
// After the contract called FHE.makePubliclyDecryptable(handle) on-chain:
const { cleartext, proof } = await instance.publicDecrypt(handle, contractAddress);
await contract.finalizeReveal(cleartext, proof);
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
euint64 fee = FHE.mul(amount, FHE.asEuint64(5));
// Note: can't divide — design around this constraint
```

### ❌ 4: Trying to use encrypted value in a `require`
```solidity
// WRONG
require(FHE.le(amount, balance), "Insufficient funds");

// CORRECT
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

### ❌ 6: Using Node.js below v20
```
Warning from Hardhat: Node.js version <20 is not supported
```
Current `@fhevm/solidity@0.11.x` declares `node >=20`. Install v20 or v22:
`nvm install 22 && nvm use 22`. Earlier versions (v18) will produce Hardhat
unsupported-version warnings and may fail on certain plugin operations.

### ❌ 7: Comparing encrypted value to plaintext directly
```solidity
// WRONG
if (encryptedBalance > 1000) { ... }

// CORRECT
euint64 threshold = FHE.asEuint64(1000);
ebool isAbove = FHE.gt(encryptedBalance, threshold);
```

### ❌ 8: Comparing decrypted test result to a JS `number`
```typescript
// WRONG — userDecryptEuint returns a bigint; this assertion fails
// with "expected 1000n to equal 1000"
const clear = await fhevm.userDecryptEuint(FhevmType.euint64, handle, contractAddress, alice);
expect(clear).to.eq(1000);

// CORRECT — use a bigint literal or wrap the number
expect(clear).to.eq(1000n);
expect(clear).to.eq(BigInt(1000));
```

---

## 16. Validated Example Projects

This SKILL.md was validated against working projects:

**ConfidentialBank** — https://github.com/Delphineuzoeto/fhevm-confidential-bank
- Encrypted deposit / withdraw / transfer
- Migrated from deprecated `TFHE` / `fhevm` API to `FHE` / `@fhevm/solidity`
- Deployed and verified on Sepolia
- Note: test assertions in this repo use numeric comparisons that need to be
  updated to bigint comparisons as described in section 12 and anti-pattern #8
  — this is a library behavior change, not a contract issue.

**ConfidentialVoting** (Builder Track submission) — binary yes/no polls with
encrypted tallies and winner-only reveal via the v0.11 self-relaying
public decryption flow.

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
- [ ] Compare `userDecryptEuint` results against a bigint (`1000n`, not `1000`)
- [ ] No `Gateway` / `GatewayCaller` / `FHE.requestDecryption` — use
      `FHE.makePubliclyDecryptable` + off-chain `publicDecrypt` + `FHE.checkSignatures`
- [ ] Node.js v20+ (v22 recommended)
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