;;; Utilities

;; TODO This is already defined in util.scm
(define-macro (push! list obj)
  `(set! ,list (cons ,obj ,list)))

(define (find-one? pred? lst)
    (let loop ((lst lst))
      (cond
       ((null? lst)
        #f)

       ((pair? lst)
        (if (pred? (car lst))
            #t
            (loop (cdr lst))))

       (else
        (error "Improper list" lst)))))

(define (string-for-each fn str)
  (let ((len (string-length str)))
    (let loop ((i 0))
      (cond
       ((= i len) #!void)
       (else
        (fn (string-ref str i))
        (loop (+ i 1)))))))

(define (reverse-list->string list)
  (let* ((len (length list))
         (str (make-string len)))
    (let loop ((i (- len 1))
               (list list))
      (cond
       ((pair? list)
        (string-set! str i (car list))
        (loop (- i 1) (cdr list)))))
    str))

(define (string-split chr str #!optional (sparse #f))
  (let* ((curr-str '())
         (result '())
         (new-str (lambda ()
                    (push! result (reverse-list->string curr-str))
                    (set! curr-str '())))
         (add-char (lambda (chr)
                     (push! curr-str chr))))
    (string-for-each (lambda (c)
                       (cond
                        ((eq? c chr)
                         (if (or (not sparse)
                                 (not (null? curr-str)))
                             (new-str)))
                        (else
                         (add-char c))))
                     str)
    (new-str)
    (reverse result)))

(define (with-input-from-url url thunk)
  (with-input-from-process
   (list path: "curl"
         arguments: `("-sL" ,url))
   thunk))

(define (read-url url)
  (with-input-from-url url read))

