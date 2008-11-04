#lang scheme/base
(require "../decode.ss"
         "../scheme.ss"
         "../struct.ss"
         (for-syntax scheme/base
                     syntax/kerncase
                     syntax/boundmap)
         (for-label scheme/base
                    scheme/class))

(provide deftogether
         with-scheme-variables
         with-togetherable-scheme-variables
         (struct-out box-splice))

(define-struct (box-splice splice) ())

(define-syntax (with-togetherable-scheme-variables stx)
  (syntax-case stx ()
    [(_ . rest)
     ;; Make it transparent, so deftogether is allowed to pull it apart
     (syntax-property
      (syntax/loc stx
        (with-togetherable-scheme-variables* . rest))
      'certify-mode
      'transparent)]))

(define-syntax-rule (with-togetherable-scheme-variables* . rest)
  (with-scheme-variables . rest))

(define-syntax (with-scheme-variables stx)
  (syntax-case stx ()
    [(_ lits ([kind s-exp] ...) body)
     (let ([ht (make-bound-identifier-mapping)]
           [lits (syntax->datum #'lits)])
       (for-each (lambda (kind s-exp)
                   (case (syntax-e kind)
                     [(proc)
                      (for-each
                       (lambda (arg)
                         (if (identifier? arg)
                             (unless (or (eq? (syntax-e arg) '...)
                                         (eq? (syntax-e arg) '...+)
                                         (memq (syntax-e arg) lits))
                               (bound-identifier-mapping-put! ht arg #t))
                             (syntax-case arg ()
                               [(kw arg . rest)
                                (keyword? (syntax-e #'kw))
                                (bound-identifier-mapping-put! ht #'arg #t)]
                               [(arg . rest)
                                (identifier? #'arg)
                                (bound-identifier-mapping-put! ht #'arg #t)])))
                       (cdr (syntax->list s-exp)))]
                     [(form form/maybe non-term)
                      (let loop ([form (case (syntax-e kind)
                                         [(form) (if (identifier? s-exp)
                                                     null
                                                     (cdr (syntax-e s-exp)))]
                                         [(form/maybe)
                                          (syntax-case s-exp ()
                                            [(#f form) #'form]
                                            [(#t (id . form)) #'form])]
                                         [(non-term) s-exp])])
                        (if (identifier? form)
                            (unless (or (eq? (syntax-e form) '...)
                                        (eq? (syntax-e form) '...+)
                                        (eq? (syntax-e form) '?)
                                        (memq (syntax-e form) lits))
                              (bound-identifier-mapping-put! ht form #t))
                            (syntax-case form (unsyntax)
                              [(unsyntax _) (void)]
                              [(a . b) (loop #'a) (loop #'b)]
                              [#(a ...) (loop #'(a ...))]
                              [_ (void)])))]
                     [else
                      (raise-syntax-error
                       #f
                       "unknown variable mode"
                       stx
                       kind)]))
                 (syntax->list #'(kind ...))
                 (syntax->list #'(s-exp ...)))
       (with-syntax ([(id ...) (bound-identifier-mapping-map ht (lambda (k v) k))])
         #'(parameterize ([current-variable-list '(id ...)])
             body)))]))


(define (*deftogether boxes body-thunk)
  (make-splice
   (cons
    (make-table
     'boxed
     (map
      (lambda (box)
        (unless (and (box-splice? box)
                     (= 1 (length (splice-run box)))
                     (table? (car (splice-run box)))
                     (eq? 'boxed (table-style (car (splice-run box)))))
          (error 'deftogether
                 "element is not a boxing splice containing a single table: ~e"
                 box))
        (list (make-flow (list (make-table
                                "together"
                                (table-flowss (car (splice-run box))))))))
      boxes))
    (body-thunk))))

(define-syntax (deftogether stx)
  (syntax-case stx ()
    [(_ (def ...) . body)
     (with-syntax ([((_ (lit ...) (var ...) decl) ...)
                    (map (lambda (def)
                           (let ([exp-def (local-expand 
                                           def
                                           'expression
                                           (cons
                                            #'with-togetherable-scheme-variables*
                                            (kernel-form-identifier-list)))])
                             (syntax-case exp-def (with-togetherable-scheme-variables*)
                               [(with-togetherable-scheme-variables* lits vars decl)
                                exp-def]
                               [_
                                (raise-syntax-error
                                 #f
                                 "sub-form is not a documentation form that can be combined"
                                 stx
                                 def)])))
                         (syntax->list #'(def ...)))])
       #'(with-togetherable-scheme-variables
          (lit ... ...)
          (var ... ...)
          (*deftogether (list decl ...) (lambda () (list . body)))))]))