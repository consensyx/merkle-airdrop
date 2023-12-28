//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

struct Project {
    address token;
    address projectOwner;
    bytes32 root;
    uint64 allocated;
    uint64 claimed;
    string projectName;
}

contract MerkleAirdrop is Ownable {
    using SafeERC20 for IERC20;

    mapping(IERC20 token => bool supported) private _tokens;
    mapping(string id => Project project) private _projects;

    mapping(address tokenReceiver => mapping(string projectId => mapping(uint256 index => bool claimed)))
        private _claimed;

    event TokenIssued(address indexed account, string id, uint256 index, uint64 amount);
    event TokenReclaimed(address indexed projectOwner, string id, uint64 amount);

    /// @notice Constructor sets the tokenHolder address and supported tokens.
    /// @param tokens supported tokens.
    constructor(IERC20[] memory tokens) {
        for (uint256 i = 0; i < tokens.length; ) {
            _tokens[tokens[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    /// @notice Issues tokens to a receiver.
    /// @param id The id of the merkle root.
    /// @param amount The total available of the token to be issued.
    /// @param proof The merkle proof.
    function issueTokens(string calldata id, uint256 index, uint64 amount, bytes32[] calldata proof) public {
        // early check
        require(amount > 0, "ERC20IssuerV2: amount must be greater than 0");
        address token = _projects[id].token;
        address receiver = msg.sender;
        require(token != address(0), "Project not exists!");
        require(!_claimed[receiver][id][index], "Already claimed!");
        require(verify(id, getLeaf(index, receiver, address(token), amount), proof), "Invalid merkle proof!");

        if (_projects[id].allocated > _projects[id].claimed) {
            _claimed[receiver][id][index] = true;
            _projects[id].claimed += amount;

            IERC20(token).safeTransfer(receiver, amount);
            emit TokenIssued(receiver, id, index, amount);
        } else {
            revert("No tokens available to claim!");
        }
    }

    /// @notice Allows the project owner to reclaim unclaimed tokens.
    /// @dev Reverts if the project does not exist, the caller is not the project owner or
    ///      the allocated tokens have been claimed.
    /// @param id The id of the project.
    function reclaimTokens(string calldata id) public {
        address token = _projects[id].token;
        address projectOwner = _projects[id].projectOwner;

        require(token != address(0), "Project does not exists!");
        require(address(_projects[id].token) != address(0), "Project does not exist!");
        require(msg.sender == projectOwner, "Caller is not project owner!");

        uint64 allocated = _projects[id].allocated;
        uint64 claimed = _projects[id].claimed;

        require(allocated > claimed, "All allocated tokens have already been claimed!");

        uint64 reclaimAmount = allocated - claimed;

        _projects[id].claimed = allocated;

        IERC20(token).safeTransfer(projectOwner, reclaimAmount);
        emit TokenReclaimed(projectOwner, id, reclaimAmount);
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
        require(allocated > 0, "Allocated amount should greater than 0");
        require(_tokens[IERC20(token)], "Invalid token");

        address projectOwner = msg.sender;
        require(_projects[id].projectOwner == address(0), "Project already exists");

        _projects[id] = Project(token, projectOwner, root, allocated, 0, projectName);

        IERC20(token).safeTransferFrom(projectOwner, address(this), allocated);
    }

    /// @param id The id for this project.
    /// @param root The new root of the merkle tree.
    function updateMerkleRoot(string calldata id, bytes32 root) public {
        require(msg.sender == _projects[id].projectOwner, "Caller is not project owner");
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
        // early check
        require(_tokens[IERC20(token)], "Invalid token");
        require(_projects[id].claimed == 0, "Project has started claimed");
        address projectOwner = msg.sender;
        require(msg.sender == _projects[id].projectOwner, "Caller is not project owner!");

        uint64 oldAllocated = _projects[id].allocated;
        address oldTokenAddress = _projects[id].token;

        _projects[id] = Project(token, projectOwner, root, allocated, 0, projectName);

        IERC20(oldTokenAddress).safeTransfer(projectOwner, oldAllocated);
        IERC20(token).safeTransferFrom(projectOwner, address(this), allocated);
    }

    /// @notice User increase reward token for a existing project
    /// @param id The project id.
    /// @param amount The total deposit tokens for the project.
    function deposit(string calldata id, uint64 amount) public {
        require(msg.sender == _projects[id].projectOwner, "Caller is not project owner!");

        _projects[id].allocated += amount;
        IERC20(_projects[id].token).safeTransferFrom(msg.sender, address(this), amount);
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
    function getLeaf(uint256 index, address receiver, address token, uint64 amount) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, receiver, token, amount));
    }

    /**
     * @notice Verifies a given leaf is in the merkle-tree with the given root.
     * @dev About MerkleProof, Refer below documents or code
     * https://ethereum.org/en/developers/tutorials/merkle-proofs-for-offline-data-integrity/
     * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/MerkleProof.sol#L32
     * https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributor.sol
     */
    function verify(string calldata id, bytes32 leaf, bytes32[] calldata proof) public view returns (bool) {
        return MerkleProof.verify(proof, _projects[id].root, leaf);
    }
}
