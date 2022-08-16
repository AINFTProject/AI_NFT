const AINFT = artifacts.require("AINFT");
const AIMP_SC = artifacts.require("AIMP_SC");

let gu = {
    registerWorker: [],
    registerVerifier: [],
    verifyWorker: [],
    modelVerificationReq: [],
    registerForTask: [],
    submitResult: [],
    registerOracle: [],
    startAuction: [],
    bidOnAuction: [],
    withdrawBid: [],
    endAuction: [],
    transferAndRecieveFunds: [],
    mint: [],
    setApprovalForAll: [],
    withdrawFunds: [],
    sendAsset: [],
    registerREP: []
}
contract("Unit testing royalties", async accounts => {
    it("Should Deploy 3 Unique NFTS to 3 different accounts, with each being a child of predecessor", async () => {
        var resp;
        const instance = await AINFT.deployed();
        //Mint 3 NFTS for 3 different users, each having the previous as a parent
        let accZero = "0x0000000000000000000000000000000000000000";
        resp = await instance.mint(accounts[1], "QmNaeSB2Q7HXYG69F3ufz4DuvEApUBtpxx82AXPZnGVm2R", accZero, 0, { from: accounts[1] }); gu.mint.push(resp.receipt.gasUsed);
        resp = await instance.mint(accounts[2], "QmbNAoDJmsEmiVTdmnCwoXjscnbnp5dw4MuCwpLiPc8XNC", accounts[1], 1, { from: accounts[2] }); gu.mint.push(resp.receipt.gasUsed);
        resp = await instance.mint(accounts[3], "QmY3UyiYuy4cDovwPpY2ZZJATgLMTWGzDeJX7tGhSoC4nq", accounts[2], 2, { from: accounts[3] }); gu.mint.push(resp.receipt.gasUsed);

        //Get parent of each NFT
        const acc2Parent = await instance.getParent(2);
        const acc3Parent = await instance.getParent(3);
        //Assert that each NFT has the right parent associaed to it
        assert.equal(acc2Parent, accounts[1], "Wrong Parent");
        assert.equal(acc3Parent, accounts[2], "Wrong Parent");
        //Print Token URIS for visual validation
        let tokenURI1 = await instance.tokenURI(1);
        let tokenURI2 = await instance.tokenURI(2);
        let tokenURI3 = await instance.tokenURI(3);
        console.log("Token URI of token 1 is: " + tokenURI1);
        console.log("Token URI of token 2 is: " + tokenURI2);
        console.log("Token URI of token 3 is: " + tokenURI3);
    });
    it("Should give control to marketplace smart contract for all tokens", async () => {
        var resp;
        // Get instances of the contracts
        const instance = await AINFT.deployed();
        const instanceMP = await AIMP_SC.deployed();
        // Add the NFT contract address to the marketplace
        await instanceMP.addNFTContract(instance.address);
        //await instance.setApprovalForAll(instance.address, true, { from: accounts[1] });
        //Approve the marketplace as operator for users that want to auction NFTS
        resp = await instance.setApprovalForAll(instanceMP.address, true, { from: accounts[1] }); gu.setApprovalForAll.push(resp.receipt.gasUsed);
        resp = await instance.setApprovalForAll(instanceMP.address, true, { from: accounts[2] }); gu.setApprovalForAll.push(resp.receipt.gasUsed);
        resp = await instance.setApprovalForAll(instanceMP.address, true, { from: accounts[3] }); gu.setApprovalForAll.push(resp.receipt.gasUsed);
        const approved1 = await instance.isApprovedForAll(accounts[1], instanceMP.address);
        const approved2 = await instance.isApprovedForAll(accounts[2], instanceMP.address);
        const approved3 = await instance.isApprovedForAll(accounts[3], instanceMP.address);
        //Validate the correct assignment of the marketplace as operator for the NFTS
        assert(approved1, "Account one did not approve the operator");
        assert(approved2, "Account two did not approve the operator");
        assert(approved3, "Account three did not approve the operator");
    });

    it("Should register workers and verifiers correctly, as well as verifying the workers", async () => {
        const instance = await AINFT.deployed();
        let attestation = web3.utils.asciiToHex("123456789"); //dummy value for testing
        var resp;
        //accounts 12 to 17 assigned as workers
        for (let i = 12; i < 18; i++) {
            resp = await instance.registerWorker(attestation, { from: accounts[i] }); gu.registerWorker.push(resp.receipt.gasUsed);
        }
        //accounts 20 to 24 assigned as verifiers
        for (let j = 20; j < 25; j++) {
            resp = await instance.registerVerifier({ from: accounts[j] }); gu.registerVerifier.push(resp.receipt.gasUsed);
        }
        //await instance.verifyWorker(accounts[2], 1, { from: accounts[2] });
        //verify workers 12 to 16
        for (let k = 12; k < 17; k++) {
            for (let z = 20; z < 25; z++) {// goes through the verifiers
                if (z == 22) {//One of the verifiers goes against the majority and votes for invalidity
                    resp = await instance.verifyWorker(accounts[k], -1, { from: accounts[z] });
                    gu.verifyWorker.push(resp.receipt.gasUsed);
                } else {
                    await instance.verifyWorker(accounts[k], 1, { from: accounts[z] });
                }
            }
        }
        //one verifier votes for worker 17
        resp = await instance.verifyWorker(accounts[17], 1, { from: accounts[20] });
        gu.verifyWorker.push(resp.receipt.gasUsed);
        // The same verifier attempts to verify the worker again but is prevented from doing so
        try {
            await instance.verifyWorker(accounts[17], 1, { from: accounts[20] });
        } catch (e) {
            console.log("verifyWorker: Prevented Verifier 1 from verifying twice!");
        }
        // two more verifiers vote to verify the worker
        resp = await instance.verifyWorker(accounts[17], 1, { from: accounts[21] }); gu.verifyWorker.push(resp.receipt.gasUsed);
        resp = await instance.verifyWorker(accounts[17], 1, { from: accounts[22] }); gu.verifyWorker.push(resp.receipt.gasUsed);
        for (let w = 12; w < 18; w++) {
            assert(instance.isWorker(accounts[w]), "Worker was not verified appropriately!");
        }
    });
    it("Should initiate, process and end a model assessment appropriately", async () => {
        const instance = await AINFT.deployed();
        let taskNo = 1;
        let taskOracles = [];
        let oracleCount = 0;
        var resp;
        //Account 1 requests its model to be verified
        resp = await instance.modelVerificationReq(1, accounts[1], 3, 2, { from: accounts[1] }); gu.modelVerificationReq.push(resp.receipt.gasUsed);
        for (let l = 12; l < 18; l++) {
            //Oracles register for tasks
            taskOracles[l - 12] = oracleCount++;
            resp = await instance.registerForTask(taskNo, { from: accounts[l] }); gu.registerForTask.push(resp.receipt.gasUsed);
        }

        try {// Oracle attempts to register twice for the same task 
            await instance.registerForTask(taskNo, { from: accounts[12] });
        } catch (e) {
            console.log("Prevented Oracle 1 from registering again for a task!")
        }
        console.log("Oracles assigned for task: " + taskOracles);
        for (let m = 12; m < 18; m++) {// oracles heads submit the test results, non-head oracle are prevented from doing so
            try {
                resp = await instance.submitResult(taskNo, taskOracles[m - 12], 97, { from: accounts[m] }); gu.submitResult.push(resp.receipt.gasUsed);
            } catch (e) {
                console.log("Worker" + (m - 11) + " is not a head!");
            }
        }
        assert(instance.isVerified(1), "The model was not verified successfully!");
        //Repeating the same process but for NFT 3 for account 3
        taskNo++;
        let taskOracles2 = [];
        oracleCount = 0;
        respt = await instance.modelVerificationReq(3, accounts[3], 3, 2, { from: accounts[3] }); gu.modelVerificationReq.push(resp.receipt.gasUsed);
        for (let l = 17; l >= 12; l--) {
            taskOracles2[l - 12] = oracleCount++;
            resp = await instance.registerForTask(taskNo, { from: accounts[l] }); gu.registerForTask.push(resp.receipt.gasUsed);
        }
        console.log(taskOracles2);
        for (let m = 12; m < 18; m++) {
            try {
                resp = await instance.submitResult(taskNo, taskOracles2[m - 12], 97, { from: accounts[m] }); gu.submitResult.push(resp.receipt.gasUsed);
            } catch (e) {
                console.log("Worker" + (taskOracles2[m - 12] + 1) + " is not a head!");
            }
        }
        assert(instance.isVerified(3), "The model was not verified successfully!");
    });
    it("Should start auction correctly and prevent misbehaviour", async () => {//
        const instance1 = await AIMP_SC.deployed();
        var resp;
        //register the time oracle
        resp = await instance1.registerOracle({ from: accounts[6] }); gu.registerOracle.push(resp.receipt.gasUsed);
        //validate the correct assignment of the oracle
        const oracle = await instance1.isOracle(accounts[6]);
        assert.equal(oracle, true, "This account is not an oracle!");
        // series of invalid auction attempts
        try {
            await instance1.startAuction(accounts[2], 2, 1632797637, { from: accounts[2] });
        } catch (e) {
            console.log("startAuction: Prevented start of auction due to invalid timeframe!");
        }
        try {
            await instance1.startAuction(accounts[5], 5, 1652797637, { from: accounts[5] });
        } catch (e) {
            console.log("startAuction: Prevented start of auction due to invalid token!");
        }
        try {
            await instance1.startAuction(accounts[5], 2, 1652797637, { from: accounts[5] });
        } catch (e) {
            console.log("startAuction: Prevented start of auction due to unauthorized address attempting to auction token!");
        }
        //starting auction for NFT 3 by account 3
        resp = await instance1.startAuction(accounts[3], 3, 1662797637, { from: accounts[3] }); gu.startAuction.push(resp.receipt.gasUsed);

        // const resp = await instance1.startAuction2(accounts[1], 1, 1652604636, 1652797637, 9000000000, { from: accounts[1] });
        // console.log(resp.receipt.gasUsed);
    });
    it("Should ensure correct bidding functionality", async () => {
        const instance1 = await AIMP_SC.deployed();
        var resp;
        resp = await instance1.bidOnAuction(3, { from: accounts[8], value: 90000000000000000 }); gu.bidOnAuction.push(resp.receipt.gasUsed);
        resp = await instance1.bidOnAuction(3, { from: accounts[9], value: 95000000000000000 }); gu.bidOnAuction.push(resp.receipt.gasUsed);
        try {
            await instance1.bidOnAuction(2, { from: accounts[4], value: 95000000000000000 });
        } catch (e) {
            console.log("bidOnAuction: Prevented user from bidding an amount equal to or less than highest bidder!");
        }
    });
    it("Should ensure correct withdrawing functionality", async () => {
        const instance1 = await AIMP_SC.deployed();
        var resp;
        try {
            await instance1.withdrawBid({ from: accounts[5] });
        } catch (e) {
            console.log("withdrawBid: Prevented a non-bidding account from withdrawing funds!");
        }
        try {
            await instance1.withdrawBid({ from: accounts[9] });
        } catch (e) {
            console.log("withdrawBid: Prevented the highest bidder from withdrawing funds while auction is ongoing!");
        }

        resp = await instance1.withdrawBid({ from: accounts[8] }); gu.withdrawBid.push(resp.receipt.gasUsed);
    });
    it("Should ensure correct end auction functionality", async () => {
        const instance1 = await AIMP_SC.deployed();
        var resp;
        try {
            await instance1.endAuction(3, { from: accounts[2] });
        } catch (e) {
            console.log("endAuction: An account that is not owner or oracle attempted to end auction, disallowed!");
        }
        try {
            await instance1.endAuction(3, { from: accounts[6] });
        } catch (e) {
            console.log("endAuction: An oracle attempted to end auction before its end time!");
        }
        try {
            await instance1.transferAndRecieveFunds(3, { from: accounts[3] });
        } catch (e) {
            console.log("transfer: Prevented the transfer sale of the token before the auction end!")
        }
        resp = await instance1.endAuction(3, { from: accounts[3] }); gu.endAuction.push(resp.receipt.gasUsed);
    });
    it("Should successfully assign shares, transfer token and asset to buyer", async () => {
        const instance1 = await AIMP_SC.deployed();
        const instance2 = await AINFT.deployed();
        var resp;
        resp = await instance2.registerREP({ from: accounts[18] }); gu.registerREP.push(resp.receipt.gasUsed);
        resp = await instance2.registerREP({ from: accounts[19] }); gu.registerREP.push(resp.receipt.gasUsed);

        let length = 1;
        let amount = 950000000000000;
        let share = 100;
        for (let i = 0; i < length; i++) {
            payment =
                ((amount * (share * (i + 1))) *
                    (((11 - length) * 100) / 2)) /
                1000000;
            amount -= payment;
        }
        console.log("Payment: " + payment)
        console.log("Amount: " + amount)
        try {
            await instance1.transferAndRecieveFunds(3, { from: accounts[2] });
        } catch (e) {
            console.log("transfer: Prevented the sale of the token due to unauthorized user!")
        }
        try {
            await instance1.transferAndRecieveFunds(2, { from: accounts[3] });
        } catch (e) {
            console.log("transfer: Prevented the sale of the token that was not auctioned!");
        }
        try {
            await instance1.transferAndRecieveFunds(3, { from: accounts[3] });
        } catch (e) {
            console.log("transfer: Prevented the sale of token, asset not submitted yet!");
        }
        resp = await instance2.sendAsset(3, "QmNaeSB2Q7HXYG69F3ufz4DuvEApUBtpxx82AXPZnGVm2K", "470adf558bde5b94e0141de306c293e26d6b140d4230525a51864d0b8982d9e1", "0774c27cc64750d3c11dd3e22cfea7cd397278923ec29e4845d68da0fcb185e1", { from: accounts[18] }); gu.sendAsset.push(resp.receipt.gasUsed);
        resp = await instance2.sendAsset(3, "QmPaeSB2Q7HXYG69F3ufz4DuvEApUBtpxx82AXPZnGVm2K", "770adf558bde5b94e0141de306c293e26d6b140d4230525a51864d0b8982d9e1", "2774c27cc64750d3c11dd3e22cfea7cd397278923ec29e4845d68da0fcb185e1", { from: accounts[19] }); gu.sendAsset.push(resp.receipt.gasUsed);
        resp = await instance2.sendAsset(3, "", "", "", { from: accounts[9] }); gu.sendAsset.push(resp.receipt.gasUsed);
        resp = await instance1.transferAndRecieveFunds(3, { from: accounts[3] }); gu.transferAndRecieveFunds.push(resp.receipt.gasUsed);
    });
    it("Should allow eligible users to withdraw funds correclty", async () => {
        const instance1 = await AIMP_SC.deployed();
        var resp;
        try {
            await instance1.withdrawFunds({ from: accounts[7] });
        } catch (e) {
            console.log("withdrawFunds: Prevented non-eligible account from withdrawing funds!");
        }
        let acc1Balance = await web3.eth.getBalance(accounts[1]);
        let acc2Balance = await web3.eth.getBalance(accounts[2]);
        let acc3Balance = await web3.eth.getBalance(accounts[3]);
        console.log("The initial balance of the accounts is:");
        console.log(web3.utils.fromWei(acc1Balance, "ether"));
        console.log(web3.utils.fromWei(acc2Balance, "ether"));
        console.log(web3.utils.fromWei(acc3Balance, "ether"));
        resp = await instance1.withdrawFunds({ from: accounts[1] }); gu.withdrawFunds.push(resp.receipt.gasUsed);
        resp = await instance1.withdrawFunds({ from: accounts[2] }); gu.withdrawFunds.push(resp.receipt.gasUsed);
        resp = await instance1.withdrawFunds({ from: accounts[3] }); gu.withdrawFunds.push(resp.receipt.gasUsed);

        console.log("The current balance of the accounts is:")

        acc1Balance = await web3.eth.getBalance(accounts[1]);
        acc2Balance = await web3.eth.getBalance(accounts[2]);
        acc3Balance = await web3.eth.getBalance(accounts[3]);
        console.log(web3.utils.fromWei(acc1Balance, "ether"));
        console.log(web3.utils.fromWei(acc2Balance, "ether"));
        console.log(web3.utils.fromWei(acc3Balance, "ether"));
    });
    it("Should validate correct transfer of token", async () => {
        const instance2 = await AINFT.deployed();
        const owner = await instance2.ownerOf(3);
        const oldOwner = await instance2.isApprovedOrOwner(accounts[3], 3);
        // console.log(owner);
        // console.log(oldOwner);

        assert.equal(owner, accounts[9], "Token Not successfully transferred!");
        assert(!oldOwner, "The old owner still has access to token!");
    });

    it("Measuring average gas used", async () => {
        for (var fn of Object.keys(gu)) {
            console.log(fn + ": " + gu[fn].reduce((a, c) => a + c, 0) / gu[fn].length);
        }
    });  
})
