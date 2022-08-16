// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/////////////  Structs  /////////////
struct Royalty {
    // Royalty struct
    uint256 value;
    address recepient;
}
struct Token {
    // A struct that keeps a provenance chain that will be used in distributing royalties
    address childOf;
    uint256 parentToken;
    uint256 tokenNo;
    bool verified;
    address owner;
    uint256 level;
}

struct Task {
    //PlaceHolder Struct, delete(clear) after end of each task of assessing a model
    uint256 token;
    uint256 workers;
    uint256 wCount;
    uint256 iterations;
    uint256 result;
    address[] workersAddr;
    bool[] submitted;
}
struct Worker {
    // Oracles that participate in verifying a submitted model
    bool registering;
    int256 validation;
    uint256 taskNo;
    bool valid;
    bytes32 attestation;
    uint256 position;
}

/////////////  Contract  /////////////
contract AINFT is ERC721URIStorage {
    /////////////  Mappings & State Variables  /////////////
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => Royalty) tokenRoyalty;
    mapping(uint256 => Token) token;
    //AIMP_SC marketplace;
    address marketplaceAddr;
    uint256 defaultRoyalty = 100;
    uint256 decayRange = 11;

    /////////////  Modifiers /////////////

    modifier onlyOwner(uint256 _token) {
        require(msg.sender == token[_token].owner);
        _;
    }

    modifier onlyMarket() {
        require(msg.sender == marketplaceAddr);
        _;
    }

    /////////////  Events  /////////////
    event royalty(address[]);
    event royaltyPay(Royalty[] withdraws, string _msg);

    /////////////  Functions  /////////////
    //
    constructor(address _marketplace) ERC721("Model NFT", "AINFT") {
        marketplaceAddr = _marketplace;
        _tokenIdCounter.increment();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "ipfs://";
    }

    function mint(
        address _to,
        string calldata _uri,
        address _parent,
        uint256 _parentToken
    ) public {
        require(msg.sender == _to, "Only the owner can mint!");
        ///////////// Implements the ERC-721 _mint and _setTokenURI and approves the marketplace as operator
        _mint(_to, _tokenIdCounter.current());
        _setTokenURI(_tokenIdCounter.current(), _uri);
        setToken(_to, _parent, _tokenIdCounter.current(), _parentToken);
        setRoyalty(defaultRoyalty, _to, _tokenIdCounter.current());
        _tokenIdCounter.increment();
    }

    function closeDeal(
        uint256 _token,
        uint256 _price,
        address _buyer
    ) public payable onlyMarket returns (Royalty[] memory) {
        ///////////// Assign the appropriate payments for the involved users and transfer token to the buyer
        require(!toSubmit[_token], "Asset needs to be submitted first!");
        uint256 amount = _price;
        Royalty[] memory withdraws;
        if (token[_token].childOf == address(0)) {
            withdraws = new Royalty[](0);
            safeTransferFrom(token[_token].owner, _buyer, _token);
        } else {
            uint256 share = tokenRoyalty[_token].value;
            uint256 payment;
            (address[] memory toPay, uint256 length) = getRoyalty(_token);
            withdraws = new Royalty[](length + 1);
            for (uint256 i = 0; i < length; i++) {
                payment =
                    ((amount * (share * (length - i))) *
                        ((((decayRange - length) * 100) * 2) / 5)) /
                    1000000;

                withdraws[i] = (Royalty(payment, toPay[i]));
                amount -= payment;
            }
            withdraws[length].recepient = token[_token].owner;
            withdraws[length].value = amount;
            emit royaltyPay(
                withdraws,
                "Withdraw your earnings from the smart contract(withdrawFunds)!"
            );
            safeTransferFrom(token[_token].owner, _buyer, _token);
        }
        return withdraws;
    }

    function getRoyalty(uint256 _token)
        internal
        returns (address[] memory, uint256)
    {
        ///////////// Gets all the predecessors of the token getting sold and their corresponding royalties
        if (token[_token].childOf == address(0)) {
            revert("No Royalties");
        }
        address[] memory royalAccounts;
        royalAccounts = new address[](decayRange);
        address parentAccount = token[_token].childOf;
        uint256 Ptoken = token[_token].parentToken;
        uint256 i = 0;
        while (parentAccount != address(0) && i < decayRange) {
            royalAccounts[i] = parentAccount;
            parentAccount = token[Ptoken].childOf;
            Ptoken = token[Ptoken].parentToken;
            i++;
        }
        emit royalty(royalAccounts);
        return (royalAccounts, i);
    }

    function setToken(
        address _owner,
        address _childOf,
        uint256 _tokenNo,
        uint256 _parentToken
    ) internal {
        ///////////// Initialize the token struct
        Token memory tokenInst;
        tokenInst.owner = _owner;
        tokenInst.tokenNo = _tokenNo;
        tokenInst.parentToken = _parentToken;
        tokenInst.childOf = _childOf;
        if (_parentToken != 0 && _childOf != address(0))
            tokenInst.level = token[_parentToken].level + 1;
        token[_tokenNo] = tokenInst;
    }

    function setRoyalty(
        uint256 _amount,
        address _recepient,
        uint256 _token
    ) internal {
        ///////////// Initialize the Royalty struct
        tokenRoyalty[_token] = Royalty(_amount, _recepient);
    }

    /////////////  Modifiers /////////////
    modifier notRegistered() {
        require(
            verifiers[msg.sender] == address(0) && !workers[msg.sender].valid
        );
        _;
    }
    modifier onlyVerifier() {
        require(verifiers[msg.sender] != address(0));
        _;
    }

    modifier onlyWorker() {
        require(workers[msg.sender].valid);
        _;
    }
    /////////////  Mappings & State Variables  /////////////
    mapping(address => address) verifiers;
    mapping(address => Worker) workers;
    mapping(uint256 => Task) task;
    mapping(address => bool) rep;
    mapping(uint256 => address) assetToSubmit;
    mapping(uint256 => bool) toSubmit;
    //uint256 totalREP = 0;
    uint256 taskCounter = 1;
    int256 verificationRequirement = 3;
    uint256 noWorkers = 0;

    /////////////  Events  /////////////
    event NewWorker(address, bytes32);
    event NewWorkerVerified(address Worker);
    event ModelVerificationTask(
        uint256 Token,
        address Owner,
        uint256 Workers,
        uint256 Iterations,
        uint256 taskNumber
    );
    event workerRegisterTask(address Worker, uint256 position);
    event modelAssessment(uint256 Accuracy, uint256 TaskNumber);
    event workerSubmit(address, uint256);
    event verified(bool, uint256);

    /////////////  Functions  /////////////
    function registerREP() public notRegistered {
        rep[msg.sender] = true;
    }

    function registerWorker(bytes32 _attestation) public notRegistered {
        Worker memory workerInst;
        workerInst.registering = true;
        workerInst.attestation = _attestation;
        workers[msg.sender] = workerInst;
        noWorkers++;
        emit NewWorker(msg.sender, _attestation);
    }

    function registerVerifier() public notRegistered {
        verifiers[msg.sender] = address(0x01); // 0x01 means that verifier is not assigned to a worker verification task
    }

    function verifyWorker(address _worker, int256 _result) public onlyVerifier {
        require(
            workers[_worker].validation != verificationRequirement &&
                workers[_worker].validation != (-verificationRequirement) &&
                workers[_worker].registering &&
                verifiers[msg.sender] != _worker,
            "User not allowed to register"
        );
        workers[_worker].validation += _result;
        verifiers[msg.sender] = _worker;
        if (workers[_worker].validation == verificationRequirement) {
            workers[_worker].valid = true;
            workers[_worker].registering = false;
            emit NewWorkerVerified(_worker);
        } else if (workers[_worker].validation == (-verificationRequirement)) {
            workers[_worker].registering = false;
        }
    }

    // public isOwner(_token)
    function modelVerificationReq(
        uint256 _token,
        address _owner,
        uint256 _workersNo,
        uint256 _iterations
    ) public onlyOwner(_token) {
        //check if it costs more to pass as paramter or access struct variable, change accordingly
        require(
            _owner == msg.sender &&
                token[_token].tokenNo != 0 &&
                _workersNo * _iterations <= noWorkers,
            "Owner should correspond to sender and workers requested should not exceed available workers!"
        );
        Task memory taskInst;
        taskInst.workers = _workersNo;
        taskInst.iterations = _iterations;
        taskInst.token = _token;
        taskInst.workersAddr = new address[](_iterations * _workersNo);
        task[taskCounter] = taskInst;
        emit ModelVerificationTask(
            _token,
            _owner,
            _workersNo,
            _iterations,
            taskCounter
        );
        taskCounter++;
    }

    function registerForTask(uint256 _taskNo) public onlyWorker {
        require(
            task[_taskNo].wCount !=
                task[_taskNo].workers * task[_taskNo].iterations &&
                workers[msg.sender].taskNo != _taskNo,
            "No more workers needed for task"
        );
        task[_taskNo].workersAddr[task[_taskNo].wCount] = msg.sender;
        workers[msg.sender].taskNo = _taskNo;
        workers[msg.sender].position = 0;
        task[_taskNo].wCount++;
        emit workerRegisterTask(msg.sender, task[_taskNo].wCount - 1);
    }

    function submitResult(
        uint256 _taskNo,
        uint256 _order,
        uint256 _result
    ) public onlyWorker {
        //make sure to enter the array index
        //might be able to remove the submitted array
        require(
            task[_taskNo].wCount ==
                task[_taskNo].workers * task[_taskNo].iterations &&
                workers[msg.sender].position == 0,
            "Task assignment not done yet"
        );
        require(
            (_order + 1) % task[_taskNo].workers == 0 &&
                task[_taskNo].workersAddr[_order] == msg.sender,
            "Invalid user/index to submit result!"
        );
        task[_taskNo].result += _result;
        emit workerSubmit(msg.sender, _order);
        task[_taskNo].submitted.push(true);
        workers[msg.sender].position = task[_taskNo].submitted.length;

        if (task[_taskNo].submitted.length == task[_taskNo].iterations) {
            //TODO: Delete and end the task //done
            task[_taskNo].result =
                task[_taskNo].result /
                task[_taskNo].submitted.length;
            emit modelAssessment(task[_taskNo].result, _taskNo);
            token[task[_taskNo].token].verified = true;
            emit verified(
                token[task[_taskNo].token].verified,
                task[_taskNo].token
            );
            delete task[_taskNo];
        }
    }

    event assetTransfer(uint256 assetID, string, string, string);
    event submitAsset(uint256 assetID, address buyer);

    function assetSubmissionReq(uint256 _token, address _buyer) public {
        toSubmit[_token] = true;
        assetToSubmit[_token] = _buyer;
        emit submitAsset(_token, _buyer);
    }

    function sendAsset(
        uint256 _tokenID,
        string calldata _path,
        string calldata _clearHash,
        string calldata _encryptedSecretKey
    ) public {
        if (msg.sender == assetToSubmit[_tokenID]) {
            delete toSubmit[_tokenID];
            delete assetToSubmit[_tokenID];
        } else {
            require(
                toSubmit[_tokenID] = true && rep[msg.sender],
                " Invalid Asset Submission!"
            );
            emit assetTransfer(
                _tokenID,
                _path,
                _clearHash,
                _encryptedSecretKey
            );
        }
    }

    /////////////  Gas-Free functions(View/Pure) and Fallback  /////////////

    function isApprovedOrOwner(address spender, uint256 tokenId)
        public
        view
        returns (bool)
    {
        return super._isApprovedOrOwner(spender, tokenId);
    }

    //functions used for Testing
    function getParent(uint256 _token) public view returns (address) {
        return token[_token].childOf;
    }

    function getCount(uint256 _taskNo) public view returns (uint256) {
        //function only used for testing
        return task[_taskNo].wCount;
    }

    function isVerified(uint256 _token) public view returns (bool) {
        return token[_token].verified;
    }

    function isWorker(address _workerAddress) public view returns (bool) {
        return workers[_workerAddress].valid;
    }

    fallback() external payable {}

    receive() external payable {}
}
