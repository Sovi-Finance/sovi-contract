pragma solidity 0.6.8;


import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./SoviToken.sol";
import "./IReferral.sol";
import "./IBadgePool.sol";




// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SOVI is sufficiently
// distributed and the community can show to govern itself.
contract SoviProtocol is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Events
    event ChangedReward(uint256 indexed pid, uint256 reward);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    // Info of each user.
    struct UserInfo {
        uint256 amount;             // How many LP tokens the user has provided.
        uint256 rewardDebt;         // Reward debt.
        uint256 refRewardDebt;      // Claimed rebate reward.
        uint256 yieldRewardDebt;    // Claimed production reward.
        uint256 pendingRebate;      // Unclaimed rebate reward.
        uint256 extraRebateRatio;   // Extra rebate.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. SOVIs to distribute per block.
        uint256 lastRewardBlock;    // Last block number that SOVIs distribution occurs.
        uint256 accRewardPerShare;  // Accumulated SOVIs per share, times 1e18. See below.
        uint256 totalAmount;        // Total LP in pool.
        bool enableRebate;          // Whether to enable rebate
    }

    // Badge Pool Info
    struct BadgePoolInfo {
        bool enable;
        IBadgePool badgePool;
        uint256 ratio;
    }

    // The SOVI TOKEN!
    SoviToken public SOVI;
    // Dev address.
    address public devAddr;
    // SOVI tokens created per block.
    uint256 public rewardPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP/BPT tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Info of each user that stakes LP/BPT tokens.
    mapping(address => bool) public existedPool;
    // Badge Pool Info
    BadgePoolInfo public badgePoolInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // Info of reduction
    uint256 public startBlock;
    uint256 public rewardEndBlock;
    uint256 public reductionBlockCount;
    uint256 public maxReductionCount;
    uint256 public nextReductionBlock;
    uint256 public reductionCounter;
    uint256 public reductionPercent;

    // Constants
    uint256 public constant DECIMALS = 1e18;
    uint256 public constant TEN = 10;
    uint256 public constant HUNDRED = 100;
    uint256 public constant DAILY_BLOCKS = 664;

    // Info of rebate
    uint256 public REBATE_BASIC_RATIO = 6;
    uint256 public REBATE_HSOV_BASE = uint256(1000).mul(DECIMALS);
    uint256 public constant REBATE_BASIC_GAP = 1;
    uint256 public constant REBATE_PERSONAL_LIMIT_MIN = 500;
    uint256 public constant REBATE_PERSONAL_LIMIT_MAX = 5000;
    uint256 public constant REBATE_PERSONAL_GAP_RATIO = 10;
    uint256 public constant REBATE_MAX_LEVEL = 2;

    IReferral public hSOV;
    ERC20 public USDT_CONTRACT = ERC20(0x0);
    address public SOVI_POOL_ADDRESS = address(0x0);

    constructor(
        SoviToken _SOVI,
        IReferral _hSOV,
        address _devAddr,
        uint256 _startBlock,
        address usdtContract,
        address uniPoolAddress
    ) public {

        // TODO NOTE: Replace with the address in the mainnet before deploy
        require(address(_SOVI) != address(0), "SoviProtocol: SOVI is the zero address");
        require(address(_hSOV) != address(0), "SoviProtocol: hSOV is the zero address");
        require(_devAddr != address(0), "SoviProtocol: devAddr is the zero address");
        require(address(usdtContract) != address(0), "SoviProtocol: usdtContract is the zero address");
        require(address(uniPoolAddress) != address(0), "SoviProtocol: uniPoolAddress is the zero address");

        SOVI = _SOVI;
        devAddr = _devAddr;
        hSOV = _hSOV;
        USDT_CONTRACT = ERC20(usdtContract);
        SOVI_POOL_ADDRESS = address(uniPoolAddress);

        startBlock = _startBlock;
        rewardEndBlock = _startBlock.add(DAILY_BLOCKS.mul(365));
        rewardPerBlock = TEN.mul(TEN ** uint256(_SOVI.decimals()));
        maxReductionCount = 4;
        reductionPercent = 70;
        reductionBlockCount = DAILY_BLOCKS.mul(21);
        nextReductionBlock = _startBlock.add(DAILY_BLOCKS.mul(14));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, bool _enableRebate) external onlyOwner {
        require(!existedPool[address(_lpToken)], "SoviProtocol: lpToken had been added!");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accRewardPerShare : 0,
        totalAmount : 0,
        enableRebate : _enableRebate
        }));
    }

    // Update the given pool's SOVI allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _enableRebate, bool _withUpdate) external onlyOwner {
        require(_pid < poolInfo.length && _pid >= 0, "SoviProtocol: _pid is not exist");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].enableRebate = _enableRebate;
    }

    // Update badgePool address by the previous badgePool address.
    function setBadgePool(bool _enable, IBadgePool _addr, uint256 _ratio) external onlyOwner {
        require(address(_addr) != address(0), "empty!");
        badgePoolInfo.enable = _enable;
        badgePoolInfo.badgePool = _addr;
        badgePoolInfo.ratio = _ratio;
    }

    // Return blocks total reward
    function getBlocksReward(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(rewardPerBlock);
    }

    // View function to see pending SOVIs on frontend.
    function pendingReward(uint256 _pid, address _addr) external view returns (uint256, uint256, uint256, uint256, uint256) {
        PoolInfo storage _pool = poolInfo[_pid];
        UserInfo storage _user = userInfo[_pid][_addr];
        uint256 accRewardPerShare = _pool.accRewardPerShare;
        if (block.number > _pool.lastRewardBlock && _pool.totalAmount != 0) {
            uint256 blockReward = getBlocksReward(_pool.lastRewardBlock, block.number);
            uint256 poolReward = blockReward.mul(_pool.allocPoint).div(totalAllocPoint);
            // Assign reward to badge pool
            if (badgePoolInfo.enable) {
                uint256 badgePoolAmount = poolReward.mul(badgePoolInfo.ratio).div(HUNDRED);
                poolReward = poolReward.sub(badgePoolAmount);
            }
            accRewardPerShare = accRewardPerShare.add(poolReward.mul(DECIMALS).div(_pool.totalAmount));
        }
        uint256 _pending = _user.amount.mul(accRewardPerShare).div(DECIMALS).add(_user.refRewardDebt).add(_user.yieldRewardDebt).sub(_user.rewardDebt);
        return yieldCalc(_pid, _addr, _pending);
    }

    // View function to see my army balance on frontend.
    function armyBalance(uint256 _pid, address _addr) external view returns (uint256, uint256) {
        return selectInvitees(_pid, _addr);
    }

    function selectInvitees(uint256 _pid, address _addr) internal view returns (uint256, uint256) {
        address[] memory _invitees = hSOV.getInvitees(_addr);
        uint256 _total_count;
        uint256 _total_amount;
        for (uint256 idx; idx < _invitees.length; idx ++) {
            address u = _invitees[idx];
            _total_count = _total_count.add(1);
            _total_amount = _total_amount.add(userInfo[_pid][u].amount);
            if (hSOV.getInvitees(u).length > 0) {
                (uint256 _count, uint256 _amount) = selectInvitees(_pid, u);
                _total_count = _total_count.add(_count);
                _total_amount = _total_amount.add(_amount);
            }
        }
        return (_total_count, _total_amount);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        // Reduce yield according to reductionPercent
        if (block.number > nextReductionBlock && reductionCounter < maxReductionCount) {
            nextReductionBlock = nextReductionBlock.add(reductionBlockCount);
            reductionCounter = reductionCounter.add(uint256(1));
            rewardPerBlock = rewardPerBlock.mul(reductionPercent).div(HUNDRED);
            REBATE_BASIC_RATIO = REBATE_BASIC_RATIO.add(REBATE_BASIC_GAP);
            emit ChangedReward(_pid, rewardPerBlock);
        }
        uint256 lpSupply = pool.totalAmount;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getBlocksReward(pool.lastRewardBlock, block.number);
        uint256 poolReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        SOVI.mint(devAddr, poolReward.div(TEN));
        mintToBadgePool(poolReward.mul(badgePoolInfo.ratio).div(HUNDRED));
        SOVI.mint(address(this), poolReward);
        pool.accRewardPerShare = pool.accRewardPerShare.add(poolReward.mul(DECIMALS).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Update rebate reward when pool.enableRebate is true
    function setRebateReward(address _addr, uint256 _yield, uint256 _pid) internal {
        PoolInfo storage _pool = poolInfo[_pid];
        if (!_pool.enableRebate) {
            return;
        }

        // Referrals
        address[] memory refs = hSOV.getReferrals(_addr);

        uint256 refReward = _yield.mul(REBATE_BASIC_RATIO).div(HUNDRED);
        if (refs.length == 0) {
            mintToBadgePool(refReward);
            return;
        }

        // Maximum 2 levels
        uint256 level = Math.min(REBATE_MAX_LEVEL, refs.length);
        uint256 levelReward = refReward.div(level);
        uint256 _badgePoolReward;
        uint256 _thisReward;

        for (uint256 idx = 0; idx < level; idx ++) {
            if (userInfo[_pid][refs[idx]].extraRebateRatio == 0) {
                _badgePoolReward = _badgePoolReward.add(levelReward);
            } else {
                _thisReward = _thisReward.add(levelReward);
                userInfo[_pid][refs[idx]].pendingRebate = userInfo[_pid][refs[idx]].pendingRebate.add(levelReward);
            }
        }

        if (_thisReward > 0) {
            SOVI.mint(address(this), _thisReward);
        }
        if (_badgePoolReward > 0) {
            mintToBadgePool(_badgePoolReward);
        }
    }

    // Claim & rebate
    function harvest(address _addr, uint256 _pending, uint256 _pid) internal {
        UserInfo storage _user = userInfo[_pid][_addr];
        uint256 _extraYield;
        uint256 _pendingRebate;
        uint256 _extraRebate;
        uint256 _totalPending;
        (, _extraYield, _pendingRebate, _extraRebate, _totalPending) = yieldCalc(_pid, _addr, _pending);
        safeTokenTransfer(_addr, _pending.add(_pendingRebate));
        if (_extraYield > 0) {
            _user.yieldRewardDebt = _user.yieldRewardDebt.add(_extraYield);
        }
        if (_pendingRebate > 0) {
            _user.refRewardDebt = _user.refRewardDebt.add((_pendingRebate.add(_extraRebate)));
            _user.pendingRebate = 0;
        }

        // Mint extra yield & rebate
        uint256 extraMint = _extraYield.add(_extraRebate);
        if (extraMint > 0) {
            SOVI.mint(_addr, extraMint);
        }

        // Rebate allocation
        setRebateReward(_addr, _pending, _pid);
    }

    function yieldCalc(uint256 _pid, address _addr, uint256 _pending) public view returns (uint256, uint256, uint256, uint256, uint256){
        uint256 _extraYield = _pending.mul(getExtraYield(_addr, _pending)).div(HUNDRED);
        uint256 _pendingRebate = userInfo[_pid][_addr].pendingRebate;
        uint256 _extraRebate;
        if (_pendingRebate > 0) {
            uint256 ratio = getHsovExtraRebate(_addr).add(userInfo[_pid][_addr].extraRebateRatio);
            _extraRebate = _pendingRebate.mul(ratio).div(HUNDRED);
        }
        uint256 _totalPending = _pending.add(_extraYield).add(_pendingRebate).add(_extraRebate);
        return (_pending, _extraYield, _pendingRebate, _extraRebate, _totalPending);
    }

    // Extra yield
    function getExtraYield(address _addr, uint256 _amount) public view returns (uint256){
        if (!badgePoolInfo.enable) {
            return 0;
        }
        return badgePoolInfo.badgePool.getYieldAddition(_addr, _amount);
    }

    // HSOV extra rebate
    function getHsovExtraRebate(address _addr) internal view returns (uint256){
        uint256 _hsovBalance = hSOV.balanceOf(_addr);
        if (_hsovBalance >= REBATE_HSOV_BASE.mul(5)) {
            return uint256(5);
        } else if (_hsovBalance >= REBATE_HSOV_BASE.mul(3)) {
            return uint256(3);
        } else if (_hsovBalance >= REBATE_HSOV_BASE) {
            return uint256(1);
        }
        return uint256(0);
    }

    // Return User rebate extra based on the deposit amount
    function userRebateExtra(uint256 _pid, uint256 _lpAmount) public view returns (uint256){
        uint256 lpValue = getAssetValue(_pid, _lpAmount);
        if (lpValue < REBATE_PERSONAL_LIMIT_MIN) {
            return uint256(0);
        }
        if (lpValue >= REBATE_PERSONAL_LIMIT_MAX) {
            return uint256(100);
        }
        return lpValue.mul(REBATE_PERSONAL_GAP_RATIO).div(REBATE_PERSONAL_LIMIT_MIN);
    }

    // Get asset value from LP amount
    function getAssetValue(uint256 _pid, uint256 _lpAmount) public view returns (uint256){
        uint256 usdtInUni = USDT_CONTRACT.balanceOf(SOVI_POOL_ADDRESS).div(TEN ** USDT_CONTRACT.decimals());
        uint256 lpTotalSupply = poolInfo[_pid].lpToken.totalSupply();
        return usdtInUni.mul(_lpAmount).div(lpTotalSupply);
    }

    // Mint to badge pool when the pool is enable
    function mintToBadgePool(uint256 _amount) internal {
        if (badgePoolInfo.enable && _amount > 0) {
            SOVI.mint(address(badgePoolInfo.badgePool), _amount);
        }
    }

    // Deposit LP tokens to Sovi for SOVI allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = totalReward(_pid, msg.sender).sub(user.rewardDebt);
            if (pending > 0) {
                harvest(msg.sender, pending, _pid);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
            uint256 _extraRebateRatio = userRebateExtra(_pid, user.amount);
            if (_extraRebateRatio > user.extraRebateRatio) {
                user.extraRebateRatio = _extraRebateRatio;
            }
        }
        user.rewardDebt = totalReward(_pid, msg.sender);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Sovi.
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = totalReward(_pid, msg.sender).sub(user.rewardDebt);
        if (pending > 0) {
            harvest(msg.sender, pending, _pid);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            uint256 _extraRebateRatio = userRebateExtra(_pid, user.amount);
            if (_extraRebateRatio < user.extraRebateRatio) {
                user.extraRebateRatio = _extraRebateRatio;
            }
        }
        user.rewardDebt = totalReward(_pid, msg.sender);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // User total reward
    function totalReward(uint256 _pid, address _addr) internal view returns (uint256){
        UserInfo storage _user = userInfo[_pid][_addr];
        return _user.amount.mul(poolInfo[_pid].accRewardPerShare).div(DECIMALS).add(_user.refRewardDebt).add(_user.yieldRewardDebt);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        delete userInfo[_pid][msg.sender];
    }

    // Safe SOVI transfer function, just in case if rounding error causes pool to not have enough SOVIs.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 bal = SOVI.balanceOf(address(this));
        if (_amount > bal) {
            SOVI.transfer(_to, bal);
        } else {
            SOVI.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devAddr) external {
        require(msg.sender == devAddr, "dev: wut?");
        devAddr = _devAddr;
    }
}
