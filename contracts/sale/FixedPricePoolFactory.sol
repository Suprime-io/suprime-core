// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "solady/src/utils/LibClone.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "../utils/Merkle.sol";
import {
FixedPricePool,
FjordMath,
PoolType,
Tier,
TiersModified,
PoolStatus,
FixedPointMathLib
} from "../sale/FixedPricePool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

    struct BaseCreationParams {
        ///@notice Address of the owner of the pool
        address owner;
        ///@notice Address of the token being sold in the sale.
        address shareToken;
        ///@notice Address of the token being raised in the sale.
        address assetToken;
        ///@notice The amount of shares being sold in the sale.
        uint256 sharesForSale;
        ///@notice The minimum amount of tokens that must be sold in the sale.
        uint256 minimumTokensForSale;
        ///@notice The maximum amount of tokens that a user can purchase in the sale.
        ///@dev Note if used in conjunction with tiers, this maximum applies to the entire sale.
        uint256 maximumTokensPerUser;
        ///@notice The minimum amount of tokens that a user can purchase in the sale.
        ///@dev Note if used in conjunction with tiers, this minimum applies to the entire sale.
        uint256 minimumTokensPerUser;
        ///@notice The fee charged on swaps in the pool.
        uint64 swapFeeWAD;
        ///@notice The fee charged on the the total funds raised for the sale.
        uint64 platformFeeWAD;
        ///@notice The timestamp when the sale starts.
        uint40 saleStart;
        ///@notice The timestamp when the sale ends.
        uint40 saleEnd;
        ///@notice The timestamp when the funds can be redeemed.
        uint40 redemptionDelay;
        ///@notice The timestamp when the vesting period ends.
        uint40 vestEnd;
        ///@notice The timestamp when the cliff period ends.
        uint40 vestCliff;
        ///@notice Boolean indicating if anti-snipe/bot protection is enabled, requiring a delegated signature to purchase.
        uint8 antiSnipeEnabled;
        ///@notice The merkle root of the whitelist for the pool.
        bytes32 whitelistMerkleRoot;
    }

