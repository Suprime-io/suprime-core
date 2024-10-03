const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { toWei, getCurrentBlockTimestamp, toBN, getTransactionBlock, increaseTime, advanceBlocks, advanceBlockTo, fromWei } = require('../helpers/utils')
const { upgrades, hre } = require('hardhat');

const { AddressZero } = require("@ethersproject/constants");

describe("SuprimeStaking", function () {

  const ONE_DAY_IN_SECS = 24 * 60 * 60;

  let suprimeToken;
  let owner;
  let addr1;
  let addr2;
  let addr3;

  before("Setup", async() => {
    const SuprimeTokenMock = await ethers.getContractFactory("SuprimeTokenMock");
    suprimeToken = await SuprimeTokenMock.deploy();
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    await suprimeToken.mintArbitrary(addr1, toWei('100000'));
    await suprimeToken.mintArbitrary(addr2, toWei('100000'));
    await suprimeToken.mintArbitrary(addr3, toWei('100000'));
  });

  async function deploySuprimeStaking() {
    const SuprimeStaking = await ethers.getContractFactory("SuprimeStaking");
    const suprimeStaking = await upgrades.deployProxy(SuprimeStaking,
      [await suprimeToken.getAddress(), 60 * 60 * 24], {initializer: '__SuprimeStaking_init'});
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
      await suprimeToken.transfer(suprimeStaking.getAddress(), toWei("10000"));
      await suprimeToken.connect(addr1).approve(suprimeStaking.getAddress(), toWei('100000'));
      await suprimeToken.connect(addr2).approve(suprimeStaking.getAddress(), toWei('100000'));
      await suprimeToken.connect(addr3).approve(suprimeStaking.getAddress(), toWei('100000'));

      await suprimeStaking.setRewards(toWei("10000"), 1);
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
      expect(await suprimeToken.balanceOf(suprimeStaking.getAddress())).to.be.equal(toWei("10000"));

      await suprimeStaking.connect(addr1).stake(toWei("100"), 0, 3);

      expect(await suprimeToken.balanceOf(addr1)).to.be.equal(toWei("99900"));
      expect(await suprimeToken.balanceOf(suprimeStaking.getAddress())).to.be.equal(toWei("10100"));
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
        .to.be.revertedWithCustomError(suprimeStaking, 'TransferNotAllowed');;
    });

   /*it("should update user rewards before", async () => {
     const tx = await suprimeStaking.connect(addr1).stake(toWei("50"), 0, 3);
     expect((await suprimeStaking.earned(1)).toString()).to.be.equal(toWei("0"));

     console.log(await time.latest())

     const dayLater = (await time.latest()) + ONE_DAY_IN_SECS;

     await suprimeStaking.connect(addr1).stake(toWei("50"), 0, 3);
     await time.increaseTo(dayLater);

     console.log(await time.latest())

     //const tx = await suprimeStaking.connect(addr2).stake(toWei("50"), 0, 3);


     const currentBlock = getTransactionBlock(tx);

     expect(await suprimeStaking.lastUpdateBlock()).to.be.equal(currentBlock + 1);
     //expect((await suprimeStaking.earned(1)).toString()).to.be.equal(toWei("100"));
     expect((await suprimeStaking.rewardPerToken()).toString()).to.be.equal(toWei("2"));
   });*/
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
        .to.be.revertedWithCustomError(suprimeStaking, 'ClaimNotReady');
    });

    it("should withdraw staked amount + rewards + brun nft after locking period is ended", async () => {
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


    it("should decrease totalPool & total pool power with multiple locking period", async () => {
      /*await suprimeStaking.stake(toWei("100"), 0, 6, { from: addr2 });
      await suprimeStaking.stake(toWei("100"), 0, 12, { from: addr1 });
      await suprimeStaking.stake(toWei("100"), 0, 24, { from: addr2 });
      await suprimeStaking.stake(toWei("100"), 0, 36, { from: addr1 });

      await increaseTime(LOCKING_PERIOD.MONTH_1 * PERIOD_DURATION + 10); // increase time 1 month
      await suprimeStaking.withdraw(1, { from: addr1 });

      assert.equal((await suprimeStaking.totalPool()).toString(), toWei("400"));
      assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), toWei("1400"));

      await increaseTime(LOCKING_PERIOD.MONTH_6 * PERIOD_DURATION + 10); // increase time 6 month
      await suprimeStaking.withdraw(2, { from: addr2 });

      assert.equal((await suprimeStaking.totalPool()).toString(), toWei("300"));
      assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), toWei("1200"));

      await increaseTime(LOCKING_PERIOD.MONTH_12 * PERIOD_DURATION + 10); // increase time 12 month
      await suprimeStaking.withdraw(3, { from: addr1 });

      assert.equal((await suprimeStaking.totalPool()).toString(), toWei("200"));
      assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), toWei("900"));

      await increaseTime(LOCKING_PERIOD.MONTH_24 * PERIOD_DURATION + 10); // increase time 24 month
      await suprimeStaking.withdraw(4, { from: addr2 });

      assert.equal((await suprimeStaking.totalPool()).toString(), toWei("100"));
      assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), toWei("500"));

      await increaseTime(LOCKING_PERIOD.MONTH_36 * PERIOD_DURATION + 10); // increase time 36 month
      await suprimeStaking.withdraw(5, { from: addr1 });

      assert.equal((await suprimeStaking.totalPool()).toString(), 0);
      assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), 0);*/
    });
/*
            it("should withdraw staked amount with liquidation", async () => {
              const rewards1 = toWei("200");
              const rewards2 = toWei("300");

              await suprimeStaking.stake(toWei("100"), LOCKING_PERIOD.MONTH_6, { from: addr2 });

              assert.equal((await suprimeStaking.totalPool()).toString(), toWei("200"));
              assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), toWei("300"));

              await compoundPool.liquidatesuprimeStaking(toWei("100"), USER3);

              assert.equal((await suprimeStaking.liquidationAmount()).toString(), toWei("100"));

              await increaseTime(LOCKING_PERIOD.MONTH_6 * PERIOD_DURATION + 10); // increase time 6 month

              const balanceaddr1Before = (await suprimeToken.balanceOf(addr1)).toString();

              const balanceaddr2Before = (await suprimeToken.balanceOf(addr2)).toString();

              await suprimeStaking.withdraw(1, { from: addr1 });

              assert.equal((await suprimeStaking.liquidationAmount()).toString(), toWei("50"));
              assert.equal((await suprimeStaking.totalPool()).toString(), toWei("100"));
              assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), toWei("200"));

              await suprimeStaking.withdraw(2, { from: addr2 });

              const balanceaddr1After = (await suprimeToken.balanceOf(addr1)).toString();
              const balanceaddr2After = (await suprimeToken.balanceOf(addr2)).toString();

              assert.equal(
                toBN(balanceaddr1After).minus(balanceaddr1Before).precision(5).toString(),
                toBN(withdrawAmount).plus(rewards1).minus(toWei("50")).toString(),
              );

              assert.equal(
                toBN(balanceaddr2After).minus(balanceaddr2Before).precision(5).toString(),
                toBN(withdrawAmount).plus(rewards2).minus(toWei("50")).toString(),
              );
              assert.equal((await suprimeStaking.totalPool()).toString(), 0);
              assert.equal((await suprimeStaking.totalPoolWithPower()).toString(), 0);
              assert.equal((await suprimeStaking.liquidationAmount()).toString(), 0);
            });*/
  });


})
