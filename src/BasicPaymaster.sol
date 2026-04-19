// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IPaymaster} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BasicPaymaster is IPaymaster, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BasicPaymaster__NotFromEntryPoint();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint private immutable i_entryPoint;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert BasicPaymaster__NotFromEntryPoint();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Accepts all UserOps unconditionally — demo only, not for production.
    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        requireFromEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        // Accept all requests, return empty context (no postOp needed)
        context = "";
        validationData = 0; // SIG_VALIDATION_SUCCESS
    }

    function postOp(IPaymaster.PostOpMode, bytes calldata, uint256, uint256) external requireFromEntryPoint {
        // No-op for this basic implementation
    }

    /// @notice Owner deposits ETH into the EntryPoint to fund gas for users
    function deposit() external payable onlyOwner {
        i_entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Owner withdraws ETH from the EntryPoint deposit
    function withdrawTo(address payable withdrawAddress, uint256 amount) external onlyOwner {
        i_entryPoint.withdrawTo(withdrawAddress, amount);
    }

    /// @notice Returns the Paymaster's deposit balance in the EntryPoint
    function getDeposit() external view returns (uint256) {
        return i_entryPoint.balanceOf(address(this));
    }

    /// @notice Owner adds stake to the EntryPoint (required by some bundlers)
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        i_entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }
}
