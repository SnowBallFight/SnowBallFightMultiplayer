(load "gui.rkt")
(load "init.rkt")
(load "networking.rkt")

(define sync-semaphore (make-semaphore 1))
;(require graphics/graphics) seems to work without it

(define Game%
  (class object%
    (super-new)
    (field (WIDTH 21)
           (HEIGHT 21)
           (*should-run* #f)
           (mouse-x 0)
           (mouse-y 0)
           )
    
    (define/public (get-width) WIDTH)
    (define/public (get-height) HEIGHT)
    
    
    
    (define (draw)
      (clear)
      (draw-object-list *object-list*)
      (draw-object-list (get-remote-objects))
      ;(draw-pic *image* mouse-x mouse-y);(draw-pic character characterx charactery). Draws a picture where the mouse is. 
      (show)
      )
    
    (define (draw-object-list object-list)
      (for-each (lambda (object)           ;iterates through a list with all the objects and draws the objects images on the objects coordinates
                                (draw-pic (send object get-sprite)
                                          (send object get-x) 
                                          (send object get-y)))
                object-list ))
    
    (define (update)
      (update-snowballs)
      (send *player* set-xy! mouse-x mouse-y)
      (draw))
    
    (define (update-snowballs)
      (define templist (cons (car *object-list*) (cdr *object-list*))) ;; creates new list with the same elements as *object-list*
      (for-each (lambda (object) (if (send object move) (set! templist (remove object templist eq?)))) *object-list*)
      (semaphore-wait sync-semaphore)
      (set! *object-list* templist)
      (semaphore-post sync-semaphore))
    
    (define/public (update-mouse x y)
      (set! mouse-x x)
      (set! mouse-y y))
    
       
    (define/public (pause-update)
      (set! *should-run* #f)
      )
    
    (define/public (exit-game)
      (pause-update)
      (hide-gui *gui*))
    
    (define/public (start-update)
      (when (not *should-run*)
        (set! *should-run* #t)
        (new timer%
             [notify-callback update]
             [interval 20]
             [just-once? #f])
        (show-gui *gui*)))
    
    (define/public (start-game)
      (start-update)
      )
    )
  )

(define new-game (new Game%))
(send new-game start-game)