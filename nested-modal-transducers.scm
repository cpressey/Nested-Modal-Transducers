;
; Runnable example code, in R5RS Scheme, to accompany the article
; about Nested Modal Transducer Assemblages.
;
; Example usage: install Chicken Scheme, then run
;     csi -q -b nested-modal-transducers.scm
; to run all the tests.  All tests passed if the output is only `()`'s.
;
; All of this code is in the public domain.  Do what you like with it.
;

(define expect
  (lambda (pairs)
    (if (null? pairs)
      '()
      (let* ((pair (car pairs))
             (fst (car pair))
             (snd (cdr pair)))
        (if (equal? fst snd)
          (expect (cdr pairs))
          pair)))))

;
; Purely functional definition of a simple transducer.
;

(define light-transducer
  (lambda (mode input)
    (let* ((transition (list mode input)))
      (cond
        ((equal? transition '(on turn-off))
          (list 'off '()))
        ((equal? transition '(off turn-on))
          (list 'on '(ring-bell)))
        (else
          (list mode '()))))))

;
; Purely functional test harness for transducers:
; Determine what state and outputs it will produce, given a sequence of inputs.
; You can think of it as having a type like:
;
;     rehearse :: Transducer -> State -> [Input] -> (State, [Output])
;

(define rehearse
  (lambda (t state inputs)
    (if (null? inputs)
      (list state '())
      (let* ((input (car inputs))
             (result1 (t state input))
             (state1 (car result1))
             (outputs1 (cadr result1))
             (result2 (rehearse t (car result1) (cdr inputs)))
             (state2 (car result2))
             (outputs2 (cadr result2)))
        (list state2 (append outputs1 outputs2))))))



(display (expect (list
  (cons
    (rehearse light-transducer 'on '(turn-off))
    '(off ())
  )
  (cons
    (rehearse light-transducer 'off '(turn-off))
    '(off ())
  )
  (cons
    (rehearse light-transducer 'off '(turn-on turn-on turn-off))
    '(off (ring-bell))
  )
  (cons
    (rehearse light-transducer 'on '(turn-on turn-on turn-off))
    '(off ())
  )
)))
(newline)


;
; ---- ---- ---- ----
;

(define combine-transducers
  (lambda (ta tb)
    (lambda (state input)
      (let* ((state-a    (car state))
             (result-a   (ta state-a input))
             (newstate-a (car result-a))
             (outputs-a  (cadr result-a))
             (state-b    (cdr state))
             (result-b   (tb state-b input))
             (newstate-b (car result-b))
             (outputs-b  (cadr result-b)))
        (list (cons newstate-a newstate-b) (append outputs-a outputs-b))))))

(define two-light-transducer (combine-transducers light-transducer light-transducer))

(display (expect (list
  (cons
    (rehearse two-light-transducer '(on . off) '(turn-off))
    '((off . off) ())
  )
  (cons
    (rehearse two-light-transducer '(on . off) '(turn-off turn-on))
    '((on . on) (ring-bell ring-bell))
  )
)))
(newline)

;
; ---- ---- ---- ----
;

(define counting-light-transducer
  (lambda (config input)
    (let* ((mode       (car config))
           (count      (cadr config))
           (transition (list mode input)))
      (cond
        ((equal? transition '(on turn-off))
          (list (list 'off count) '()))
        ((equal? transition '(off turn-on))
          (list (list 'on (+ count 1)) '(ring-bell)))
        (else
          (list config '()))))))

(display (expect (list
  (cons
    (rehearse counting-light-transducer '(off 0) '(turn-on))
    '((on 1) (ring-bell))
  )
  (cons
    (rehearse counting-light-transducer '(off 0) '(turn-on turn-on))
    '((on 1) (ring-bell))
  )
  (cons
    (rehearse counting-light-transducer '(off 0) '(turn-on turn-on turn-off))
    '((off 1) (ring-bell))
  )
  (cons
    (rehearse counting-light-transducer '(off 0) '(turn-on turn-on turn-off turn-on))
    '((on 2) (ring-bell ring-bell))
  )
)))
(newline)

;
; Nested state machine.  The light is now in a room, behind a door.
; It can only be turned on or off when the door is open.
;

(define door-transducer
  (lambda (config input)
    (let* ((mode         (car config))
           (light-config (cadr config))
           (transition   (list mode input)))
      (cond
        ((equal? transition '(closed open))
          (list (list 'opened light-config) '()))
        ((equal? transition '(opened close))
          (list (list 'closed light-config) '()))
        ((equal? mode 'opened)
          (let* ((inner-result     (counting-light-transducer light-config input))
                 (new-light-config (car inner-result))
                 (light-outputs    (cadr inner-result)))
            (list (list mode new-light-config) light-outputs)))
        (else
          (list config '()))))))

(display (expect (list
  (cons
    (rehearse door-transducer '(closed (off 0)) '(open))
    '((opened (off 0)) ())
  )
  (cons
    (rehearse door-transducer '(closed (off 0)) '(turn-on))
    '((closed (off 0)) ())
  )
  (cons
    (rehearse door-transducer '(closed (off 0)) '(open turn-on close))
    '((closed (on 1)) (ring-bell))
  )
)))
(newline)

;
; Array of orthogonal regions - a list of lights are behind a barn door.
;

(define transduce-all
  (lambda (t input configs acc)
    (if (null? configs)
      (list (reverse (car acc)) (cadr acc))
      (let* ((config        (car configs))
             (rest-configs  (cdr configs))
             (acc-configs   (car acc))
             (acc-outputs   (cadr acc))
             (result        (t config input))
             (new-config    (car result))
             (these-outputs (cadr result))
             (new-acc       (list (cons new-config acc-configs) (append these-outputs acc-outputs))))
        (transduce-all t input rest-configs new-acc)))))

(define barn-transducer
  (lambda (config input)
    (let* ((mode          (car config))
           (light-configs (cadr config))
           (transition    (list mode input)))
      (cond
        ((equal? transition '(closed open))
          (list (list 'opened light-configs) '()))
        ((equal? transition '(opened close))
          (list (list 'closed light-configs) '()))
        ((equal? mode 'opened)
          (let* ((inner-results     (transduce-all counting-light-transducer input light-configs '(() ())))
                 (new-light-configs (car inner-results))
                 (light-outputs     (cadr inner-results)))
            (list (list mode new-light-configs) light-outputs)))
        (else
          (list config '()))))))


(display (expect (list
  (cons
    (rehearse barn-transducer '(closed  ((off 0) (on 0)) ) '(open))
    '( (opened  ((off 0) (on 0)) ) ())
  )
  (cons
    (rehearse barn-transducer '(closed  ((off 0) (on 0)) ) '(turn-on))
    '( (closed  ((off 0) (on 0)) ) ())
  )
  (cons
    (rehearse barn-transducer '(closed  ((off 0) (on 0)) ) '(open turn-on close))
    '( (closed  ((on 1) (on 0)) ) (ring-bell))
  )
  (cons
    (rehearse barn-transducer '(closed  ((off 0) (off 0)) ) '(open turn-on close))
    '( (closed  ((on 1) (on 1)) ) (ring-bell ring-bell))
  )
)))
(newline)


;
; Entry and exit actions
;
; Like the article says, we don't pretend to have a good solution, we only
; want to show that it is possible.
;
; door-transducer-2 is the same as door-transducer except that the
; counting-light-transducer nested within it, is decorated with
; add-entry-exit-outputs.
;

(define add-entry-exit-outputs
  (lambda (t config input)
    (let* ((old-mode      (car config))
           (result        (t config input))
           (new-config    (car result))
           (new-mode      (car new-config))
           (new-data      (cadr new-config))
           (outputs       (cadr result))
           (exit-outputs  (if (equal? old-mode 'off) '(buzz-buzzer) '()))
           (entry-outputs (if (equal? new-mode 'closed) '(blow-horn) '()))
           (new-outputs   (append exit-outputs outputs entry-outputs)))
      (list new-config new-outputs))))

(define door-transducer-2
  (lambda (config input)
    (let* ((mode         (car config))
           (light-config (cadr config))
           (transition   (list mode input)))
      (cond
        ((equal? transition '(closed open))
          (list (list 'opened light-config) '()))
        ((equal? transition '(opened close))
          (list (list 'closed light-config) '()))
        ((equal? mode 'opened)
          (let* ((inner-result     (add-entry-exit-outputs counting-light-transducer light-config input))
                 (new-light-config (car inner-result))
                 (light-outputs    (cadr inner-result)))
            (list (list mode new-light-config) light-outputs)))
        (else
          (list config '()))))))

(define deco-door-transducer
  (lambda (config input)
    (add-entry-exit-outputs door-transducer-2 config input)))


(display (expect (list
  (cons
    (rehearse deco-door-transducer '(closed (off 0)) '(open))
    '((opened (off 0)) ())
  )
  (cons
    (rehearse deco-door-transducer '(closed (off 0)) '(turn-on))
    '((closed (off 0)) (blow-horn))
  )
  (cons
    (rehearse deco-door-transducer '(closed (off 0)) '(open turn-on close))
    '((closed (on 1)) (buzz-buzzer ring-bell blow-horn))
  )
)))
(newline)


;
; Synthesized events
;

(define make-gui-input-synthesizing-transducer
  (lambda (t)
    (lambda (config input)
      (let* ((mode (car config)))
        (cond
          ((and (equal? mode 'mouse-down) (list? input) (equal? (car input) 'mouse-move))
            (t config (list 'drag (cadr input) (caddr input))))
          (else
            (t config input)))))))

(define base-gui-transducer
  (lambda (config input)
    (let* ((mode       (car config))
           (x          (cadr config))
           (y          (caddr config))
           (transition (list mode input)))
      (cond
        ((equal? transition '(mouse-down mouse-release))
          (list (list 'mouse-up x y) '()))
        ((equal? transition '(mouse-up mouse-press))
          (list (list 'mouse-down x y) (list (list 'show-click x y))))
        ((equal? (car input) 'mouse-move)
          (let* ((new-x (cadr input)) (new-y (caddr input)))
            (list (list mode new-x new-y) '())))
        ((equal? (car input) 'drag)
          (let* ((new-x (cadr input)) (new-y (caddr input)))
            (list (list mode new-x new-y) (list (list 'show-hand new-x new-y)))))
        (else
          (list (list mode x y) '()))))))

(define gui-transducer (make-gui-input-synthesizing-transducer base-gui-transducer))


(display (expect (list
  (cons
    (rehearse gui-transducer '(mouse-up 0 0) '((mouse-move 10 10) mouse-press mouse-release))
    '((mouse-up 10 10) ((show-click 10 10)))
  )
  (cons
    (rehearse gui-transducer '(mouse-up 0 0) '(mouse-press (mouse-move 10 10) mouse-release))
    '((mouse-up 10 10) ((show-click 0 0) (show-hand 10 10)))
  )
)))
(newline)
