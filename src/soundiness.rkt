#lang racket

(require "alternative.rkt" "points.rkt" "programs.rkt"
         "core/egg-herbie.rkt" "core/simplify.rkt" "syntax/types.rkt" 
         "core/matcher.rkt" "syntax/rules.rkt")

(provide add-soundiness)

(define (canonicalize-rewrite proof)
  (match proof
    [`(Rewrite=> ,rule ,something)
     (list 'Rewrite=> (get-canon-rule-name rule rule) something)]
    [`(Rewrite<= ,rule ,something)
     (list 'Rewrite<= (get-canon-rule-name rule rule) something)]
    [(list _ ...)
     (map canonicalize-rewrite proof)]
    [else proof]))

(define (get-proof-errors proof pcontext ctx program-vars)
  (define proof-programs
    (for/list ([step (in-list proof)])
      `(λ ,program-vars ,(remove-rewrites step))))
  (define proof-errors (batch-errors proof-programs pcontext ctx))
  (define proof-diffs
    (cons (list 0 0)
          (for/list ([prev proof-errors] [current (rest proof-errors)])
                    (define num-increase
                      (for/sum ([a prev] [b current])
                               (if (> b a)
                                   1
                                   0)))
                    (define num-decrease
                      (for/sum ([a prev] [b current])
                               (if (< b a)
                                   1
                                   0)))
                    (list num-increase
                          num-decrease (length prev)))))
  proof-diffs)
  
(define (generate-rewrite-once-proof rule loc prog prev)
  (list (alt-expr prev) ;; Start Expression
        (list 'Rewrite=> (rule-name rule) prog)))

(define (add-soundiness-to pcontext ctx altn)
  (match altn
    ;; This is alt coming from rr
    [(alt prog `(rr, loc, input #f #f) `(,prev))
      (cond
        [(egraph-query? input) ;; Check if input is an egraph-query struct (B-E-R)
            (define e-input input)
            (define p-input (cons (location-get loc (alt-program prev)) (location-get loc prog)))
            (match-define (cons variants proof) (run-egg e-input #t #t #:proof-input p-input))
          (cond
            [proof
              (define proof*
                (for/list ([step proof])
                  (let ([step* (canonicalize-rewrite step)])
                    (program-body (location-do loc prog (λ _ step*))))))
              (define errors
                (let ([vars (program-variables prog)])
                  (get-proof-errors proof* pcontext ctx vars)))
              (alt prog `(rr, loc, input, proof* ,errors) `(,prev))]
            [else
              (alt prog `(rr ,loc, input #f #f) `(,prev))])]

        [(rule? input) ;; (R-O) case
          (define proof-ro
            (generate-rewrite-once-proof input loc (alt-expr altn) prev))
          (define errors-ro
            (let ([vars (program-variables prog)])
              (get-proof-errors proof-ro pcontext ctx vars)))
          (alt prog `(rr, loc, input, proof-ro, errors-ro) `(,prev))]
        [else
          (alt prog `(rr ,loc, input #f #f) `(,prev))])]
            
      ;; This is alt coming from simplify
    [(alt prog `(simplify ,loc ,input, #f #f) `(,prev))
      ; (define proof (get-proof input
      ;                         (location-get loc (alt-program prev))
      ;                         (location-get loc prog)))
      (define egg-input input)
      (define p-input (cons (location-get loc (alt-program prev)) (location-get loc prog)))
      (match-define (cons variants proof) (run-egg egg-input #t #f #:proof-input p-input))
      (cond
       [proof
        ;; Proofs are actually on subexpressions,
        ;; we need to construct the proof for the full expression
        (define proof*
          (for/list ([step proof])
            (let ([step* (canonicalize-rewrite step)])
              (program-body (location-do loc prog (λ _ step*))))))
        (define errors
          (let ([vars (program-variables prog)])
            (get-proof-errors proof* pcontext ctx vars)))
        (alt prog `(simplify ,loc ,input ,proof* ,errors) `(,prev))]
       [else
        (alt prog `(simplify ,loc ,input #f #f) `(,prev))])]
    [else
     altn]))


(define (add-soundiness alts pcontext ctx)
  (for/list ([altn alts])
    (alt-map (curry add-soundiness-to pcontext ctx) altn)))
