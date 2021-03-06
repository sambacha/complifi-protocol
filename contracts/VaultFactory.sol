// "SPDX-License-Identifier: GNU General Public License v3.0"

pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "./IDerivativeSpecification.sol";
import "./registries/IAddressRegistry.sol";
import "./IVaultBuilder.sol";
import "./IPausableVault.sol";

/// @title Vault Factory implementation contract
/// @notice Creates new vaults and registers them in internal storage
contract VaultFactory is OwnableUpgradeSafe {
    address[] internal _vaults;

    IAddressRegistry public derivativeSpecificationRegistry;
    IAddressRegistry public oracleRegistry;
    IAddressRegistry public collateralTokenRegistry;
    IAddressRegistry public collateralSplitRegistry;
    address public tokenBuilder;
    address public feeLogger;

    /// @notice protocol fee multiplied by 10 ^ 12
    uint public protocolFee;
    /// @notice protocol fee receiving wallet
    address public feeWallet;
    /// @notice author above limit fee multiplied by 10 ^ 12
    uint public authorFeeLimit;

    IVaultBuilder public vaultBuilder;
    IAddressRegistry public oracleIteratorRegistry;

    /// @notice redeem function can only be called after the end of the Live period + delay
    uint public settlementDelay;

    event VaultCreated(bytes32 indexed derivativeSymbol, address vault, address specification);

    /// @notice Initializes vault factory contract storage
    /// @dev Used only once when vault factory is created for the first time
    function initialize(
        address _derivativeSpecificationRegistry,
        address _oracleRegistry,
        address _oracleIteratorRegistry,
        address _collateralTokenRegistry,
        address _collateralSplitRegistry,
        address _tokenBuilder,
        address _feeLogger,
        uint _protocolFee,
        address _feeWallet,
        uint _authorFeeLimit,
        address _vaultBuilder,
        uint _settlementDelay
    ) external initializer {

        __Ownable_init();

        setDerivativeSpecificationRegistry(_derivativeSpecificationRegistry);
        setOracleRegistry(_oracleRegistry);
        setOracleIteratorRegistry(_oracleIteratorRegistry);
        setCollateralTokenRegistry(_collateralTokenRegistry);
        setCollateralSplitRegistry(_collateralSplitRegistry);

        setTokenBuilder(_tokenBuilder);
        setFeeLogger(_feeLogger);
        setVaultBuilder(_vaultBuilder);

        setSettlementDelay(_settlementDelay);

        protocolFee = _protocolFee;
        authorFeeLimit = _authorFeeLimit;

        require(_feeWallet != address(0), "Fee wallet");
        feeWallet = _feeWallet;
    }

    /// @notice Creates a new vault based on derivative specification symbol and initialization timestamp
    /// @dev Initialization timestamp allows to target a specific start time for Live period
    /// @param _derivativeSymbolHash a symbol hash which resolves to the derivative specification
    /// @param _initializationTime vault initialization timestamp
    function createVault(bytes32 _derivativeSymbolHash, uint _initializationTime) external {
        IDerivativeSpecification derivativeSpecification = IDerivativeSpecification(
            derivativeSpecificationRegistry.get(_derivativeSymbolHash));
        require(address(derivativeSpecification) != address(0), "Specification is absent");

        address collateralToken = collateralTokenRegistry.get(derivativeSpecification.collateralTokenSymbol());
        address collateralSplit = collateralSplitRegistry.get(derivativeSpecification.collateralSplitSymbol());

        bytes32[] memory oracleSymbols = derivativeSpecification.oracleSymbols();
        bytes32[] memory oracleIteratorSymbols = derivativeSpecification.oracleIteratorSymbols();
        require(oracleSymbols.length == oracleIteratorSymbols.length, "Oracles and iterators length");

        address[] memory oracles = new address[](oracleSymbols.length);
        address[] memory oracleIterators = new address[](oracleIteratorSymbols.length);
        for(uint i = 0; i < oracleSymbols.length; i++) {
            address oracle = oracleRegistry.get(oracleSymbols[i]);
            require(address(oracle) != address(0), "Oracle is absent");
            oracles[i] = oracle;

            address oracleIterator = oracleIteratorRegistry.get(oracleIteratorSymbols[i]);
            require(address(oracleIterator) != address(0), "OracleIterator is absent");
            oracleIterators[i] = oracleIterator;
        }

        require(_initializationTime > 0, "Zero initialization time");

        address vault = vaultBuilder.buildVault(
            _initializationTime,
            protocolFee,
            feeWallet,
            address(derivativeSpecification),
            collateralToken,
            oracles,
            oracleIterators,
            collateralSplit,
            tokenBuilder,
            feeLogger,
            authorFeeLimit,
            settlementDelay
        );
        emit VaultCreated(_derivativeSymbolHash, vault, address(derivativeSpecification));
        _vaults.push(vault);
    }

    function setProtocolFee(uint _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;
    }

    function setAuthorFeeLimit(uint _authorFeeLimit) external onlyOwner {
        authorFeeLimit = _authorFeeLimit;
    }

    function setTokenBuilder(address _tokenBuilder) public onlyOwner {
        require(_tokenBuilder != address(0), "Token builder");
        tokenBuilder = _tokenBuilder;
    }

    function setFeeLogger(address _feeLogger) public onlyOwner {
        require(_feeLogger != address(0), "Fee logger");
        feeLogger = _feeLogger;
    }

    function setVaultBuilder(address _vaultBuilder) public onlyOwner {
        require(_vaultBuilder != address(0), "Vault builder");
        vaultBuilder = IVaultBuilder(_vaultBuilder);
    }

    function setSettlementDelay(uint _settlementDelay) public onlyOwner {
        settlementDelay = _settlementDelay;
    }

    function setDerivativeSpecificationRegistry(address _derivativeSpecificationRegistry) public onlyOwner {
        require(_derivativeSpecificationRegistry != address(0), "Derivative specification registry");
        derivativeSpecificationRegistry = IAddressRegistry(_derivativeSpecificationRegistry);
    }

    function setOracleRegistry(address _oracleRegistry) public onlyOwner {
        require(_oracleRegistry != address(0), "Oracle registry");
        oracleRegistry = IAddressRegistry(_oracleRegistry);
    }

    function setOracleIteratorRegistry(address _oracleIteratorRegistry) public onlyOwner {
        require(_oracleIteratorRegistry != address(0), "Oracle iterator registry");
        oracleIteratorRegistry = IAddressRegistry(_oracleIteratorRegistry);
    }

    function setCollateralTokenRegistry(address _collateralTokenRegistry) public onlyOwner {
        require(_collateralTokenRegistry != address(0), "Collateral token registry");
        collateralTokenRegistry = IAddressRegistry(_collateralTokenRegistry);
    }

    function setCollateralSplitRegistry(address _collateralSplitRegistry) public onlyOwner {
        require(_collateralSplitRegistry != address(0), "Collateral split registry");
        collateralSplitRegistry = IAddressRegistry(_collateralSplitRegistry);
    }

    function pauseVault(address _vault) public onlyOwner {
        IPausableVault(_vault).pause();
    }

    function unpauseVault(address _vault) public onlyOwner {
        IPausableVault(_vault).unpause();
    }

    function setDerivativeSpecification(address _value) external {
        derivativeSpecificationRegistry.set(_value);
    }

    function setOracle(address _value) external {
        oracleRegistry.set(_value);
    }

    function setOracleIterator(address _value) external {
        oracleIteratorRegistry.set(_value);
    }

    function setCollateralToken(address _value) external {
        collateralTokenRegistry.set(_value);
    }

    function setCollateralSplit(address _value) external {
        collateralSplitRegistry.set(_value);
    }

    /// @notice Returns vault based on internal index
    /// @param _index internal vault index
    /// @return vault address
    function getVault(uint _index) external view returns(address) {
        return _vaults[_index];
    }

    /// @notice Get last created vault index
    /// @return last created vault index
    function getLastVaultIndex() external view returns(uint) {
        return _vaults.length - 1;
    }

    /// @notice Get all previously created vaults
    /// @return all previously created vaults
    function getAllVaults() external view returns(address[] memory) {
        return _vaults;
    }

    uint256[47] private __gap;
}
