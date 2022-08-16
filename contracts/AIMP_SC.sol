// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./AINFT.sol";


/////////////  Structs  /////////////
struct Auction {
    //PlaceHolder Struct, delete(clear) after end of each Auction
    address owner;
    uint256 saleToken;
    bool onGoing;
    uint256 end;
    uint256 highestBid;
    address highestBidder;
}

struct Bids {
    //PlaceHolder Struct, delete(clear) after withdrawal of bid
    uint256 bidToken;
    uint256 amount;
}

struct Oracle {
    // Time Oracle notifies SC when auction ends
    uint256 successfulTxs;
    bool active;
}

/////////////  Contract  /////////////

contract AIMP_SC {
    /////////////  Mappings & State Variables  /////////////
    mapping(uint256 => Auction) auction;
    mapping(address => Bids) bid;
    mapping(address => Oracle) oracle;
    mapping(address => Royalty) withdrawingAccs;
    AINFT nftContract;
    address nftContractAddr;
    uint256 gracePeriod = 30 minutes;

    /////////////  Modifiers /////////////
    modifier isOwnerandVerified(uint256 _token) {
        require(
            nftContract.isApprovedOrOwner(msg.sender, _token) &&
                nftContract.isVerified(_token),
            "User not approved to auction the model!"
        );
        _;
    }
    modifier isVerified(uint256 _token) {
        require(nftContract.isVerified(_token), "Model is not verified");
        _;
    }
    modifier isOwner(uint256 _token) {
        require(
            nftContract.isApprovedOrOwner(msg.sender, _token),
            "User not approved to auction the model!"
        );
        _;
    }

    /////////////  Events  /////////////
    event auctionStarted(
        address Owner,
        uint256 Token,
        uint256 Start,
        uint256 End,
        uint256 MinIncrement,
        uint256 GracePeriod
    );

    event newBid(address Bidder, uint256 Token, uint256 Bid);

    event auctionEnded(
        address Owner,
        uint256 Token,
        address WinningBidder,
        uint256 Price
    );

    /////////////  Functions  /////////////

    function addNFTContract(address payable _NFTSC) public {
        ///////////// Link the Marketplace to the NFT Contract
        nftContract = AINFT(_NFTSC);
        nftContractAddr = _NFTSC;
    }

    function registerOracle() public {
        ///////////// Register the time oracle
        Oracle memory oracleInst;
        oracleInst.active = true;
        oracle[msg.sender] = oracleInst;
    }

    //isOwnerandVerified(_token)
    function startAuction(
        address _owner,
        uint256 _token,
        uint256 _end
    ) public isOwner(_token) isVerified(_token) {
        ///////////// Start Auction, ensure time>now, owner of the token started the auction
        require(
            _end > (block.timestamp + 1000) && msg.sender == _owner,
            "Can not start auction due to invalid owner or time period!"
        );
        Auction memory auctionInst;
        auctionInst.owner = _owner;
        auctionInst.saleToken = _token;
        auctionInst.onGoing = true;
        auctionInst.end = _end;
        auction[_token] = auctionInst;

        emit auctionStarted( ///////////// Notify subscribers about the start of the auction
            _owner,
            _token,
            block.timestamp,
            _end,
            1000,
            30 minutes
        );
    }

    function bidOnAuction(uint256 _auctionToken) public payable {
        ///////////// Bid on auction providing the bid. Ensure: auction ongoing, price higher than last bid(and higher the minimum increment) and higher than reserve price
        require(
            auction[_auctionToken].onGoing,
            "There is no available auction for the model!"
        );
        require(
            msg.value > auction[_auctionToken].highestBid + 1000,
            "Should bid higher than last bid!"
        );
        if (
            bid[msg.sender].amount != 0 &&
            bid[msg.sender].bidToken == _auctionToken
        ) bid[msg.sender].amount += msg.value;
        else bid[msg.sender] = Bids(_auctionToken, msg.value);
        auction[_auctionToken].highestBid = msg.value;
        auction[_auctionToken].highestBidder = msg.sender;
        if (auction[_auctionToken].end - block.timestamp < gracePeriod)
            auction[_auctionToken].end = block.timestamp + gracePeriod;
        emit newBid(msg.sender, _auctionToken, msg.value);
    }

    function withdrawBid() public {
        ///////////// Withdraw bid that is not the highest bid
        require(
            bid[msg.sender].amount != 0 && bid[msg.sender].bidToken != 0,
            "Should provide a valid bid to withdraw!"
        );
        require(
            msg.sender != auction[bid[msg.sender].bidToken].highestBidder,
            "The highest bidder can not withraw deposit!"
        );
        payable(address(msg.sender)).transfer(bid[msg.sender].amount);
        delete bid[msg.sender];
    }

    function endAuction(uint256 _auctionToken) public {
        ///////////// End the auction. Ensure: Only can manually end it, or when time ends (notified by oracle)
        require(
            oracle[msg.sender].active == true ||
                auction[_auctionToken].owner == msg.sender,
            "Should be verified oracle or the owner of the auction to end it!"
        );
        if (auction[_auctionToken].owner == msg.sender) {
            auction[_auctionToken].onGoing = false;
        } else {
            if (block.timestamp >= auction[_auctionToken].end) {
                oracle[msg.sender].successfulTxs++;
                auction[_auctionToken].onGoing = false;
                // delete auction[_auctionToken];
            } else {
                oracle[msg.sender].successfulTxs--;
                revert("Time is not up yet, invalid request!");
            }
        }
        nftContract.assetSubmissionReq(
            _auctionToken,
            auction[_auctionToken].highestBidder
        );
        emit auctionEnded(
            auction[_auctionToken].owner,
            _auctionToken,
            auction[_auctionToken].highestBidder,
            auction[_auctionToken].highestBid
        );
    }

    event withdrawn(address, uint256);

    function withdrawFunds() public {
        ///////////// Withdraw the funds(Royalties/Share). Ensure: The caller is a verified address by the NFT contract
        require(
            withdrawingAccs[msg.sender].recepient == msg.sender,
            "Non-eligible account, can not withdraw funds!"
        );
        payable(address(msg.sender)).transfer(
            withdrawingAccs[msg.sender].value
        );
        emit withdrawn(msg.sender, withdrawingAccs[msg.sender].value);
        delete withdrawingAccs[msg.sender];
    }

    function transferAndRecieveFunds(uint256 _auctionToken) public payable {
        ///////////// Request the transfer of token to winning bidder and distribute earnings Ensure: auction ended and there is a winning bidder,
        /////////////only the owner can accept and initiate the request
        require(
            !auction[_auctionToken].onGoing &&
                auction[_auctionToken].owner == msg.sender &&
                auction[_auctionToken].highestBidder != address(0),
            "Invalid request, only the owner of the model is able to sell the item after auction ends!"
        );
        Royalty[] memory temp = nftContract.closeDeal(
            _auctionToken,
            auction[_auctionToken].highestBid,
            auction[_auctionToken].highestBidder
        );
        if (temp.length == 0) {
            withdrawingAccs[auction[_auctionToken].highestBidder] = Royalty(
                auction[_auctionToken].highestBid,
                auction[_auctionToken].highestBidder
            );
        } else {
            for (uint256 i; i < temp.length; i++) {
                withdrawingAccs[temp[i].recepient] = temp[i];
            }
        }
        delete auction[_auctionToken];
    }

    /////////////  Gas-free(View/Pure) functions  /////////////

    function isOracle(address _oracAddr) public view returns (bool) {
        ///////////// check if the provided address is a valid active oracle
        return oracle[_oracAddr].active;
    }

    function getTime() public view returns (uint256) {
        ///////////// Get the current Unix Epoch Timestamp
        return block.timestamp;
    }
}

