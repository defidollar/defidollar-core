pragma solidity 0.5.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20, SafeMath} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {IStakeLPToken} from "../interfaces/IStakeLPToken.sol";
import {IPeak} from "../interfaces/IPeak.sol";
import {IDUSD} from "../interfaces/IDUSD.sol";
import {ICore} from "../interfaces/ICore.sol";

import {Initializable} from "../common/Initializable.sol";
import {OwnableProxy} from "../common/OwnableProxy.sol";

contract Core is OwnableProxy, Initializable, ICore {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Math for uint;

    uint constant FEE_PRECISION = 10000;

    IDUSD public dusd;
    IStakeLPToken public stakeLPToken;
    IOracle public oracle;
    address[] public systemCoins;
    uint[] public feed;

    uint public totalAssets;
    uint public unclaimedRewards;
    bool public inDeficit;
    uint public redeemFactor;
    uint public colBuffer;

    // Interface contracts for third-party protocol integrations
    enum PeakState { Extinct, Active, Dormant }
    struct Peak {
        uint[] systemCoinIds; // system indices of the coins accepted by the peak
        uint amount;
        uint ceiling;
        PeakState state;
    }
    mapping(address => Peak) public peaks;
    address[] public peaksAddresses;

    // END OF STORAGE VARIABLES

    event Mint(address indexed account, uint amount);
    event Redeem(address indexed account, uint amount);
    event TokenWhiteListed(address indexed token);
    event PeakWhitelisted(address indexed peak);

    /**
    * @dev Used to initialize contract state from the proxy
    */
    function initialize(
        IDUSD _dusd,
        IStakeLPToken _stakeLPToken,
        IOracle _oracle,
        uint _redeemFactor,
        uint _colBuffer
    )   public
        notInitialized
    {
        require(
            address(_dusd) != address(0),
            "0 address during initialization"
        );
        require(
            _redeemFactor <= FEE_PRECISION && _colBuffer <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        dusd = _dusd;
        stakeLPToken = _stakeLPToken;
        oracle = _oracle;
        redeemFactor = _redeemFactor;
        colBuffer = _colBuffer;
    }

    /**
    * @notice Mint DUSD
    * @dev Only whitelisted peaks can call this function
    * @param dusdAmount DUSD amount to mint
    * @param account Account to mint DUSD to
    * @return dusdAmount DUSD amount minted
    */
    function mint(uint dusdAmount, address account)
        external
        returns(uint)
    {
        Peak storage peak = peaks[msg.sender];
        uint tvl = peak.amount.add(dusdAmount);
        require(
            dusdAmount > 0
            && peak.state == PeakState.Active
            && tvl <= peak.ceiling,
            "ERR_MINT"
        );
        peak.amount = tvl;
        dusd.mint(account, dusdAmount);
        emit Mint(account, dusdAmount);
        return dusdAmount;
    }

    /**
    * @notice Redeem DUSD
    * @dev Only whitelisted peaks can call this function
    * @param dusdAmount DUSD amount to redeem.
    * @param account Account to burn DUSD from
    */
    function redeem(uint dusdAmount, address account)
        external
        returns(uint usd)
    {
        Peak storage peak = peaks[msg.sender];
        require(
            dusdAmount > 0 && peak.state != PeakState.Extinct,
            "ERR_REDEEM"
        );
        peak.amount = peak.amount.sub(peak.amount.min(dusdAmount));
        dusd.burn(account, dusdAmount);
        emit Redeem(account, dusdAmount);
        return dusdAmount;
    }

    function harvest() external {
        require(msg.sender == authorizedController() || isOwner(), "HARVEST_NO_AUTH");
        uint earned = earned();
        if (earned > 0) {
            dusd.mint(msg.sender, earned);
        }
    }

    /* ##### View ##### */

    function authorizedController() public view returns(address) {
        return address(getStore(0));
    }

    function earned() public view returns(uint) {
        uint _totalAssets = totalSystemAssets();
        uint supply = dusd.totalSupply();
        if (_totalAssets > supply) {
            return _totalAssets.sub(supply);
        }
        return 0;
    }

    function totalSystemAssets() public view returns (uint _totalAssets) {
        for (uint i = 0; i < peaksAddresses.length; i++) {
            Peak memory peak = peaks[peaksAddresses[i]];
            if (peak.state == PeakState.Extinct) {
                continue;
            }
            _totalAssets = _totalAssets.add(
                IPeak(peaksAddresses[i]).portfolioValue()
            );
        }
    }

    /**
    * @dev Unused but kept for backwards compatibility with CurveSusdPeak.
    */
    function dusdToUsd(uint _dusd, bool fee) public view returns(uint usd) {
        usd = _dusd;
        if (fee) {
            usd = usd.mul(redeemFactor).div(FEE_PRECISION);
        }
        return usd;
    }

    /* ##### Admin ##### */

    function authorizeController(address _controller)
        external
        onlyOwner
    {
        require(_controller != address(0x0), "Zero Address");
        setStore(0, uint(_controller));
        // just a sanity check, not strictly required
        require(authorizedController() == _controller, "Sanity Check Failed");
    }

    /**
    * @notice Whitelist new tokens supported by the peaks.
    * These are vanilla coins like DAI, USDC, USDT etc.
    * @dev onlyOwner ACL is provided by the whitelistToken call
    * @param tokens Token addresses to whitelist
    */
    function whitelistTokens(address[] calldata tokens)
        external
        onlyOwner
    {
        for (uint i = 0; i < tokens.length; i++) {
            _whitelistToken(tokens[i]);
        }
    }

    /**
    * @notice Whitelist a new peak
    * @param peak Address of the contract that interfaces with the 3rd-party protocol
    * @param _systemCoins Indices of the system coins, the peak supports
    */
    function whitelistPeak(
        address peak,
        uint[] calldata _systemCoins,
        uint ceiling
    )   external
        onlyOwner
    {
        uint numSystemCoins = systemCoins.length;
        for (uint i = 0; i < _systemCoins.length; i++) {
            require(_systemCoins[i] < numSystemCoins, "Invalid system coin index");
        }
        require(
            peaks[peak].state == PeakState.Extinct,
            "Peak already exists"
        );
        peaksAddresses.push(peak);
        peaks[peak] = Peak(_systemCoins, 0, ceiling, PeakState.Active);
        emit PeakWhitelisted(peak);
    }

    /**
    * @notice Change a peaks status
    */
    function setPeakStatus(address peak, uint ceiling, PeakState state)
        external
        onlyOwner
    {
        require(
            peaks[peak].state != PeakState.Extinct,
            "Peak is extinct"
        );
        peaks[peak].ceiling = ceiling;
        peaks[peak].state = state;
    }

    function setFee(uint _redeemFactor, uint _colBuffer)
        external
        onlyOwner
    {
        require(
            _redeemFactor <= FEE_PRECISION && _colBuffer <= FEE_PRECISION,
            "Incorrect upper bound for fee"
        );
        redeemFactor = _redeemFactor;
        colBuffer = _colBuffer;
    }

    /* ##### Internal ##### */

    function _whitelistToken(address token)
        internal
    {
        for (uint i = 0; i < systemCoins.length; i++) {
            require(systemCoins[i] != token, "Adding a duplicate token");
        }
        systemCoins.push(token);
        feed.push(0);
        emit TokenWhiteListed(token);
    }
}
