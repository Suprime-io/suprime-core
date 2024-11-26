// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "./BasePool.sol";

import "solady/src/utils/SafeCastLib.sol";

/// @title FixedERC2Pool
/// @notice A fixed price pool that allows users to purchase shares with a predefined standard ERC20 token.
/// @notice The pool creator can set the number of shares available for purchase, the price of each share,
/// @notice the sale start and end dates, the redemption date, and the maximum number of shares a user can purchase.
/// @notice The pool creator can also set a minimum number of shares that must be sold for the sale to be considered successful.
/// @notice The pool creator can also set a platform fee and a swap fee that will be taken from the raised funds.
/// @dev Creation will fail if the asset token has less than 2 or more than 18 decimals, or if the share token has more than 18 decimals.
/// @dev The pool will fail if the sale start date is after the sale end date, or if the redemption date is before the sale end date.
/// @dev The pool will fail if the platform fee or swap fee is greater than or equal to 1e18.
/// @dev The pool will fail if the price of each share is 0, or if the minimum number of shares that must be sold is greater than the number of shares available for purchase.
contract FixedPricePool is BasePool {
    /// -----------------------------------------------------------------------
    /// Dependencies
    /// -----------------------------------------------------------------------

    using MerkleProofLib for bytes32;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using FjordMath for uint256;
    using SafeCastLib for uint256;

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    error TierMaxPurchaseExceeded();
    error TierPurchaseTooLow(uint256 tierIndex);
    error InvalidTierPurchaseAmount();
    error SlippageExceeded();

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Emitted when a user purchases shares in the pool.
    event BuyFixedShares(
        address indexed recipient, uint256 sharesOut, uint256 baseAssetsIn, uint256 feesPaid
    );

    /// @notice Emitted when a tiered sale rolls over to the next tier.
    event TierRollover(uint256 newTier);

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    constructor(address _sablier) BasePool(_sablier) { }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// FIXED PRICE LOGIC -- Immutable Arguments -- Public -- Read Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice The number of assets (with decimals) required to purchase 1 share.
    /// @dev This value is normalized to 18 decimals.
    function assetsPerToken() public pure returns (uint256) {
        return _getArgUint256(ASSETS_PER_TOKEN_OFFSET);
    }

    /// @notice All the tiers available for this sale.
    function tiers() public pure returns (Tier[] memory) {
        return abi.decode(_getArgBytes(TIERS_OFFSET, _tierDataLength()), (Tier[]));
    }

    /// @notice Whether the sale has multiple Tiers enabled, modifying the sale price and user-specific limits per tier.
    function isTiered() public pure returns (bool) {
        return _tierDataLength() > EMPTY_TIER_ARRAY_OFFSET;
    }

    /// @notice The current tier of the sale.
    function getCurrentTierData() public view returns (Tier memory) {
        return tiers()[currentTier];
    }

    /// @notice The tier data for a specific index.
    function getTierData(uint256 index) public pure returns (Tier memory) {
        return tiers()[index];
    }

    /// @notice The number of tiers slots allocated to the tiers array.
    /// @dev This is used to instantiate
    function getTierLength() public pure returns (uint8) {
        uint256 offDiff = _tierDataLength().rawSub(EMPTY_TIER_ARRAY_OFFSET);

        if (offDiff == 0) {
            return SafeCastLib.toUint8(0);
        } else {
            return (offDiff.rawDiv(TIER_BASE_OFFSET)).toUint8();
        }
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// FIXED PRICE LOGIC -- Immutable Arguments -- Internal -- Read Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice The byte length of the `Tiers` arg, used to decode the tiers array into the proper number of elements.
    function _tierDataLength() internal pure returns (uint256) {
        return _getArgUint256(TIER_DATA_LENGTH_OFFSET);
    }

    /// -----------------------------------------------------------------------
    /// FIXED PRICE LOGIC -- Mutable State -- Public
    /// -----------------------------------------------------------------------

    /// @notice The active Tier of the sale, if in use.
    uint8 public currentTier;

    /// @notice The number of shares sold per tier.
    mapping(uint8 tier => uint256 totalSold) public amountSoldInTier;

    /// @notice The number of shares sold per tier per user.
    mapping(uint8 tier => mapping(address user => uint256 purchaseAmount)) public purchasedByTier;

    /// @notice The number of shares purchased by each user.
    /// @dev This value is normalized to 18 decimals.
    mapping(address user => uint256 sharesPurchased) public purchasedShares;

    /// @notice The total number of shares sold during the sale so far.
    /// @dev This value is normalized to 18 decimals.
    uint256 public totalSharesSold;

    /// @notice The total number of shares remaining for purchase.
    /// @dev This value is normalized to 18 decimals.
    function sharesRemaining() public view returns (uint256) {
        return sharesForSale().rawSub(totalSharesSold);
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// GLOBAL LOGIC -- OVERRIDE REQUIRED -- Public -- Read Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Checks if the sale period has passed or the pool has reached its shares out cap.
    function canClose() public view override returns (bool) {
        if (status == PoolStatus.Closed || status == PoolStatus.Canceled) {
            return false;
        }
        // Greater comparision for safety purpose only
        if (totalSharesSold >= sharesForSale() || uint40(block.timestamp) >= saleEnd()) {
            return true;
        }

        return false;
    }

    /// @notice The underlying pricing mechanism for the pool.
    function poolType() public pure override returns (PoolType) {
        return PoolType.Fixed;
    }

    /// @notice The keccak256 hash of the function used to buy shares in the pool.
    function typeHash() public pure override returns (bytes32) {
        return keccak256(
            "BuyExactShares(uint256 sharesOut,address recipient,uint32 nonce,uint64 deadline)"
        );
    }

    /// @notice Returns the number of shares remaining for purchase for a specific user.
    /// @param user The address of the user to check.
    /// @return The number of shares remaining for purchase.
    /// @dev This value is normalized to 18 decimals.
    function userTokensRemaining(address user) public view override returns (uint256) {
        return maximumTokensPerUser().rawSub(purchasedShares[user]).min(sharesRemaining());
    }

    struct Pool {
        address asset;
        address share;
        uint256 assets;
        uint256 shares;
        uint256 assetsPerToken;
        uint256 saleStart;
        uint256 saleEnd;
        uint256 totalPurchased;
    }

    /// @dev For offchain read
    function args() public view virtual returns (Pool memory) {
        return Pool(
            assetToken(),
            shareToken(),
            totalNormalizedAssetsIn,
            sharesForSale(),
            assetsPerToken(),
            saleStart(),
            saleEnd(),
            totalSharesSold
        );
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// GLOBAL LOGIC -- OVERRIDE REQUIRED -- Internal -- Read Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    ///@notice Checks if the minimum number of asset tokens have been swapped into the pool
    ///surpassed the creator-defined minimum.
    ///@dev Returning false will trigger refunds on `close` and user refunds on `redeem`.
    function _minReserveMet() internal view override returns (bool) {
        if (minimumTokensForSale() > 0 && totalSharesSold < minimumTokensForSale()) {
            return false;
        }
        return true;
    }

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- OVERRIDE REQUIRED -- Internal -- Read Functions
    /// -----------------------------------------------------------------------

    /// @notice Calculates the number of asset tokens that will be swapped into the pool before fees.
    /// @dev For overflow pools this is always the tokenAmount passed in, we're just conforming to the interface.
    function _calculateBaseAssetsIn(
        address recipient,
        uint256 tokenAmount,
        uint256 maxPricePerShare
    )
    internal
    view
    override
    returns (uint256, TiersModified[] memory)
    {
        if (!isTiered()) {
            return (tokenAmount.mulWadUp(assetsPerToken()), new TiersModified[](0));
        }

        return _calculateTieredPurchase(recipient, tokenAmount, maxPricePerShare);
    }

    /// @notice Normalizes the assets being swapped in to 18 decimals, if needed.
    /// @param amount The amount of assets being swapped in.
    function _normalizeAmount(uint256 amount) internal pure override returns (uint256) {
        return amount.normalize(shareDecimals());
    }

    /// @notice Checks if the pool has reached its asset token hard cap.
    /// @dev This value does not account for assets in the pool in the form of swap fees.
    function _raiseCapMet() internal view override returns (bool) {
        // Greater comparision for safety purpose only
        return totalSharesSold >= sharesForSale();
    }

    /// @notice Validates the amount of shares being swapped in do not exceed Overflow specific limits.
    /// @dev The amount of shares being swapped in must not exceed the shares for sale.
    /// @dev The amount of shares remaining for purchase before the pool cap is met after the swap must be greater than the mandatoryMinimumSwapIn to prevent the pool from being left with dust.
    /// @param amount The amount of shares being swapped in.
    function _validatePoolLimits(uint256 amount) internal view override {
        if (amount > sharesForSale()) {
            revert MaxPurchaseExeeded();
        }
        if (totalSharesSold.rawAdd(amount) > sharesForSale()) {
            revert MaxPurchaseExeeded();
        }
        if (
            mandatoryMinimumSwapIn() > 0 && sharesRemaining().rawSub(amount) > 0
            && sharesRemaining().rawSub(amount) < mandatoryMinimumSwapIn()
        ) {
            revert MandatoryMinimumSwapThreshold();
        }
    }

    /// @notice Validates the amount of shares being swapped in do not exceed FixedPrice specific user limits.
    /// @dev The amount of shares purchased in total(including this swap) by the user must not exceed the user's maximum purchase limit.
    /// @dev The amount of shares purchased in total(including this swap) must not be less than the user's minimum purchase limit.
    /// @param recipient The address of the user swapping in.
    /// @param tokenAmount The amount of shares being swapped in.
    function _validateUserLimits(address recipient, uint256 tokenAmount) internal view override {
        uint256 updatedUserAmount = purchasedShares[recipient].rawAdd(tokenAmount);
        if (updatedUserAmount > maximumTokensPerUser()) revert UserMaxPurchaseExceeded();
        if (updatedUserAmount < minimumTokensPerUser()) revert UserMinPurchaseNotMet();
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// BUY LOGIC -- OVERRIDE REQUIRED --  Internal -- Write Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Helper function to emit the BuyFixedShares event post purchase.
    /// @dev All values are denormalized before being emitted.
    function _emitBuyEvent(
        address recipient,
        uint256 assetsIn,
        uint256 feesPaid,
        uint256 sharesOut
    )
    internal
    override
    {
        emit BuyFixedShares(
            recipient,
            sharesOut.denormalizeDown(shareDecimals()),
            assetsIn.denormalizeUp(assetDecimals()),
            feesPaid.denormalizeUp(assetDecimals())
        );
    }

    /// @notice Updates the pool state after a successful asset swap in.
    /// @dev Updates the total shares sold, the user's purchased shares, the user's assets in,
    /// the total assets in, and the total fees in.
    function _updatePoolState(
        address recipient,
        uint256 assetsIn,
        uint256 sharesOut,
        uint256 fees,
        TiersModified[] memory tiersModified
    )
    internal
    override
    returns (uint256)
    {
        //Update Pool shares
        totalSharesSold = totalSharesSold.rawAdd(sharesOut);

        purchasedShares[recipient] = purchasedShares[recipient].rawAdd(sharesOut);

        //Update Pool assets
        userNormalizedAssetsIn[recipient] = userNormalizedAssetsIn[recipient].rawAdd(assetsIn);
        totalNormalizedAssetsIn = totalNormalizedAssetsIn.rawAdd(assetsIn);

        //Update Pool fees
        totalNormalizedAssetFeesIn = totalNormalizedAssetFeesIn.rawAdd(fees);

        if (isTiered()) {
            _updateTierData(recipient, tiersModified);
        }

        return (assetsIn.rawAdd(fees));
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// BUY LOGIC --  TIER SPECIFIC -- Internal -- Read Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    ///@notice Helper function to calculate the amount of assets the user will swap into the pool and the amount of shares they are able to receive.
    ///@param tier The tier the user is attempting to purchase in.
    ///@param tierIndex The index of the tier the user is attempting to purchase in.
    ///@param newTotalUserPurchased The total amount of shares the user will have purchased in the tier after this purchase.
    ///@param newTotalSold The total amount of shares sold in the tier after this purchase.
    ///@param sharesOut The amount of shares the user is attempting to purchase.
    ///@return assetsIn The total amount of assets the user will swap into the pool before swap fees are applied.
    ///@return sharesOutInTier The total amount of shares the user will purchase in the tier.
    ///@dev This function will revert if the user is attempting to purchase more shares than they are allowed across all tiers.
    function _calculatePurchaseAmounts(
        Tier memory tier,
        address recipient,
        uint8 tierIndex,
        uint256 newTotalUserPurchased,
        uint256 newTotalSold,
        uint256 sharesOut
    )
    internal
    view
    returns (uint256 assetsIn, uint256 sharesOutInTier)
    {
        (uint256 userMaxAssetsIn, uint256 userMaxSharesOutInTier) = (0, 0);
        (uint256 tierMaxAssetsIn, uint256 tierMaxSharesOutInTier) = (0, 0);
        if (newTotalUserPurchased > tier.maximumPerUser) {
            (userMaxAssetsIn, userMaxSharesOutInTier) =
            _handleExcessPurchase(tier, recipient, tierIndex);
        }
        if (newTotalSold > tier.amountForSale) {
            (tierMaxAssetsIn, tierMaxSharesOutInTier) = _handleTierOverflow(tier, tierIndex);
        }

        if (userMaxAssetsIn == 0 && tierMaxAssetsIn == 0) {
            assetsIn = sharesOut.mulWadUp(tier.pricePerShare);
            sharesOutInTier = sharesOut;
        }
            // If only the tier limit was exceeded
        else if (userMaxAssetsIn == 0) {
            (assetsIn, sharesOutInTier) = (tierMaxAssetsIn, tierMaxSharesOutInTier);
        }
            // If only the user limit was exceeded
        else if (tierMaxAssetsIn == 0) {
            (assetsIn, sharesOutInTier) = (userMaxAssetsIn, userMaxSharesOutInTier);
        }
            // If both limits were exceeded, take the minimum
        else {
            if (tierMaxAssetsIn < userMaxAssetsIn) {
                (assetsIn, sharesOutInTier) = (tierMaxAssetsIn, tierMaxSharesOutInTier);
            } else {
                (assetsIn, sharesOutInTier) = (userMaxAssetsIn, userMaxSharesOutInTier);
            }
        }
    }

    ///@notice Helper function to handle the case where a user is attempting to purchase more shares than they are allowed for that tier.
    ///@param tier The tier the user is attempting to purchase in.
    ///@param recipient The address of the user attempting to purchase.
    ///@param tierIndex The index of the tier the user is attempting to purchase in.
    ///@dev This function will revert if there is no next tier as that would indicate they are unable to fulfill the current order.
    function _handleExcessPurchase(
        Tier memory tier,
        address recipient,
        uint8 tierIndex
    )
    internal
    view
    returns (uint256 assetsIn, uint256 sharesOutInTier)
    {
        _validateNextTierExists(tierIndex);

        sharesOutInTier = tier.maximumPerUser.rawSub(purchasedByTier[tierIndex][recipient]);
        assetsIn = sharesOutInTier.mulWadUp(tier.pricePerShare);
    }

    ///@notice Helper function to handle the case where a user is attempting to purchase more shares than are available in the current tier.
    ///@param tier The tier the user is attempting to purchase in.
    ///@param tierIndex The index of the tier the user is attempting to purchase in.
    ///@dev This function will revert if there is no next tier as that would indicate they are unable to fulfill the current order.
    function _handleTierOverflow(
        Tier memory tier,
        uint8 tierIndex
    )
    internal
    view
    returns (uint256 assetsIn, uint256 sharesOutInTier)
    {
        _validateNextTierExists(tierIndex);

        sharesOutInTier = tier.amountForSale.rawSub(amountSoldInTier[tierIndex]);

        assetsIn = sharesOutInTier.mulWadUp(tier.pricePerShare);
    }

    ///@notice Helper function to check that the requested swap amount meets the minimum purchase requirements for the tier.
    // function _validateMinimumPurchase(
    //     uint256 tierIndex,
    //     uint256 minimumPerUser,
    //     uint256 tokenAmount
    // )
    //     internal
    //     pure
    // {
    //     if (tokenAmount < minimumPerUser) {
    //         revert TierPurchaseTooLow(tierIndex);
    //     }
    // }

    ///@notice Helper function to validate that the next tier exists before attempting to purchase in it and accessing OOB data.
    ///@param tierIndex The index of the tier the user is attempting to purchase in.
    ///@dev This function will revert if there is no next tier as that would indicate they are unable to fulfill the current order.
    function _validateNextTierExists(uint8 tierIndex) internal pure {
        if (tierIndex + 1 > getTierLength() - 1) {
            revert TierMaxPurchaseExceeded();
        }
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// BUY LOGIC --  TIER SPECIFIC -- Internal -- Write Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    ///@notice Helper function to check if the current tier has reached its maximum shares sold and rollover to the next tier if needed.
    ///@param currentTierSharesOut The total amount of shares sold in the current tier.
    ///@param maximumInTier The maximum amount of shares that can be sold in the current tier.
    ///@dev emits a `TierRollover` event if the current tier has reached its maximum shares sold.
    function _handleTierRollover(uint256 currentTierSharesOut, uint256 maximumInTier) internal {
        if (currentTierSharesOut >= maximumInTier) {
            currentTier++;
            emit TierRollover(currentTier);
        }
    }

    ///@notice Helper function to perform an iteration across the current tier and all subsequent tiers to validate the user's
    ///requested purchase amount is within the bounds of the Tiers combined min/max purchase limits.
    ///@param recipient The address of the user purchasing shares.
    ///@param shareAmount The amount of shares the user is attempting to purchase.
    ///@return assetsIn The total amount of assets the user will swap into the pool before swap fees are applied.
    ///@dev This function will revert if the user is attempting to purchase more shares than they are allowed across all tiers. It will additionally
    ///rollover the tier to the next one if the current tier reaches its maximum shares sold within this transaction.
    function _calculateTieredPurchase(
        address recipient,
        uint256 shareAmount,
        uint256 maxPricePerShare
    )
    internal
    view
    returns (uint256 assetsIn, TiersModified[] memory tiersModified)
    {
        uint256 tempSharesOut;

        uint8 lengthOfTiers = getTierLength();
        uint8 iter;

        tiersModified = new TiersModified[](lengthOfTiers);

        for (uint8 i = currentTier; i < lengthOfTiers; i++) {
            if (maxPricePerShare != 0 && getTierData(i).pricePerShare > maxPricePerShare) {
                revert SlippageExceeded();
            }
            //Ensure there is a next tier available and the user is not attempting to purchase more/less shares than they are allowed.
            (uint256 assetsInInTier, uint256 sharesOutInTier) =
                            _validateAndReturnTierLimits(i, recipient, shareAmount.rawSub(tempSharesOut));

            tiersModified[iter] = TiersModified({
                tierIndex: i,
                assetsIn: assetsInInTier,
                sharesOutInTier: sharesOutInTier
            });

            tempSharesOut = tempSharesOut.rawAdd(sharesOutInTier);
            assetsIn = assetsIn.rawAdd(assetsInInTier);

            if (tempSharesOut > shareAmount) {
                revert TierMaxPurchaseExceeded();
            }

            //If the user has purchased the requested amount of shares, exit the loop.
            if (tempSharesOut == shareAmount) {
                break;
            }

            unchecked {
                iter++;
            }
        }

        if (tempSharesOut != shareAmount) {
            revert InvalidTierPurchaseAmount();
        }
    }

    ///@notice Helper function to update state data for the tier at index after this iteration of purchases is complete.
    function _updateTierData(address recipient, TiersModified[] memory tiersModified) internal {
        uint8 length = tiersModified.length.toUint8();
        for (uint8 i; i < length; i++) {
            if (tiersModified[i].assetsIn == 0) {
                continue;
            }

            uint8 tierIndex = tiersModified[i].tierIndex;

            uint256 sharesOutInTier = tiersModified[i].sharesOutInTier;

            purchasedByTier[tierIndex][recipient] += sharesOutInTier;
            amountSoldInTier[tierIndex] += sharesOutInTier;
            _handleTierRollover(amountSoldInTier[tierIndex], getTierData(tierIndex).amountForSale);
        }
    }

    ///@notice Helper function to update state data for the tier at index after this iteration of purchases is complete, and return both the assets in and shares out for the user.
    ///@param tierIndex The index of the tier to update.
    ///@param recipient The address of the user purchasing shares.
    ///@param sharesOutInTier The amount of shares the user is purchasing in the tier.
    ///@dev This function will revert if the user is attempting to purchase more shares than they are allowed across all tiers.
    function _validateAndReturnTierLimits(
        uint8 tierIndex,
        address recipient,
        uint256 tokenAmount
    )
    internal
    view
    returns (uint256 assetsIn, uint256 sharesOutInTier)
    {
        Tier memory tier = getTierData(tierIndex);

        // if one tier fail this condition when rollover the whole transaction will be reverted
        if (tokenAmount < tier.minimumPerUser) {
            revert TierPurchaseTooLow(tierIndex);
        }

        // _validateMinimumPurchase(tierIndex, tier.minimumPerUser, tokenAmount);

        (assetsIn, sharesOutInTier) = _calculatePurchaseAmounts(
            tier,
            recipient,
            tierIndex,
            purchasedByTier[tierIndex][recipient].rawAdd(tokenAmount),
            amountSoldInTier[tierIndex].rawAdd(tokenAmount),
            tokenAmount
        );
    }

    /// -----------------------------------------------------------------------
    /// BUY LOGIC -- PUBLIC -- Write Functions
    /// -----------------------------------------------------------------------

    ///@notice Allows a user to purchase shares in the pool by swapping in assets.
    ///@param sharesOut The amount of shares to swap out the pool.
    ///@param recipient The address that will receive the shares.
    ///@param deadline The deadline for the swap to be executed.
    ///@param signature The signature of the user authorizing the swap.
    ///@param proof The Merkle proof for the user's whitelist status.
    ///@dev If the pool has reached its asset token hard cap, the pool will emit a `PoolCompleted` event.
    /// @dev The sharesOut value should not be normalized to 18 decimals when supplied.
    function buyExactShares(
        uint256 sharesOut,
        address recipient,
        uint64 deadline,
        bytes memory signature,
        bytes32[] memory proof
    )
    public
    whenSaleActive
    {
        buy(sharesOut, recipient, deadline, signature, proof, 0);
    }

    ///@notice Allows a user to purchase shares in the pool by swapping in assets.
    ///@param sharesOut The amount of shares to swap out the pool.
    ///@param recipient The address that will receive the shares.
    ///@param deadline The deadline for the swap to be executed.
    ///@param signature The signature of the user authorizing the swap.
    ///@param proof The Merkle proof for the user's whitelist status.
    ///@param maxPricePerShare The maximum price per share the user is willing to pay.
    ///@dev If the pool has reached its asset token hard cap, the pool will emit a `PoolCompleted` event.
    /// @dev The sharesOut value should not be normalized to 18 decimals when supplied.
    function buyExactShares(
        uint256 sharesOut,
        address recipient,
        uint64 deadline,
        bytes memory signature,
        bytes32[] memory proof,
        uint256 maxPricePerShare
    )
    public
    whenSaleActive
    {
        buy(sharesOut, recipient, deadline, signature, proof, maxPricePerShare);
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// CLOSE LOGIC -- Overriden --  Internal -- Read Functionss
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Calculates and denormalizes the number of unsold shares that will be refunded to the owner.
    /// @dev For FixedPricePools this is the difference between the total shares sold and the shares available for purchase.
    function _calculateLeftoverShares() internal view override returns (uint256 sharesNotSold) {
        sharesNotSold = (sharesForSale().rawSub(totalSharesSold)).denormalizeDown(shareDecimals());
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// CLOSE LOGIC -- Overriden --  Internal -- Write Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Helper function to handle refunding in the case of a minReserve not being met.
    /// @dev Refunds all shares to the owner(), and distro's asset swap fees to the platform.
    function _handleManagerRefund()
    internal
    override
    returns (uint256 sharesNotSold, uint256 fundsRaised, uint256 swapFeesGenerated)
    {
        (sharesNotSold, fundsRaised, swapFeesGenerated) = super._handleManagerRefund();
        sharesNotSold = sharesNotSold.rawSub(totalSharesSold.denormalizeDown(shareDecimals()));
        if (shareToken() != address(0)) {
            uint256 sharesTotal = IERC20(shareToken()).balanceOf(address(this));
            if (sharesTotal > 0) {
                shareToken().safeTransfer(owner(), sharesTotal);
            }
        }
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// REDEEM LOGIC -- Overriden --  Internal -- READ Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Calculates and denormalizes the number of shares owed to the user based on the number of shares they have purchased.
    function _calculateSharesOwed(address sender)
    internal
    view
    override
    returns (uint256 sharesOut)
    {
        sharesOut = purchasedShares[sender].denormalizeDown(shareDecimals());
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    /// REDEEM LOGIC -- Overriden --  Internal -- Write Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Sets the users assets in and purchased shares balances to 0 after a successful redemption.
    function _handleUpdateUserRedemption(address sender) internal override {
        purchasedShares[sender] = 0;
        userNormalizedAssetsIn[sender] = 0;
    }

    /// @notice Helper function to handle refunding in the case of a minReserve not being met.
    /// @dev Refunds all assets to the purchaser sans swap fees.
    function _handleUserRefund(address sender) internal override returns (uint256 assetsOwed) {
        assetsOwed = userNormalizedAssetsIn[sender].denormalizeDown(assetDecimals());
        purchasedShares[sender] = 0;
        userNormalizedAssetsIn[sender] = 0;

        if (assetsOwed > 0) {
            assetToken().safeTransfer(sender, assetsOwed);
        }
    }

    /// -----------------------------------------------------------------------------------------------------------------------------------------
    ///  EIP712 Helper Functions
    /// -----------------------------------------------------------------------------------------------------------------------------------------

    /// @notice Overrides the default domain name and version for EIP-712 signatures.
    function _domainNameAndVersion()
    internal
    pure
    override
    returns (string memory name, string memory version)
    {
        name = "FixedPricePool";
        version = "1.0.0";
    }
}
