;
; Runnable example code to accompany the write-up in README.md.
;
; Example usage: install Chicken Scheme, then run
;     csi transducer-assembagles
; to run all the tests.
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
    '((closed (off 0)) ())
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
