const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { toWei, getCurrentBlockTimestamp, toBN, getTransactionBlock, advanceBlocks} = require('../helpers/utils')
const { ethers, upgrades } = require('hardhat');

const { AddressZero } = require("@ethersproject/constants");

describe("SuprimeStaking", function () {

  let suprimeToken;
  let owner;
  let addr1;
  let addr2;
  let addr3;

  before("Setup", async() => {
    const SuprimeTokenMock = await ethers.getContractFactory("SuprimeTokenMock");
    const suprimeTokenTdly = (await SuprimeTokenMock.deploy());
    suprimeToken = suprimeTokenTdly.nativeContract;

    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    await suprimeToken.mintArbitrary(addr1, toWei('100000'));
    await suprimeToken.mintArbitrary(addr2, toWei('100000'));
    await suprimeToken.mintArbitrary(addr3, toWei('100000'));
  });

  async function deploySuprimeStaking() {
    const SuprimeStaking = await ethers.getContractFactory("SuprimeStaking");
    const suprimeStakingTdly = await upgrades.deployProxy(SuprimeStaking,
      [await suprimeToken.getAddress(), 60 * 60 * 24], {initializer: '__SuprimeStaking_init'});
    const suprimeStaking = suprimeStakingTdly.proxyContract;
    await suprimeStaking.transferOwnership(owner)
    return suprimeStaking;
  }

  describe("util functions", () => {

    let suprimeStaking;

    it("should set URI", async () => {
      suprimeStaking  = await loadFixture(deploySuprimeStaking);
      expect(await suprimeStaking.uri(0)).to.equal("0");

      await suprimeStaking.setBaseURI("https://token-cdn-domain/");
      expect(await suprimeStaking.uri(0)).to.equal("https://token-cdn-domain/0");
      expect(await suprimeStaking.uri(10)).to.equal("https://token-cdn-domain/10");

      await expect(suprimeStaking.setBaseURI("")).to.be.revertedWithCustomError(suprimeStaking, 'InvalidInput');
    });
  });

  describe("stake", () => {

    let suprimeStaking;

    beforeEach(async () => {
      suprimeStaking = await loadFixture(deploySuprimeStaking);
      await suprimeToken.transfer(suprimeStaking.getAddress(), toWei("10000000"));
      await suprimeToken.connect(addr1).approve(suprimeStaking.getAddress(), toWei('100000'));
      await suprimeToken.connect(addr2).approve(suprimeStaking.getAddress(), toWei('100000'));
      await suprimeToken.connect(addr3).approve(suprimeStaking.getAddress(), toWei('100000'));

      // 60 * 60 + 24 blocks per day
      // 60 * 60 + 24 rewards per day
      // 1 block = 1 sec = 1 reward

      const secondsAndBlocksAndRewardsOneDay = 60 * 60 * 24;
      const secondsAndBlocksAndRewards90Days = secondsAndBlocksAndRewardsOneDay * 90;
      await suprimeStaking.setRewards(toWei(secondsAndBlocksAndRewards90Days.toString()), 90);
    });

    it("should revert if stake 0 tokens", async () => {
      await expect(suprimeStaking
        .connect(addr1)
        .stake(0, 0, 3)).to.be.revertedWithCustomError(suprimeStaking, 'InvalidInput');
    });

    it("should revert if locking period is invalid", async () => {
      await expect(suprimeStaking
        .connect(addr1)
        .stake(toWei("100"), 0, 1)).to.be.revertedWithCustomError(suprimeStaking, 'InvalidInput');
    });

    it("should transfer SUPRIME tokens", async () => {
      expect(await suprimeToken.balanceOf(addr1)).to.be.equal(toWei("100000"));
      expect(await suprimeToken.balanceOf(suprimeStaking.getAddress())).to.be.equal(toWei("10000000"));

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);

      expect(await suprimeToken.balanceOf(addr1)).to.be.equal(toWei("99900"));
      expect(await suprimeToken.balanceOf(suprimeStaking.getAddress())).to.be.equal(toWei("10000100"));
    });

    it("should increase totalPool & total pool power", async () => {
      expect(await suprimeStaking.totalPool()).to.be.equal("0");
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal("0");

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("100"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("100"));
    });

    it("should increase totalPool & total pool power with multiple locking period", async () => {
      expect(await suprimeStaking.totalPool()).to.be.equal("0");
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal("0");

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("100"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("100"));

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 6);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("200"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("300"));

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 12);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("300"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("600"));

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 24);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("400"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("1000"));

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 36);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("500"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("1500"));
    });

    it("should mint new NFT & check staking info", async () => {
      await expect(suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3))
        .to.emit(suprimeStaking, "NFTMinted")
        .withArgs(1, addr1);

      const info = await suprimeStaking.getStakingInfoByIndex(1);

      const timeStamp = (await getCurrentBlockTimestamp()).toString();

      expect(await suprimeStaking.balanceOf(addr1)).to.be.equal(1);
      expect(await suprimeStaking.ownerOf(1)).to.be.equal(addr1);

      expect(info.staked.toString()).to.be.equal(toWei("100"));
      expect(info.startTime.toString()).to.be.equal(timeStamp);
      expect(info.endTime.toString()).to.be.equal(toBN(timeStamp).plus(toBN(3).times(30 * 86400)));
      expect(info.lockingPeriod).to.be.equal(3);
      expect(info.stakingMultiplier).to.be.equal(1);
    });

    it("should fail on NFT transfer", async () => {
      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);
      expect(await suprimeStaking.balanceOf(addr1)).to.be.equal(1);
      const emptyByteParam = ethers.getBytes('0x');

      await expect(suprimeStaking.connect(addr1).safeTransferFrom(addr1, addr2, 1, 1, emptyByteParam))
        .to.be.revertedWithCustomError(suprimeStaking, 'TransferNotAllowed');
    });

   it("should update user rewards before", async () => {
     await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);
     expect((await suprimeStaking.earned(1)).toString()).to.be.equal(toWei("0"));

     const oneDayInSec = 60 * 60 * 24;
     await advanceBlocks(oneDayInSec);

     const tx = await suprimeStaking.connect(addr1).stake(toWei("100"), 1, 0);
     const currentBlock = getTransactionBlock(tx);

     expect(await suprimeStaking.lastUpdateBlock()).to.be.equal(currentBlock);
     expect((await suprimeStaking.earned(1)).toString()).to.be.equal(toWei(toBN(oneDayInSec + 1).toString()));
   });

    it("should mint new nft while staking for another lock", async () => {
      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);

      //another lock
      await expect(suprimeStaking.connect(addr1).stake(toWei("100"), 0, 6))
        .to.emit(suprimeStaking, "NFTMinted");

      await expect(suprimeStaking.connect(addr1).stake(toWei("100"), 0, 0))
        .to.be.revertedWithCustomError(suprimeStaking, 'InvalidInput');
    });
  });

  describe("withdraw", () => {
    let suprimeStaking;

    beforeEach(async () => {
      suprimeStaking = await loadFixture(deploySuprimeStaking);
      await suprimeToken.transfer(suprimeStaking.getAddress(), toWei("10000000"));
      await suprimeToken.connect(addr1).approve(suprimeStaking.getAddress(), toWei('100000'));
      await suprimeToken.connect(addr2).approve(suprimeStaking.getAddress(), toWei('100000'));
      await suprimeToken.connect(addr3).approve(suprimeStaking.getAddress(), toWei('100000'));

      // 60 * 60 + 24 blocks per day
      // 60 * 60 + 24 rewards per day
      // 1 block = 1 sec = 1 reward

      const secondsAndBlocksAndRewardsOneDay = 60 * 60 * 24;
      const secondsAndBlocksAndRewards90Days = secondsAndBlocksAndRewardsOneDay * 90;
      await suprimeStaking.setRewards(toWei(secondsAndBlocksAndRewards90Days.toString()), 90);

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);
    });

    it("should revert if user not the owner of NFT", async () => {
      await expect(suprimeStaking.connect(addr2).withdraw(1))
        .to.be.revertedWithCustomError(suprimeStaking, 'Unauthorized');
    });

    it("should revert if locking period not ended", async () => {
      await expect(suprimeStaking.connect(addr1).withdraw(1))
        .to.be.revertedWithCustomError(suprimeStaking, 'WithdrawNotReady');
    });

    it("should withdraw staked amount + rewards + burn nft after locking period is ended", async () => {
      const secondsAndBlocksAndRewards = 60 * 60 * 24 * 90; // in 3 months = 7.776.000
      await advanceBlocks(secondsAndBlocksAndRewards); // increase time 3 month

      const balanceBefore = (await suprimeToken.balanceOf(addr1)).toString();

      const infoBefore = await suprimeStaking.getStakingInfoByIndex(1);
      expect(infoBefore.staked.toString()).to.be.equal(toWei("100"));

      await expect(suprimeStaking.connect(addr1).withdraw(1))
        .to.emit(suprimeStaking, "RewardPaid")
        .withArgs(addr1, 1, toWei((secondsAndBlocksAndRewards - 2).toString()))
        .and
        .to.emit(suprimeStaking, "NFTBurned")
        .withArgs(1, addr1);


      const balanceAfter = (await suprimeToken.balanceOf(addr1)).toString();
      const infoAfter = await suprimeStaking.getStakingInfoByIndex(1);

      const withdrawn = toBN(balanceAfter).minus(toBN(balanceBefore));
      const expected = toBN(toWei("100"))                 //initial stake
        .plus(toBN(toWei(secondsAndBlocksAndRewards.toString())))     //all rewards
        .minus(toBN(toWei('2')));
      expect(expected.toFixed())
        .to.be.equal(withdrawn.toFixed());

      expect(await suprimeStaking.totalPool()).to.be.equal('0');
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(0);
      expect(infoAfter.staked).to.be.equal(0);


      expect(await suprimeStaking.balanceOf(addr1)).to.be.equal('0');
      expect((await suprimeStaking.ownerOf(1)).toString()).to.be.equal(AddressZero);
    });


    it("should increase totalPool & total pool power with multiple stakings", async () => {
      //add the existing stake
      await expect(suprimeStaking.connect(addr1).stake(toWei("100"), 1, 0))
        .to.not.emit(suprimeStaking, "NFTMinted");

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("200"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("200"));

      await advanceBlocks(60 * 60 * 24 * 90 + 1); // 3 month
      await expect(suprimeStaking.connect(addr1).stake(toWei("100"), 1, 0))
        .to.not.emit(suprimeStaking, "NFTMinted");

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("300"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("300"));

      //instantly try to withdraw
      await expect(suprimeStaking.connect(addr1).withdraw(1))
        .to.emit(suprimeStaking, "Withdrawn")
        .withArgs(addr1, 1, toWei("300"), anyValue);

      expect(await suprimeStaking.totalPool()).to.be.equal(toWei("0"));
      expect(await suprimeStaking.totalPoolWithPower()).to.be.equal(toWei("0"));
    });
  });

  describe("restake", async () => {
    let suprimeStaking;

    beforeEach(async () => {
      suprimeStaking = await loadFixture(deploySuprimeStaking);
      await suprimeToken.transfer(suprimeStaking.getAddress(), toWei("10000000"));
      await suprimeToken.connect(addr1).approve(suprimeStaking.getAddress(), toWei('100000'));

      // 60 * 60 + 24 blocks per day
      // 60 * 60 + 24 rewards per day
      // 1 block = 1 sec = 1 reward

      const secondsAndBlocksAndRewardsOneDay = 60 * 60 * 24;
      const secondsAndBlocksAndRewards90Days = secondsAndBlocksAndRewardsOneDay * 90;
      await suprimeStaking.setRewards(toWei(secondsAndBlocksAndRewards90Days.toString()), 90);

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);
    });

    it("should revert if user not the owner of NFT", async () => {
      await expect(suprimeStaking.connect(addr2).restakeReward(1))
        .to.be.revertedWithCustomError(suprimeStaking, 'Unauthorized');
    });

    it("should update rewards on restake", async () => {
      const tx = await suprimeStaking.connect(addr1).restakeReward(1);

      const currentBlock = getTransactionBlock(tx);
      const info = await suprimeStaking.getStakingInfoByIndex(1);

      expect(info.rewards).to.be.equal("0");
      expect(info.staked).to.be.equal(toWei("101"));

      expect(await suprimeStaking.lastUpdateBlock()).to.be.equal(currentBlock);
    });


  });


})
