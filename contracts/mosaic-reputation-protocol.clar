;; Mind Mosaic  - Borderless Expertise Protocol
;; This contract enables a tokenless economy of intellectual capital transfer.

;; =============================
;; Reputation Framework
;; =============================

;; Reputation System Data Structures
(define-map contributor-reputation-assessments {contributor: principal, assessor: principal} uint)
(define-map contributor-assessment-frequency principal uint)
(define-map contributor-cumulative-assessment principal uint)

;; =============================
;; Administrative Configuration
;; =============================

;; Foundational Error Codes
(define-constant admin-only-err (err u410))
(define-constant inadequate-resources-err (err u411))
(define-constant invalid-contribution-err (err u412))
(define-constant invalid-compensation-err (err u413))
(define-constant capacity-threshold-reached-err (err u414))
(define-constant unauthorized-participant-err (err u415))

;; Administrative Address
(define-constant protocol-steward tx-sender)

;; =============================
;; Global Protocol Parameters
;; =============================

;; Data Variables for Protocol Configuration
(define-data-var contribution-valuation uint u10)  ;; Base valuation for contributions
(define-data-var participant-max-contributions uint u100)  ;; Maximum contributions allowed per participant
(define-data-var protocol-maintenance-allocation uint u10)  ;; Percentage allocated for protocol maintenance
(define-data-var ecosystem-contribution-pool uint u0)  ;; Total contributions available in ecosystem
(define-data-var ecosystem-capacity-ceiling uint u1000)  ;; Maximum capacity of contribution ecosystem

;; =============================
;; Participant Data Structures
;; =============================

;; Account Resource Tracking
(define-map participant-contribution-repository principal uint)  ;; Tracks contributions owned by participants
(define-map participant-token-repository principal uint)  ;; Tracks tokens owned by participants
(define-map available-contributions {contributor: principal} {contribution-units: uint, compensation-rate: uint})  ;; Tracks contributions available for exchange


;; =============================
;; Exchange Protocol Records
;; =============================

;; Exchange Proposal Tracking
(define-map contribution-exchange-proposals 
  {identifier: uint} 
  {
    seeker: principal,
    contributor: principal,
    units: uint,
    compensation: uint,
    state: uint,  ;; 0=awaiting response, 1=approved, 2=declined, 3=fulfilled
    timestamp: uint
  }
)
(define-data-var proposal-sequence-counter uint u1)

;; =============================
;; Internal Utility Functions
;; =============================

;; Calculate maintenance allocation for protocol sustainability
(define-private (determine-maintenance-allocation (value uint))
  (/ (* value (var-get protocol-maintenance-allocation)) u100))

;; Modify the ecosystem contribution pool
(define-private (modify-ecosystem-capacity (change int))
  (let (
    (current-capacity (var-get ecosystem-contribution-pool))
    (new-capacity (if (< change 0)
                    (if (>= current-capacity (to-uint (- 0 change)))
                        (- current-capacity (to-uint (- 0 change)))
                        u0)
                    (+ current-capacity (to-uint change))))
  )
    (asserts! (<= new-capacity (var-get ecosystem-capacity-ceiling)) capacity-threshold-reached-err)
    (var-set ecosystem-contribution-pool new-capacity)
    (ok true)))

;; =============================
;; Contribution Management
;; =============================

;; Register new contributions to participant account
;; Allows participants to register new contribution units they can offer
;; @param units: the number of contribution units to register
(define-public (register-contributions (units uint))
  (let (
    (current-repository (default-to u0 (map-get? participant-contribution-repository tx-sender)))
    (max-contributions (var-get participant-max-contributions))
    (updated-repository (+ current-repository units))
  )
    (asserts! (> units u0) invalid-contribution-err)  ;; Ensure units are greater than 0
    (asserts! (<= updated-repository max-contributions) (err u421))  ;; Ensure participant doesn't exceed max contributions
    (map-set participant-contribution-repository tx-sender updated-repository)
    (ok updated-repository)))

