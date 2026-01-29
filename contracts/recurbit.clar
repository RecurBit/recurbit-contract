
;; title: recurbit
;; version: 1.0
;; summary: Automated Bitcoin Dollar Cost Averaging (DCA) service
;; description: Allows users to schedule and automate Bitcoin purchases on Stacks.

;; traits
;;

;; token definitions
;;

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-plan-paused (err u106))
(define-constant err-too-early (err u107))

;; Fixed exchange rate for simulation: 1 STX = 1000 Sats (example)
;; In reality this would come from an oracle
(define-constant SIMULATED-BTC-PRICE-STX u50) ;; 50 STX per BTC (very cheap for testing!) or similar ratio

;; data vars
(define-data-var next-plan-id uint u1)
(define-data-var next-purchase-id uint u1)
(define-data-var counter uint u0) ;; Utility counter

;; data maps
(define-map dca-plans
    uint
    {
        owner: principal,
        frequency-blocks: uint, ;; simplifying "frequency" to blocks for MVP
        amount-per-purchase: uint,
        total-deposited: uint,
        total-spent: uint,
        bitcoin-acquired: uint,
        purchases-completed: uint,
        next-purchase-block: uint,
        status: (string-ascii 10), ;; "active", "paused", "cancelled"
        created-at: uint
    }
)

(define-map purchase-history
    uint
    {
        plan-id: uint,
        block-height: uint,
        stx-spent: uint,
        btc-acquired: uint,
        btc-price: uint,
        timestamp: uint
    }
)

(define-map user-stats
    principal
    {
        total-plans: uint,
        active-plans: uint,
        total-invested: uint,
        total-btc-acquired: uint
    }
)

;; public functions

;; Utility Counter Logic (Requested)
(define-public (count-up)
    (begin
        (var-set counter (+ (var-get counter) u1))
        (ok (var-get counter))
    )
)

(define-read-only (get-counter)
    (ok (var-get counter))
)

;; Core DCA Functions

(define-public (create-dca-plan (frequency-blocks uint) (amount uint) (start-delay uint))
    (let
        (
            (plan-id (var-get next-plan-id))
            (start-block (+ block-height start-delay))
        )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (> frequency-blocks u0) err-invalid-amount)

        (map-set dca-plans plan-id
            {
                owner: tx-sender,
                frequency-blocks: frequency-blocks,
                amount-per-purchase: amount,
                total-deposited: u0,
                total-spent: u0,
                bitcoin-acquired: u0,
                purchases-completed: u0,
                next-purchase-block: start-block,
                status: "active",
                created-at: block-height
            }
        )
        
        ;; Update user stats
        (let
            ((stats (default-to { total-plans: u0, active-plans: u0, total-invested: u0, total-btc-acquired: u0 } (map-get? user-stats tx-sender))))
            (map-set user-stats tx-sender
                (merge stats {
                    total-plans: (+ (get total-plans stats) u1),
                    active-plans: (+ (get active-plans stats) u1)
                })
            )
        )

        (var-set next-plan-id (+ plan-id u1))
        (ok plan-id)
    )
)

(define-public (deposit-funds (plan-id uint) (amount uint))
    (let
        (
            (plan (unwrap! (map-get? dca-plans plan-id) err-not-found))
        )
        (asserts! (> amount u0) err-invalid-amount)
        ;; Transfer STX from user to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update plan balance info
        (map-set dca-plans plan-id
            (merge plan {
                total-deposited: (+ (get total-deposited plan) amount)
            })
        )
        (ok true)
    )
)

(define-public (execute-purchase (plan-id uint))
    (let
        (
            (plan (unwrap! (map-get? dca-plans plan-id) err-not-found))
            (amount (get amount-per-purchase plan))
            (balance (- (get total-deposited plan) (get total-spent plan)))
            (is-active (is-eq (get status plan) "active"))
            (is-due (>= block-height (get next-purchase-block plan)))
        )
        (asserts! is-active err-plan-paused)
        (asserts! is-due err-too-early)
        (asserts! (>= balance amount) err-insufficient-balance)

        ;; Calculate BTC amount (Simulated exchange)
        ;; For simplicity, 1 STX = 1 MockBTC unit (adjusted by some factor if needed)
        ;; Let's say 1 STX buys 100 MockSatoshis
        (let
             (
                (btc-amount (* amount u100)) ;; Simulation rate
                (purchase-id (var-get next-purchase-id))
             )
             
             ;; Mint Mock BTC to the plan owner
             ;; We use contract-call? to the sibling contract
             (try! (contract-call? .mock-btc mint btc-amount (get owner plan)))

             ;; Record Purchase
             (map-set purchase-history purchase-id
                {
                    plan-id: plan-id,
                    block-height: block-height,
                    stx-spent: amount,
                    btc-acquired: btc-amount,
                    btc-price: u100, ;; simulated price
                    timestamp: u0 ;; clarity doesn't have native timestamp, usually rely on block-header or ignore
                }
             )

             ;; Update Plan
             (map-set dca-plans plan-id
                (merge plan {
                    total-spent: (+ (get total-spent plan) amount),
                    bitcoin-acquired: (+ (get bitcoin-acquired plan) btc-amount),
                    purchases-completed: (+ (get purchases-completed plan) u1),
                    next-purchase-block: (+ block-height (get frequency-blocks plan))
                })
             )

             (var-set next-purchase-id (+ purchase-id u1))
             (ok purchase-id)
        )
    )
)

;; read only functions

(define-read-only (get-plan (plan-id uint))
    (map-get? dca-plans plan-id)
)

(define-read-only (get-purchase-history (purchase-id uint))
    (map-get? purchase-history purchase-id)
)

(define-read-only (get-user-stats (user principal))
    (default-to { total-plans: u0, active-plans: u0, total-invested: u0, total-btc-acquired: u0 } (map-get? user-stats user))
)
