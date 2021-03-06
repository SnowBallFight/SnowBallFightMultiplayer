(load "table-helper.scm")

(define network-session%
  (class object%
    (super-new)
    (init-field (host "192.168.1.104")
                (port 9000))
    
   
    (field (inport null) ; Bound to tcp-port by listen/connect
           (outport null)
           (player-sprite 
            (make-object bitmap% "pics/blue_player.png" 'png/alpha #f))
           (player-radius 0)
           (remote-object-list '()) 
           ; Contains the moast recent representation of the other players 
           ;*object-list* when networking in active.
           (change-check '()) 
           ;Used to make sure that the string constucted from *object-list* 
           ;is sent only once per update-loop.
           (syncflag-semaphore (make-semaphore 1)) 
           (remote-object-list-semaphore (make-semaphore 1))
           (send-semaphore (make-semaphore 1))
           (sync #t)) ; Syncflag
    
    
    ;--------actual networking-stuff-------
    
    ; Thread that listens for message-strings from tcp-port 'inport' and 
    ; sends the messages (as lists of words) to the interpet proc.
    (define (listen-for-data)
      (define remote-word-list '())
      (define (loop)
        (set! remote-word-list (string->wordlist (read-line inport 'any))) 
        ; Read tcp-message and convert the recieved string to a list of words 
        (if (eq? (string->symbol (car remote-word-list)) 'sync) 
            ; If message is 'sync set syncflag true to allow send-thread to 
            ; send another *object-list* message.
            (begin (semaphore-wait syncflag-semaphore) 
                   (set! sync #t) 
                   (semaphore-post syncflag-semaphore))
            (begin (interpet remote-word-list) (send-string "sync"))) ; Send sync message to allow other computer to send the next *object-list* message.
        (loop))
      (loop))
    
    ; Thread that converts the relevant information in *object-list* 
    ; to a message-string and sends it through the tcp-port.
    (define (send-thread)
      (let ((tempsync #f)
            (temp-object-list '()))
        (define (loop)
          (semaphore-wait *object-list-semaphore*) 
          (set! temp-object-list *object-list*) 
          (semaphore-post *object-list-semaphore*)
          
          (semaphore-wait syncflag-semaphore) 
          (set! tempsync sync) 
          (semaphore-post syncflag-semaphore)
          
          (if (and (not (eq? change-check temp-object-list)) tempsync) 
              ; If *object-list has changed since last time and syncflag is #t 
              (begin (send-string (make-message temp-object-list)) 
                     ; Construct message-sring from object-list and send it.
                     (set! change-check temp-object-list) 
                     (begin (semaphore-wait syncflag-semaphore) 
                            (set! sync #f) 
                            (semaphore-post syncflag-semaphore))))
          (sleep .01)
          (loop))
        (semaphore-wait *object-list-semaphore*) 
        (set! change-check *object-list*) 
        (semaphore-post *object-list-semaphore*)
        (loop)))
    

    
    
    
    ;----------------interpeting of messages----------------------------------
    
    (define (interpet wordlst)
      (cond 
        ((eq? (string->symbol (car wordlst)) 'hit) (hit-player!)) 
        ((eq? (string->symbol (car wordlst)) 'weapon-taken!) 
         (send new-game remove-weapon!) 
         (set-remote-sprites-weapon!))
        ((eq? (string->symbol (car wordlst)) 'you-win) (send new-game win!)) 
        (else (update-remote-objectlist wordlst))))
    
    ; Decodes information in message-string to construct a list approximating
    ; the other computers *object-list* and updates remote-object-list.
    (define (update-remote-objectlist word-list)
      (let ((temp-object-list '()))
        (define (new-temp wordlist) ; creates new temporary remote-object-list 
          (if (null? wordlist) (void)
              (begin (set! temp-object-list 
                           (cons (apply 
                                  (get 'remote-commands 
                                       (string->symbol (car wordlist))) 
                                  (cons (cadr wordlist) 
                                        (cons (caddr wordlist) '())))
                                 temp-object-list))
                     (new-temp (cdddr wordlist)))))
        (new-temp word-list)
        (semaphore-wait remote-object-list-semaphore)
        (set! remote-object-list temp-object-list)
        (semaphore-post remote-object-list-semaphore)))
    
    ; uses *object-list*
    (define (hit-player!)
      (let ((temp-object-list '()))
        (semaphore-wait *object-list-semaphore*) 
        (set! temp-object-list *object-list*)
        (semaphore-post *object-list-semaphore*)
        (for-each (lambda (object) (if (is-a? object player%) 
                                       (send object hit!))) temp-object-list)))
    
    ; Converts string to list of "wordstrings" 
    ; ex. "Hello World!" -> '("Hello" "World")
    ; (not fully generalised)
    (define (string->wordlist string) 
      (let ((current-word ""))
        (define (st->w str)
          (begin
            (set! current-word (first-word (string->list str)))
            (cond
              ((= (string-length current-word) (string-length str)) 
               (cons  current-word '()))
              ((equal? current-word "") '())
              (else (cons current-word 
                          (st->w (substring str 
                                            (+ 1 (string-length current-word)))))))))
        (st->w string)))
    
    (define (first-word charlist)
      (if (or (null? charlist) (equal? (car charlist) #\space))
          ""
          (string-append (string (car charlist)) (first-word (cdr charlist)))))
    
    
    (define (set-remote-sprites-weapon!)
      (if (= (send *player* get-side) 1)
          (begin
            (set! player-sprite 
                  (make-object bitmap% "pics/blue_playerweapon.png" 'png/alpha #f))
            (set! player-radius (round (/ (send player-sprite get-height) 2))))
          (begin
            (set! player-sprite 
                  (make-object bitmap% "pics/red_playerweapon.png" 'png/alpha #f))
            (set! player-radius (round (/ (send player-sprite get-height) 2)))))
      (set! snowball-sprite 
            (make-object bitmap% "pics/weapon-projectile.png" 'png/alpha #f))
      (set! snowball-radius (/ (send snowball-sprite get-height) 2)))

            
    
    ;-----------------construction of messages--------------------
 
    ; Constructs a message string from list of objects
    (define/public (make-message lst) 
      (let ((str ""))
        (define (msg-loop iter-lst)
          (cond
            ((null? iter-lst) (substring str 1))
            ((is-a? (car iter-lst) snowball%)
             (set! str (string-append str " make-snowball "  
                                      (number->string 
                                       (send (car iter-lst) get-x)) " "
                                      (number->string 
                                       (send (car iter-lst) get-y))))
             (msg-loop (cdr iter-lst)))
            ((is-a? (car iter-lst) player%)
             (set! str (string-append str 
                                      " make-player " 
                                      (number->string 
                                       (send (car iter-lst) get-x)) " "
                                      (number->string 
                                       (send (car iter-lst) get-y))))
             (msg-loop (cdr iter-lst)))
            ((is-a? (car iter-lst) bunker%)
             (set! str (string-append str 
                                      " make-bunker " 
                                      (number->string 
                                       (send (car iter-lst) get-x)) " "
                                      (number->string 
                                       (send (car iter-lst) get-y))))
             (msg-loop (cdr iter-lst)))
             ((is-a? (car iter-lst) weapon%)
             (set! str (string-append str 
                                      " make-weapon-box " 
                                      (number->string 
                                       (send (car iter-lst) get-x)) " "
                                      (number->string 
                                       (send (car iter-lst) get-y))))
             (msg-loop (cdr iter-lst)))
            (else (msg-loop (cdr iter-lst)))))
        (msg-loop lst)))
    

    
    ;-------------------command-table init---------------------
    (define snowball-sprite 
      (make-object bitmap% "pics/snowballe.png" 'png/alpha #f))
    
    (define snowball-radius 
      (/ (send snowball-sprite get-height) 2))
    
    (define bunker-sprite 
      (make-object bitmap% "pics/bunker.png" 'png/alpha #f))
    
    (define bunker-radius (/ (send bunker-sprite get-height) 2))
    
    
    (define weapon-box-sprite 
      (make-object bitmap% "pics/weaponbox.png" 'png/alpha #f))
    
    (define weapon-box-radius (/ (send weapon-box-sprite get-height) 2))
    
    (define empty-powerbar 
      (new powerbar% 
           [sprite (make-object bitmap% "pics/kraft0.png" 'png/alpha #f)]))
    
    (define (remote-make-snowball . args)
      (new snowball% 
           [sprite snowball-sprite]
           [radius snowball-radius]
           [x (string->number (car args))]
           [y (string->number (cadr args))]))
    
    (define (remote-make-player . args)
      (new player% 
           [sprite player-sprite]
           [radius player-radius]
           [powerbar empty-powerbar]
           [x (string->number (car args))]
           [y (string->number (cadr args))]))
    
    (define (remote-make-bunker . args)
      (new bunker% 
           [sprite bunker-sprite]
           [radius bunker-radius]
           [x (string->number (car args))]
           [y (string->number (cadr args))]))
    
     (define (remote-make-weapon-box . args)
      (new weapon% 
           [sprite weapon-box-sprite]
           [radius weapon-box-radius]
           [x (string->number (car args))]
           [y (string->number (cadr args))]))
    
    (put 'remote-commands 'make-snowball remote-make-snowball)
    (put 'remote-commands 'make-player remote-make-player)
    (put 'remote-commands 'make-bunker remote-make-bunker)
    (put 'remote-commands 'make-weapon-box remote-make-weapon-box)
    
    ;---------------------interface--------------------------
    
    ;---------------------get-methods------------------------
    
    (define/public (get-host) host)
    
    (define/public (get-remote-objects) 
      (let ((temp-list '()))
        (begin
          (semaphore-wait remote-object-list-semaphore)
          (set! temp-list remote-object-list)
          (semaphore-post remote-object-list-semaphore)
          temp-list)))
    
    (define/public (sync-check) sync)
    
    ;---------------------set-methods------------------------
    
    (define/public (set-host! new-host) (set! host new-host))
    (define/public (set-sync! new-sync) (set! sync new-sync))
    
    ;---------------------interface---------------------------¨
    
    (define/public (set-player-sprite! pic-location)
      (set! player-sprite (make-object bitmap% pic-location 'png/alpha #f))
      (set! player-radius (round (/ (send player-sprite get-height) 2))))
    
    (define/public (send-string string)
      (semaphore-wait send-semaphore)
      (display string outport)
      (newline outport)
      ; newline + empty-string seems to be the only way to get 
      ; racket to send anything over tcp...
      (display "" outport)
      (semaphore-post send-semaphore))
    
    (define/public (hit!) 
      (send-string "hit"))
    
    (define/public (weapon-is-taken!)
      (send-string "weapon-taken!"))
    
       (define/public (start-send)
      (thread send-thread))
    
        
    (define/public (listen)
      (let ((listener (tcp-listen port 1 #t)))
        (set!-values (inport outport) (tcp-accept listener))
        (thread listen-for-data)
        (start-send)))
    
    (define/public (connect) 
      (set!-values (inport outport) (tcp-connect host port))
      (thread listen-for-data)
      (start-send))))