(define (port-passthru in out)
  (let* ((buf-size 1000)
         (buf (make-u8vector buf-size)))
    (let loop ()
      (write-subu8vector
       buf
       0
       (read-subu8vector buf 0 buf-size in)
       out)
      (let ((byte (read-u8 in)))
        (if (not (eq? #!eof byte))
            (begin
              (write-u8 byte out)
              (loop)))))))

(define (untar port)
  (with-output-to-process
   (list path: "tar"
         arguments: '("xz"))
   (lambda ()
     (port-passthru port (current-output-port)))))

;;; Version numbers

(define-type version
  id: 31B8EF4A-9244-450F-8FA3-A5E914448B3A
  constructor: make-version/internal
  
  (major read-only:)
  (minor read-only:)
  (build read-only:))

(define (make-version #!optional
                      major
                      minor
                      build)
  (make-version/internal major minor build))

(define version-complete? version-build)

(define (version<? a b)
  (cond
   ((not (and (version-complete? a)
              (version-complete? b)))
    (error "Can't compare incomplete versions" a b))
   
   (else
    (let ((a-maj (version-major a))
          (b-maj (version-major b))
          (a-min (version-minor a))
          (b-min (version-major b))
          (a-b (version-build a))
          (b-b (version-build b))

          (v< (lambda (a b)
                (cond
                 ((eq? 'max a)
                  #f)
                 ((eq? 'max b)
                  #t)
                 (else
                  (< a b))))))
      (or (v< a-maj b-maj)
          (and (= a-maj b-maj)
               (or (v< a-min b-min)
                   (and (= a-min b-min)
                        (v< a-b b-b)))))))))

(define (string->version str #!key force-complete?)
  (if (not (string? str))
      (error "Expected string" str))
  (let* ((str-len (string-length str))
         (str-no-v
          (if (> str-len 1)
              (substring str 1 str-len)
              (error "Invalid format" str)))
         (split-string (string-split #\. str-no-v))
         (split-string-len (length split-string)))
    (if (not (<= 0 split-string-len 3))
        (error "Invalid format" str))
    (let ((s->i
           (lambda (str)
             (let ((res (string->number str)))
               (if (or (not (integer? res))
                       (< res 0))
                   (error "Invalid format" res str))
               res))))
      (let ((res
             (make-version (and (>= split-string-len 1)
                                (s->i (car split-string)))
                           (and (>= split-string-len 2)
                                (s->i (cadr split-string)))
                           (and (= split-string-len 3)
                                (s->i (caddr split-string))))))
        (if (and force-complete?
                 (not (version-complete? res)))
            (error "Version is not complete" str))
        res))))

(define (symbol->version str #!key force-complete?)
  (string->version (symbol->string str)
                   force-complete?: force-complete?))

(define (version->string v)
  (apply
   string-append
   `("v"
     ,@(if (version-major v)
           `(,(number->string
               (version-major v))
             ,@(if (version-minor v)
                   `("."
                     ,(number->string
                       (version-minor v))
                     ,@(if (version-build v)
                           `("."
                             ,(number->string
                               (version-build v)))
                           '()))
                   '()))
           '()))))

(define (version->symbol v)
  (string->symbol (version->string v)))

(define (version-comparison pred?)
  (lambda (v ref)
    (or (not (version-major v))
        (and (pred? (version-major v)
                    (version-major ref))
             (or (not (version-minor v))
                 (and (pred? (version-minor v)
                             (version-minor ref))
                      (or (not (version-build v))
                          (pred? (version-build v)
                                 (version-build ref)))))))))
  
(define version~=? (version-comparison =))
(define version~<? (version-comparison <))
(define version~<=? (version-comparison <=))
(define version~>? (version-comparison >))
(define version~>=? (version-comparison >=))

(define version-match?
  (let ((tests
         `((< ,@version~<?)
           (<= ,@version~<=?)
           (> ,@version~>?)
           (>= ,@version~>=?)
           (= ,@version~=?))))
    (lambda (v original-exp)
      (let loop ((exp original-exp))
        (cond
         ((eq? exp #t) #t)
         
         ((eq? exp #f) #f)
         
         ((pair? exp)
          (let ((test (car exp)))
            (cond
             ((eq? 'or test)
              (find-one? loop
                         (cdr exp)))
             
             ((eq? 'and test)
              (not
               (find-one? (lambda (x)
                            (not (loop x)))
                          (cdr exp))))
             
             ((assq test tests) =>
              (lambda (test-pair)
                (if (not (and (pair? (cdr exp))
                              (null? (cddr exp))))
                    (error "Invalid expression" original-exp))
                ((cdr test-pair)
                 (symbol->version (cadr exp))
                 v)))
             
             (else
              (error "Unknown expression" original-exp)))))
          
          (else
           (error "Unknown expression" original-exp)))))))
  


;;; Package metadata

(define-type package-metadata
  id: FBD3E6A5-3587-4152-BF57-B7D5E448DAB8

  (version read-only:)
  (maintainer read-only:)
  (author read-only:)
  (homepage read-only:)
  (description read-only:)
  (keywords read-only:)
  (license read-only:)
  (dependencies read-only:)

  (exported-modules read-only:)
  (default-module read-only:)
  (source-directory read-only:))

(define (parse-package-metadata form)
  (if (or (not (list? form))
          (not (eq? 'package (car form))))
      (error "Invalid package metadata" form))
  (let* ((tbl (list->table (cdr form)))

         (one
          (lambda (name pred? #!key require?)
            (let ((lst (table-ref tbl name #f)))
              (if (and require? (not lst))
                  (error "Package attribute required:" name))
              (and lst
                   (if (or (not (pair? lst))
                           (not (null? (cdr lst)))
                           (not (pred? (car lst))))
                       (error "Invalid package metadata"
                              (list name lst))
                       (car lst))))))
         (list
          (lambda (name pred?)
            (let ((lst (table-ref tbl name #f)))
              (and lst
                   (if (or (not (list? lst))
                           (find-one? (lambda (x) (not (pred? x)))
                                      lst))
                       (error "Invalid package metadata"
                              (list name lst))
                       lst))))))
    (make-package-metadata
     (let ((v (symbol->version (one 'version symbol? require?: #t))))
       (if (not (version-build v))
           (error "Complete version required" (version->symbol v)))
       v)
     (one 'maintainer string?)
     (one 'author string?)
     (one 'homepage string?)
     (one 'description string?)
     (list 'keywords symbol?)
     (list 'license symbol?)
     (map (lambda (dep)
            (if (symbol? dep)
                (cons dep '())
                dep))
       (or (list 'dependencies (lambda (x) #t))
           '()))
     
     (list 'exported-modules symbol?)
     (one 'default-module symbol?)
     (or (one 'source-directory string?)
         ""))))

(define (load-package-metadata fn)
  (with-input-from-file fn
    (lambda ()
      (parse-package-metadata (read)))))


;;; Packages

(define pkgfile-name
  "pkgfile")

(define-type package
  id: EC2E4078-EDCA-4BE4-B81E-2B60468F042D
  
  (name read-only:)
  (version read-only:)
  (dir read-only:)
  (url read-only:)
  (metadata package-metadata/internal
            package-metadata-set!))

(define (package<? a b)
  (let ((a-name (package-name a))
        (b-name (package-name b)))
    (or (string<? a-name b-name)
        (and (string=? a-name b-name)
             (version<? (package-version a)
                        (package-version b))))))

(define (package-metadata ip)
  (let ((md (package-metadata/internal ip)))
    (or md
        (let* ((pkg-filename (path-expand
                              "pkgfile"
                              (package-dir ip)))
               (md (if (file-exists? pkg-filename)
                       (load-package-metadata
                        pkg-filename)
                       (error "Pkgfile does not exist:"
                              pkg-filename))))
          (package-metadata-set! ip md)
          md))))

(define (package-installed? p)
  (and (package? p) (package-dir p) #t))

(define (package-noninstalled? p)
  (and (package? p) (package-url p) #t))

(define (make-installed-package name version dir)
  (make-package name
                version
                dir
                #f
                #f))

(define (make-noninstalled-package name url metadata)
  (make-package name
                (package-metadata-version metadata)
                #f
                url
                metadata))

(define (make-dummy-package name version)
  (make-package name
                version
                #f
                #f
                #f))


;;; Remote packages

(define (load-remote-packages)
  ;; TODO
  '(("sack"
     ("http://github.com/pereckerdal/sack/tarball/master"
      (package
       (version v0.0.1)
       (maintainer "Per Eckerdal <per dot eckerdal at gmail dot com>")
       (author "Per Eckerdal <per dot eckerdal at gmail dot com>")
       (homepage "http://example.com")
       (description "An example package")
       (keywords http web i/o)
       (license mit)

       (source-directory "src"))))))

(define (parse-remote-package-list package-list)
  (list->tree
   (apply
    append
    (map (lambda (package)
           (map (lambda (package-version-desc)
                  (if (not (= 2 (length package-version-desc)))
                      (error "Invalid package version descriptor"
                             package-version-desc))
                  (make-noninstalled-package
                   (car package)
                   (car package-version-desc)
                   (parse-package-metadata
                    (cadr package-version-desc))))
             (cdr package)))
      package-list))
   package<?))

(define get-remote-packages
  (let ((*remote-packages* #f))
    (lambda ()
      (or *remote-packages*
          (let ((rp (parse-remote-package-list
                     (load-remote-packages))))
            (set! *remote-packages* rp)
            rp)))))


;;; Local packages

(define *local-packages-dir*
  (path-expand "pkgs"
               *blackhole-work-dir*))

(define (load-installed-packages #!optional
                                 (pkgs-dir *local-packages-dir*))
  (let ((pkg-dirs
         (filter (lambda (x)
                   (is-directory? (path-expand x pkgs-dir)))
                 (if (file-exists? pkgs-dir)
                     (directory-files pkgs-dir)
                     '()))))
    (list->tree
     (map (lambda (pkg-dir)
            (let ((version-str
                   (last (string-split #\- pkg-dir))))
              (if (= (string-length version-str)
                     (string-length pkg-dir))
                  (error "Invalid package directory name" pkg-dir))
              (let ((version
                     (string->version
                      (last (string-split #\- pkg-dir))
                      force-complete?: #t))
                    (pkg-name
                     (substring pkg-dir
                                0
                                (- (string-length pkg-dir)
                                   (string-length version-str)
                                   1))))
                (make-installed-package
                 pkg-name
                 version
                 (path-expand pkg-dir pkgs-dir)))))
       pkg-dirs)
     package<?)))

(define *installed-packages* #f)

(define (reset-installed-packages!)
  (set! *installed-packages* #f))

(define (get-installed-packages)
  (or *installed-packages*
      (let ((ip (load-installed-packages)))
        (set! *installed-packages* ip)
        ip)))


;;; Module loader and resolver

(define *loaded-packages* (make-table))

(define (find-suitable-package pkgs
                               pkg-name
                               #!key
                               (version #t)
                               (throw-error? #t))
  (or (tree-backwards-fold-from
       pkgs
       (make-dummy-package pkg-name
                           (make-version 'max 'max 'max))
       package<?
       #f
       (lambda (p accum k)
         (cond
          ((not (equal? (package-name p)
                        pkg-name))
           #f)
          
          ((version-match? (package-version p)
                           version)
           p)

          (else
           (k #f)))))
      (and throw-error?
           (error "No package with matching version is installed:"
                  pkg-name
                  version))))

(define (find-suitable-loaded-package pkg-name
                                      #!key
                                      (version #t)
                                      (throw-error? #t))
  (let ((loaded-package (table-ref *loaded-packages* pkg-name #f)))
    (if loaded-package
        (if (version-match? (package-version loaded-package)
                            version)
            loaded-package
            (and throw-error?
                 (error "A package is already loaded, with incompatible version:"
                        (package-version loaded-package)
                        version)))
        (find-suitable-package (get-installed-packages)
                               pkg-name
                               version: version
                               throw-error?: throw-error?))))

(define (load-package! pkg)
  (let ((currently-loading (make-table))
        (name (package-name pkg))
        (version (package-version pkg)))
    (let loop ((pkg pkg))
      (cond
       ((table-ref *loaded-packages* name #f)
        'already-loaded)
       ((eq? 'loading (table-ref currently-loading name #f))
        (error "Circular package dependency" pkg))
       (else
        (table-set! currently-loading name 'loading)
        (let* ((other-pkg (table-ref *loaded-packages* name #f))
               (other-version (package-version other-pkg)))
          (if other-pkg
              (and other-pkg
                   (not (equal? other-version version)))
              (error "Another incompatible package version is already loaded:"
                     name
                     version
                     other-version))
          
          (for-each (lambda (dep)
                      (loop
                       (if (symbol? dep)
                           (find-suitable-loaded-package dep)
                           (find-suitable-loaded-package
                            (car dep)
                            version:
                            `(and
                              ,@(cdr dep))))))
            (package-metadata-dependencies
             (package-metadata pkg)))
          
          (table-set! *loaded-packages* name pkg))
        (table-set! currently-loading name 'loaded))))))

(define (package-module-path-path path)
  (path-normalize (string-append (symbol->string
                                  (package-module-path-id path))
                                 ".scm")
                  #f ;; Don't allow relative paths
                  (path-normalize
                   ;; This call to path-normalize ensures that the
                   ;; directory actually exists. Otherwise
                   ;; path-normalize might segfault.
                   (let ((pkg (package-module-path-package path)))
                     (path-expand
                      (package-metadata-source-directory
                       (package-metadata pkg))
                      (package-dir pkg))))))

(define (make-package-module-path pkg id)
  (vector '56BBBA2B-66E5-49A7-A74A-D6992792526E
          (version->symbol (package-version pkg))
          (package-name pkg)
          id))

(define (package-module-path? pmp)
  (and (vector? pmp)
       (eq? '56BBBA2B-66E5-49A7-A74A-D6992792526E
            (vector-ref pmp 0))))

(define (package-module-path-package pmp)
  (if (not (package-module-path? pmp))
      (error "Expected package-module-path" pmp))
  (find-suitable-package (get-installed-packages)
                         (vector-ref pmp 2)
                         version:
                         `(= ,(vector-ref pmp 1))))

(define (package-module-path-id pmp)
  (if (not (package-module-path? pmp))
      (error "Expected package-module-path" pmp))
  (vector-ref pmp 3))

(define (package-module-resolver loader path relative pkg-name
                                 #!rest
                                 ids
                                 #!key
                                 (version #t))
  (let ((package (find-suitable-loaded-package (symbol->string pkg-name)
                                               version: version)))
    (map (lambda (id)
           (make-module-reference
            package-loader
            (make-package-module-path package id)))
      ids)))

(define package-loader
  (make-loader
   name:
   'package

   path-absolute?:
   (lambda (p) #t)
   
   path-absolutize:
   (lambda (path #!optional ref)
     (if (not (package-module-path? ref))
         (error "Invalid parameters" ref))
     (make-package-module-path
      (string->symbol
       (remove-dot-segments
        (string-append (symbol->string (package-module-path-id ref))
                       "/"
                       (symbol->string path))))
      (package-module-path-package ref)))
   
   load-module:
   (lambda (path)
     (let* ((ref (make-module-reference package-loader path))
            (actual-path (package-module-path-path path)))
       (let ((invoke-runtime
              invoke-compiletime
              visit
              info-alist
              (load-module-from-file ref
                                     actual-path)))
         (make-loaded-module
          invoke-runtime: invoke-runtime
          invoke-compiletime: invoke-compiletime
          visit: visit
          info: (make-module-info-from-alist ref info-alist)
          stamp: (path->stamp actual-path)
          reference: ref))))

   compare-stamp:
   (lambda (path stamp)
     (= (path->stamp (package-module-path-path path))
        stamp))

   module-name:
   (lambda (path)
     (path-strip-directory
      (cond ((symbol? path)
             (symbol->string path))
            ((package-module-path? path)
             (path-strip-extension
              (package-module-path-path path)))
            (else
             (error "Invalid path" path)))))))


;;; Package installation and uninstallation

(define (package-install! pkg-name-sym
                          #!key
                          (version #t)
                          ignore-dependencies)
  (let* ((pkg-name (symbol->string pkg-name-sym))
         (pkg
          (find-suitable-package (get-remote-packages)
                                 pkg-name
                                 version: version))
         (pkg-md
          (package-metadata pkg))
         (pkgs-to-be-installed (list pkg)))
    (if (not ignore-dependencies)
        (let loop ((deps (package-metadata-dependencies pkg-md)))
          (cond
           ((pair? deps)
            (let* ((dep-pkg-name
                    (symbol->string (caar deps)))
                   (dep-pkg-v `(and ,@(cdar deps)))
                   (installed-pkg
                    (find-suitable-package (get-installed-packages)
                                           dep-pkg-name
                                           version: dep-pkg-v
                                           throw-error?: #f)))
              (if (not installed-pkg)
                  (let ((install-pkg
                         (find-suitable-package (get-remote-packages)
                                                dep-pkg-name
                                                version: dep-pkg-v
                                                throw-error?: #f)))
                    (if (not install-pkg)
                        (error "Can't install dependency"
                               dep-pkg-name
                               dep-pkg-v)
                        (begin
                          (loop (package-metadata-dependencies
                                 (package-metadata install-pkg)))
                          (push! pkgs-to-be-installed install-pkg))))))
            (loop (cdr deps))))))
    
    (for-each (lambda (pkg)
                (package-install-from-url!
                 (package-name pkg)
                 (package-url pkg)))
      pkgs-to-be-installed)))

(define (package-install-from-url! name url)
  (with-input-from-url
   url
   (lambda ()
     (package-install-from-port! name (current-input-port)))))

(define (package-install-from-port! name
                                    port
                                    #!key
                                    (compile? #t)
                                    (to-dir *local-packages-dir*))
  ;;; Create temporary directory
  (generate-tmp-dir
   (path-expand "pkgs-tmp"
                *blackhole-work-dir*)
   (lambda (dir)
     (parameterize
         ((current-directory dir))
       ;;; Untar
       (untar port)

       ;;; Extract metadata
       (let ((dir
              metadata
              (let* ((files
                      (directory-files
                       (list path: dir
                             ignore-hidden: 'dot-and-dot-dot)))
                     (dir
                      (path-expand
                       (if (= (length files) 1)
                           (car files)
                           (error "Invalid package contents (un-nice tarball)"
                                  files))
                       dir))
                     (metadata-file
                      (path-expand pkgfile-name
                                   dir)))
                (if (or (not (file-exists? metadata-file))
                        (is-directory? metadata-file))
                    (error "Invalid package contents (no metadata file)"))
                (values dir
                        (load-package-metadata metadata-file)))))
         ;;; Compile
         'TODO
         
         ;;; Move to installed package directory
         (let ((target-dir
                (path-expand
                 (string-append name
                                "-"
                                (version->string
                                 (package-metadata-version
                                  metadata)))
                 to-dir)))
           (if (file-exists? target-dir)
               (error "Package is already installed" target-dir))
           (rename-file dir target-dir)))
                      
       ;;; Update *installed-packages*
       (reset-installed-packages!)
       
       #!void))))

(define (package-uninstall! pkg)
  (if (not (package-installed? pkg))
      (error "Invalid parameter" pkg))
  (recursively-delete-file
   (package-dir pkg))
  (reset-installed-packages!))
