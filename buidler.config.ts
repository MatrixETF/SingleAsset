require("dotenv").config();

import {usePlugin, task, types} from "@nomiclabs/buidler/config";
import {Signer, Wallet, utils, constants, Contract, BytesLike} from "ethers";
import {deployContract} from "ethereum-waffle";
import {ISmartPoolRegistryFactory} from "./typechain/ISmartPoolRegistryFactory"
import {V1CompatibleRecipeFactory} from "./typechain/V1CompatibleRecipeFactory"
import {IUniRouterFactory} from "./typechain/IUniRouterFactory"
import { Ierc20Factory } from "./typechain/Ierc20Factory";

import {ISmartPoolFactory} from "./typechain/ISmartPoolFactory"

usePlugin("@nomiclabs/buidler-ethers");
usePlugin('solidity-coverage');
usePlugin("@nomiclabs/buidler-etherscan");
usePlugin('solidity-coverage');

const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const KOVAN_PRIVATE_KEY = process.env.KOVAN_PRIVATE_KEY || "";
const KOVAN_PRIVATE_KEY_SECONDARY = process.env.KOVAN_PRIVATE_KEY_SECONDARY || "";

const RINKEBY_PRIVATE_KEY = process.env.RINKEBY_PRIVATE_KEY || "";
const RINKEBY_PRIVATE_KEY_SECONDARY = process.env.RINKEBY_PRIVATE_KEY_SECONDARY || "";
const MAINNET_PRIVATE_KEY = process.env.MAINNET_PRIVATE_KEY || "";
const MAINNET_PRIVATE_KEY_SECONDARY = process.env.MAINNET_PRIVATE_KEY_SECONDARY || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";

const config = {
    defaultNetwork: 'buidlerevm',
    networks: {
        buidlerevm: {
            gasPrice: 0,
            blockGasLimit: 10000000,
        },
        localhost: {
            url: 'http://localhost:8545'
        },
        mainnet: {
            url: `https://mainnet.infura.io/v3/${INFURA_API_KEY}`,
            accounts: [
                MAINNET_PRIVATE_KEY,
                MAINNET_PRIVATE_KEY_SECONDARY
            ].filter((item) => item !== "")
        },
        kovan: {
            url: `https://kovan.infura.io/v3/${INFURA_API_KEY}`,
            accounts: [
                KOVAN_PRIVATE_KEY,
                KOVAN_PRIVATE_KEY_SECONDARY
            ].filter((item) => item !== "")
        },
        coverage: {
            url: 'http://127.0.0.1:8555', // Coverage launches its own ganache-cli client
            gasPrice: 0,
            blockGasLimit: 100000000,
        },
        frame: {
            url: "http://localhost:1248"
        }
    },
    solc: {
        version: '0.8.1',
        optimizer: {
            // Factory goes above contract size limit
            enabled: true,
            runs: 200
        }
    },
    etherscan: {apiKey: process.env.ETHERSCAN_KEY}
}

task("deploy-smart-pool-registry", "deploy smart pool registry")
    .setAction(async (taskArgs, {ethers}) => {
        const SmartPoolRegistry = await ethers.getContractFactory("SmartPoolRegistry");
        const smartPoolRegistry = await SmartPoolRegistry.deploy();
        await smartPoolRegistry.deployed();
        console.log("smartPoolRegistry deployed to:", smartPoolRegistry.address);
    });

task("smart-pool-register", "smart pool register")
    .addParam("register")
    .addParam("pool", "the register smart pool address")
    .setAction(async (taskArgs, {ethers}) => {
        const signers = await ethers.getSigners();
        const register = ISmartPoolRegistryFactory.connect(taskArgs.register, signers[0]);
        const tx = await register.addSmartPool(taskArgs.pool)
        const receipt = await tx.wait(1);
        console.log(`addSmartPool to:" ${receipt.transactionHash}`);
    });

task("in-register", "smart pool is in register")
    .addParam("register")
    .addParam("pool", "the register smart pool address")
    .setAction(async (taskArgs, {ethers}) => {
        const signers = await ethers.getSigners();
        const register = ISmartPoolRegistryFactory.connect(taskArgs.register, signers[0]);
        const tx = await register.inRegistry(taskArgs.pool)
        console.log(`in-register :" ${tx}`);
    });

task("deploy-v1-compatible-recipe", "deploy v1 compatible recipe")
    .addParam("weth", "The weth address")
    .addParam("uni", "The uniRouter address")
    .addParam("registry", "The smartPoolRegistry address")
    .setAction(async (taskArgs, {ethers}) => {
        const V1CompatibleRecipe = await ethers.getContractFactory("V1CompatibleRecipe");
        const recipe = await V1CompatibleRecipe.deploy(taskArgs.weth, taskArgs.uni, taskArgs.registry);
        await recipe.deployed();
        console.log("v1CompatibleRecipe deployed to:", recipe.address);
    });

task("to-etf", "swap etf")
    .addParam("recipe", "the recipe address")
    .addParam("pool", "the smart pool address")
    .addParam("amount")
    .setAction(async (taskArgs, {ethers}) => {
        const signers = await ethers.getSigners();
        const v1CompatibleRecipe = V1CompatibleRecipeFactory.connect(taskArgs.recipe, signers[0]);
        const tx = await v1CompatibleRecipe["toETF(address,uint256)"](taskArgs.pool, utils.parseEther(taskArgs.amount),
            {value: utils.parseEther(taskArgs.amount)});
        const receipt = await tx.wait(1);
        console.log(`toETF tx: ${receipt.transactionHash}`);
    });

task("to-eth", "swap eth")
    .addParam("recipe", "the recipe address")
    .addParam("pool", "the smart pool address")
    .addParam("amount")
    .setAction(async (taskArgs, {ethers}) => {
        const signers = await ethers.getSigners();
        const v1CompatibleRecipe = V1CompatibleRecipeFactory.connect(taskArgs.recipe, signers[0]);
        console.log("v1CompatibleRecipe deployed to:", taskArgs.recipe);
        const token = Ierc20Factory.connect(taskArgs.pool, signers[0]);
        console.log("approving token");
        await (await token.approve(taskArgs.recipe, constants.MaxUint256)).wait(1);

        const tx = await v1CompatibleRecipe.toETH(taskArgs.pool, utils.parseEther(taskArgs.amount));
        const receipt = await tx.wait(1);
        console.log(`toETH tx: ${receipt.transactionHash}`);
    });

export default config;