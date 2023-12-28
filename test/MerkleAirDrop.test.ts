import { ethers } from "hardhat";
import { expect } from "chai";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { MerkleAirdrop, MockERC20 } from "../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { parseEther } from "./utils/common";
import { MerkleTree } from "merkletreejs";
import keccak256 = require("keccak256");
import { utils } from "ethers";

declare var hre: HardhatRuntimeEnvironment;

describe("Airdrop Merkle Proof Test", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let token0: MockERC20;
  let token1: MockERC20;
  let token2: MockERC20;
  let token3: MockERC20;
  let airdrop: MerkleAirdrop;

  beforeEach(async () => {
    [owner, user1, user2, user3] = await ethers.getSigners();

    // setup merkle distributor
    const MerkleAirdrop = await ethers.getContractFactory("MerkleAirdrop");
    const ERC20 = await ethers.getContractFactory("MockERC20");

    token0 = await ERC20.deploy("Token0", "T0");
    token1 = await ERC20.deploy("Token1", "T1");
    token2 = await ERC20.deploy("Token2", "T2");
    token3 = await ERC20.deploy("Token3", "T3");

    airdrop = await MerkleAirdrop.deploy([
      token0.address,
      token1.address,
      token2.address,
      token3.address,
    ]);

    // mint stablecoion
    await token0.mint(owner.address, parseEther("100000"));
    await token1.mint(owner.address, parseEther("100000"));
    await token2.mint(owner.address, parseEther("100000"));
    await token3.mint(owner.address, parseEther("100000"));

    // approve token
    await token0.connect(owner).approve(airdrop.address, parseEther("100000"));
    await token1.connect(owner).approve(airdrop.address, parseEther("100000"));
    await token2.connect(owner).approve(airdrop.address, parseEther("100000"));
    await token3.connect(owner).approve(airdrop.address, parseEther("100000"));
  });

  it("issueTokens + updateMerkleRoot", async function () {
    let user1IssueAmount = 9000;
    let user2IssueAmount = 10000;

    let user1Element = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [0, user1.address, token0.address, user1IssueAmount]
        )
        .substr(2),
      "hex"
    );

    let user2Element = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [1, user2.address, token0.address, user2IssueAmount]
        )
        .substr(2),
      "hex"
    );

    let elements = [user1Element, user2Element];
    const merkleTree = new MerkleTree(elements, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    });

    const root = merkleTree.getHexRoot();
    const leaf = keccak256(elements[0]);
    const proof = merkleTree.getHexProof(leaf);

    let id = "1";
    let projectName = "project-0";
    let allocated = parseEther("10");

    await airdrop.setProject(token0.address, id, root, projectName, allocated);

    // issued token amount  should exactly match merkle tree element
    await expect(
      airdrop.connect(user1).issueTokens(id, 0, user1IssueAmount - 1, proof)
    ).to.be.revertedWith("Invalid merkle proof!");

    let user1BeforeBalance = await token0.balanceOf(user1.address);

    await airdrop.connect(user1).issueTokens(id, 0, user1IssueAmount, proof);

    let user1AfterBalance = await token0.balanceOf(user1.address);

    expect(user1AfterBalance.sub(user1BeforeBalance)).to.be.eq(
      user1IssueAmount
    );

    let user3IssueAmount = 11000;

    let user3Element = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [2, user3.address, token0.address, user3IssueAmount]
        )
        .substr(2),
      "hex"
    );

    elements.push(user3Element);

    const newMerkleTree = new MerkleTree(elements, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    });

    const newRoot = newMerkleTree.getHexRoot();
    const user2leaf = keccak256(elements[1]);
    const user2Proof = newMerkleTree.getHexProof(user2leaf);

    const user3leaf = keccak256(elements[2]);
    const user3Proof = newMerkleTree.getHexProof(user3leaf);
    // update Merkle Root
    await airdrop.updateMerkleRoot(id, newRoot);

    await airdrop
      .connect(user2)
      .issueTokens(id, 1, user2IssueAmount, user2Proof);
    await airdrop
      .connect(user3)
      .issueTokens(id, 2, user3IssueAmount, user3Proof);
  });

  it("assign multiple aidrop for same user", async function () {
    let issueAmount0 = 9000;
    let issueAmount1 = 10000;

    // 1st airdrop for user1
    let user1Element0 = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [0, user1.address, token0.address, issueAmount0]
        )
        .substr(2),
      "hex"
    );

    // 2nd airdrop for user1
    let user1Element1 = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [1, user1.address, token0.address, issueAmount1]
        )
        .substr(2),
      "hex"
    );

    let elements = [user1Element0, user1Element1];
    const merkleTree = new MerkleTree(elements, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    });

    const root = merkleTree.getHexRoot();
    const leaf0 = keccak256(elements[0]);
    const proof0 = merkleTree.getHexProof(leaf0);

    const leaf1 = keccak256(elements[1]);
    const proof1 = merkleTree.getHexProof(leaf1);

    let id = "1";
    let projectName = "project-0";
    let allocated = parseEther("10");

    await airdrop.setProject(token0.address, id, root, projectName, allocated);

    await airdrop.connect(user1).issueTokens(id, 0, issueAmount0, proof0);
    await airdrop.connect(user1).issueTokens(id, 1, issueAmount1, proof1);
  });

  it("reclaimTokens", async function () {
    let user1IssueAmount = 9000;
    let user2IssueAmount = 10000;

    let user1Element = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [0, user1.address, token0.address, user1IssueAmount]
        )
        .substr(2),
      "hex"
    );

    let user2Element = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [1, user2.address, token0.address, user2IssueAmount]
        )
        .substr(2),
      "hex"
    );

    let elements = [user1Element, user2Element];
    const merkleTree = new MerkleTree(elements, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    });

    const root = merkleTree.getHexRoot();
    const leaf = keccak256(elements[0]);
    const proof = merkleTree.getHexProof(leaf);

    let id = "1";
    let projectName = "project-0";
    let allocated = parseEther("10");

    await airdrop.setProject(token0.address, id, root, projectName, allocated);

    await airdrop.connect(user1).issueTokens(id, 0, user1IssueAmount, proof);

    let remainningTokens = allocated.sub(user1IssueAmount);

    let ownerBeforeBalance = await token0.balanceOf(owner.address);

    // project owner recliam Tokens
    await airdrop.reclaimTokens(id);

    let ownerAfterBalance = await token0.balanceOf(owner.address);

    expect(ownerAfterBalance.sub(ownerBeforeBalance)).to.be.eq(
      remainningTokens
    );
  });

  it("updateProject", async function () {
    let user1IssueAmount = 9000;

    let user1Element = Buffer.from(
      utils
        .solidityPack(
          ["uint256", "address", "address", "uint64"],
          [0, user1.address, token0.address, user1IssueAmount]
        )
        .substr(2),
      "hex"
    );

    let elements = [user1Element];
    const merkleTree = new MerkleTree(elements, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    });

    const root = merkleTree.getHexRoot();
    const leaf = keccak256(elements[0]);
    const proof = merkleTree.getHexProof(leaf);

    let id = "1";
    let projectName = "project-0";
    let allocated = parseEther("10");

    await airdrop.setProject(token0.address, id, root, projectName, allocated);

    elements.push(
      Buffer.from(
        utils
          .solidityPack(
            ["uint256", "address", "address", "uint64"],
            [1, user2.address, token0.address, 10000]
          )
          .substr(2),
        "hex"
      )
    );
    const newMerkleTree = new MerkleTree(elements, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    });
    const newRoot = newMerkleTree.getHexRoot();

    let newProjectName = "new-project-0";
    let newAllocated = parseEther("5");

    await airdrop.updateProject(
      token0.address,
      id,
      newRoot,
      newProjectName,
      newAllocated
    );

    await airdrop.deposit(id, parseEther("1"));

    let newLeaf = keccak256(elements[0]);
    let newProof = newMerkleTree.getHexProof(newLeaf);
    await airdrop.connect(user1).issueTokens(id, 0, user1IssueAmount, newProof);
  });
});
