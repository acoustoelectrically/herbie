#lang racket

(require (only-in xml write-xexpr xexpr?)
         (only-in fpbench core->tex supported-by-lang?))
(require "../points.rkt" "../float.rkt" "../alternative.rkt" "../syntax/types.rkt"
         "../syntax/rules.rkt" "../core/bsearch.rkt" "../common.rkt"
         "common.rkt" "../syntax/sugar.rkt" "../programs.rkt")
(provide render-history)

(define (split-pcontext pcontext splitpoints alts ctx)
  (define preds (splitpoints->point-preds splitpoints alts ctx))

  (for/list ([pred preds])
    (define-values (pts* exs*)
      (for/lists (pts exs)
        ([(pt ex) (in-pcontext pcontext)] #:when (pred pt))
        (values pt ex)))

    ;; TODO: The (if) here just corrects for the possibility that we
    ;; might have sampled new points that include no points in a given
    ;; regime. Instead it would be best to continue sampling until we
    ;; actually have many points in each regime. That would require
    ;; breaking some abstraction boundaries right now so we haven't
    ;; done it yet.
    (if (null? pts*) pcontext (mk-pcontext pts* exs*))))

(struct interval (alt-idx start-point end-point expr))

(define (interval->string ival repr)
  (define start (interval-start-point ival))
  (define end (interval-end-point ival))
  (string-join
   (list
    (if start
        (format "~a < " (value->string start repr))
        "")
    (~a (interval-expr ival))
    (if (equal? end +nan.0)
        ""
        (format " < ~a" (value->string end repr))))))

(define (splice-proof-step step)
  (let/ec k
    (let loop ([expr step] [loc '()])
      (match expr
        [(list 'Rewrite=> rule sub)
         (define loc* (reverse loc))
         (k 'Rewrite=> rule loc* (location-do loc* step (λ _ sub)))]
        [(list 'Rewrite<= rule sub)
         (define loc* (reverse loc))
         (k 'Rewrite<= rule loc* (location-do loc* step (λ _ sub)))]
        [(list op args ...)
         (for ([arg (in-list args)] [i (in-naturals 1)])
           (loop arg (cons i loc)))]
        [_ (void)]))
    (k 'Goal #f #f step)))

;; Extracts render information from the proof
(define (compute-proof proof soundiness)
  (for/list ([step (in-list proof)] [sound soundiness])
     (define-values (dir rule loc expr) (splice-proof-step step))
     (if (eq? dir 'Goal)
         (list #f #f #f expr #f)
         (list dir rule loc expr sound))))

;; HTML renderer for derivations
(define/contract (render-history altn pcontext pcontext2 ctx)
  (-> alt? pcontext? pcontext? context? (listof xexpr?))

  (define repr (context-repr ctx))
  (define err
    (format-accuracy (errors-score (errors (alt-expr altn) pcontext ctx)) repr #:unit "%"))
  (define err2
    (format "Internally ~a" (format-accuracy (errors-score (errors (alt-expr altn) pcontext2 ctx)) repr)))

  (match altn
    [(alt (list _ _ prog) 'start (list))
     (list
      `(li (p "Initial program " (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[" ,(program->tex prog ctx) "\\]")))]

    [(alt (list _ _ prog) `(start ,strategy) `(,prev))
     `(,@(render-history prev pcontext pcontext2 ctx)
       (li ([class "event"]) "Using strategy " (code ,(~a strategy))))]

    [(alt _ `(regimes ,splitpoints) prevs)
     (define intervals
       (for/list ([start-sp (cons (sp -1 -1 #f) splitpoints)] [end-sp splitpoints])
         (interval (sp-cidx end-sp) (sp-point start-sp) (sp-point end-sp) (sp-bexpr end-sp))))

     `((li ([class "event"]) "Split input into " ,(~a (length prevs)) " regimes")
       (li
        ,@(apply
           append
           (for/list ([entry prevs] [idx (in-naturals)]
                      [new-pcontext (split-pcontext pcontext splitpoints prevs ctx)]
                      [new-pcontext2 (split-pcontext pcontext2 splitpoints prevs ctx)])
             (define entry-ivals (filter (λ (intrvl) (= (interval-alt-idx intrvl) idx)) intervals))
             (define condition (string-join (map (curryr interval->string repr) entry-ivals) " or "))
             `((h2 (code "if " (span ([class "condition"]) ,condition)))
               (ol ,@(render-history entry new-pcontext new-pcontext2 ctx))))))
       (li ([class "event"]) "Recombined " ,(~a (length prevs)) " regimes into one program."))]

    [(alt (list _ _ prog) `(taylor ,pt ,var ,loc) `(,prev))
     `(,@(render-history prev pcontext pcontext2 ctx)
       (li (p "Taylor expanded in " ,(~a var)
              " around " ,(~a pt) " " (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(program->tex prog ctx #:loc loc) "\\]")))]

    [(alt (list _ _ prog) `(simplify ,loc ,input ,proof ,soundiness) `(,prev))
     (define proof*
       (if proof (compute-proof proof soundiness) #f))
     `(,@(render-history prev pcontext pcontext2 ctx)
       (li (p "Simplified" (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(program->tex prog ctx #:loc loc) 
                "\\]")
           (div ([class "proof"])
             (details
               (summary "Proof")
               ,(if proof*
                    (render-proof proof* pcontext ctx)
                    `(li ([class "event"]) "No proof available- proof too large to flatten."))))))]

    [(alt (list _ _ prog) `initial-simplify `(,prev))
     `(,@(render-history prev pcontext pcontext2 ctx)
       (li (p "Initial simplification" (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(program->tex prog ctx) "\\]")))]

    [(alt (list _ _ prog) `final-simplify `(,prev))
     `(,@(render-history prev pcontext pcontext2 ctx)
       (li (p "Final simplification" (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(program->tex prog ctx) "\\]")))]

    [(alt (list _ _ prog) `(rr , loc, input, proof, soundiness) `(,prev))
     (define proof*
       (if proof (compute-proof proof soundiness) #f))
     `(,@(render-history prev pcontext pcontext2 ctx)
       (li (p "Applied " (span ([class "rule"]) , (if (rule? input) "rewrite-once" "egg-rr"))
              (span ([class "error"] [title ,err2]) ,err))
           (div ([class "math"]) "\\[\\leadsto " ,(program->tex prog ctx #:loc loc) "\\]")
           (div ([class "proof"])
             (details
               (summary "Proof")
               ,(if proof*
                    (render-proof proof* pcontext ctx)
                    `(li ([class "event"]) "No proof available- proof too large to flatten."))))))]
    ))


(define (render-proof proof pcontext ctx)
  `(table
    ,@(for/list ([step proof])
        (match-define (list dir rule loc expr sound) step)
        (define step-prog (program->fpcore expr ctx))
        (define err (format-accuracy (errors-score (errors expr pcontext ctx)) (context-repr ctx)))
        `(tr (th ,(if dir
                      (let ([dir (match dir ['Rewrite<= "<="] ['Rewrite=> "=>"])]
                            [tag (string-append (format " ↑ ~a" (first sound))
                                                (format " ↓ ~a" (second sound)))])
                        `(p ,(format "~a [~a]" rule dir)
                            (span ([class "info"] [title ,tag]) ,err)))
                      `(p "[Start]"
                          (span ([class "info"]) ,err))))
             (td (div ([class "math"])
                      "\\[ "
                      ,(if dir
                           (core->tex step-prog #:loc (cons 2 loc) #:color "blue")
                           (core->tex step-prog))
                      "\\]"))))))
