(in-package "USER")

;;; Hide CLOS from CLX, so objects stay implemented as structures.
;;;
(when (find-package "CLOS")
  (rename-package (find-package "CLOS") "NO-CLOS-HERE"))
(when (find-package "PCL")
  (rename-package (find-package "PCL") "NO-PCL-HERE"))

#+bootstrap
(unless (find-package "OLD-XLIB")
  (when (find-package "XLIB")
    (rename-package (find-package "XLIB") "OLD-XLIB"))
  
  (make-package "XLIB" :use '("LISP")))

(with-compiler-log-file
    ("clx:compile-clx.log"
     :optimize
     '(optimize (debug-info #-small 2 #+small .5) 
		(speed 2) (inhibit-warnings 2)
		(safety #-small 1 #+small 0))
     :optimize-interface
     '(optimize-interface (debug-info .5))
     :context-declarations
     '(((:and :external :global)
	(declare (optimize-interface (safety 2) (debug-info 1))))
       ((:and :external :macro)
	(declare (optimize (safety 2))))))
  (let ((c::*suppress-values-declaration* t))
    (comf "clx:package" :load t)
    (comf "clx:defsystem" :load t)
    (comf "clx:depdefs" :load t)
    (comf "clx:clx" :load t)
    (comf "clx:dependent" :load t)
    (comf "clx:macros" :load t)	; these are just macros
    (comf "clx:bufmac" :load t)		; these are just macros
    (comf "clx:buffer" :load t)
    (comf "clx:display" :load t)
    (comf "clx:gcontext" :load t)
    (comf "clx:input" :load t)
    (comf "clx:requests" :load t)
    (comf "clx:fonts" :load t)
    (comf "clx:graphics" :load t)
    (comf "clx:text" :load t)
    (comf "clx:attributes" :load t)
    (comf "clx:translate" :load t)
    (comf "clx:keysyms" :load t)
    (comf "clx:manager" :load t)
    (comf "clx:image" :load t)
    (comf "clx:resource" :load t)))
