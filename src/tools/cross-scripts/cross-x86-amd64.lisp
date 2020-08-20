(in-package :c)

;;; Used to record the source-location of definitions.
;;;
(define-info-class source-location)
(define-info-type source-location defvar (or form-numbers null) nil)

;; Boot file for adding *runtime-features*
(in-package :sys)
(defvar *runtime-features* nil)

(in-package "LISP")

(defun c::%%defconstant (name value doc source-location)
  (when doc
    (setf (documentation name 'variable) doc))
  (when (boundp name)
    (unless (equalp (symbol-value name) value)
      (warn "Constant ~S being redefined." name)))
  (setf (symbol-value name) value)
  (setf (info variable kind name) :constant)
  (clear-info variable constant-value name)
  (set-defvar-source-location name source-location)
  name)

(in-package :disassem)

(use-package :extensions)
(defun sap-ref-int (sap offset length byte-order)
  (declare (type system:system-area-pointer sap)
	   (type (unsigned-byte 16) offset)
	   (type (member 1 2 4 8) length)
	   (type (member :little-endian :big-endian) byte-order)
	   (optimize (speed 3) (safety 0)))
  (ecase length
    (1 (system:sap-ref-8 sap offset))
    (2 (if (eq byte-order :big-endian)
	   (+ (ash (system:sap-ref-8 sap offset) 8)
	      (system:sap-ref-8 sap (+ offset 1)))
	   (+ (ash (system:sap-ref-8 sap (+ offset 1)) 8)
	      (system:sap-ref-8 sap offset))))
    (4 (if (eq byte-order :big-endian)
	   (+ (ash (system:sap-ref-8 sap offset) 24)
	      (ash (system:sap-ref-8 sap (+ 1 offset)) 16)
	      (ash (system:sap-ref-8 sap (+ 2 offset)) 8)
	      (system:sap-ref-8 sap (+ 3 offset)))
	   (+ (system:sap-ref-8 sap offset)
	      (ash (system:sap-ref-8 sap (+ 1 offset)) 8)
	      (ash (system:sap-ref-8 sap (+ 2 offset)) 16)
	      (ash (system:sap-ref-8 sap (+ 3 offset)) 24))))
    (8 (if (eq byte-order :big-endian)
	   (+ (ash (system:sap-ref-8 sap offset) 56)
	      (ash (system:sap-ref-8 sap (+ 1 offset)) 48)
	      (ash (system:sap-ref-8 sap (+ 2 offset)) 40)
	      (ash (system:sap-ref-8 sap (+ 3 offset)) 32)
	      (ash (system:sap-ref-8 sap (+ 4 offset)) 24)
	      (ash (system:sap-ref-8 sap (+ 5 offset)) 16)
	      (ash (system:sap-ref-8 sap (+ 6 offset)) 8)
	      (system:sap-ref-8 sap (+ 7 offset)))
	   (+ (system:sap-ref-8 sap offset)
	      (ash (system:sap-ref-8 sap (+ 1 offset)) 8)
	      (ash (system:sap-ref-8 sap (+ 2 offset)) 16)
	      (ash (system:sap-ref-8 sap (+ 3 offset)) 24)
	      (ash (system:sap-ref-8 sap (+ 4 offset)) 32)
	      (ash (system:sap-ref-8 sap (+ 5 offset)) 40)
	      (ash (system:sap-ref-8 sap (+ 6 offset)) 48)
	      (ash (system:sap-ref-8 sap (+ 7 offset)) 56))))))

(defun read-suffix (length dstate)
  (declare (type (member 8 16 32 64) length)
	   (type disassem-state dstate)
	   (optimize (speed 3) (safety 0)))
  (let ((length (ecase length (8 1) (16 2) (32 4) (64 8))))
    (declare (type (unsigned-byte 3) length))
    (prog1
      (sap-ref-int (dstate-segment-sap dstate)
		   (dstate-next-offs dstate)
		   length
		   (dstate-byte-order dstate))
      (incf (dstate-next-offs dstate) length))))

(defun disassemble-segments (segments stream dstate)
  nil)

(in-package "ALIEN")
(defun sign-extend-32-bit (num)
  (if (> num #x7fffffff)
      (- num #x100000000)
      num))

(def-alien-type-method (integer :naturalize-gen) (type alien)
  (if (and (alien-integer-type-signed type)
	   (< (alien-integer-type-bits type) 64))
      `(sign-extend-32-bit ,alien)
      alien))

(in-package :cl-user)

;; need this since we change them a little
(comf "target:compiler/pack" :load t)
(comf "target:compiler/aliencomp" :load t)

;;; Rename the X86 package and backend so that new-backend does the
;;; right thing.
(rename-package "X86" "OLD-X86")
(setf (c:backend-name c:*native-backend*) "OLD-X86")

(c::new-backend "AMD64"
   ;; Features to add here
   '(:amd64
     :stack-checking
     :gencgc
     :hash-new
     :random-xoroshiro
     :linux
     :glibc2
     :glibc2.1
     :cmucl
     :cmu
     :cmu21
     :cmu21d
     :double-double
     :sse2
     :relocatable-stacks
     :unicode
     )
   ;; Features to remove from current *features* here
   '(:x86 :i486 :pentium :x86-bootstrap :alpha :osf1 :mips
     :propagate-fun-type :propagate-float-type :constrain-float-type
     :openbsd :freebsd :glibc2 :linux :mp :heap-overflow-check
     :long-float :new-random :small
     :alien-callback
     :modular-arith
     ;;:double-double
     ))

(print c::*target-backend*)
(print (c::backend-features c::*target-backend*))

;;; Compile the new backend.
(pushnew :bootstrap *features*)
(pushnew :building-cross-compiler *features*)

;;; Info environment hacks.
;;;
;;; Some of the code that is compiled and loaded by comcom references
;;; exported symbols from AMD64.  So frob the symbols here and export
;;; them.
(macrolet ((frob (&rest syms)
	     `(progn ,@(mapcar #'(lambda (sym)
				   `(defconstant ,(intern (symbol-name sym)
							  "AMD64")
				      (symbol-value
				       (find-symbol ,(symbol-name sym)
						    :OLD-X86))))
			       syms)
		     (export ',(mapcar #'(lambda (sym)
					   (intern (symbol-name sym) "AMD64"))
				       syms)
			     "AMD64"))))
  (frob OLD-X86:BYTE-BITS
	OLD-X86:WORD-BITS
	OLD-X86:WORD-BYTES
	OLD-X86:CHAR-BITS
	OLD-X86:CHAR-BYTES
	OLD-X86:WORD-SHIFT
	#+long-float OLD-X86:SIMPLE-ARRAY-LONG-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-DOUBLE-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-SINGLE-FLOAT-TYPE
	#+long-float OLD-X86:SIMPLE-ARRAY-COMPLEX-LONG-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-COMPLEX-DOUBLE-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-COMPLEX-SINGLE-FLOAT-TYPE
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-2-TYPE 
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-4-TYPE
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-8-TYPE 
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-16-TYPE 
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-32-TYPE 
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-8-TYPE 
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-16-TYPE
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-30-TYPE 
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-32-TYPE
	OLD-X86:SIMPLE-BIT-VECTOR-TYPE
	OLD-X86:SIMPLE-STRING-TYPE OLD-X86:SIMPLE-VECTOR-TYPE 
	OLD-X86:SIMPLE-ARRAY-TYPE OLD-X86:VECTOR-DATA-OFFSET
	OLD-X86:DOUBLE-FLOAT-EXPONENT-BYTE
	OLD-X86:DOUBLE-FLOAT-NORMAL-EXPONENT-MAX 
	OLD-X86:DOUBLE-FLOAT-NORMAL-EXPONENT-MIN
	OLD-X86:DOUBLE-FLOAT-SIGNIFICAND-BYTE
	OLD-X86:SINGLE-FLOAT-EXPONENT-BYTE
	OLD-X86:SINGLE-FLOAT-NORMAL-EXPONENT-MAX
	OLD-X86:SINGLE-FLOAT-NORMAL-EXPONENT-MIN
	OLD-X86:SINGLE-FLOAT-SIGNIFICAND-BYTE
	OLD-X86:DOUBLE-FLOAT-DIGITS
	OLD-X86:SINGLE-FLOAT-DIGITS
	OLD-X86:DOUBLE-FLOAT-BIAS
	OLD-X86:SINGLE-FLOAT-BIAS

	OLD-X86:ERROR-TRAP
	OLD-X86:CERROR-TRAP
	OLD-X86:BREAKPOINT-TRAP
	OLD-X86:PENDING-INTERRUPT-TRAP
	OLD-X86:HALT-TRAP
	OLD-X86:FUNCTION-END-BREAKPOINT-TRAP

	OLD-X86:UNBOUND-MARKER-TYPE
	))

(in-package :vm)
(defvar *num-fixups* 0)
(defun fixup-code-object (code offset fixup kind)
  (declare (type index offset))
  (flet ((add-fixup (code offset)
	   ;; Although this could check for and ignore fixups for code
	   ;; objects in the read-only and static spaces, this should
	   ;; only be the case when *enable-dynamic-space-code* is
	   ;; True.
	   (when lisp::*enable-dynamic-space-code*
	     (incf *num-fixups*)
	     (let ((fixups (code-header-ref code code-constants-offset)))
	       (cond ((typep fixups '(simple-array (unsigned-byte 32) (*)))
		      (let ((new-fixups
			     (adjust-array fixups (1+ (length fixups))
					   :element-type '(unsigned-byte 32))))
			(setf (aref new-fixups (length fixups)) offset)
			(setf (code-header-ref code code-constants-offset)
			      new-fixups)))
		     (t
		      (unless (or (eq (get-type fixups) vm:unbound-marker-type)
				  (zerop fixups))
			(format t "** Init. code FU = ~s~%" fixups))
		      (setf (code-header-ref code code-constants-offset)
			    (make-array 1 :element-type '(unsigned-byte 32)
					:initial-element offset))))))))
    (system:without-gcing
     (let* ((sap (truly-the system-area-pointer
			    (kernel:code-instructions code)))
	    (obj-start-addr (logand (kernel:get-lisp-obj-address code)
				    #xfffffff8))
	    #+nil (const-start-addr (+ obj-start-addr (* 5 4)))
	    (code-start-addr (sys:sap-int (kernel:code-instructions code)))
	    (ncode-words (kernel:code-header-ref code 1))
	    (code-end-addr (+ code-start-addr (* ncode-words 8))))
       (unless (member kind '(:absolute :relative))
	 (error (intl:gettext "Unknown code-object-fixup kind ~s.") kind))
       (ecase kind
	 (:absolute
	  ;; Word at sap + offset contains a value to be replaced by
	  ;; adding that value to fixup.
	  (setf (sap-ref-32 sap offset) (+ fixup (sap-ref-32 sap offset)))
	  ;; Record absolute fixups that point within the code object.
	  (when (> code-end-addr (sap-ref-32 sap offset) obj-start-addr)
	    (add-fixup code offset)))
	 (:relative
	  ;; Fixup is the actual address wanted.
	  ;;
	  ;; Record relative fixups that point outside the code
	  ;; object.
	  (when (or (< fixup obj-start-addr) (> fixup code-end-addr))
	    (add-fixup code offset))
	  ;; Replace word with value to add to that loc to get there.
	  (let* ((loc-sap (+ (sap-int sap) offset))
		 (rel-val (- fixup loc-sap 4)))
	    (declare (type (unsigned-byte 32) loc-sap)
		     (type (signed-byte 32) rel-val))
	    (setf (signed-sap-ref-32 sap offset) rel-val))))))
    nil))
(export 'fixup-code-object)

(defun sanctify-for-execution (component)
  (declare (ignore component))
  nil)
(export 'sanctify-for-execution)

(in-package :cl-user)

(print "***Comcom")
(load "target:tools/comcom")

;;; Load the new backend.
(setf (search-list "c:")
      '("target:compiler/"))
(setf (search-list "vm:")
      '("c:amd64/" "c:generic/"))
(setf (search-list "assem:")
      '("target:assembly/" "target:assembly/amd64/"))

;; Load the backend of the compiler.
(print "***Load backend")
(in-package "C")

(load "vm:vm-fndb")

(load "vm:vm-macs")
(load "vm:parms")
(load "vm:objdef")
(load "vm:interr")
(load "assem:support")


(load "target:compiler/srctran")
(load "vm:vm-typetran")
(load "target:compiler/float-tran")
;;(load "target:compiler/float-tran-dd")
(load "target:compiler/saptran")

(load "vm:macros")
(load "vm:utils")

(load "vm:vm")
(load "vm:insts")
(load "vm:primtype")
(load "vm:move")
(load "vm:sap")
(load "vm:sse2-sap")
(load "vm:system")
(load "vm:char")
(load "vm:float-sse2")

(load "vm:memory")
(load "vm:static-fn")
(load "vm:arith")
(load "vm:cell")
(load "vm:subprim")
(load "vm:debug")
(load "vm:c-call")
(load "vm:sse2-c-call")

(load "vm:print")
(load "vm:alloc")
(load "vm:call")
(load "vm:nlx")
(load "vm:values")
;; These need to be loaded before array because array wants to use
;; some vops as templates.
(load "vm:sse2-array")
(load "vm:array")
(load "vm:pred")
(load "vm:type-vops")

(load "assem:assem-rtns")

(load "assem:array")
(load "assem:arith")
(load "assem:alloc")

(load "c:pseudo-vops")

(check-move-function-consistency)

;; Aret these necessary?
;;(load "target:compiler/codegen")
;;(load "target:compiler/array-tran.lisp")

(load "vm:new-genesis")

;;; OK, the cross compiler backend is loaded.

(setf *features* (remove :building-cross-compiler *features*))

;;; Info environment hacks.
#+nil
(macrolet ((frob (&rest syms)
	     `(progn ,@(mapcar #'(lambda (sym)
				   `(defconstant ,sym
					(symbol-value
					 (find-symbol ,(symbol-name sym)
						      :vm))))
			       syms)
		     (export ,(mapcar #'(lambda (sym)
					  (intern (symbol-name sym) "AMD64"))
				      syms)
			     "AMD64"))))
  (frob OLD-X86:BYTE-BITS
	OLD-X86:WORD-BITS
	OLD-X86:CHAR-BITS
	OLD-X86:CHAR-BYTES
	#+long-float OLD-X86:SIMPLE-ARRAY-LONG-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-DOUBLE-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-SINGLE-FLOAT-TYPE
	#+long-float OLD-X86:SIMPLE-ARRAY-COMPLEX-LONG-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-COMPLEX-DOUBLE-FLOAT-TYPE 
	OLD-X86:SIMPLE-ARRAY-COMPLEX-SINGLE-FLOAT-TYPE
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-2-TYPE 
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-4-TYPE
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-8-TYPE 
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-16-TYPE 
	OLD-X86:SIMPLE-ARRAY-UNSIGNED-BYTE-32-TYPE 
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-8-TYPE 
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-16-TYPE
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-30-TYPE 
	OLD-X86:SIMPLE-ARRAY-SIGNED-BYTE-32-TYPE
	OLD-X86:SIMPLE-BIT-VECTOR-TYPE
	OLD-X86:SIMPLE-STRING-TYPE OLD-X86:SIMPLE-VECTOR-TYPE 
	OLD-X86:SIMPLE-ARRAY-TYPE OLD-X86:VECTOR-DATA-OFFSET
	OLD-X86:DOUBLE-FLOAT-EXPONENT-BYTE
	OLD-X86:DOUBLE-FLOAT-NORMAL-EXPONENT-MAX 
	OLD-X86:DOUBLE-FLOAT-SIGNIFICAND-BYTE
	OLD-X86:SINGLE-FLOAT-EXPONENT-BYTE
	OLD-X86:SINGLE-FLOAT-NORMAL-EXPONENT-MAX
	OLD-X86:SINGLE-FLOAT-SIGNIFICAND-BYTE
	))

(let ((function (symbol-function 'kernel:error-number-or-lose)))
  (let ((*info-environment* (c:backend-info-environment c:*target-backend*)))
    (setf (symbol-function 'kernel:error-number-or-lose) function)
    (setf (info function kind 'kernel:error-number-or-lose) :function)
    (setf (info function where-from 'kernel:error-number-or-lose) :defined)))

(defun fix-class (name)
  (let* ((new-value (find-class name))
	 (new-layout (kernel::%class-layout new-value))
	 (new-cell (kernel::find-class-cell name))
	 (*info-environment* (c:backend-info-environment c:*target-backend*)))
    (remhash name kernel::*forward-referenced-layouts*)
    (kernel::%note-type-defined name)
    (setf (info type kind name) :instance)
    (setf (info type class name) new-cell)
    (setf (info type compiler-layout name) new-layout)
    new-value))
(fix-class 'c::vop-parse)
(fix-class 'c::operand-parse)

#+random-mt19937
(declaim (notinline kernel:random-chunk))

(setf c:*backend* c:*target-backend*)

;;; Extern-alien-name for the new backend.
(in-package :vm)
(defun extern-alien-name (name)
  (declare (type simple-string name))
  #+(and bsd (not elf))
  (concatenate 'string "_" name)
  #-(and bsd (not elf))
  name)
(export 'extern-alien-name)
(export 'fixup-code-object)
(export 'sanctify-for-execution)
(in-package :cl-user)

;;; Don't load compiler parts from the target compilation

(defparameter *load-stuff* nil)

;; hack, hack, hack: Make old-x86::any-reg the same as
;; amd64::any-reg as an SC.  Do this by adding old-x86::any-reg
;; to the hash table with the same value as amd64::any-reg.
(let ((ht (c::backend-sc-names c::*target-backend*)))
  (setf (gethash 'old-x86::any-reg ht)
	(gethash 'amd64::any-reg ht)))