;; Make contributions available for exchange
;; @param units: contribution units to make available
;; @param compensation: requested compensation rate per unit
(define-public (offer-contributions-for-exchange (units uint) (compensation uint))
  (let (
    (current-repository (default-to u0 (map-get? participant-contribution-repository tx-sender)))
    (current-offered (get contribution-units (default-to {contribution-units: u0, compensation-rate: u0} 
                      (map-get? available-contributions {contributor: tx-sender}))))
    (total-offered (+ units current-offered))
  )
    (asserts! (> units u0) invalid-contribution-err)  ;; Ensure units are greater than 0
    (asserts! (> compensation u0) invalid-compensation-err)  ;; Ensure compensation is greater than 0
    (asserts! (>= current-repository total-offered) inadequate-resources-err)
    (try! (modify-ecosystem-capacity (to-int units)))
    (map-set available-contributions {contributor: tx-sender} 
             {contribution-units: total-offered, compensation-rate: compensation})
    (ok true)))

;; Remove contributions from exchange pool
;; @param units: contribution units to remove from availability
(define-public (withdraw-contributions-from-exchange (units uint))
  (let (
    (current-offered (get contribution-units (default-to {contribution-units: u0, compensation-rate: u0} 
                      (map-get? available-contributions {contributor: tx-sender}))))
  )
    (asserts! (>= current-offered units) inadequate-resources-err)
    (try! (modify-ecosystem-capacity (to-int (- units))))
    (map-set available-contributions {contributor: tx-sender} 
             {contribution-units: (- current-offered units), 
              compensation-rate: (get compensation-rate (default-to {contribution-units: u0, compensation-rate: u0} 
                                 (map-get? available-contributions {contributor: tx-sender})))})
    (ok true)))

;; =============================
;; Exchange Mechanisms
;; =============================

;; Direct exchange of contributions
;; @param contributor: principal of the contribution provider
;; @param units: number of contribution units requested
(define-public (exchange-contributions (contributor principal) (units uint))
  (let (
    (exchange-info (default-to {contribution-units: u0, compensation-rate: u0} 
                   (map-get? available-contributions {contributor: contributor})))
    (exchange-value (* units (get compensation-rate exchange-info)))
    (maintenance-fee (determine-maintenance-allocation exchange-value))
    (total-exchange-cost (+ exchange-value maintenance-fee))
    (contributor-repository (default-to u0 (map-get? participant-contribution-repository contributor)))
    (seeker-tokens (default-to u0 (map-get? participant-token-repository tx-sender)))
    (contributor-tokens (default-to u0 (map-get? participant-token-repository contributor)))
  )
    (asserts! (not (is-eq tx-sender contributor)) unauthorized-participant-err)
    (asserts! (> units u0) invalid-contribution-err)  ;; Ensure units are greater than 0
    (asserts! (>= (get contribution-units exchange-info) units) inadequate-resources-err)
    (asserts! (>= contributor-repository units) inadequate-resources-err)
    (asserts! (>= seeker-tokens total-exchange-cost) inadequate-resources-err)

    ;; Update contributor's contribution repository and available units
    (map-set participant-contribution-repository contributor (- contributor-repository units))
    (map-set available-contributions {contributor: contributor} 
             {contribution-units: (- (get contribution-units exchange-info) units), 
              compensation-rate: (get compensation-rate exchange-info)})

    ;; Update seeker's tokens and contribution repository
    (map-set participant-token-repository tx-sender (- seeker-tokens total-exchange-cost))
    (map-set participant-contribution-repository tx-sender 
             (+ (default-to u0 (map-get? participant-contribution-repository tx-sender)) units))

    ;; Update contributor's token repository
    (map-set participant-token-repository contributor (+ contributor-tokens exchange-value))

    ;; Update protocol steward's token repository for the maintenance fee
    (map-set participant-token-repository protocol-steward 
             (+ (default-to u0 (map-get? participant-token-repository protocol-steward)) maintenance-fee))

    (ok true)))

;; Deposit tokens into platform for future exchanges
;; @param amount: the amount of tokens (in micro units) to deposit
(define-public (deposit-tokens (amount uint))
  (let (
    (sender tx-sender)
    (current-balance (default-to u0 (map-get? participant-token-repository sender)))
    (new-balance (+ current-balance amount))
  )
    (asserts! (> amount u0) (err u420))  ;; Ensure deposit amount is greater than 0
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    (map-set participant-token-repository sender new-balance)
    (ok new-balance)))

;; =============================
;; Protocol Governance Functions
;; =============================