/// @title MultiModalFactory
/// @notice Factory contract to deploy Fixed Price Pools with native and ERC20 token as the asset token
/// @notice and any arbitrary ERC20 token(or none at all) as the share token. The pools are deployed using the create3 method.
/// @dev The asset token decimals must be >=2 and <=18 and the share token decimals must be >=0 and <=18
/// @dev Any transfer-hooks applied during swaps will be ignored during the sale but will be applied during redemption and closure
/// @dev if the pool is not whitelisted/exempted from these features.
contract FixedPricePoolFactory is Merkle {
    /// -----------------------------------------------------------------------
    /// Dependencies
    /// -----------------------------------------------------------------------
    using LibClone for address;
    using SafeTransferLib for address;
    using FjordMath for *;
    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error ZeroAddress();
    error FeeTooHigh();
    error InvalidAssetPrice();
    error InvalidDecimals();
    error InvalidMinimumPurchaseAmount();
    error InvalidPoolCap();
    error InvalidPoolDuration();
    error InvalidPoolLimits();
    error InvalidTierMinimums();
    error InvalidTierLength();
    error InvalidTierAmountsSold();
    error InvalidVestingConfig();
    error InvalidTierMaximums();
    error InvalidRedemptionDelay();
    error InvalidMinSharesPerAsset();
    error InvalidMinimumSwapThreshold();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    ///@notice Emitted when a new pool is created
    event PoolCreated(address indexed poolAddress, PoolType poolType, string ipfsData);

    /// -----------------------------------------------------------------------
    /// Immutable State
    /// -----------------------------------------------------------------------

    ///@notice Address of the FixedPricePool implementation contract
    address public immutable FIXED_PRICE_IMPL;

    ///@notice Address of the signer used for anti-snipe/bot protection
    address public immutable DELEGATE_SIGNER;

    uint8 public constant MAX_TIERS = 80;

    /// -----------------------------------------------------------------------
    /// Mutable Write Functions
    /// -----------------------------------------------------------------------

    ///@notice Address of the fee recipient that receives platform and swap fees.
    address public feeRecipient;

    constructor(address _feeRecipient, address signer, address sablier) {
        FIXED_PRICE_IMPL = address(new FixedPricePool(sablier));

        feeRecipient = _feeRecipient;
        DELEGATE_SIGNER = signer;
    }

    /// -----------------------------------------------------------------------
    /// Public Write Functions
    /// -----------------------------------------------------------------------

    /// @notice Creates a new Fixed Price Pool with the given parameters
    /// @param params BaseCreationParams struct containing the parameters for the pool
    /// @param assetsPerShare The amount of asset tokens per share token
    /// @return pool The address of the newly created pool
    function createFixedPricePool(
        BaseCreationParams memory params,
        uint256 assetsPerShare,
        Tier[] memory tiers,
        string memory ipfsData
    )
    public
    returns (address pool)
    {
        (uint8 assetDecimals, uint8 shareDecimals) = _getTokenDecimals(params);

        _verifyBaseArgs(params);
        _verifyFixedArgs(params, assetsPerShare, assetDecimals, shareDecimals, tiers);

        uint256 initialSharesForSale = params.sharesForSale;
        params = _normalizeTokenParams(params, shareDecimals);

        bytes memory tierData = abi.encode(_normalizeTiers(tiers, shareDecimals, assetDecimals));
        uint256 tierDataLength = tierData.length;

        bytes memory encodedParams = abi.encodePacked(
            _encodeBaseParams(params, shareDecimals, assetDecimals),
            abi.encodePacked(assetsPerShare.normalize(assetDecimals), tierDataLength),
            tierData
        );

        pool = _createPool(
            initialSharesForSale, params.shareToken, encodedParams, FIXED_PRICE_IMPL,
            PoolType.Fixed, ipfsData
        );
    }

    /// -----------------------------------------------------------------------
    /// Internal Write Functions
    /// -----------------------------------------------------------------------

    function _createPool(
        uint256 sharesForSale,
        address shareToken,
        bytes memory encodedParams,
        address implementation,
        PoolType poolType,
        string memory ipfsData
    )
    internal
    returns (address pool)
    {
        pool = implementation.clone(encodedParams);

        if (shareToken != address(0)) shareToken.safeTransferFrom(msg.sender, pool, sharesForSale);

        emit PoolCreated(pool, poolType, ipfsData);
    }

    /// -----------------------------------------------------------------------
    /// Internal Helper Functions
    /// -----------------------------------------------------------------------

    function _normalizeTiers(
        Tier[] memory tiers,
        uint8 shareDecimals,
        uint8 assetDecimals
    )
    internal
    pure
    returns (Tier[] memory)
    {
        uint8 tierLength = uint8(tiers.length);
        for (uint8 i; i < tierLength; i++) {
            tiers[i].amountForSale = tiers[i].amountForSale.normalize(shareDecimals);
            tiers[i].pricePerShare = tiers[i].pricePerShare.normalize(assetDecimals);
            tiers[i].maximumPerUser = tiers[i].maximumPerUser == 0
                ? type(uint256).max
                : tiers[i].maximumPerUser.normalize(shareDecimals);
            tiers[i].minimumPerUser = tiers[i].minimumPerUser.normalize(shareDecimals);
        }
        return tiers;
    }

    /// @notice Validates the BaseCreationParams pre-normalization to ensure all pool settings are valid before creation.
    /// @dev This is executed prior to either pool type being launched.
    function _verifyBaseArgs(BaseCreationParams memory args) internal pure {
        if (args.owner == address(0)) {
            revert ZeroAddress();
        }

        if (args.platformFeeWAD > 1e18 || args.swapFeeWAD > 1e18) {
            revert FeeTooHigh();
        }

        if (args.saleEnd <= args.saleStart) {
            revert InvalidPoolDuration();
        }

        // Ensure the pool has a minimum duration of 10 minutes to avoid mis-configuration
        if (args.saleEnd - args.saleStart < 10 minutes) {
            revert InvalidPoolDuration();
        }

        // Ensure the redemption delay is less than 30 days to avoid mis-configuration
        if (args.redemptionDelay > 0 && args.redemptionDelay > 86_400 * 30) {
            revert InvalidRedemptionDelay();
        }

        bool vestingEnabled = args.vestEnd != 0 && args.vestCliff != 0;

        if (vestingEnabled) {
            if (args.shareToken == address(0)) {
                revert InvalidVestingConfig();
            }

            if (args.vestCliff >= args.vestEnd) {
                revert InvalidVestingConfig();
            }
            if (args.saleEnd >= args.vestCliff) {
                revert InvalidVestingConfig();
            }
        } else {
            if (args.vestCliff == 0 && args.vestEnd != 0) {
                revert InvalidVestingConfig();
            }
            if (args.vestCliff != 0 && args.vestEnd == 0) {
                revert InvalidVestingConfig();
            }
        }
        if (args.maximumTokensPerUser > 0) {
            if (args.minimumTokensPerUser > args.maximumTokensPerUser) {
                revert InvalidPoolLimits();
            }
        }
    }

    function _verifyFixedArgs(
        BaseCreationParams memory args,
        uint256 assetsPerShare,
        uint8 assetDecimals,
        uint8 shareDecimals,
        Tier[] memory tiers
    )
    internal
    pure
    {
        uint8 tierLength = uint8(tiers.length);
        if (tierLength == 0 && assetsPerShare == 0) {
            revert InvalidAssetPrice();
        }
        if (args.minimumTokensPerUser > 0 && args.sharesForSale < args.minimumTokensPerUser) {
            revert InvalidMinimumPurchaseAmount();
        }
        if (args.minimumTokensForSale > 0 && args.minimumTokensForSale > args.sharesForSale) {
            revert InvalidMinimumPurchaseAmount();
        }
        if (
            args.maximumTokensPerUser > 0
            && args.maximumTokensPerUser < shareDecimals.mandatoryMinimumSwapIn(assetDecimals)
        ) {
            revert InvalidMinimumSwapThreshold();
        }

        if (tierLength > MAX_TIERS) {
            revert InvalidTierLength();
        }
        if (tierLength != 0) {
            if (args.minimumTokensPerUser > 0) {
                revert InvalidTierMinimums();
            }
            // if (assetsPerShare > 0) {
            //     revert InvalidAssetPrice();
            // }
            uint256 totalAmountForSaleInTiers;
            for (uint8 i; i < tierLength; i++) {
                if (
                    args.maximumTokensPerUser != 0
                    && args.maximumTokensPerUser < tiers[i].minimumPerUser
                ) {
                    revert InvalidTierMaximums();
                }
                if (tiers[i].amountForSale == 0) {
                    revert InvalidTierAmountsSold();
                }
                if (tiers[i].pricePerShare == 0) {
                    revert InvalidAssetPrice();
                }
                if (tiers[i].minimumPerUser > 0) {
                    if (tiers[i].minimumPerUser > tiers[i].amountForSale) {
                        revert InvalidTierMinimums();
                    }
                }
                if (tiers[i].maximumPerUser > 0) {
                    if (tiers[i].minimumPerUser > tiers[i].maximumPerUser) {
                        revert InvalidTierMaximums();
                    }
                    if (tiers[i].amountForSale < tiers[i].maximumPerUser) {
                        revert InvalidTierMaximums();
                    }
                }

                totalAmountForSaleInTiers += tiers[i].amountForSale;
            }
            // args.sharesForSale is a derived value from the tiers, so we don't need to check if
            if (args.sharesForSale != totalAmountForSaleInTiers) {
                revert InvalidTierAmountsSold();
            }
        }
    }

    /// @notice Normalizes the token parameters to the token decimals
    /// @param params BaseCreationParams struct containing the parameters for the pool
    /// @param shareDecimals The number of decimals for the share token
    /// @return params The normalized BaseCreationParams struct
    function _normalizeTokenParams(
        BaseCreationParams memory params,
        uint8 shareDecimals
    )
    internal
    pure
    returns (BaseCreationParams memory)
    {
        uint8 tokenDecimals = shareDecimals;
        params.sharesForSale = params.sharesForSale.normalize(shareDecimals);
        params.minimumTokensForSale = params.minimumTokensForSale.normalize(tokenDecimals);
        params.maximumTokensPerUser = params.maximumTokensPerUser == 0
            ? type(uint256).max
            : params.maximumTokensPerUser.normalize(tokenDecimals);
        params.minimumTokensPerUser = params.minimumTokensPerUser.normalize(tokenDecimals);
        return params;
    }

    function _encodeBaseParams(
        BaseCreationParams memory params,
        uint8 shareDecimals,
        uint8 assetDecimals
    )
    internal
    view
    returns (bytes memory)
    {
        return abi.encodePacked(
            abi.encodePacked(
                params.owner, params.shareToken, params.assetToken, feeRecipient, DELEGATE_SIGNER
            ),
            abi.encodePacked(
                params.sharesForSale,
                params.minimumTokensForSale,
                params.maximumTokensPerUser,
                params.minimumTokensPerUser
            ),
            abi.encodePacked(params.swapFeeWAD, params.platformFeeWAD),
            abi.encodePacked(
                params.saleStart,
                params.saleEnd,
                params.redemptionDelay,
                params.vestEnd,
                params.vestCliff
            ),
            abi.encodePacked(shareDecimals, assetDecimals, params.antiSnipeEnabled),
            abi.encodePacked(params.whitelistMerkleRoot)
        );
    }

    function _getTokenDecimals(BaseCreationParams memory params)
    internal view
    returns (uint8 assetDecimals, uint8 shareDecimals)
    {
        if (params.assetToken != address(0)) {
            assetDecimals = ERC20(params.assetToken).decimals();
            if (assetDecimals < 2 || assetDecimals > 18) {
                revert InvalidDecimals();
            }
        } else {
            revert ZeroAddress();
        }

        shareDecimals = 18;
        if (params.shareToken != address(0)) {
            shareDecimals = ERC20(params.shareToken).decimals();
            if (shareDecimals > 18) {
                revert InvalidDecimals();
            }
        }
    }
}
