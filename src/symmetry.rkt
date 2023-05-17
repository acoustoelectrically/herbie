#lang racket
(require "common.rkt" "programs.rkt" "core/simplify.rkt" "syntax/rules.rkt" "core/egg-herbie.rkt")

(provide connected-components)

(define (get-swaps vars expr)
  (define swapt
    (for/list ([swap (in-combinations vars 2)])
      (match-define (list a b) swap)
      (replace-vars (list (cons a b) (cons b a)) expr)))
  (define out (map last
                   (simplify-batch (make-egg-query (cons expr swapt) (*simplify-rules*)) #t)))
  (match-define (cons orig swapt*) out)
  (for/list ([swap* swapt*] [swap (in-combinations vars 2)]
             #:when (equal? swap* orig))
    swap))

(define (connected-components expr)
  (define vars (program-variables expr))
  (define body (program-body expr))

  (define swaps (get-swaps vars body))
  (define rules*
    (for/list ([swap swaps])
      (match-define (list a b) swap)
      (rule (string->symbol (format "swap-~a-~a" a b))
            (index-of vars a)
            (index-of vars b)
            '()
            'real)))
  (define groups (map last
                      (simplify-batch (make-egg-query (range (length vars)) rules*) #f)))
  (map (lambda (group) (map car group)) (group-by cdr (map cons vars groups))))



