(define (print-fail expression result fail success)
  (println "  Test number " (+ fail success) " failed:")
  (write expression)
  (println "\n  With result:")
  (write result)
  (println))

(define (unit-test #!optional (file "units.scm"))
  (let ((test-expressions
         (with-input-from-file file
           (lambda () (read-all))))
        (success 0)
        (fail 0))
    (for-each
     (lambda (expression)
       (let ((result
              (with-exception-catcher
               (lambda (e)
                 e)
               (lambda ()
                 (eval expression)))))
         (cond
          ((eq? result #t)
           (set! success (+ 1 success)))
          
          (else
           (set! fail (+ 1 fail))
           (print-fail expression result fail success)))))
     test-expressions)
    
    (println "\nRan " (+ fail success) " tests. " fail " tests failed.")))

(define (filter fn list)
  (let loop ((list list))
    (cond
     ((pair? list)
      (if (fn (car list))
          (cons (car list) (loop (cdr list)))
          (loop (cdr list))))
     (else
      list))))

(define (module-tests)
  (let ((directories
         (filter (lambda (name)
                   (string->number name))
                 (directory-files ".")))
        (success 0)
        (fail 0))
    (for-each
     (lambda (directory)
       (let ((module
              (string->symbol
               (string-append directory "/test"))))
         (eval '(define bh#test-ran #f))
         (expand-macro `(import ,module))
         
         (cond
          ((not bh#test-ran)
           ;; Test didn't run
           )
          
          ((eq? bh#test-result #t)
           (set! success (+ 1 success)))
          
          (else
           (set! fail (+ 1 fail))
           (print-fail module bh#test-result)))))
     directories)

    (println "\nRan " (+ fail success) " tests. " fail " tests failed.")))
