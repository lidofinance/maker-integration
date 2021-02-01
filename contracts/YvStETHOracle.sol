pragma solidity ^0.6.11;

interface OracleLike {
    function read() external view returns (uint256);
}

interface StEthLike {
    function totalSupply() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
}

interface StableSwapLike {
    function balances(uint256 i) external view returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

contract YvStETHOracle {

    // --- Auth ---
    mapping (address => uint256) public wards;                                       // Addresses with admin authority
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }  // Add admin
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }  // Remove admin
    modifier auth {
        require(wards[msg.sender] == 1, "YvStETHOracle/not-authorized");
        _;
    }

    address public orb;             // Oracle for ETHUSD price, ideally a Medianizer
    uint16  public hop = 1 hours;   // Minimum time inbetween price updates
    uint64  public zzz;             // Time of last price update
    bytes32 public immutable wat;   // Token whose price is being tracked

    // --- Whitelisting ---
    mapping (address => uint256) public bud;
    modifier toll { require(bud[msg.sender] == 1, "YvStETHOracle/contract-not-whitelisted"); _; }

    struct Feed {
        uint128 val;  // Price
        uint128 has;  // Is price valid
    }

    Feed public cur;  // Current price  (mem slot 0x3)
    Feed public nxt;  // Queued price   (mem slot 0x4)

    uint128 low  = 7 * (10 ** 17); // Minimum stETH/ETH price
    uint128 high = 10 ** 18;       // Maximum stETH/ETH price

    // --- Stop ---
    uint256 public stopped;  // Stop/start ability to read
    modifier stoppable { require(stopped == 0, "YvStETHOracle/is-stopped"); _; }

    // --- Const config ---
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant SWAP  = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    int128 constant SWAP_ETH = 0;
    int128 constant SWAP_STETH = 1;

    // --- Math ---
    uint256 constant WAD = 10 ** 18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Step(uint256 hop);
    event Stop();
    event Start();
    event Frame(uint256 low, uint256 high);
    event Value(uint128 curVal, uint128 nxtVal);
    event Link(address orb);

    // --- Init ---
    constructor (bytes32 _wat, address _orb) public {
        require(_orb != address(0),  "YvStETHOracle/invalid-oracle-address");
        wards[msg.sender] = 1;
        zzz = 0;
        wat = _wat;
        orb = _orb;
    }

    function stop() external auth {
        stopped = 1;
        emit Stop();
    }

    function start() external auth {
        stopped = 0;
        emit Start();
    }

    function step(uint256 _hop) external auth {
        require(_hop <= uint16(-1), "YvStETHOracle/invalid-hop");
        hop = uint16(_hop);
        emit Step(hop);
    }

    function link(address _orb) external auth {
        require(orb != address(0), "YvStETHOracle/no-contract-0");
        orb = _orb;
        emit Link(_orb);
    }

    function frame(uint256 _low, uint256 _high) external auth {
        require(_low <= uint128(-1), "YvStETHOracle/invalid-low");
        require(_high <= uint128(-1), "YvStETHOracle/invalid-high");
        require(_low <= _high, "YvStETHOracle/invalid-frame");
        low = uint128(_low);
        high = uint128(_high);
        emit Frame(_low, _high);
    }

    function pass() public view returns (bool ok) {
        return block.timestamp >= add(zzz, hop);
    }

    function seek() internal returns (uint128 quote, uint32 ts) {
        // Assert reserves of the Curve liquidity pool
        uint256 res0 = StableSwapLike(SWAP).balances(uint256(SWAP_ETH));
        uint256 res1 = StableSwapLike(SWAP).balances(uint256(SWAP_STETH));
        require(res0 != 0 && res1 != 0, "YvStETHOracle/invalid-reserves");

        // Query ETHUSD price from oracle (WAD)
        uint256 val = OracleLike(orb).read();
        require(val != 0, "YvStETHOracle/invalid-oracle-price");

        // Query stETH total supply and total shares (both WAD)
        uint256 supply = StEthLike(STETH).totalSupply();
        uint256 shares = StEthLike(STETH).getTotalShares();

        // Calc the amount of ETH received for one stETH (WAD)
        uint256 eth = min(high, max(low, StableSwapLike(SWAP).get_dy(SWAP_STETH, SWAP_ETH, WAD)));

        // Calc the amount of USD received for one stETH share (WAD)
        // usdPerShare = usdPerEther * (etherPerToken * totalTokens / totalShares)
        quote = uint128(
            mul(
                val,
                mul(eth, supply) / shares
            ) / WAD
        );

        ts = uint32(block.timestamp);
    }

    function poke() external stoppable {
        require(pass(), "YvStETHOracle/not-passed");
        (uint256 val, uint32 ts) = seek();
        require(val != 0, "YvStETHOracle/invalid-price");
        cur = nxt;
        nxt = Feed(uint128(val), 1);
        zzz = ts;
        emit Value(cur.val, nxt.val);
    }

    function peek() external view toll returns (bytes32,bool) {
        return (bytes32(uint256(cur.val)), cur.has == 1);
    }

    function peep() external view toll returns (bytes32,bool) {
        return (bytes32(uint256(nxt.val)), nxt.has == 1);
    }

    function read() external view toll returns (bytes32) {
        require(cur.has == 1, "YvStETHOracle/no-current-value");
        return (bytes32(uint256(cur.val)));
    }

    function kiss(address a) external auth {
        require(a != address(0), "YvStETHOracle/no-contract-0");
        bud[a] = 1;
    }

    function kiss(address[] calldata a) external auth {
        for(uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "YvStETHOracle/no-contract-0");
            bud[a[i]] = 1;
        }
    }

    function diss(address a) external auth {
        bud[a] = 0;
    }

    function diss(address[] calldata a) external auth {
        for(uint256 i = 0; i < a.length; i++) {
            bud[a[i]] = 0;
        }
    }
}
