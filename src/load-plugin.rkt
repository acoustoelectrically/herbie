#lang racket
(require setup/getinfo racket/runtime-path)
(require "config.rkt" "platform.rkt" "syntax/types.rkt"
         (submod "syntax/types.rkt" internals))

(provide load-herbie-plugins load-herbie-builtins make-debug-context)

;; Builtin plugins
(define-runtime-module-path bool-plugin     "reprs/bool.rkt")
(define-runtime-module-path binary32-plugin "reprs/binary32.rkt")
(define-runtime-module-path binary64-plugin "reprs/binary64.rkt")
(define-runtime-module-path fallback-plugin "reprs/fallback.rkt")
(define-runtime-module-path float-plugin    "reprs/float.rkt")

;; Builtin platforms
(define-runtime-module-path default-platform "platforms/default.rkt")

(define (load-herbie-builtins)
  ;; Warning: the order here is important!
  (dynamic-require bool-plugin #f)
  (dynamic-require binary64-plugin #f)
  (dynamic-require binary32-plugin #f)
  (dynamic-require fallback-plugin #f)
  (dynamic-require float-plugin #f)
  (dynamic-require default-platform #f))

;; loads builtin representations as needed
;; usually if 'load-herbie-plugins' has not been called
(define (generate-builtins name)
  (match name
   ['bool     (dynamic-require bool-plugin #f) #t]
   ['binary64 (dynamic-require binary64-plugin #f) #t]
   ['binary32 (dynamic-require binary32-plugin #f) #t]
   ['racket   (dynamic-require fallback-plugin #f) #t]
   [_ #f]))

(define (load-herbie-plugins)
  (load-herbie-builtins) ; automatically load default representations
  ; search packages for herbie plugins
  (for ([dir (find-relevant-directories '(herbie-plugin))])
    (define info
      (with-handlers ([exn:fail:filesystem? (const false)])
        (get-info/full dir)))
    (define value (info 'herbie-plugin (const false)))
    (when value
      (with-handlers ([exn:fail:filesystem:missing-module? void])
        (dynamic-require value #f))))
  ; load in "loose" plugins
  (for ([path (in-list (*loose-plugins*))]) 
    (dynamic-require path #f))
  ; activate the platform now
  (*active-platform* (get-platform (*default-platform-name*)))
  (activate-platform! (*active-platform*)))

;; requiring "load-plugin.rkt" automatically registers
;; all built-in representation but does not load them
(register-generator! generate-builtins)

(define (make-debug-context vars)
  (load-herbie-builtins)
  (define repr (get-representation 'binary64))
  (context vars repr (map (const repr) vars)))
