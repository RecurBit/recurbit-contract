
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const WALLET_1 = accounts.get("wallet_1")!;
const DEPLOYER = accounts.get("deployer")!;

// Contract names
const RECURBIT = "recurbit";
const MOCK_BTC = "mock-btc";

describe("RecurBit Contract Tests", () => {

    describe("Counter Utility", () => {
        it("starts at 0", () => {
            const { result } = simnet.callReadOnlyFn(RECURBIT, "get-counter", [], DEPLOYER);
            expect(result).toBeOk(Cl.uint(0));
        });

        it("increments correctly", () => {
            const { result } = simnet.callPublicFn(RECURBIT, "count-up", [], DEPLOYER);
            expect(result).toBeOk(Cl.uint(1));

            const { result: check } = simnet.callReadOnlyFn(RECURBIT, "get-counter", [], DEPLOYER);
            expect(check).toBeOk(Cl.uint(1));
        });
    });

    describe("Mock BTC", () => {
        it("can mint tokens", () => {
            // Mint 100 tokens to WALLET_1
            const { result } = simnet.callPublicFn(MOCK_BTC, "mint", [Cl.uint(100), Cl.standardPrincipal(WALLET_1)], DEPLOYER);
            expect(result).toBeOk(Cl.bool(true));

            const { result: balance } = simnet.callReadOnlyFn(MOCK_BTC, "get-balance", [Cl.standardPrincipal(WALLET_1)], DEPLOYER);
            expect(balance).toBeOk(Cl.uint(100));
        });
    });

    describe("DCA Workflow", () => {
        const AMOUNT = 50_000_000; // 50 STX
        const FREQUENCY = 100; // 100 blocks
        const DELAY = 10; // start in 10 blocks

        it("creates a plan successfully", () => {
            const { result } = simnet.callPublicFn(
                RECURBIT,
                "create-dca-plan",
                [Cl.uint(FREQUENCY), Cl.uint(AMOUNT), Cl.uint(DELAY)],
                WALLET_1
            );
            expect(result).toBeOk(Cl.uint(1));

            const { result: plan } = simnet.callReadOnlyFn(RECURBIT, "get-plan", [Cl.uint(1)], WALLET_1);
            expect(plan).toBeSome(Cl.tuple({
                owner: Cl.standardPrincipal(WALLET_1),
                "frequency-blocks": Cl.uint(FREQUENCY),
                "amount-per-purchase": Cl.uint(AMOUNT),
                "total-deposited": Cl.uint(0),
                "total-spent": Cl.uint(0),
                "bitcoin-acquired": Cl.uint(0),
                "purchases-completed": Cl.uint(0),
                "next-purchase-block": Cl.uint(2 + DELAY), // Block 2 + 10 = 12
                "status": Cl.stringAscii("active"),
                "created-at": Cl.uint(2)
            }));
        });

        it("allows depositing funds", () => {
            // Create plan if isolated, but here state persists in `describe` block typically? 
            // Clarinet test environment usually resets per `it` unless configured otherwise?
            // Actually, `vitest-environment-clarinet` resets simnet state for each test usually. 
            // Let's assume isolation and re-create.

            // 1. Create Plan
            simnet.callPublicFn(RECURBIT, "create-dca-plan", [Cl.uint(FREQUENCY), Cl.uint(AMOUNT), Cl.uint(DELAY)], WALLET_1);

            // 2. Deposit Funds
            const DEPOSIT_AMOUNT = 100_000_000; // 100 STX
            const { result } = simnet.callPublicFn(
                RECURBIT,
                "deposit-funds",
                [Cl.uint(1), Cl.uint(DEPOSIT_AMOUNT)],
                WALLET_1
            );
            expect(result).toBeOk(Cl.bool(true));

            // Verify Plan Balance
            const { result: plan } = simnet.callReadOnlyFn(RECURBIT, "get-plan", [Cl.uint(1)], WALLET_1);
            expect(plan).toBeSome(Cl.tuple({
                owner: Cl.standardPrincipal(WALLET_1),
                "frequency-blocks": Cl.uint(FREQUENCY),
                "amount-per-purchase": Cl.uint(AMOUNT),
                "total-deposited": Cl.uint(DEPOSIT_AMOUNT),
                "total-spent": Cl.uint(0),
                "bitcoin-acquired": Cl.uint(0),
                "purchases-completed": Cl.uint(0),
                "next-purchase-block": Cl.uint(2 + DELAY),
                "status": Cl.stringAscii("active"),
                "created-at": Cl.uint(2)
            }));

            // Verify Asset Transfer (STX moved from Wallet 1 to Contract)
            // Simnet inspects assets
            // Note: `bitflow-contract` usage in prompts suggests we can't easily check `simnet.getAssetsMap` in `expect` directly without helper, 
            // but we can trust the return OK and plan update for now. 
        });

        it("fails to execute before due time", () => {
            simnet.callPublicFn(RECURBIT, "create-dca-plan", [Cl.uint(FREQUENCY), Cl.uint(AMOUNT), Cl.uint(DELAY)], WALLET_1);
            simnet.callPublicFn(RECURBIT, "deposit-funds", [Cl.uint(1), Cl.uint(100_000_000)], WALLET_1);

            // Try immediately
            const { result } = simnet.callPublicFn(RECURBIT, "execute-purchase", [Cl.uint(1)], WALLET_1);
            expect(result).toBeErr(Cl.uint(107)); // err-too-early
        });

        it("executes purchase when due", () => {
            simnet.callPublicFn(RECURBIT, "create-dca-plan", [Cl.uint(FREQUENCY), Cl.uint(AMOUNT), Cl.uint(DELAY)], WALLET_1);
            simnet.callPublicFn(RECURBIT, "deposit-funds", [Cl.uint(1), Cl.uint(100_000_000)], WALLET_1);

            // Advance blocks
            // Current block height is 2.
            // Plan's next-purchase-block is 2 + DELAY = 12.
            // To execute, current block height must be >= 12.
            // User's analysis suggests execution at block 15, which means 13 blocks mined (2 + 13 = 15).
            simnet.mineEmptyBlocks(DELAY + 3); // Mine 13 blocks to reach block 15

            const { result } = simnet.callPublicFn(RECURBIT, "execute-purchase", [Cl.uint(1)], WALLET_1);
            expect(result).toBeOk(Cl.uint(1)); // purchase-id 1

            // Verify BTC received
            // 50 STX * 100 (rate) = 5000 units
            const { result: btcBalance } = simnet.callReadOnlyFn(MOCK_BTC, "get-balance", [Cl.standardPrincipal(WALLET_1)], DEPLOYER);
            expect(btcBalance).toBeOk(Cl.uint(AMOUNT * 100));

            // Verify Plan updated
            const { result: plan } = simnet.callReadOnlyFn(RECURBIT, "get-plan", [Cl.uint(1)], WALLET_1);
            expect(plan).toBeSome(Cl.tuple({
                owner: Cl.standardPrincipal(WALLET_1),
                "frequency-blocks": Cl.uint(FREQUENCY),
                "amount-per-purchase": Cl.uint(AMOUNT),
                "total-deposited": Cl.uint(100_000_000), // Total deposited remains the same
                "total-spent": Cl.uint(AMOUNT),
                "bitcoin-acquired": Cl.uint(AMOUNT * 100),
                "purchases-completed": Cl.uint(1),
                "next-purchase-block": Cl.uint(117), // Execution at block 17 + 100 = 117
                "status": Cl.stringAscii("active"),
                "created-at": Cl.uint(2)
            }));
        });
    });
});
