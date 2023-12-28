pragma solidity 0.8.21;

// import { Ownable } from "openzeppelin/access/Ownable.sol";
// import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

struct Project {
    address token;
    bytes32 root;
    string projectName;
    address projectOwner;
    uint64 allocated;
    uint64 claimed;
}

contract ContractToBeOptimised is Ownable {
    mapping(IERC20 token => bool supported) private _tokens;
    mapping(string id => Project project) private _projects;

    mapping(address tokenReceiver => mapping(string projectId => uint64 claimedTokens))
        private _claimedTokens;

    /// @notice Constructor sets the tokenHolder address and supported tokens.
    /// @param tokens supported tokens.
    constructor(IERC20[] memory tokens) {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens[tokens[i]] = true;
        }
    }

    /// @notice Issues tokens to a receiver.
    /// @param id The id of the merkle root.
    /// @param amount The total available of the token to be issued.
    /// @param proof The merkle proof.
    function issueTokens(
        string calldata id,
        uint64 amount,
        bytes32[] calldata proof
    ) public {
        require(amount > 0, "ERC20IssuerV2: amount must be greater than 0");

        address receiver = msg.sender;
        address token = _projects[id].token;
        uint64 allocated = _projects[id].allocated;
        uint64 claimed = _projects[id].claimed;

        require(token != address(0), "Project already exists!");
        require(
            _claimedTokens[receiver][id] < amount,
            "Insufficient tokens available to claim!"
        );
        require(
            allocated > claimed,
            "All allocated tokens have already been claimed! Please contact the project owner."
        );

        require(
            verify(id, getLeaf(receiver, address(token), amount), proof),
            "Invalid merkle proof!"
        );

        if (allocated > claimed && _claimedTokens[receiver][id] < amount) {
            uint64 availableClaimedTokens = amount -
                _claimedTokens[receiver][id];

            IERC20(token).approve(address(this), availableClaimedTokens);
            IERC20(token).transferFrom(
                address(this),
                receiver,
                availableClaimedTokens
            );

            _claimedTokens[receiver][id] = amount;
            _projects[id].claimed += availableClaimedTokens;
        } else {
            revert("No tokens available to claim!");
        }
    }

    /// @notice Allows the project owner to reclaim unclaimed tokens.
    /// @dev Reverts if the project does not exist, the caller is not the project owner or
    ///      the allocated tokens have been claimed.
    /// @param id The id of the project.
    function reclaimTokens(string calldata id) public {
        uint64 allocated = _projects[id].allocated;
        uint64 claimed = _projects[id].claimed;

        require(
            address(_projects[id].token) != address(0),
            "Project does not exist!"
        );
        require(
            msg.sender == _projects[id].projectOwner,
            "Caller is not project owner!"
        );
        require(
            allocated > claimed,
            "All allocated tokens have already been claimed!"
        );

        uint64 reclaimAmount = allocated - claimed;

        IERC20(_projects[id].token).approve(address(this), reclaimAmount);
        IERC20(_projects[id].token).transferFrom(
            address(this),
            _projects[id].projectOwner,
            reclaimAmount
        );

        _projects[id].claimed = allocated;
    }

    /// @notice Sets a new project with a specific token, merkle root, project name,
    ///         project owner and total allocated tokens.
    /// @dev Only callable by the owner of this contract.
    /// @param token The token to be issued.
    /// @param id The id for this project.
    /// @param root The root of the merkle tree.
    /// @param projectName The name of the project.
    /// @param allocated The total allocated tokens for the project.
    function setProject(
        address token,
        string calldata id,
        bytes32 root,
        string memory projectName,
        uint64 allocated
    ) public {
        address projectOwner = msg.sender;
        require(_tokens[IERC20(token)], "Invalid token");
        require(
            _projects[id].projectOwner == address(0),
            "Project already exists"
        );
        _projects[id] = Project(
            token,
            root,
            projectName,
            projectOwner,
            allocated,
            0
        );

        IERC20(token).transferFrom(projectOwner, address(this), allocated);
    }

    /// @param id The id for this project.
    /// @param root The new root of the merkle tree.
    function updateMerkleRoot(string calldata id, bytes32 root) public {
        require(
            msg.sender == _projects[id].projectOwner,
            "Caller is not project owner"
        );
        _projects[id].root = root;
    }

    /// @notice Update existed project with a specific token, merkle root, project name,
    ///         project owner and total allocated tokens.
    /// @dev Only callable by the project owner.
    /// @param token The token to be issued.
    /// @param id The id for this project.
    /// @param root The root of the merkle tree.
    /// @param projectName The name of the project.
    /// @param allocated The total allocated tokens for the project.
    function updateProject(
        address token,
        string calldata id,
        bytes32 root,
        string memory projectName,
        uint64 allocated
    ) public {
        address projectOwner = msg.sender;
        require(_tokens[IERC20(token)], "Invalid token");
        require(
            msg.sender == _projects[id].projectOwner,
            "Caller is not project owner!"
        );

        uint64 oldAllocated = _projects[id].allocated;
        address oldTokenAddress = _projects[id].token;
        uint64 claimed = _projects[id].claimed;
        require(claimed == 0, "Project has started claimed");

        IERC20(oldTokenAddress).transfer(projectOwner, oldAllocated);

        _projects[id] = Project(
            token,
            root,
            projectName,
            projectOwner,
            allocated,
            0
        );

        IERC20(token).transferFrom(projectOwner, address(this), allocated);
    }

    /// @notice User increase reward token for a existing project
    /// @param id The project id.
    /// @param amount The total deposit tokens for the project.
    function deposit(string calldata id, uint64 amount) public {
        require(
            msg.sender == _projects[id].projectOwner,
            "Caller is not project owner!"
        );

        address token = _projects[id].token;
        _projects[id].allocated += amount;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Sets a token.
    /// @param token The token to be supported.
    function addToken(IERC20 token) public onlyOwner {
        _tokens[token] = true;
    }

    /// @notice Removes a token.
    /// @param token The token to be removed.
    function removeToken(IERC20 token) public onlyOwner {
        _tokens[token] = false;
    }

    /// @notice Returns a leaf of the merkle-tree.
    /// @param receiver The receiver of the tokens.
    /// @param token The token to be issued.
    /// @param amount The amount of the token to be issued.
    function getLeaf(
        address receiver,
        address token,
        uint64 amount
    ) public pure returns (bytes32) {
        // write code to generate the merkle leaf
    }

    /// @notice Verifies a given leaf is in the merkle-tree with the given root.
    function verify(
        string calldata id,
        bytes32 leaf,
        bytes32[] calldata proof
    ) public view returns (bool) {
        // write code to verify the merkle proof
    }
}
