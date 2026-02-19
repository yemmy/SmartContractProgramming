// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * School Management System
 * - Register students & staff
 * - Pay school fees on registration (or later)
 * - Pay staff salaries from contract balance
 * - Pricing based on level: 100, 200, 300, 400
 * - Payment status updates include timestamp
 *
 * Notes:
 * - Fees are paid in ETH (msg.value). we can set per-level fees later.
 * - Staff salary payments are paid in ETH from the contract balance.
 * - Uses simple owner-based admin access control.
 */
contract SchoolManagement {
    // -------------------------
    // Access Control (Owner)
    // -------------------------
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    // -------------------------
    // Reentrancy Guard
    // -------------------------
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrancy");
        _locked = 2;
        _;
        _locked = 1;
    }

    // -------------------------
    // Domain Models
    // -------------------------
    enum Level {
        L100,
        L200,
        L300,
        L400
    }

    struct PaymentInfo {
        bool paid;
        uint256 amountPaid;     // total paid so far (supports top-up)
        uint256 paidAt;         // last payment timestamp (0 if never)
    }

    struct Student {
        uint256 id;
        string fullName;
        address wallet;
        Level level;
        PaymentInfo feePayment;
        uint256 createdAt;
        bool exists;
    }

    struct Staff {
        uint256 id;
        string fullName;
        address wallet;
        string role;            // e.g., "Teacher", "Accountant"
        uint256 salaryWei;      // salary amount (in wei)
        uint256 lastPaidAt;     // timestamp of last salary payment (0 if never)
        uint256 createdAt;
        bool exists;
    }

    // -------------------------
    // Storage
    // -------------------------
    uint256 private _studentSeq;
    uint256 private _staffSeq;

    // Per-level fee in wei
    mapping(Level => uint256) public levelFeeWei;

    // Records
    mapping(uint256 => Student) private studentsById;
    mapping(uint256 => Staff) private staffsById;

    // Index lists (for enumeration)
    uint256[] private studentIds;
    uint256[] private staffIds;

    // Optional: Prevent duplicate wallets registering multiple times
    mapping(address => uint256) public studentIdByWallet; // 0 if none (since ids start at 1)
    mapping(address => uint256) public staffIdByWallet;   // 0 if none

    // -------------------------
    // Events
    // -------------------------
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    event LevelFeeSet(uint8 indexed level, uint256 feeWei);

    event StudentRegistered(
        uint256 indexed studentId,
        address indexed wallet,
        uint8 level,
        uint256 feeRequiredWei,
        uint256 paidWei,
        bool paid,
        uint256 timestamp
    );

    event StudentFeePaid(
        uint256 indexed studentId,
        address indexed payer,
        uint256 amountWei,
        uint256 totalPaidWei,
        bool paid,
        uint256 timestamp
    );

    event StaffRegistered(
        uint256 indexed staffId,
        address indexed wallet,
        uint256 salaryWei,
        uint256 timestamp
    );

    event StaffPaid(
        uint256 indexed staffId,
        address indexed wallet,
        uint256 salaryWei,
        uint256 timestamp
    );

    event Withdrawn(address indexed to, uint256 amountWei);

    // -------------------------
    // Constructor
    // -------------------------
    constructor() {
        owner = msg.sender;

        // Default fees (you can change later)
        levelFeeWei[Level.L100] = 0.01 ether;
        levelFeeWei[Level.L200] = 0.02 ether;
        levelFeeWei[Level.L300] = 0.03 ether;
        levelFeeWei[Level.L400] = 0.04 ether;
    }

    // -------------------------
    // Admin / Config
    // -------------------------
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setLevelFee(Level level, uint256 feeWei) external onlyOwner {
        levelFeeWei[level] = feeWei;
        emit LevelFeeSet(uint8(level), feeWei);
    }

    // -------------------------
    // Student Operations
    // -------------------------

    /**
     * Register a student and (optionally) pay fees immediately.
     * Requirement: "Pay School fees on registration."
     * - If you want to enforce full payment on registration, set `requireFullPayment=true`.
     */
    function registerStudent(
        string calldata fullName,
        address wallet,
        Level level,
        bool requireFullPayment
    ) external payable nonReentrant returns (uint256 studentId) {
        require(wallet != address(0), "Zero wallet");
        require(studentIdByWallet[wallet] == 0, "Student wallet already registered");

        uint256 required = levelFeeWei[level];
        require(required > 0, "Fee not set");

        if (requireFullPayment) {
            require(msg.value >= required, "Insufficient fee on registration");
        }

        _studentSeq += 1;
        studentId = _studentSeq;

        Student storage s = studentsById[studentId];
        s.id = studentId;
        s.fullName = fullName;
        s.wallet = wallet;
        s.level = level;
        s.createdAt = block.timestamp;
        s.exists = true;

        studentIds.push(studentId);
        studentIdByWallet[wallet] = studentId;

        // If paid anything at registration, record it
        if (msg.value > 0) {
            _applyStudentPayment(s, required, msg.value);
            emit StudentFeePaid(
                studentId,
                msg.sender,
                msg.value,
                s.feePayment.amountPaid,
                s.feePayment.paid,
                s.feePayment.paidAt
            );
        }

        emit StudentRegistered(
            studentId,
            wallet,
            uint8(level),
            required,
            msg.value,
            s.feePayment.paid,
            block.timestamp
        );

        // Refund overpayment (optional)
        if (msg.value > required && requireFullPayment) {
            uint256 refund = msg.value - required;
            (bool ok, ) = payable(msg.sender).call{value: refund}("");
            require(ok, "Refund failed");
        }
    }

    /**
     * Pay (or top-up) student fees after registration.
     * Updates status + timestamp when the required fee is met.
     */
    function payStudentFees(uint256 studentId) external payable nonReentrant {
        require(msg.value > 0, "No payment");
        Student storage s = studentsById[studentId];
        require(s.exists, "Student not found");

        uint256 required = levelFeeWei[s.level];
        require(required > 0, "Fee not set");

        _applyStudentPayment(s, required, msg.value);

        emit StudentFeePaid(
            studentId,
            msg.sender,
            msg.value,
            s.feePayment.amountPaid,
            s.feePayment.paid,
            s.feePayment.paidAt
        );
    }

    /**
     * Owner can manually mark a student as paid (e.g., paid off-chain),
     * while still recording a timestamp.
     * This does NOT move any funds.
     */
    function markStudentPaidManually(uint256 studentId, uint256 paidAtTimestamp) external onlyOwner {
        Student storage s = studentsById[studentId];
        require(s.exists, "Student not found");

        s.feePayment.paid = true;
        s.feePayment.paidAt = paidAtTimestamp == 0 ? block.timestamp : paidAtTimestamp;
        // amountPaid remains as-is (or could be set by owner if you want)
    }

    function getStudent(uint256 studentId) external view returns (Student memory) {
        Student storage s = studentsById[studentId];
        require(s.exists, "Student not found");
        return s;
    }

    function getStudentsCount() external view returns (uint256) {
        return studentIds.length;
    }

    /**
     * Get students paged (recommended instead of returning all, to avoid gas issues).
     * start is index into studentIds, count is max returned.
     */
    function getStudents(uint256 start, uint256 count) external view returns (Student[] memory page) {
        uint256 n = studentIds.length;
          if (start >= n) {
             return new Student[](0);
        }

        uint256 end = start + count;
        if (end > n) end = n;

        page = new Student[](end - start);
        uint256 j = 0;
        for (uint256 i = start; i < end; i++) {
            page[j] = studentsById[studentIds[i]];
            j++;
        }
    }

    // -------------------------
    // Staff Operations
    // -------------------------

    function registerStaff(
        string calldata fullName,
        address wallet,
        string calldata role,
        uint256 salaryWei
    ) external onlyOwner returns (uint256 staffId) {
        require(wallet != address(0), "Zero wallet");
        require(staffIdByWallet[wallet] == 0, "Staff wallet already registered");
        require(salaryWei > 0, "Salary must be > 0");

        _staffSeq += 1;
        staffId = _staffSeq;

        Staff storage st = staffsById[staffId];
        st.id = staffId;
        st.fullName = fullName;
        st.wallet = wallet;
        st.role = role;
        st.salaryWei = salaryWei;
        st.createdAt = block.timestamp;
        st.exists = true;

        staffIds.push(staffId);
        staffIdByWallet[wallet] = staffId;

        emit StaffRegistered(staffId, wallet, salaryWei, block.timestamp);
    }

    function updateStaffSalary(uint256 staffId, uint256 newSalaryWei) external onlyOwner {
        require(newSalaryWei > 0, "Salary must be > 0");
        Staff storage st = staffsById[staffId];
        require(st.exists, "Staff not found");
        st.salaryWei = newSalaryWei;
    }

    /**
     * Pay a staff salary from contract balance.
     * Requirement: "Pay staffs also."
     */
    function payStaff(uint256 staffId) external onlyOwner nonReentrant {
        Staff storage st = staffsById[staffId];
        require(st.exists, "Staff not found");

        uint256 amount = st.salaryWei;
        require(address(this).balance >= amount, "Insufficient contract balance");

        st.lastPaidAt = block.timestamp;

        (bool ok, ) = payable(st.wallet).call{value: amount}("");
        require(ok, "Salary transfer failed");

        emit StaffPaid(staffId, st.wallet, amount, st.lastPaidAt);
    }

    function getStaff(uint256 staffId) external view returns (Staff memory) {
        Staff storage st = staffsById[staffId];
        require(st.exists, "Staff not found");
        return st;
    }

    function getStaffCount() external view returns (uint256) {
        return staffIds.length;
    }

    function getStaffs(uint256 start, uint256 count) external view returns (Staff[] memory page) {
        uint256 n = staffIds.length;
        if (start >= n) {
            return new Staff[](0);
        }

        uint256 end = start + count;
        if (end > n) end = n;

        page = new Staff[](end - start);
        uint256 j = 0;
        for (uint256 i = start; i < end; i++) {
            page[j] = staffsById[staffIds[i]];
            j++;
        }
    }

    // -------------------------
    // Finance / Treasury
    // -------------------------

    /// Allow contract to receive ETH (fees funding salary pool)
    receive() external payable {}

    /**
     * Withdraw surplus funds (e.g., to school treasury wallet).
     */
    function withdraw(address to, uint256 amountWei) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        require(amountWei > 0, "Amount must be > 0");
        require(address(this).balance >= amountWei, "Insufficient balance");

        (bool ok, ) = payable(to).call{value: amountWei}("");
        require(ok, "Withdraw failed");

        emit Withdrawn(to, amountWei);
    }

    // -------------------------
    // Internals
    // -------------------------
    function _applyStudentPayment(Student storage s, uint256 required, uint256 amountPaidNow) internal {
        // Accumulate
        s.feePayment.amountPaid += amountPaidNow;

        // Mark paid and set timestamp when requirement is met
        if (!s.feePayment.paid && s.feePayment.amountPaid >= required) {
            s.feePayment.paid = true;
            s.feePayment.paidAt = block.timestamp;
        } else if (s.feePayment.paid) {
            // If already paid, still update "last payment time" for audit
            s.feePayment.paidAt = block.timestamp;
        }
    }
}
