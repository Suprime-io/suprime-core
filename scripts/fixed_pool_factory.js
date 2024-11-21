const hre = require("hardhat");
const { SABLER, TREASURY_FEE_RECIPIENT, TREASURY, MAIN } = require('./addresses_lookup')

async function main() {

  const deployerAddr = (await hre.ethers.getSigners())[0];

  const mathLib = await hre.ethers.deployContract("FjordMath");
  await mathLib.waitForDeployment();

  const factoryArgs = [
    TREASURY[hre.network.name],
    MAIN[hre.network.name],
    SABLER[hre.network.name]
  ];
  const factory = await hre.ethers.deployContract("FixedPricePoolFactory", factoryArgs, {
    signer: deployerAddr,
    libraries: {
      FjordMath: mathLib.target,
    },
  });
  await factory.waitForDeployment();
  console.log(
    `Factory deployed to ${factory.target}`
  );

  //verify Factory
  if (hre.network.name !== 'localhost') {
    console.log('Waiting before verification....')
    const delay = ms => new Promise(res => setTimeout(res, ms));
    await delay(45000);

    await hre.run("verify:verify", {
      address: mathLib.target
    });

    await hre.run("verify:verify", {
      address: factory.target,
      constructorArguments: factoryArgs,
    });

    //verify Pool impl
    const poolImplAddr = await factory.FIXED_PRICE_IMPL;
    await hre.run("verify:verify", {
      address: poolImplAddr,
      constructorArguments: [
        SABLER[hre.network.name]
      ],
      libraries: {
        FjordMath: mathLib.target,
      },
    });
  }

  //TODO TransferOwnership: ProxyAdmin

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
