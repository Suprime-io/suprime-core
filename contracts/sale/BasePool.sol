// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "solady/src/utils/SafeTransferLib.sol";
import "solady/src/utils/FixedPointMathLib.sol";
import "solady/src/utils/ReentrancyGuard.sol";
import "solady/src/utils/Clone.sol";
import "solady/src/utils/MerkleProofLib.sol";
import "solady/src/utils/EIP712.sol";
import "solady/src/utils/ECDSA.sol";
import { ud60x18 } from "@prb/math/src/UD60x18.sol";
import "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import "@sablier/v2-core/src/types/DataTypes.sol";

import { FjordMath } from "../utils/FjordMath.sol";
import { FjordConstants } from "../utils/FjordConstants.sol";

    enum PoolStatus {
        Active,
        Paused,
        Closed,
        Canceled
    }

    enum PoolType {
        Fixed,
        Overflow
    }

/// @notice A struct representing a tiered sale within a FixedPricePool.
/// @param amountForSale The total number of shares available for purchase in this tier.
/// @param pricePerShare The price per share in this tier.
/// @param maximumPerUser The maximum number of shares a user can purchase in this tier.
/// @param minimumPerUser The minimum number of shares a user must purchase in this tier.
    struct Tier {
        uint256 amountForSale;
        uint256 pricePerShare;
        uint256 maximumPerUser;
        uint256 minimumPerUser;
    }

    struct TiersModified {
        uint8 tierIndex;
        uint256 assetsIn;
        uint256 sharesOutInTier;
    }

