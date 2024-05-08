import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { expect } from "chai";

import { forkNetwork, deployContract, ThenArgRecursive } from "./shared/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

async function fixture() {
    const [deployer, user1, user2] = await ethers.getSigners();
    const userStorage = await deployUserStorage(deployer, []);
    // console.log("UserStorage:", userStorage.address);
    return {
        deployer,
        user1,
        user2,
        userStorage
    };
}

async function deployUserStorage(deployer: SignerWithAddress, agrs: any[]) {
    return deployContract(
        deployer,
        "UserStorage",
        agrs
    )
}

// async function ethereumFixture(blockNumber: number) {
//     await forkNetwork("mainnet", blockNumber);
//     return fixture();
// }

async function arbitrumFixture(blockNumber: number) {
    await forkNetwork("arbitrum", blockNumber);
    return fixture();
}

describe("UserStorage", async () => {
    context("arbitrum", () => {

        context("207259510", async () => {
            let fix: ThenArgRecursive<ReturnType<typeof arbitrumFixture>>;

            beforeEach(async () => {
                fix = await arbitrumFixture(207259510);
                await fix.userStorage.setOperators([fix.deployer.address], [true]);
                expect(await fix.userStorage.operator(fix.deployer.address)).equals(true)
            });

            it("setManager", async () => {
                expect(await fix.userStorage.manager()).equals(fix.deployer.address)
                await expect(fix.userStorage.connect(fix.user1).setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
                await fix.userStorage.setManager(fix.user1.address)
                expect(await fix.userStorage.manager()).equals(fix.user1.address)
                await expect(fix.userStorage.setManager(fix.user1.address)).to.be.revertedWith('Forbidden')
            });

            it("setOperators", async () => {
                await expect(fix.userStorage.connect(fix.user1).setOperators([fix.user1.address], [true])).to.be.revertedWith('Forbidden')
                await expect(fix.userStorage.setOperators([fix.user1.address], [])).to.be.revertedWith('BadLengths')
                await expect(fix.userStorage.setOperators([], [true])).to.be.revertedWith('BadLengths')
                await fix.userStorage.setOperators([fix.user1.address], [true])
                expect(await fix.userStorage.operator(fix.deployer.address)).equals(true)
                expect(await fix.userStorage.operator(fix.user1.address)).equals(true)

                await fix.userStorage.setOperators([fix.user1.address], [false])
                expect(await fix.userStorage.operator(fix.deployer.address)).equals(true)
                expect(await fix.userStorage.operator(fix.user1.address)).equals(false)
            });

            it("updateRef", async () => {
                await expect(fix.userStorage.connect(fix.user1).updateRef(fix.user1.address, fix.deployer.address)).to.be.revertedWith('Forbidden')
                await fix.userStorage.setOperators([fix.user1.address], [true])
                await fix.userStorage.connect(fix.user1).updateRef(fix.user1.address, fix.deployer.address)
                const userInfo1 = await fix.userStorage.getUserInfo(fix.user1.address)
                expect(userInfo1['id']).equals(fix.user1.address)
                expect(userInfo1['ref']).equals(fix.deployer.address)

                await fix.userStorage.connect(fix.user1).updateRef(fix.user1.address, fix.user2.address)
                const userInfo2 = await fix.userStorage.getUserInfo(fix.user1.address)
                expect(userInfo2['id']).equals(fix.user1.address)
                expect(userInfo2['ref']).equals(fix.user2.address)
            });

            it("updateMembership", async () => {
                const userInfo1 = await fix.userStorage.getUserInfo(fix.user1.address)
                expect(userInfo1['membershipLevel']).equals(BigNumber.from("0"))

                await expect(fix.userStorage.connect(fix.user1).updateMembership(fix.user1.address, 1)).to.be.revertedWith('Forbidden')
                await fix.userStorage.setOperators([fix.user1.address], [true])
                await fix.userStorage.connect(fix.user1).updateMembership(fix.user1.address, 1)
                const userInfo2 = await fix.userStorage.getUserInfo(fix.user1.address)
                expect(userInfo2['id']).equals(fix.user1.address)
                expect(userInfo2['membershipLevel']).equals(BigNumber.from("1"))
            });

            it("discountedFee", async () => {
                const fee = BigNumber.from("100")
                const membershipLevel = BigNumber.from("1")
                const factor = BigNumber.from("4")
                const discountedFee1 = await fix.userStorage.discountedFee(fix.user1.address, fee)
                expect(discountedFee1).equals(fee)

                await fix.userStorage.updateMembership(fix.user1.address, membershipLevel)
                const discountedFee2 = await fix.userStorage.discountedFee(fix.user1.address, fee)
                const discount = fee.mul(membershipLevel).div(membershipLevel.add(factor))
                expect(discountedFee2).equals(fee.sub(discount))
            });
        });
    });
});