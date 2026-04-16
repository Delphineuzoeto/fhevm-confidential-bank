import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";
import { ConfidentialBank, ConfidentialBank__factory } from "../types";
import { expect } from "chai";
import { FhevmType } from "@fhevm/hardhat-plugin";

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
};

async function deployFixture() {
  const factory = (await ethers.getContractFactory("ConfidentialBank")) as ConfidentialBank__factory;
  const confidentialBank = (await factory.deploy()) as ConfidentialBank;
  const confidentialBankAddress = await confidentialBank.getAddress();
  return { confidentialBank, confidentialBankAddress };
}

describe("ConfidentialBank", function () {
  let signers: Signers;
  let confidentialBank: ConfidentialBank;
  let confidentialBankAddress: string;

  before(async function () {
    const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
    signers = { deployer: ethSigners[0], alice: ethSigners[1], bob: ethSigners[2] };
  });

  beforeEach(async function () {
    if (!fhevm.isMock) {
      console.warn(`This hardhat test suite cannot run on Sepolia Testnet`);
      this.skip();
    }
    ({ confidentialBank, confidentialBankAddress } = await deployFixture());
  });

  it("balance should be uninitialized after deployment", async function () {
    const encryptedBalance = await confidentialBank.getEncryptedBalance(signers.alice.address);
    expect(encryptedBalance).to.eq(ethers.ZeroHash);
  });

  it("alice can deposit an encrypted amount", async function () {
    const depositAmount = 1000;
    const encryptedDeposit = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(depositAmount)
      .encrypt();
    const tx = await confidentialBank
      .connect(signers.alice)
      .deposit(encryptedDeposit.handles[0], encryptedDeposit.inputProof);
    await tx.wait();
    const encryptedBalance = await confidentialBank.getEncryptedBalance(signers.alice.address);
    const clearBalance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      encryptedBalance,
      confidentialBankAddress,
      signers.alice,
    );
    expect(clearBalance).to.eq(depositAmount);
  });

  it("alice can withdraw an encrypted amount", async function () {
    const depositAmount = 1000;
    const withdrawAmount = 400;
    const encryptedDeposit = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(depositAmount)
      .encrypt();
    let tx = await confidentialBank
      .connect(signers.alice)
      .deposit(encryptedDeposit.handles[0], encryptedDeposit.inputProof);
    await tx.wait();
    const encryptedWithdraw = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(withdrawAmount)
      .encrypt();
    tx = await confidentialBank
      .connect(signers.alice)
      .withdraw(encryptedWithdraw.handles[0], encryptedWithdraw.inputProof);
    await tx.wait();
    const encryptedBalance = await confidentialBank.getEncryptedBalance(signers.alice.address);
    const clearBalance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      encryptedBalance,
      confidentialBankAddress,
      signers.alice,
    );
    expect(clearBalance).to.eq(depositAmount - withdrawAmount);
  });

  it("alice can transfer encrypted funds to bob", async function () {
    const depositAmount = 1000;
    const transferAmount = 300;
    const encryptedDeposit = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(depositAmount)
      .encrypt();
    let tx = await confidentialBank
      .connect(signers.alice)
      .deposit(encryptedDeposit.handles[0], encryptedDeposit.inputProof);
    await tx.wait();
    const encryptedTransfer = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(transferAmount)
      .encrypt();
    tx = await confidentialBank
      .connect(signers.alice)
      .transfer(signers.bob.address, encryptedTransfer.handles[0], encryptedTransfer.inputProof);
    await tx.wait();
    const aliceEncryptedBalance = await confidentialBank.getEncryptedBalance(signers.alice.address);
    const aliceClearBalance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      aliceEncryptedBalance,
      confidentialBankAddress,
      signers.alice,
    );
    expect(aliceClearBalance).to.eq(depositAmount - transferAmount);
    const bobEncryptedBalance = await confidentialBank.getEncryptedBalance(signers.bob.address);
    const bobClearBalance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      bobEncryptedBalance,
      confidentialBankAddress,
      signers.bob,
    );
    expect(bobClearBalance).to.eq(transferAmount);
  });

  it("withdraw should not go below zero (insufficient balance protection)", async function () {
    const depositAmount = 100;
    const withdrawAmount = 500;
    const encryptedDeposit = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(depositAmount)
      .encrypt();
    let tx = await confidentialBank
      .connect(signers.alice)
      .deposit(encryptedDeposit.handles[0], encryptedDeposit.inputProof);
    await tx.wait();
    const encryptedWithdraw = await fhevm
      .createEncryptedInput(confidentialBankAddress, signers.alice.address)
      .add64(withdrawAmount)
      .encrypt();
    tx = await confidentialBank
      .connect(signers.alice)
      .withdraw(encryptedWithdraw.handles[0], encryptedWithdraw.inputProof);
    await tx.wait();
    const encryptedBalance = await confidentialBank.getEncryptedBalance(signers.alice.address);
    const clearBalance = await fhevm.userDecryptEuint(
      FhevmType.euint64,
      encryptedBalance,
      confidentialBankAddress,
      signers.alice,
    );
    expect(clearBalance).to.eq(depositAmount);
  });
});
