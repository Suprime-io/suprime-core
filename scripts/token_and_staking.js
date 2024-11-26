const hre = require("hardhat");
const { MAIN, BLOCKS_PER_DAY } = require('./addresses_lookup')
const { upgrades } = require('hardhat')
const { toWei } = require('../helpers/utils')

async function main() {
  const [deployer] = await ethers.getSigners();
  let token;
  if (hre.network.name == 'mainnet') {
    //mint to 'main'
    token = await hre.ethers.deployContract("SuprimeToken", [MAIN[hre.network.name]]);
  } else {
    //mint to 'deployer'
    token = await hre.ethers.deployContract("SuprimeToken", [deployer.address]);
  }
  await token.waitForDeployment();
  console.log(
    `SuprimeToken with OWNER address  ${MAIN[hre.network.name]} deployed to ${token.target}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(45000);

    await hre.run("verify:verify", {
      address: token.target,
      constructorArguments: [
        MAIN[hre.network.name]
      ],
    });
  }


  /*  STAKING */
  const SuprimeStaking = await ethers.getContractFactory("SuprimeStaking");
  const suprimeStaking = await upgrades.deployProxy(SuprimeStaking,
    [await token.target, BLOCKS_PER_DAY[hre.network.name]], {initializer: '__SuprimeStaking_init'});
  await suprimeStaking.waitForDeployment();
  console.log(
    `SuprimeStaking was deployed to ${await suprimeStaking.getAddress()}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(10000);

    await hre.run("verify:verify", {
      address: await suprimeStaking.getAddress()
    });
  }

  if (hre.network.name == 'sepolia') {
    await suprimeStaking.setBaseURI("https://protocol.mypinata.cloud/ipfs/QmXggm4Qfgjbx3owiZtzE5DVXBKGeCAPn6J4DwXwxuRvhL/");
    await token.transfer(await suprimeStaking.getAddress(), toWei("10000000"));
    await suprimeStaking.setRewards(toWei('1290000'), 180);
    console.log("URI and Rewards are SET");
  }


  /*  STAKING VIEW */
  const SuprimeStakingView = await ethers.getContractFactory("SuprimeStakingView");
  const suprimeStakingView = await upgrades.deployProxy(SuprimeStakingView,
    [await suprimeStaking.getAddress()], {initializer: '__SuprimeStakingView_init'});
  await suprimeStakingView.waitForDeployment();
  console.log(
    `suprimeStakingView was deployed to ${await suprimeStakingView.getAddress()}`
  );

  //verify
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(10000);

    await hre.run("verify:verify", {
      address: await suprimeStakingView.getAddress()
    });
  }


  //OWNERSHIP
  await suprimeStaking.transferOwnership(MAIN[hre.network.name])
  console.log(`Ownership of Staking contract was set to ${MAIN[hre.network.name]}`);

  //TODO TransferOwnership: ProxyAdmin


}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
