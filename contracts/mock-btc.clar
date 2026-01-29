
;; Mock Bitcoin Token
;; A simple SIP-010-like token to simulate Bitcoin on Stacks for RecurBit

(define-fungible-token mock-btc)

(define-constant err-owner-only (err u100))
(define-constant contract-owner tx-sender)

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) (err u101))
        (try! (ft-transfer? mock-btc amount sender recipient))
        (match memo to-print (print to-print) 0x)
        (ok true)
    )
)

(define-public (mint (amount uint) (recipient principal))
    (begin
        ;; In a real scenario, this would be restricted. 
        ;; For simulation, we allow anyone to mint or maybe just the recurbit contract?
        ;; Let's restrict to contract owner or the recurbit contract (if we knew its principal).
        ;; For simplicity of "simulation" where the contract "buys" it, let's allow public minting 
        ;; or just keep it simple.
        (ft-mint? mock-btc amount recipient)
    )
)

(define-read-only (get-name)
    (ok "Mock Bitcoin")
)

(define-read-only (get-symbol)
    (ok "mBTC")
)

(define-read-only (get-decimals)
    (ok u8)
)

(define-read-only (get-balance (who principal))
    (ok (ft-get-balance mock-btc who))
)

(define-read-only (get-total-supply)
    (ok (ft-get-supply mock-btc))
)

(define-read-only (get-token-uri)
    (ok none)
)
