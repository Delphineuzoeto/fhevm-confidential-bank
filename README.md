# ConfidentialBank — Encrypted Banking on Zama fhEVM

Built for **Zama Developer Program Season 2** by Delphine Uzoeto.

## What This Project Does

This project implements a **confidential banking system** on the blockchain using **Fully Homomorphic Encryption (FHE)**.

In a normal blockchain, every transaction is public — anyone can see how much you deposited, withdrew, or transferred. This project solves that problem. Using Zama's fhEVM, all balances and transaction amounts stay **encrypted on-chain at all times**. Even the blockchain itself never sees the actual numbers.

### The Core Idea: Arithmetic on Encrypted Data

Normally, to add two numbers you need to know what they are. FHE breaks that rule — it lets you perform math (add, subtract, compare) on encrypted values **without ever decrypting them**. The result comes out still encrypted, and only the authorized user can decrypt their own balance.

---

## Contracts

### `ConfidentialBank.sol` — The Main Contract
- **Deposit** — add an encrypted amount to your encrypted balance
- **Withdraw** — subtract encrypted amount with overdraft protection
- **Transfer** — send encrypted funds privately
- **Transfer with Fee** — transfer with plaintext fee rate

### `EncryptedTransfer.sol` — Transfer Primitives
### `MinimalExample.sol` — Simplest FHE subtraction example

---

## How Privacy Works

When Alice deposits 1000 tokens:
- `1000` is encrypted on her device before hitting the blockchain
- Contract receives an encrypted blob — has no idea the value is 1000
- Balance stored encrypted — only Alice can decrypt it

When Alice withdraws 400:
- Contract checks `encrypted_balance >= encrypted_withdrawal` on encrypted values
- If sufficient, subtraction happens on encrypted values
- If not, subtracts zero — all without learning her balance

This is the `FHE.select()` pattern — encrypted if/else.

---

## API Migration (TFHE → FHE)

| Deprecated | Current v0.11 |
|---|---|
| `import "fhevm/lib/TFHE.sol"` | `import "@fhevm/solidity/lib/FHE.sol"` |
| `TFHE.setCoprocessor(...)` | Inherited via `ZamaEthereumConfig` |
| `TFHE.sub()`, `TFHE.add()` | `FHE.sub()`, `FHE.add()` |
| `bytes32 encryptedAmount` | `externalEuint64 encryptedAmount` |
| `TFHE.asEuint64(input)` | `FHE.fromExternal(input, proof)` |

---

## Test Results
ConfidentialBank
✔ balance should be uninitialized after deployment
✔ alice can deposit an encrypted amount
✔ alice can withdraw an encrypted amount
✔ alice can transfer encrypted funds to bob
✔ withdraw should not go below zero (insufficient balance protection)
8 passing (2s)
---

## Running the Project

```bash
git clone https://github.com/Delphineuzoeto/confidential-bank-fhevm
cd confidential-bank-fhevm
npm install
npx hardhat node
npx hardhat test --network localhost
```

---

## Built With

- [Zama fhEVM](https://docs.zama.ai/protocol) — Fully Homomorphic Encryption for EVM
- [@fhevm/solidity](https://github.com/zama-ai/fhevm) v0.11
- [Hardhat](https://hardhat.org/) v2
- Node.js v22

## License

BSD-3-Clause-Clear
