// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MultiSigAccount is IAccount {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error MultiSigAccount__NotFromEntryPoint();
    error MultiSigAccount__NotFromEntryPointOrSelf();
    error MultiSigAccount__CallFailed(bytes);
    error MultiSigAccount__PayPreFundFailed();
    error MultiSigAccount__InvalidSignatureCount();
    error MultiSigAccount__NotASigner(address);
    error MultiSigAccount__DuplicateSigner(address);
    error MultiSigAccount__InvalidRequired();
    error MultiSigAccount__SignersNotSorted();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint private immutable i_entryPoint;
    address[] private s_signers;
    uint256 private s_required;
    mapping(address => bool) private s_isSigner;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MultiSigAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrSelf() {
        if (msg.sender != address(i_entryPoint) && msg.sender != address(this)) {
            revert MultiSigAccount__NotFromEntryPointOrSelf();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address entryPoint, address[] memory signers, uint256 required) {
        if (required == 0 || required > signers.length) {
            revert MultiSigAccount__InvalidRequired();
        }
        i_entryPoint = IEntryPoint(entryPoint);
        for (uint256 i = 0; i < signers.length; i++) {
            if (s_isSigner[signers[i]]) {
                revert MultiSigAccount__DuplicateSigner(signers[i]);
            }
            s_isSigner[signers[i]] = true;
            s_signers.push(signers[i]);
        }
        s_required = required;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrSelf {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            revert MultiSigAccount__CallFailed(result);
        }
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignatures(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    function addSigner(address signer) external requireFromEntryPointOrSelf {
        if (s_isSigner[signer]) {
            revert MultiSigAccount__DuplicateSigner(signer);
        }
        s_isSigner[signer] = true;
        s_signers.push(signer);
    }

    function removeSigner(address signer) external requireFromEntryPointOrSelf {
        if (!s_isSigner[signer]) {
            revert MultiSigAccount__NotASigner(signer);
        }
        s_isSigner[signer] = false;
        for (uint256 i = 0; i < s_signers.length; i++) {
            if (s_signers[i] == signer) {
                s_signers[i] = s_signers[s_signers.length - 1];
                s_signers.pop();
                break;
            }
        }
    }

    function setRequired(uint256 required) external requireFromEntryPointOrSelf {
        if (required == 0 || required > s_signers.length) {
            revert MultiSigAccount__InvalidRequired();
        }
        s_required = required;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _validateSignatures(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        bytes[] memory signatures = abi.decode(userOp.signature, (bytes[]));

        if (signatures.length < s_required) {
            return SIG_VALIDATION_FAILED;
        }

        address lastSigner = address(0);
        for (uint256 i = 0; i < s_required; i++) {
            address signer = ECDSA.recover(ethSignedMessageHash, signatures[i]);
            if (!s_isSigner[signer]) {
                return SIG_VALIDATION_FAILED;
            }
            // Signers must be in ascending order to prevent duplicates
            if (signer <= lastSigner) {
                return SIG_VALIDATION_FAILED;
            }
            lastSigner = signer;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            if (!success) {
                revert MultiSigAccount__PayPreFundFailed();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }

    function getSigners() external view returns (address[] memory) {
        return s_signers;
    }

    function getRequired() external view returns (uint256) {
        return s_required;
    }

    function isSigner(address account) external view returns (bool) {
        return s_isSigner[account];
    }
}