abstract contract BasePool is Clone, ReentrancyGuard, EIP712, FjordConstants {
    /// -----------------------------------------------------------------------
    /// Dependencies
    /// -----------------------------------------------------------------------
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;
    using FjordMath for *;
    using MerkleProofLib for *;
    using ECDSA for bytes32;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Error when the whitelist proof provided is invalid or does not exist.
    error InvalidProof();

    /// @notice Error when the recovered signer of the signature is not the delegate signer.
    error InvalidSignature();

    /// @notice Error when the user attempts to purchase/supply more than the maximum allowed.
    error MaxPurchaseExeeded();

    /// @notice Error when the user attempts to purchase/supply less than the minimum allowed.
    error MinPurchaseNotMet();

    /// @notice Error when the user attempts to redeem shares that they do not have.
    error NoSharesRedeemable();

    /// @notice Error when the caller is not the pool owner.
    error NotOwner();

    /// @notice Error when the redemption timestamp has not been reached.
    error RedeemedTooEarly();

    /// @notice Error when the sale is still active.
    error SaleActive();

    /// @notice Error when a redeem is called on a canceled pool.
    error SaleCancelled();

    /// @notice Error when the sale is paused/canceled/closed.
    error SaleInactive();

    /// @notice Error when the sale is not cancelable due to the sale being active.
    error SaleNotCancelable();

    /// @notice Error when the sale is not pausable due to the sale being closed or cancelled.
    error SaleNotPausable();

    /// @notice Error when the user attempts to purchase/supply an amount that would leave less than the minimum swap threshold available in the pool.
    error MandatoryMinimumSwapThreshold();

    /// @notice Error when the signature deadline has passed.
    error StaleSignature();

    /// @notice Error emitted when a user tries to redeem a token that is not redeemable, generally due to the token being airdropped on a different chain post sale.
    error TokenNotRedeemable();

    /// @notice Error when a user tries to swap an amount of tokens that is 0.
    error TransferZero();

    /// @notice Error when a user tries to purchase more than the maximum purchase amount.
    error UserMaxPurchaseExceeded();

    /// @notice Error when the user tries to purchase less than the minimum purchase amount.
    error UserMinPurchaseNotMet();

    /// @notice Error when the recipient address is the zero address.
    error ZeroAddress();

    /// @notice Invalid close operations.
    error CloseConditionNotMet();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    /// @notice Emitted when the pool is closed and the funds are distributed.
    event Closed(
        uint256 totalFundsRaised, uint256 totalSharesSold, uint256 platformFee, uint256 swapFee
    );

    /// @notice Emitted when the pool is paused or unpaused.
    event PauseToggled(bool paused);

    /// @notice Emitted when the pool is canceled before it begins.
    event PoolCanceled();

    /// @notice Emitted when the pool is able to close early due to reaching its raise cap.
    event PoolCompleted();

    /// @notice Emitted when a user is refunded due to the raise goal not being met.
    event Refunded(address indexed recipient, uint256 amount);

    /// @notice Emitted when a user redeems their shares post sale if the raise goal was met.
    event Redeemed(address indexed recipient, uint256 shares, uint256 streamID);

    /// @notice Emitted when the raise goal is not met and the pool is closed.
    event RaiseGoalNotMet(uint256 sharesNotSold, uint256 fundsRaised, uint256 feesGenerated);

    /// -----------------------------------------------------------------------
    /// Immutable Arguments -- Public
    /// -----------------------------------------------------------------------

    ISablierV2LockupLinear public immutable SABLIER;

    /// -----------------------------------------------------------------------
    /// Immutable Arguments -- Public
    /// -----------------------------------------------------------------------

    /// @notice The owner of the pool.
    /// @dev The owner can cancel the sale before it starts, pause/unpause the sale, and will receive the funds raised post sale.
    function owner() public pure returns (address) {
        return _getArgAddress(OWNER_OFFSET);
    }

    /// @notice The address of the share token that is being sold off by the creator.
    function shareToken() public pure returns (address) {
        return _getArgAddress(SHARE_TOKEN_OFFSET);
    }

    /// @notice Returns the address of the asset token used for purchasing shares.
    function assetToken() public pure returns (address) {
        return _getArgAddress(ASSET_TOKEN_OFFSET);
    }

    /// @notice Returns the address of the recipient of platform and swap fees generated by the pool.
    function feeRecipient() public pure returns (address) {
        return _getArgAddress(FEE_RECIPIENT_OFFSET);
    }

    /// @notice Returns the address of the delegate signer used for anti-snipe protection.
    /// @dev This address is provided by the factory contract and is protocol-owned.
    function delegateSigner() public pure returns (address) {
        return _getArgAddress(DELEGATE_SIGNER_OFFSET);
    }

    /// @notice The total number of shares that are being sold during the sale.
    /// @dev This value is normalized to 18 decimals.
    function sharesForSale() public pure virtual returns (uint256) {
        return _getArgUint256(SHARES_FOR_SALE_OFFSET);
    }

    /// @notice Returns the minimum raise goal defined by the creator.
    /// @dev For FixedPricePools, this is the number of shares that must be sold.
    /// @dev For OverflowPools, this is the number of assets that must be raised.
    /// @dev If the minimum raise goal is not met, users and creator are refunded.
    /// @dev This value is normalized to 18 decimals.
    function minimumTokensForSale() public pure returns (uint256) {
        return _getArgUint256(MINIMUM_TOKENS_FOR_SALE_OFFSET);
    }

    /// @notice Returns the maximum number of tokens that can be purchased within a sale.
    /// @dev For FixedPricePools, this is the number of shares a user can purchase.
    /// @dev For OverflowPools, this is the number of assets a user can used to purchase.
    /// @dev This value is normalized to 18 decimals.
    function maximumTokensPerUser() public pure returns (uint256) {
        return _getArgUint256(MAXIMUM_TOKENS_PER_USER_OFFSET);
    }

    /// @notice Returns the minimum number of tokens that must be purchased within a sale.
    /// @dev For FixedPricePools, this is the minimum number of shares a user must purchase.
    /// @dev For OverflowPools, this is the minimum number of assets a user must use to purchase.
    /// @dev This value is normalized to 18 decimals.
    function minimumTokensPerUser() public pure returns (uint256) {
        return _getArgUint256(MINIMUM_TOKENS_PER_USER_OFFSET);
    }

    /// @notice The swap fee charged on each purchase.
    /// @dev This value is scaled to WAD such that 1e18 is equivalent to a 100% swap fee.
    function swapFeeWAD() public pure returns (uint64) {
        return _getArgUint64(SWAP_FEE_WAD_OFFSET);
    }

    /// @notice The platform fee charged on post-sale funds raised.
    function platformFeeWAD() public pure returns (uint64) {
        return _getArgUint64(PLATFORM_FEE_WAD_OFFSET);
    }

    /// @notice The timestamp at which the sale will start.
    function saleStart() public pure returns (uint40) {
        return _getArgUint40(SALE_START_OFFSET);
    }

    /// @notice The timestamp at which the sale will end.
    /// @dev This value is bypassed if a raise goal is defined and met or exceeded.
    function saleEnd() public pure returns (uint40) {
        return _getArgUint40(SALE_END_OFFSET);
    }

    /// @notice The timestamp at which users will be able to redeem their shares.
    /// @dev This value is bypassed in favor of a 24H max should a sale end early due to meeting its raise cap.
    function redemptionDelay() public pure returns (uint40) {
        return _getArgUint40(REDEMPTION_DELAY_OFFSET);
    }

    /// @notice The timestamp at which the vesting period will end.
    function vestEnd() public pure returns (uint40) {
        return _getArgUint40(VEST_END_OFFSET);
    }

    /// @notice The timestamp at which the vesting cliff period will end.
    function vestCliff() public pure returns (uint40) {
        return _getArgUint40(VEST_CLIFF_OFFSET);
    }

    /// @notice The number of decimals for the share token.
    function shareDecimals() public pure returns (uint8) {
        return _getArgUint8(SHARE_TOKEN_DECIMALS_OFFSET);
    }

    /// @notice Returns the number of decimals for the asset token.
    function assetDecimals() public pure returns (uint8) {
        return _getArgUint8(ASSET_TOKEN_DECIMALS_OFFSET);
    }

    /// @notice Returns true if the anti-snipe feature is enabled, false otherwise.
    /// @dev If anti-snipe is enabled, a valid signature from a delegate signer is required to make a purchase.
    function antiSnipeEnabled() public pure returns (bool) {
        return _getArgUint8(ANTISNIPE_ENABLED_OFFSET) != 0;
    }

    /// @notice A merkle root representing a whitelist of addresses allowed to participate in the sale.
    /// @dev If the whitelist is empty, the sale is open to all addresses.
    function whitelistMerkleRoot() public pure returns (bytes32) {
        return _getArgBytes32(WHITELIST_MERKLE_ROOT_OFFSET);
    }

    function vestingEnabled() public pure returns (bool) {
        return vestEnd() > saleEnd();
    }

    /// -----------------------------------------------------------------------
    /// Mutable State -- Public
    /// -----------------------------------------------------------------------

    /// @notice The current transaction nonce of the recipient, used for anti-snipe replay protection.
    mapping(address user => uint32 nonce) public nonces;

    /// @notice The current status of the pool (Paused, Active, Canceled, Closed).
    PoolStatus public status;

    /// @notice The total number of assets received during the sale, sans swap fees.
    /// @dev Must be denormalized before use.
    uint256 public totalNormalizedAssetsIn;

    /// @notice The total amount of swap fees generated during the sale.
    /// @dev Must be denormalized before use.
    uint256 public totalNormalizedAssetFeesIn;

    /// @notice The total normalized number of assets received per user, without accounting for swap fees.
    /// @dev Must be denormalized before use.
    mapping(address user => uint256 assetsIn) public userNormalizedAssetsIn;

    /// @dev actual sale end timestamp
    uint256 public saleEndTimestamp;

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    constructor(address sablier) {
        SABLIER = ISablierV2LockupLinear(sablier);
    }

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    /// @notice Checks if the caller is the owner of the pool.
    modifier onlyOwner() {
        if (msg.sender != owner()) {
            revert NotOwner();
        }
        _;
    }

    /// @notice Checks if the current timestamp is lessthan the sale start, greater than the sale end, or canceled/closed/paused.
    /// @dev If the sale is not active, the pool bought into.
    modifier whenSaleActive() {
        if (
            uint40(block.timestamp) < saleStart() || uint40(block.timestamp) >= saleEnd()
            || PoolStatus.Active != status
        ) {
            revert SaleInactive();
        }
        _;
    }

    /// -----------------------------------------------------------------------
    /// GLOBAL LOGIC -- OVERRIDE REQUIRED -- Public -- Read Functions
    /// -----------------------------------------------------------------------

    /// @notice Checks if the pool can be closed.
    /// @return True if the pool can be closed, false otherwise.
    /// @dev The pool can be closed if all shares have been sold, or the sale end date has passed.
    function canClose() public view virtual returns (bool);

    /// @notice Returns the pool's pricing model (Fixed or Overflow).
    function poolType() public pure virtual returns (PoolType);

    /// @notice Returns the hash of the EIP712 typehash for the pool's buy function.
    function typeHash() public pure virtual returns (bytes32);

    /// @notice Returns the number of tokens remaining for purchase.
    /// @dev For FixedPricePools, this is the Math.min(sharesForSale - totalSharesSold, maximumTokensPerUser - purchasedShares[user]).
    /// @dev For OverflowPools, this is maximumTokensPerUser - rawAssetsIn[user] when mTPU > 0.
    function userTokensRemaining(address user) public view virtual returns (uint256);

    /// -----------------------------------------------------------------------
    /// GLOBAL LOGIC -- OVERRIDE REQUIRED -- Internal -- Read Functions
    /// -----------------------------------------------------------------------

    ///@dev Checks if the minimum reserve is set and whether or not the shares/assets in sold surpasses this value.
    function _minReserveMet() internal view virtual returns (bool);

    /// -----------------------------------------------------------------------
    /// GLOBAL LOGIC -- Public -- Read Functions
    /// -----------------------------------------------------------------------

    /// @notice Whether or not a non-empty whitelist is present.
    function hasWhitelist() public pure returns (bool) {
        return whitelistMerkleRoot() != 0;
    }

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- OVERRIDE REQUIRED -- Internal -- Read Functions
    /// -----------------------------------------------------------------------

    ///@notice Calculates the base assets in based on the pool type.
    ///@dev For FixedPricePools, this will additionally handle tier logic.
    function _calculateBaseAssetsIn(
        address recipient,
        uint256 tokenAmount,
        uint256 maxPricePerShare
    )
    internal
    view
    virtual
    returns (uint256, TiersModified[] memory);

    ///@dev Normalizes the amount based on the pool type.
    ///@dev For FixedPricePools, this is the number of shares being purchased.
    ///@dev For OverflowPools, this is the number of assets being used to purchase.
    function _normalizeAmount(uint256 amount) internal pure virtual returns (uint256);

    ///@dev Checks if the raise cap has been met and if the pool can be closed early.
    function _raiseCapMet() internal view virtual returns (bool);

    ///@notice Validates the pool limits based on the pool type.
    ///@param amount The number of tokens being purchased/used to purchase based on the pool type.
    ///@dev For fixed price pools this checks total shares sold, for overflow pools this checks total assets in.
    function _validatePoolLimits(uint256 amount) internal view virtual;

    ///@notice Updates the user's normalized assets in the pool.
    ///@param recipient The address of the recipient of the purchase.
    ///@param tokenAmount The number of tokens being purchased/used to purchase based on the pool type.
    ///@dev Checks if the updated user amount exceeds the maximumTokensPerUser and reverts if so.
    function _validateUserLimits(address recipient, uint256 tokenAmount) internal view virtual;

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- OVERRIDE REQUIRED -- Internal -- Write Functions
    /// -----------------------------------------------------------------------

    ///@dev Emits the buy event for the pool based on the pool type's implementation.
    function _emitBuyEvent(
        address recipient,
        uint256 assetsIn,
        uint256 feesPaid,
        uint256 sharesOut
    )
    internal
    virtual;

    ///@dev Handles updating pool state and user state post-purchase.
    ///@dev Additionally handles the transfer of assets to the pool.
    ///@param recipient The address of the recipient of the purchase.
    ///@param assetsIn The number of assets being used to purchase based on the pool type.
    ///@param sharesOut The number of shares being purchased based on the pool type.
    ///@param fees The swap fees generated from the purchase.
    function _updatePoolState(
        address recipient,
        uint256 assetsIn,
        uint256 sharesOut,
        uint256 fees,
        TiersModified[] memory updatedTiers
    )
    internal
    virtual
    returns (uint256);

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- Public -- Read Functions
    /// -----------------------------------------------------------------------

    ///@notice Returns the minimum swap threshold required for a purchase to be valid.
    ///@dev This is used to prevent rounding errors when making swaps between tokens of varying decimals.
    function mandatoryMinimumSwapIn() public pure virtual returns (uint256) {
        return shareDecimals().mandatoryMinimumSwapIn(assetDecimals());
    }

    ///@notice Calculates the swap fees and assets in based on the pool type and token amount being purchased/used to purchase.
    ///@param recipient The address of the recipient of the purchase.
    ///@param tokenAmount The number of tokens being purchased/used to purchase based on the pool type.
    ///@dev This function will account for tiers and all user-defined purchase limits, if applicable.
    function previewBuy(
        uint256 tokenAmount,
        address recipient
    )
    public
    view
    returns (uint256 assetsIn, uint256 feesPaid, TiersModified[] memory updatedTiers)
    {
        return previewBuy(tokenAmount, recipient, 0);
    }

    ///@notice Calculates the swap fees and assets in based on the pool type and token amount being purchased/used to purchase.
    ///@param recipient The address of the recipient of the purchase.
    ///@param tokenAmount The number of tokens being purchased/used to purchase based on the pool type.
    ///@dev This function will account for tiers and all user-defined purchase limits, if applicable.
    function previewBuy(
        uint256 tokenAmount,
        address recipient,
        uint256 maxPricePerShare
    )
    public
    view
    returns (uint256 assetsIn, uint256 feesPaid, TiersModified[] memory updatedTiers)
    {
        //Normalize the token amount based on the pool type
        tokenAmount = _normalizeAmount(tokenAmount);

        //Zero-checks and min/max purchase amount checks
        _validateBaseConditions(tokenAmount, recipient);

        //Pool-type specific conditional checks
        _validatePoolLimits(tokenAmount);

        //Pool-type specific User-specific conditional checks
        _validateUserLimits(recipient, tokenAmount);

        (assetsIn, updatedTiers) = _calculateBaseAssetsIn(recipient, tokenAmount, maxPricePerShare);
        feesPaid = _calculateFees(assetsIn);
    }

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- Internal -- Read Functions
    /// -----------------------------------------------------------------------

    /// @notice restrict access to whitelisted addresses.
    /// @dev  checks if the recipient address is whitelisted using a Merkle proof.
    function _validateWhitelist(address recipient, bytes32[] memory proof) internal pure {
        if (!proof.verify(whitelistMerkleRoot(), keccak256(abi.encodePacked(recipient)))) {
            revert InvalidProof();
        }
    }

    ///@notice Verifies the signature of buy payload for anti-snipe protection.
    ///@param recipient The address of the recipient of the purchase.
    ///@param tokenAmount The number of tokens being purchased/used to purchase based on the pool type.
    ///@param deadline The deadline for the signature to be valid.
    ///@param signature The signature to be verified.
    ///@dev Recovers the signer of the payload and compares it to the delegate signer.
    function _validateAntisnipe(
        address recipient,
        uint256 tokenAmount,
        uint64 deadline,
        bytes memory signature
    )
    internal
    view
    {
        if (uint64(block.timestamp) > deadline) {
            revert StaleSignature();
        }

        bytes32 expectedDigest = getDigest(tokenAmount, recipient, deadline);

        address signer = expectedDigest.recover(signature);

        if (signer != delegateSigner()) {
            revert InvalidSignature();
        }
    }

    ///@notice Helper function to validate non-zero token amounts and recipient addresses and
    ///ensures minimum purchase amounts are upheld. Passes the signature and proof to the
    ///_checkWhitelistAndAntisnipe function.
    function _validateBaseConditions(uint256 tokenAmount, address recipient) internal pure {
        if (tokenAmount == 0) revert TransferZero();
        if (recipient == address(0)) revert ZeroAddress();
        if (tokenAmount < mandatoryMinimumSwapIn()) revert MinPurchaseNotMet();
    }

    ///@notice Calculates the swap fees based on the swapFeeWAD and the token amount.
    function _calculateFees(uint256 assetsIn) internal pure returns (uint256) {
        return assetsIn.mulWadUp(swapFeeWAD());
    }

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- Internal --  Write Functions
    /// -----------------------------------------------------------------------

    /// @notice Allows any user to purchase shares in the pool.
    /// @param amount The number of shares to purchase (Fixed) or assets in (Overflow).
    /// @param recipient The address to receive the shares.
    /// @param deadline The deadline for the signature to be valid if anti-snipe is enabled.
    /// @param signature The signature to be verified if anti-snipe is enabled.
    /// @param proof The Merkle proof to be verified if a whitelist is present.
    function buy(
        uint256 amount,
        address recipient,
        uint64 deadline,
        bytes memory signature,
        bytes32[] memory proof,
        uint256 maxPricePerShare
    )
    internal
    nonReentrant
    whenSaleActive
    {
        if (hasWhitelist()) {
            _validateWhitelist(recipient, proof);
        }

        if (antiSnipeEnabled()) {
            _validateAntisnipe(recipient, amount, deadline, signature);
        }

        (uint256 normalizedAssetsIn, uint256 normalizedFees, TiersModified[] memory updatedTiers) =
                        previewBuy(amount, recipient, maxPricePerShare);

        uint256 sharesOut = poolType() == PoolType.Fixed ? amount.normalize(shareDecimals()) : 0;

        uint256 normalizedAssetsOwed =
                        _updatePoolState(recipient, normalizedAssetsIn, sharesOut, normalizedFees, updatedTiers);

        if (normalizedAssetsOwed > 0) {
            assetToken().safeTransferFrom(
                msg.sender, address(this), normalizedAssetsOwed.denormalizeUp(assetDecimals())
            );
        }

        if (antiSnipeEnabled()) {
            // increase nonce
            nonces[recipient]++;
        }

        _emitBuyEvent(recipient, normalizedAssetsIn, normalizedFees, sharesOut);

        //close early if the raise cap is met

        _handleEarlyClose();
    }

    /// @notice Checks if the pool has met its raise cap
    /// and if so, emits the PoolCompleted event.
    function _handleEarlyClose() internal {
        if (_raiseCapMet()) {
            emit PoolCompleted();
            close();
        }
    }

    /// -----------------------------------------------------------------------
    /// CLOSE LOGIC -- OVERRIDE REQUIRED -- Internal -- Read Functions
    /// -----------------------------------------------------------------------

    ///@notice Calculates the leftover shares that were not sold during the sale.
    ///@dev If overflow, this is sharesForSale(), otherwise it's sharesForSale() - totalSharesSold.
    function _calculateLeftoverShares() internal view virtual returns (uint256);

    /// -----------------------------------------------------------------------
    /// CLOSE LOGIC -- OVERRIDE REQUIRED -- Internal -- Write Functions
    /// -----------------------------------------------------------------------

    /// @notice Handles the refund of the owner's shares in the pool and the transfer of swap fees to the fee recipient.
    /// @dev Only called if the raise goal was not met. The overriding function should handle the transfer of funds to the owner
    /// according to the pool type.
    function _handleManagerRefund()
    internal
    virtual
    returns (uint256 sharesNotSold, uint256 fundsRaised, uint256 swapFees)
    {
        sharesNotSold = sharesForSale().denormalizeDown(shareDecimals());

        swapFees = totalNormalizedAssetFeesIn.denormalizeDown(assetDecimals());
        if (swapFees > 0) {
            assetToken().safeTransfer(feeRecipient(), swapFees);
        }
        fundsRaised = totalNormalizedAssetsIn.denormalizeUp(assetDecimals());
        uint256 currentBalance = assetToken().balanceOf(address(this));
        if (fundsRaised > currentBalance) {
            // possible precision loss after denormalize
            fundsRaised = currentBalance;
        } else if (fundsRaised < currentBalance) {
            // if someone donates assets to the pool, then take all back to owner
            assetToken().safeTransfer(owner(), currentBalance - fundsRaised);
        }
    }

    /// -----------------------------------------------------------------------
    /// CLOSE LOGIC -- Public -- Write Functions
    /// -----------------------------------------------------------------------

    // @notice Allows any user to close the pool and distribute the fees.
    // @dev The pool can only be closed after the sale end date has passed, OR the max shares sold have been reached.
    function close() public {
        if (!canClose()) {
            revert CloseConditionNotMet();
        }

        status = PoolStatus.Closed;
        saleEndTimestamp =
            uint256(saleEnd()) < block.timestamp ? uint256(saleEnd()) : block.timestamp;

        if (!_minReserveMet()) {
            (uint256 sharesNotSold, uint256 fundsRaised, uint256 swapFee) = _handleManagerRefund();
            emit RaiseGoalNotMet(sharesNotSold, fundsRaised, swapFee);
            return;
        } else {
            // avoid shawdow variable
            (uint256 platformFees, uint256 swapFees, uint256 totalFees) = _calculateCloseFees();
            if (totalFees > 0) {
                assetToken().safeTransfer(feeRecipient(), totalFees);
            }

            uint256 fundsRaised = IERC20(assetToken()).balanceOf(address(this));
            if (fundsRaised > 0) {
                assetToken().safeTransfer(owner(), fundsRaised);
            }

            uint256 sharesNotSold = _calculateLeftoverShares();
            // return the unsold shares to the owner
            if (sharesNotSold > 0 && shareToken() != address(0)) {
                shareToken().safeTransfer(owner(), sharesNotSold);
            }

            //totalsharessold, fundsraised
            emit Closed(
                fundsRaised,
                sharesForSale().denormalizeDown(shareDecimals()).rawSub(sharesNotSold),
                platformFees,
                swapFees
            );

            if (vestingEnabled()) {
                shareToken().safeApprove(address(SABLIER), type(uint256).max);
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// CLOSE LOGIC -- Internal -- Read Functions
    /// -----------------------------------------------------------------------

    ///@dev Calculates the fees generated during the sale and denormalizes them for event emission and transfer.
    function _calculateCloseFees()
    internal
    view
    returns (uint256 platformFees, uint256 swapFees, uint256 totalFees)
    {
        platformFees = totalNormalizedAssetsIn.mulWad(platformFeeWAD());
        // denormalize the fees for event emission.
        swapFees = totalNormalizedAssetFeesIn.denormalizeDown(assetDecimals());
        platformFees = platformFees.denormalizeDown(assetDecimals());
        // totalFees sum of platformFees and swapFees
        totalFees = platformFees + swapFees;
    }
    /// -----------------------------------------------------------------------
    /// REDEEM LOGIC -- OVERRIDE REQUIRED - Internal -- Read Functions
    /// -----------------------------------------------------------------------

    /// @notice Calculates the amount of shares owed to the user based on the pool type.
    /// @dev For FixedPricePools, this is the number of shares the user has purchased directly.
    /// @dev For OverflowPools, this is calculate as the ratio of the users assets to the total assets in the pool
    /// multiplied by the total shares for sale.
    function _calculateSharesOwed(address user) internal view virtual returns (uint256);

    /// -----------------------------------------------------------------------
    /// REDEEM LOGIC -- OVERRIDE REQUIRED - Internal -- Write Functions
    /// -----------------------------------------------------------------------

    /// @notice Handles the refund/transfer of the user's assets in the pool if the raise goal was not met
    /// and updates user-specific state variables.
    /// @dev For FixedPricePools, this sets the user's sharesPurchased and assetsIn to 0.
    /// @dev For OverflowPools, this sets the user's assetsIn to 0.
    function _handleUserRefund(address user) internal virtual returns (uint256 assetsOwed);

    /// @notice Handles the state updates triggered on user-specific variables of pool state post-redemption.
    /// @dev For FixedPricePools, this sets the user's sharesPurchased and assetsIn to 0.
    /// @dev For OverflowPools, this sets the user's assetsIn to 0.
    function _handleUpdateUserRedemption(address sender) internal virtual;

    /// -----------------------------------------------------------------------
    /// REDEEM LOGIC -- External -- Write Functions
    /// -----------------------------------------------------------------------

    // @notice Allows any user to redeem their shares after the redemption timestamp has passed.
    // @dev Users can only redeem their shares if the sale has closed and the redemption timestamp has passed.
    // unless the pool met a hard cap and closed early, at which point the redemption timestamp is
    function redeem() external nonReentrant returns (uint256 streamID) {
        if (status == PoolStatus.Canceled) {
            revert SaleCancelled();
        }
        if (status != PoolStatus.Closed) {
            revert SaleActive();
        }

        if (block.timestamp < saleEndTimestamp + redemptionDelay()) {
            revert RedeemedTooEarly();
        }

        uint256 sharesOut;
        address sender = msg.sender;
        if (!_minReserveMet()) {
            emit Refunded(sender, _handleUserRefund(sender));
        } else {
            if (shareToken() != address(0)) {
                sharesOut = _calculateSharesOwed(sender);

                if (sharesOut == 0) {
                    revert NoSharesRedeemable();
                }

                _handleUpdateUserRedemption(sender);
                streamID = _handleRedemptionPayment(sender, sharesOut);
                emit Redeemed(sender, sharesOut, streamID);
            } else {
                revert TokenNotRedeemable();
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// REDEEM LOGIC -- Internal -- Write Functions
    /// -----------------------------------------------------------------------

    ///@notice Handles the transfer of shares to the user post-redemption.
    ///@param recipient The address of the recipient of the shares.
    ///@param sharesOwed The number of shares owed to the user.
    ///@dev Only utilized if the raise goal was met.
    ///@dev If vesting is enabled and not expired, the shares are streamed to the user via sablier.
    function _handleRedemptionPayment(
        address recipient,
        uint256 sharesOwed
    )
    internal
    returns (uint256 streamID)
    {
        if (vestingEnabled() && vestEnd() > uint40(block.timestamp)) {
            LockupLinear.CreateWithRange memory params;

            params.sender = owner();
            params.recipient = recipient;
            params.totalAmount = uint128(sharesOwed);
            params.asset = IERC20(shareToken());
            params.cancelable = false;
            params.range =
                                LockupLinear.Range({ start: saleEnd(), end: vestEnd(), cliff: vestCliff() });
            params.broker = Broker(address(0), ud60x18(0));

            streamID = SABLIER.createWithRange(params);
        } else {
            shareToken().safeTransfer(recipient, sharesOwed);
        }
    }

    /// -----------------------------------------------------------------------
    /// POOL ADMIN LOGIC -- External -- Owner-Only -- Write Functions
    /// -----------------------------------------------------------------------

    /// @notice Allows the pool creator to cancel the sale and withdraw all funds and shares before a sale begins.
    /// @dev The pool can only be canceled if the sale has not started.
    function cancelSale() external nonReentrant onlyOwner {
        if (status != PoolStatus.Active && status != PoolStatus.Paused) {
            revert SaleNotCancelable();
        }
        if (uint40(block.timestamp) >= saleStart()) {
            revert SaleActive();
        }

        status = PoolStatus.Canceled;

        if (shareToken() != address(0)) {
            shareToken().safeTransfer(owner(), sharesForSale().denormalizeDown(shareDecimals()));
        }
        emit PoolCanceled();
    }

    /// @notice Allows the pool creator to pause/unpause the sale, halting/enabling any trading activity.
    function togglePause() external nonReentrant onlyOwner {
        if (status == PoolStatus.Canceled || status == PoolStatus.Closed) {
            revert SaleNotPausable();
        }

        bool paused = status == PoolStatus.Paused;
        status = paused ? PoolStatus.Active : PoolStatus.Paused;

        emit PauseToggled(!paused);
    }

    /// -----------------------------------------------------------------------
    /// EIP712 Logic  -- External -- Read Functions
    /// -----------------------------------------------------------------------

    /// @notice Returns the expected digest for the EIP712 signature.
    /// @param tokenAmount The number of tokens being purchased/used to purchase based on the pool type.
    /// @param recipient The address of the recipient of the purchase.
    /// @param deadline The deadline for the signature to be valid.
    function getDigest(
        uint256 tokenAmount,
        address recipient,
        uint64 deadline
    )
    public
    view
    returns (bytes32)
    {
        return _hashTypedData(
            keccak256(
                abi.encode(typeHash(), tokenAmount, recipient, nonces[recipient] + 1, deadline)
            )
        );
    }
}