;; Update protocol configuration parameters
;; @param new-contribution-value: new base value for contributions
;; @param new-max-contributions: new maximum contribution limit per participant
;; @param new-maintenance-allocation: new maintenance allocation percentage
;; @param new-capacity-ceiling: new ecosystem capacity ceiling
(define-public (update-protocol-configuration 
                (new-contribution-value uint) 
                (new-max-contributions uint) 
                (new-maintenance-allocation uint) 
                (new-capacity-ceiling uint))
  (begin
    (asserts! (is-eq tx-sender protocol-steward) admin-only-err)
    (asserts! (<= new-maintenance-allocation u100) (err u422))  ;; Ensure maintenance allocation doesn't exceed 100%
    (asserts! (> new-contribution-value u0) invalid-compensation-err)  ;; Ensure contribution value is positive
    (asserts! (> new-max-contributions u0) (err u423))  ;; Ensure max contributions is positive
    (asserts! (>= new-capacity-ceiling (var-get ecosystem-contribution-pool)) (err u424))  ;; Ensure new ceiling accommodates current pool

    (var-set contribution-valuation new-contribution-value)
    (var-set participant-max-contributions new-max-contributions)
    (var-set protocol-maintenance-allocation new-maintenance-allocation)
    (var-set ecosystem-capacity-ceiling new-capacity-ceiling)

    (ok true)))

;; =============================
;; Reputation System Functions
;; =============================

;; Assess a contribution provider
;; @param contributor: the principal of the provider being assessed
;; @param assessment: the assessment score (1-5) given to the provider
(define-public (assess-contributor (contributor principal) (assessment uint))
  (let (
    (assessor tx-sender)
    (current-assessment (default-to u0 (map-get? contributor-reputation-assessments 
                                      {contributor: contributor, assessor: assessor})))
    (assessment-count (default-to u0 (map-get? contributor-assessment-frequency contributor)))
    (assessment-total (default-to u0 (map-get? contributor-cumulative-assessment contributor)))
    (updated-count (if (is-eq current-assessment u0) (+ assessment-count u1) assessment-count))
    (updated-total (+ (- assessment-total current-assessment) assessment))
  )
    (asserts! (not (is-eq assessor contributor)) unauthorized-participant-err)  ;; Cannot assess self
    (asserts! (and (>= assessment u1) (<= assessment u5)) (err u425))  ;; Assessment must be between 1-5

    ;; Update assessment records
    (map-set contributor-reputation-assessments {contributor: contributor, assessor: assessor} assessment)
    (map-set contributor-assessment-frequency contributor updated-count)
    (map-set contributor-cumulative-assessment contributor updated-total)

    (ok true)))

;; =============================
;; Exchange Proposal System
;; =============================

;; Create a proposal for contribution exchange
;; @param contributor: principal of the contribution provider
;; @param units: number of contribution units requested
;; @param proposed-compensation: compensation rate proposed for the exchange
(define-public (create-contribution-proposal (contributor principal) (units uint) (proposed-compensation uint))
  (let (
    (seeker tx-sender)
    (identifier (var-get proposal-sequence-counter))
    (exchange-info (default-to {contribution-units: u0, compensation-rate: u0} 
                   (map-get? available-contributions {contributor: contributor})))
    (exchange-value (* units proposed-compensation))
    (maintenance-fee (determine-maintenance-allocation exchange-value))
    (total-cost (+ exchange-value maintenance-fee))
    (seeker-balance (default-to u0 (map-get? participant-token-repository seeker)))
  )
    (asserts! (not (is-eq seeker contributor)) unauthorized-participant-err)  ;; Cannot propose to self
    (asserts! (> units u0) invalid-contribution-err)  ;; Units must be positive
    (asserts! (>= (get contribution-units exchange-info) units) inadequate-resources-err)  ;; Contributor must have enough units
    (asserts! (> proposed-compensation u0) invalid-compensation-err)  ;; Compensation must be positive
    (asserts! (>= seeker-balance total-cost) inadequate-resources-err)  ;; Seeker must have enough balance

    ;; Create the proposal
    (map-set contribution-exchange-proposals
      {identifier: identifier}
      {
        seeker: seeker,
        contributor: contributor,
        units: units,
        compensation: proposed-compensation,
        state: u0,  ;; awaiting response
        timestamp: block-height
      }
    )

    ;; Reserve tokens for the proposal
    (map-set participant-token-repository seeker (- seeker-balance total-cost))

    ;; Update proposal identifier counter
    (var-set proposal-sequence-counter (+ identifier u1))

    (ok identifier)))

