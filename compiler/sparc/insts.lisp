;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/sparc/insts.lisp,v 1.47 2003/10/18 14:05:50 toy Exp $")
;;;
;;; **********************************************************************
;;;
;;; Description of the SPARC architecture.
;;;
;;; Written by William Lott.
;;;
(in-package "SPARC")

(use-package "NEW-ASSEM")
(use-package "EXT")
(use-package "C")

(def-assembler-params
    :scheduler-p t
  :max-locations 101)


;;;; Constants, types, conversion functions, some disassembler stuff.

(defun reg-tn-encoding (tn)
  (declare (type tn tn))
  (sc-case tn
    (zero zero-offset)
    (null null-offset)
    (t
     (if (eq (sb-name (sc-sb (tn-sc tn))) 'registers)
	 (tn-offset tn)
	 (error "~S isn't a register." tn)))))

(defun fp-reg-tn-encoding (tn)
  (declare (type tn tn))
  (unless (eq (sb-name (sc-sb (tn-sc tn))) 'float-registers)
    (error "~S isn't a floating-point register." tn))
  (let ((offset (tn-offset tn)))
    (cond ((> offset 31)
	   ;; Use the sparc v9 double float register encoding.
	   (assert (backend-featurep :sparc-v9))
	   ;; No single register encoding greater than reg 31.
	   (assert (zerop (mod offset 2)))
	   ;; Upper bit of the register number is encoded in the low bit.
	   (1+ (- offset 32)))
	  (t
	   (tn-offset tn)))))

(disassem:set-disassem-params :instruction-alignment 32
			      :opcode-column-width 11)

(defvar *disassem-use-lisp-reg-names* t
  "If non-NIL, print registers using the Lisp register names.
Otherwise, use the Sparc register names")

(def-vm-support-routine location-number (loc)
  (etypecase loc
    (null)
    (number)
    (fixup)
    (tn
     (ecase (sb-name (sc-sb (tn-sc loc)))
       (registers
	(unless (zerop (tn-offset loc))
	  (tn-offset loc)))
       (float-registers
	(sc-case loc
	  (single-reg
	   (+ (tn-offset loc) 32))
	  (double-reg
	   (let ((offset (tn-offset loc)))
	     (assert (zerop (mod offset 2)))
	     (values (+ offset 32) 2)))
	  #+long-float
	  (long-reg
	   (let ((offset (tn-offset loc)))
	     (assert (zerop (mod offset 4)))
	     (values (+ offset 32) 4)))))
       (control-registers
	96)
       (immediate-constant
	nil)))
    (symbol
     (ecase loc
       (:memory 0)
       (:psr 97)
       (:fsr 98)
       (:y 99)
       (:tick 100)))))

;;; symbols used for disassembly printing
;;;
(defparameter reg-symbols
  (map 'vector
       #'(lambda (name)
	   (cond ((null name) nil)
		 (t (make-symbol (concatenate 'string "%" name)))))
       sparc::*register-names*)
  "The Lisp names for the Sparc integer registers")

(defparameter sparc-reg-symbols
  (map 'vector
       #'(lambda (name)
	   (cond ((null name) nil)
		 (t (make-symbol (concatenate 'string "%" name)))))
       #("G0" "G1" "G2" "G3" "G4" "G5" "G6" "G7"
	 "O0" "O1" "O2" "O3" "O4" "O5" "O6" "O7"
	 "L0" "L1" "L2" "L3" "L4" "L5" "L6" "L7"
	 "I0" "I1" "I2" "I3" "I4" "I5" "I6" "I7"))
  "The standard names for the Sparc integer registers")
    
(defun get-reg-name (index)
  (if *disassem-use-lisp-reg-names*
      (aref reg-symbols index)
      (aref sparc-reg-symbols index)))

(defvar *note-sethi-inst* nil
  "An alist for the disassembler indicating the target register and
value used in a SETHI instruction.  This is used to make annotations
about function addresses and register values.")

(defvar *pseudo-atomic-set* nil)

(defun sign-extend-immed-value (val)
  ;; val is a 13-bit signed number.  Extend the sign appropriately.
  (if (logbitp 12 val)
      (- val (ash 1 13))
      val))

(defmacro frob-names (names)
  `(mapcar #'(lambda (n)
	       (list (eval n) n))
    ,names))

(defmacro frob-names (names)
  `(mapcar #'(lambda (n)
	       `(,(eval n) ,n))
    ,names))

(macrolet
    ((frob (&rest names)
       (let ((results (mapcar #'(lambda (n)
				  (let ((nn (intern (concatenate 'string (string n)
								 "-TYPE"))))
				    `(,(eval nn) ,nn)))
			      names)))
	 `(eval-when (compile load eval)
	   (defconstant header-word-type-alist
	     ',results)))))
  ;; This is the same list as in objdefs.
  (frob bignum
	ratio
	single-float
	double-float
	#+long-float long-float
	complex
	complex-single-float
	complex-double-float
	#+long-float complex-long-float
  
	simple-array
	simple-string
	simple-bit-vector
	simple-vector
	simple-array-unsigned-byte-2
	simple-array-unsigned-byte-4
	simple-array-unsigned-byte-8
	simple-array-unsigned-byte-16
	simple-array-unsigned-byte-32
	simple-array-signed-byte-8
	simple-array-signed-byte-16
	simple-array-signed-byte-30
	simple-array-signed-byte-32
	simple-array-single-float
	simple-array-double-float
	#+long-float simple-array-long-float
	simple-array-complex-single-float
	simple-array-complex-double-float
	#+long-float simple-array-complex-long-float
	complex-string
	complex-bit-vector
	complex-vector
	complex-array
  
	code-header
	function-header
	closure-header
	funcallable-instance-header
	byte-code-function
	byte-code-closure
	dylan-function-header
	closure-function-header
	#-gengc return-pc-header
	#+gengc forwarding-pointer
	value-cell-header
	symbol-header
	base-char
	sap
	unbound-marker
	weak-pointer
	instance-header
	fdefn
	#+(or gengc gencgc) scavenger-hook))

;; Look at the current instruction and see if we can't add some notes
;; about what's happening.

(defun maybe-add-notes (reg dstate)
  (let* ((word (disassem::sap-ref-int (disassem:dstate-segment-sap dstate)
				      (disassem:dstate-cur-offs dstate)
				      vm:word-bytes
				      (disassem::dstate-byte-order dstate)))
	 (format (ldb (byte 2 30) word))
	 (op3 (ldb (byte 6 19) word))
	 (rs1 (ldb (byte 5 14) word))
	 (rd (ldb (byte 5 25) word))
	 (immed-p (not (zerop (ldb (byte 1 13) word))))
	 (immed-val (sign-extend-immed-value (ldb (byte 13 0) word))))
    ;; Only the value of format and rd are guaranteed to be correct
    ;; because the disassembler is trying to print out the value of a
    ;; register.  The other values may not be right.
    (case format
      (2
       (case op3
	 (#b000000
	  (when (= reg rs1)
	    (handle-add-inst rs1 immed-val rd dstate immed-p)))
	 (#b000010
	  (when (= reg rs1)
	    (handle-or-inst rs1 immed-val rd dstate immed-p)))
	 (#b000101
	  (when (= reg rs1)
	    (handle-andn-inst rs1 immed-val rd dstate immed-p)))
	 (#b111000
	  (when (= reg rs1)
	    (handle-jmpl-inst rs1 immed-val rd dstate)))
	 (#b010001
	  (when (= reg rs1)
	    (handle-andcc-inst rs1 immed-val rd dstate)))))
      (3
       (case op3
	 ((#b000000 #b000100)
	  (when (= reg rs1)
	    (handle-ld/st-inst rs1 immed-val rd dstate))))))
    ;; If this is not a SETHI instruction, and RD is the same as some
    ;; register used by SETHI, we delete the entry.  (In case we have
    ;; a SETHI without any additional instruction because the low bits
    ;; were zero.)
    (unless (and (zerop format) (= #b100 (ldb (byte 3 22) word)))
      (let ((sethi (assoc rd *note-sethi-inst*)))
	(when sethi
	  (setf *note-sethi-inst* (delete sethi *note-sethi-inst*)))))))

(defun handle-add-inst (rs1 immed-val rd dstate immed-p)
  (let* ((sethi (assoc rs1 *note-sethi-inst*)))
    (cond
      (sethi
       ;; RS1 was used in a SETHI instruction.  Assume that
       ;; this is the offset part of the SETHI instruction for
       ;; a full 32-bit address of something.  Make a note
       ;; about this usage as a Lisp assembly routine or
       ;; foreign routine, if possible.  If not, just note the
       ;; final value.
       (let ((addr (+ immed-val (ash (cdr sethi) 10))))
	 (or (disassem::note-code-constant-absolute addr dstate)
	     (disassem::maybe-note-assembler-routine addr t dstate)
	     (disassem::note (format nil "~A = #x~8,'0X"
				     (get-reg-name rd) addr)
			     dstate)))
       (setf *note-sethi-inst* (delete sethi *note-sethi-inst*)))
      ((and (= rs1 null-offset) immed-p)
       ;; We have an ADD %NULL, <n>, RD instruction.  This is a
       ;; reference to a static symbol.
       (disassem:maybe-note-nil-indexed-object immed-val
					       dstate))
      ((= rs1 alloc-offset)
       ;; ADD %ALLOC, n.  This must be some allocation or
       ;; pseudo-atomic stuff
       (cond ((and immed-p
		   (= immed-val 4)
		   (= rd alloc-offset)
		   (not *pseudo-atomic-set*))
	      ;; "ADD 4, %ALLOC" sets the flag
	      (disassem:note "Set pseudo-atomic flag" dstate)
	      (setf *pseudo-atomic-set* t))
	     ((= rd alloc-offset)
	      ;; "ADD n, %ALLOC" is either allocating space or
	      ;; resetting the flag.
	      (cond (immed-p
		     (cond ((= immed-val -4)
			    (disassem:note
			     (format nil "Reset pseudo-atomic")
			     dstate)
			    (setf *pseudo-atomic-set* nil))
			   (t
			    (disassem:note
			     (format nil "Allocating ~D bytes" immed-val)
			     dstate))))
		    (t
		     ;; Some other allocation
		     (disassem:note
			     (format nil "Allocating bytes")
			     dstate))))))
      ((and (= rs1 zero-offset) *pseudo-atomic-set*)
       ;; "ADD %ZERO, num, RD" inside a pseudo-atomic is very
       ;; likely loading up a header word.  Make a note to that
       ;; effect.
       (let ((type (second (assoc (logand immed-val #xff) header-word-type-alist)))
	     (size (ldb (byte 24 8) immed-val)))
	 (when type
	   (disassem:note (format nil "Header word ~A, size ~D?" type size)
			  dstate)))))))

(defun handle-or-inst (rs1 immed-val rd dstate immed-p)
  (let* ((sethi (assoc rs1 *note-sethi-inst*)))
    (cond
      ((= rs1 alloc-offset)
       ;; OR %ALLOC, n.  This must be some allocation or
       ;; pseudo-atomic stuff
       (cond ((and immed-p
		   (= immed-val pseudo-atomic-value)
		   (= rd alloc-offset)
		   (not *pseudo-atomic-set*))
	      ;; "OR 4, %ALLOC" sets the flag
	      (disassem:note "Set pseudo-atomic flag" dstate)
	      (setf *pseudo-atomic-set* t)))))))

(defun handle-andn-inst (rs1 immed-val rd dstate immed-p)
  (let* ((sethi (assoc rs1 *note-sethi-inst*)))
    (cond
      ((= rs1 alloc-offset)
       ;; ANDN %ALLOC, n.  Resetting pseudo-atomic
       (cond ((and immed-p
		   (= immed-val pseudo-atomic-value)
		   (= rd alloc-offset)
		   *pseudo-atomic-set*)
	      ;; "ANDN 4, %ALLOC" resets the flag
	      ;;(format t "Got reset~%")
	      (disassem:note "Reset pseudo-atomic flag" dstate)
	      (setf *pseudo-atomic-set* nil)))))))

(defun handle-jmpl-inst (rs1 immed-val rd dstate)
  (declare (ignore rd))
  (let* ((sethi (assoc rs1 *note-sethi-inst*)))
    (when sethi
      ;; RS1 was used in a SETHI instruction.  Assume that
      ;; this is the offset part of the SETHI instruction for
      ;; a full 32-bit address of something.  Make a note
      ;; about this usage as a Lisp assembly routine or
      ;; foreign routine, if possible.  If not, just note the
      ;; final value.
      (let ((addr (+ immed-val (ash (cdr sethi) 10))))
	(disassem::maybe-note-assembler-routine addr t dstate)
	(setf *note-sethi-inst* (delete sethi *note-sethi-inst*))))))

(defun handle-ld/st-inst (rs1 immed-val rd dstate)
  (declare (ignore rd))
  ;; Got an LDUW/LD or STW instruction, with immediate offset.
  (case rs1
    (29
     ;; A reference to a code constant (reg = %CODE)
     (disassem:note-code-constant immed-val dstate))
    (2
     ;; A reference to a static symbol or static function (reg =
     ;; %NULL)
     (or (disassem:maybe-note-nil-indexed-symbol-slot-ref immed-val
						      dstate)
	 (disassem:maybe-note-static-function immed-val dstate)))
    (t
     (let ((sethi (assoc rs1 *note-sethi-inst*)))
       (when sethi
	 (let ((addr (+ immed-val (ash (cdr sethi) 10))))
	   (disassem::maybe-note-assembler-routine addr nil dstate)
	   (setf *note-sethi-inst* (delete sethi *note-sethi-inst*))))))))

(defun handle-andcc-inst (rs1 immed-val rd dstate)
  ;; ANDCC %ALLOC, 3, %ZERO instruction
  (when (and (= rs1 alloc-offset) (= rd zero-offset) (= immed-val 3))
    (disassem:note "pseudo-atomic interrupted?" dstate)))
	 
(eval-when (compile load eval)
(defun reg-arg-printer (value stream dstate)
  (declare (stream stream) (fixnum value))
  (let ((regname (get-reg-name value)))
    (princ regname stream)
    (disassem:maybe-note-associated-storage-ref value
						'registers
						regname
						dstate)
    (maybe-add-notes value dstate)))
) ; eval-when
      
(disassem:define-argument-type reg
  :printer #'reg-arg-printer)

(defparameter float-reg-symbols
  (coerce 
   (loop for n from 0 to 63 collect (make-symbol (format nil "%F~d" n)))
   'vector))

(disassem:define-argument-type fp-reg
  :printer #'(lambda (value stream dstate)
	       (declare (stream stream) (fixnum value))
	       (let ((regname (aref float-reg-symbols value)))
		 (princ regname stream)
		 (disassem:maybe-note-associated-storage-ref
		  value
		  'float-registers
		  regname
		  dstate))))

;;; The extended 6 bit floating point register encoding for the double
;;; and long instructions of the sparc v9.
(disassem:define-argument-type fp-ext-reg
  :printer #'(lambda (value stream dstate)
	       (declare (stream stream) (fixnum value))
	       (let* (;; Decode the register number.
		      (value (if (oddp value) (+ value 31) value))
		      (regname (aref float-reg-symbols value)))
		 (princ regname stream)
		 (disassem:maybe-note-associated-storage-ref
		  value
		  'float-registers
		  regname
		  dstate))))

(disassem:define-argument-type relative-label
  :sign-extend t
  :use-label #'(lambda (value dstate)
		 (declare (type (signed-byte 22) value)
			  (type disassem:disassem-state dstate))
		 (+ (ash value 2) (disassem:dstate-cur-addr dstate))))

(defconstant branch-conditions
  '(:f :eq :le :lt :leu :ltu :n :vs :t :ne :gt :ge :gtu :geu :p :vc))

;;; Note that these aren't the standard names for branch-conditions, I think
;;; they're a bit more readable (e.g., "eq" instead of "e").  You could just
;;; put a vector of the normal ones here too.
(defconstant branch-cond-name-vec
  (coerce branch-conditions 'vector))

(disassem:define-argument-type branch-condition
  :printer branch-cond-name-vec)

(deftype branch-condition ()
  `(member ,@branch-conditions))

(defun branch-condition (condition)
  (or (position condition branch-conditions)
      (error "Unknown branch condition: ~S~%Must be one of: ~S"
	     condition branch-conditions)))

(defconstant branch-cond-true
  #b1000)

(defconstant branch-fp-conditions
  '(:f :ne :lg :ul :l :ug :g :u :t :eq :ue :ge :uge :le :ule :o))

(defconstant branch-fp-cond-name-vec
  (coerce branch-fp-conditions 'vector))

(disassem:define-argument-type branch-fp-condition
  :printer branch-fp-cond-name-vec)

(disassem:define-argument-type call-fixup :use-label t)

(deftype fp-branch-condition ()
  `(member ,@branch-fp-conditions))

(defun fp-branch-condition (condition)
  (or (position condition branch-fp-conditions)
      (error "Unknown fp-branch condition: ~S~%Must be one of: ~S"
	     condition branch-fp-conditions)))


;;;; dissassem:define-instruction-formats

(disassem:define-instruction-format
    (format-1 32 :default-printer '(:name :tab disp))
  (op   :field (byte 2 30) :value 1)
  (disp :field (byte 30 0)))

(disassem:define-instruction-format
    (format-2-immed 32 :default-printer '(:name :tab immed ", " rd))
  (op    :field (byte 2 30) :value 0)
  (rd    :field (byte 5 25) :type 'reg)
  (op2   :field (byte 3 22))
  (immed :field (byte 22 0)))

(defconstant branch-printer
  `(:name (:unless (:constant ,branch-cond-true) cond)
	  (:unless (a :constant 0) "," 'A)
	  :tab
	  disp))

(disassem:define-instruction-format
    (format-2-branch 32 :default-printer branch-printer)
  (op   :field (byte 2 30) :value 0)
  (a    :field (byte 1 29) :value 0)
  (cond :field (byte 4 25) :type 'branch-condition)
  (op2  :field (byte 3 22))
  (disp :field (byte 22 0) :type 'relative-label))

;; Branch with prediction instruction for V9

;; Currently only %icc and %xcc are used of the four possible values

(defconstant integer-condition-registers
  '(:icc :reserved :xcc :reserved))

(defconstant integer-cond-reg-name-vec
  (coerce integer-condition-registers 'vector))

(deftype integer-condition-register ()
  `(member ,@(remove :reserved integer-condition-registers)))

(defparameter integer-condition-reg-symbols
  (map 'vector
       #'(lambda (name)
	   (make-symbol (concatenate 'string "%" (string name))))
       integer-condition-registers))

(disassem:define-argument-type integer-condition-register
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((regname (aref integer-condition-reg-symbols value)))
		   (princ regname stream))))

(defconstant branch-predictions
  '(:pn :pt))

(defconstant branch-predictions-name-vec
  (coerce branch-predictions 'vector))

(disassem:define-argument-type branch-prediction
    :printer branch-predictions-name-vec)

(defun integer-condition (condition-reg)
  (declare (type (member :icc :xcc) condition-reg))
  (or (position condition-reg integer-condition-registers)
      (error "Unknown integer condition register:  ~S~%"
	     condition-reg)))

(defun branch-prediction (pred)
  (or (position pred branch-predictions)
      (error "Unknown branch prediction:  ~S~%Must be one of: ~S~%"
	     pred branch-predictions)))

(defconstant branch-pred-printer
  `(:name (:unless (:constant ,branch-cond-true) cond)
	  (:unless (a :constant 0) "," 'A)
          (:unless (p :constant 1) "," 'pn)
	  :tab
	  cc
	  ", "
	  disp))

(disassem:define-instruction-format
    (format-2-branch-pred 32 :default-printer branch-pred-printer)
  (op   :field (byte 2 30) :value 0)
  (a    :field (byte 1 29) :value 0)
  (cond :field (byte 4 25) :type 'branch-condition)
  (op2  :field (byte 3 22))
  (cc   :field (byte 2 20) :type 'integer-condition-register)
  (p    :field (byte 1 19))
  (disp :field (byte 19 0) :type 'relative-label))

(defconstant fp-condition-registers
  '(:fcc0 :fcc1 :fcc2 :fcc3))

(defconstant fp-cond-reg-name-vec
  (coerce fp-condition-registers 'vector))

(defparameter fp-condition-reg-symbols
  (map 'vector
       #'(lambda (name)
	   (make-symbol (concatenate 'string "%" (string name))))
       fp-condition-registers))

(disassem:define-argument-type fp-condition-register
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((regname (aref fp-condition-reg-symbols value)))
		   (princ regname stream))))

(disassem:define-argument-type fp-condition-register-shifted
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((regname (aref fp-condition-reg-symbols (ash value -1))))
		   (princ regname stream))))

(defun fp-condition (condition-reg)
  (or (position condition-reg fp-condition-registers)
      (error "Unknown integer condition register:  ~S~%"
	     condition-reg)))

(defconstant fp-branch-pred-printer
  `(:name (:unless (:constant ,branch-cond-true) cond)
	  (:unless (a :constant 0) "," 'A)
	  (:unless (p :constant 1) "," 'pn)
	  :tab
	  fcc
	  ", "
	  disp))
  
(disassem:define-instruction-format
    (format-2-fp-branch-pred 32 :default-printer fp-branch-pred-printer)
  (op   :field (byte 2 30) :value 0)
  (a    :field (byte 1 29) :value 0)
  (cond :field (byte 4 25) :type 'branch-fp-condition)
  (op2  :field (byte 3 22))
  (fcc  :field (byte 2 20) :type 'fp-condition-register)
  (p    :field (byte 1 19))
  (disp :field (byte 19 0) :type 'relative-label))
  


(disassem:define-instruction-format
    (format-2-unimp 32 :default-printer '(:name :tab data))
  (op     :field (byte 2 30) :value 0)
  (ignore :field (byte 5 25) :value 0)
  (op2    :field (byte 3 22) :value 0)
  (data   :field (byte 22 0)))

(defconstant f3-printer
  '(:name :tab
	  (:unless (:same-as rd) rs1 ", ")
	  (:choose rs2 immed) ", "
	  rd))

(disassem:define-instruction-format
    (format-3-reg 32 :default-printer f3-printer)
  (op  :field (byte 2 30))
  (rd  :field (byte 5 25) :type 'reg)
  (op3 :field (byte 6 19))
  (rs1 :field (byte 5 14) :type 'reg)
  (i   :field (byte 1 13) :value 0)
  (asi :field (byte 8 5)  :value 0)
  (rs2 :field (byte 5 0)  :type 'reg))

(disassem:define-instruction-format
    (format-3-immed 32 :default-printer f3-printer)
  (op    :field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3   :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 1)
  (immed :field (byte 13 0) :sign-extend t))	; usually sign extended

(disassem:define-instruction-format
    (format-binary-fpop 32
     :default-printer '(:name :tab rs1 ", " rs2 ", " rd))
  (op	:field (byte 2 30))
  (rd 	:field (byte 5 25) :type 'fp-reg)
  (op3  :field (byte 6 19))
  (rs1  :field (byte 5 14) :type 'fp-reg)
  (opf  :field (byte 9 5))
  (rs2  :field (byte 5 0) :type 'fp-reg))

;;; Floating point load/save instructions encoding.
(disassem:define-instruction-format
    (format-unary-fpop 32 :default-printer '(:name :tab rs2 ", " rd))
  (op	:field (byte 2 30))
  (rd 	:field (byte 5 25) :type 'fp-reg)
  (op3  :field (byte 6 19))
  (rs1  :field (byte 5 14) :value 0)
  (opf  :field (byte 9 5))
  (rs2  :field (byte 5 0) :type 'fp-reg))

;;; Floating point comparison instructions encoding.

;; This is a merge of the instructions for FP comparison and FP
;; conditional moves available in the Sparc V9.  The main problem is
;; that the new instructions use part of the opcode space used by the
;; comparison instructions.  In particular, the OPF field is arranged
;; as so:
;;
;; Bit          1       0
;;              3       5
;; FMOVcc	0nn0000xx	%fccn
;;		1000000xx	%icc
;;		1100000xx	%xcc
;; FMOVR	0ccc001yy
;; FCMP		001010zzz
;;
;; So we see that if we break up the OPF field into 4 pieces, opf0,
;; opf1, opf2, and opf3, we can distinguish between these
;; instructions. So bit 9 (opf2) can be used to distinguish between
;; FCMP and the rest.  Also note that the nn field overlaps with the
;; ccc.  We need to take this into account as well.
;;
(disassem:define-instruction-format
    (format-fpop2 32
		  :default-printer #-sparc-v9 '(:name :tab rs1 ", " rs2)
		                   #+sparc-v9 '(:name :tab rd ", " rs1 ", " rs2))
  (op	:field (byte 2 30))
  (rd 	:field (byte 5 25) :value 0)
  (op3  :field (byte 6 19))
  (rs1  :field (byte 5 14))
  (opf0 :field (byte 1 13))
  (opf1 :field (byte 3 10))
  (opf2 :field (byte 1 9))
  (opf3 :field (byte 4 5))
  (rs2  :field (byte 5 0) :type 'fp-reg))

;;; Shift instructions
(disassem:define-instruction-format
    (format-3-shift-reg 32 :default-printer f3-printer)
  (op	:field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3  :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 0)
  (x     :field (byte 1 12))
  (asi   :field (byte 7 5) :value 0)
  (rs2   :field (byte 5 0) :type 'reg))

(disassem:define-instruction-format
    (format-3-shift-immed 32 :default-printer f3-printer)
  (op	:field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3  :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 1)
  (x     :field (byte 1 12))
  (immed :field (byte 12 0) :sign-extend nil))


;;; Conditional moves (only available for Sparc V9 architectures)

;; The names of all of the condition registers on the V9: 4 FP
;; conditions, the original integer condition register and the new
;; extended register.  The :reserved register is reserved on the V9.

(defconstant cond-move-condition-registers
  '(:fcc0 :fcc1 :fcc2 :fcc3 :icc :reserved :xcc :reserved))
(defconstant cond-move-cond-reg-name-vec
  (coerce cond-move-condition-registers 'vector))

(deftype cond-move-condition-register ()
    `(member ,@(remove :reserved cond-move-condition-registers)))

(defparameter cond-move-condition-reg-symbols
  (map 'vector
       #'(lambda (name)
	   (make-symbol (concatenate 'string "%" (string name))))
       cond-move-condition-registers))

(disassem:define-argument-type cond-move-condition-register
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((regname (aref cond-move-condition-reg-symbols value)))
		   (princ regname stream))))

;; From the given condition register, figure out what the cc2, cc1,
;; and cc0 bits should be.  Return cc2 and cc1/cc0 concatenated.
(defun cond-move-condition-parts (condition-reg)
  (let ((posn (position condition-reg cond-move-condition-registers)))
    (if posn
	(truncate posn 4)
	(error "Unknown conditional move condition register:  ~S~%"
	       condition-reg))))

(defun cond-move-condition (condition-reg)
  (or (position condition-reg cond-move-condition-registers)
      (error "Unknown conditional move condition register:  ~S~%" condition-reg)))

(defconstant cond-move-printer
  `(:name cond :tab
          cc ", " (:choose immed rs2) ", " rd))

;; Conditional move integer register on integer or FP condition code
(disassem:define-instruction-format
    (format-4-cond-move 32 :default-printer cond-move-printer)
  (op	:field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3  :field (byte 6 19))
  (cc2   :field (byte 1 18) :value 1)
  (cond  :field (byte 4 14) :type 'branch-condition)
  (i     :field (byte 1 13) :value 0)
  (cc    :field (byte 2 11) :type 'integer-condition-register)
  (empty :field (byte 6 5) :value 0)
  (rs2   :field (byte 5 0) :type 'reg))

(disassem:define-instruction-format
    (format-4-cond-move-immed 32 :default-printer cond-move-printer)
  (op    :field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3   :field (byte 6 19))
  (cc2   :field (byte 1 18) :value 1)
  (cond  :field (byte 4 14) :type 'branch-condition)
  (i     :field (byte 1 13) :value 1)
  (cc    :field (byte 2 11) :type 'integer-condition-register)
  (immed :field (byte 11 0) :sign-extend t))

;; Floating-point versions of the above integer conditional moves
(defconstant cond-fp-move-printer
  `(:name rs1 :tab opf1 ", " rs2 ", " rd))

;;; Conditional move on integer register condition (only on Sparc
;;; V9). That is, move an integer register if some other integer
;;; register satisfies some condition.

(defconstant cond-move-integer-conditions
  '(:reserved :z :lez :lz :reserved :nz :gz :gez))
(defconstant cond-move-integer-condition-vec
  (coerce cond-move-integer-conditions 'vector))

(deftype cond-move-integer-condition ()
  `(member ,@(remove :reserved cond-move-integer-conditions)))

(disassem:define-argument-type register-condition
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((regname (aref cond-move-integer-condition-vec value)))
		   (princ regname stream))))

(defconstant cond-move-integer-printer
  `(:name rcond :tab rs1 ", " (:choose immed rs2) ", " rd))

(defun register-condition (rcond)
  (or (position rcond cond-move-integer-conditions)
      (error "Unknown register condition:  ~S~%" rcond)))

(disassem:define-instruction-format
    (format-4-cond-move-integer 32 :default-printer cond-move-integer-printer)
  (op    :field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3   :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 0)
  (rcond :field (byte 3 10) :type 'register-condition)
  (opf   :field (byte 5 5))
  (rs2   :field (byte 5 0) :type 'reg))

(disassem:define-instruction-format
    (format-4-cond-move-integer-immed 32 :default-printer cond-move-integer-printer)
  (op    :field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3   :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 1)
  (rcond :field (byte 3 10) :type 'register-condition)
  (immed :field (byte 10 0) :sign-extend t))

(defconstant trap-printer
  `(:name rd :tab cc ", " rs1 "+" rs2))

(defconstant trap-immed-printer
  `(:name rd :tab cc ", " (:unless (rs1 :constant 0) rs1 "+") immed))


(disassem:define-instruction-format
    (format-4-trap-immed 32 :default-printer trap-immed-printer)
  (op    :field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3   :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 1)
  (cc    :field (byte 2 11) :type 'integer-condition-register)
  (immed :field (byte 11 0)))


(disassem:define-instruction-format
    (format-4-trap 32 :default-printer trap-printer)
  (op    :field (byte 2 30))
  (rd    :field (byte 5 25) :type 'reg)
  (op3   :field (byte 6 19))
  (rs1   :field (byte 5 14) :type 'reg)
  (i     :field (byte 1 13) :value 0)
  (cc    :field (byte 2 11) :type 'integer-condition-register)
  (rs2   :field (byte 11 0) :type 'reg))


(defconstant cond-fp-move-integer-printer
  `(:name opf1 :tab rs1 ", " rs2 ", " rd))


;;;; Primitive emitters.

(define-emitter emit-word 32
  (byte 32 0))

(define-emitter emit-short 16
  (byte 16 0))

(define-emitter emit-format-1 32
  (byte 2 30) (byte 30 0))

(define-emitter emit-format-2-immed 32
  (byte 2 30) (byte 5 25) (byte 3 22) (byte 22 0))

(define-emitter emit-format-2-branch 32
  (byte 2 30) (byte 1 29) (byte 4 25) (byte 3 22) (byte 22 0))

;; Integer and FP branches with prediction for V9
(define-emitter emit-format-2-branch-pred 32
  (byte 2 30) (byte 1 29) (byte 4 25) (byte 3 22) (byte 2 20) (byte 1 19) (byte 19 0))
(define-emitter emit-format-2-fp-branch-pred 32
  (byte 2 30) (byte 1 29) (byte 4 25) (byte 3 22) (byte 2 20) (byte 1 19) (byte 19 0))
  
(define-emitter emit-format-2-unimp 32
  (byte 2 30) (byte 5 25) (byte 3 22) (byte 22 0))

(define-emitter emit-format-3-reg 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 8 5)
  (byte 5 0))

(define-emitter emit-format-3-immed 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 13 0))

(define-emitter emit-format-3-fpop 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 9 5) (byte 5 0))

(define-emitter emit-format-3-fpop2 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14)
  (byte 1 13) (byte 3 10) (byte 1 9) (byte 4 5)
  (byte 5 0))

;;; Shift instructions

(define-emitter emit-format-3-shift-reg 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 1 12) (byte 7 5)
  (byte 5 0))

(define-emitter emit-format-3-shift-immed 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 1 12) (byte 12 0))

;;; Conditional moves

;; Conditional move in condition code
(define-emitter emit-format-4-cond-move 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 1 18) (byte 4 14) (byte 1 13) (byte 2 11)
  (byte 11 0))

;; Conditional move on integer condition
(define-emitter emit-format-4-cond-move-integer 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 3 10) (byte 5 5)
  (byte 5 0))

(define-emitter emit-format-4-cond-move-integer-immed 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 3 10)
  (byte 10 0))

(define-emitter emit-format-4-trap 32
  (byte 2 30) (byte 5 25) (byte 6 19) (byte 5 14) (byte 1 13) (byte 2 11)
  (byte 11 0))
  

;;;; Most of the format-3-instructions.

(defun emit-format-3-inst (segment op op3 dst src1 src2
				   &key load-store fixup dest-kind)
  (unless src2
    (cond ((and (typep src1 'tn) load-store)
	   (setf src2 0))
	  (t
	   (setf src2 src1)
	   (setf src1 dst))))
  (etypecase src2
    (tn
     (emit-format-3-reg segment op
			(if dest-kind
			    (fp-reg-tn-encoding dst)
			    (reg-tn-encoding dst))
			op3 (reg-tn-encoding src1) 0 0 (reg-tn-encoding src2)))
    (integer
     (emit-format-3-immed segment op
			  (if dest-kind
			      (fp-reg-tn-encoding dst)
			      (reg-tn-encoding dst))
			  op3 (reg-tn-encoding src1) 1 src2))
    (fixup
     (unless (or load-store fixup)
       (error "Fixups aren't allowed."))
     (note-fixup segment :add src2)
     (emit-format-3-immed segment op
			  (if dest-kind
			      (fp-reg-tn-encoding dst)
			      (reg-tn-encoding dst))
			  op3 (reg-tn-encoding src1) 1 0))))

;;; Shift instructions because an extra bit is used in Sparc V9's to
;;; indicate whether the shift is a 32-bit or 64-bit shift.
;;;
(defun emit-format-3-shift-inst (segment op op3 dst src1 src2 &key extended)
  (unless src2
    (setf src2 src1)
    (setf src1 dst))
  (etypecase src2
    (tn
     (emit-format-3-shift-reg segment op (reg-tn-encoding dst)
			      op3 (reg-tn-encoding src1) 0 (if extended 1 0)
			      0 (reg-tn-encoding src2)))
    (integer
     (emit-format-3-shift-immed segment op (reg-tn-encoding dst)
				op3 (reg-tn-encoding src1) 1
				(if extended 1 0) src2))))


(eval-when (compile eval)

;;; have to do this because defconstant is evalutated in the null lex env.
(defmacro with-ref-format (printer)
  `(let* ((addend
	   '(:choose (:plus-integer immed) ("+" rs2)))
	  (ref-format
	   `("[" rs1 (:unless (:constant 0) ,addend) "]"
	     (:choose (:unless (:constant 0) asi) nil))))
     ,printer))

(defconstant load-printer
  (with-ref-format `(:NAME :TAB ,ref-format ", " rd)))

(defconstant store-printer
  (with-ref-format `(:NAME :TAB rd ", " ,ref-format)))

(defmacro define-f3-inst (name op op3 &key fixup load-store (dest-kind 'reg)
			       (printer :default) reads writes flushable print-name)
  (let ((printer
	 (if (eq printer :default)
	     (case load-store
	       ((nil) :default)
	       ((:load t) 'load-printer)
	       (:store 'store-printer))
	     printer)))
    (when (and (atom reads) (not (null reads)))
      (setf reads (list reads)))
    (when (and (atom writes) (not (null writes)))
       (setf writes (list writes)))
    `(define-instruction ,name (segment dst src1 &optional src2)
       (:declare (type tn dst)
		 ,(if (or fixup load-store)
		      '(type (or tn (signed-byte 13) null fixup) src1 src2)
		      '(type (or tn (signed-byte 13) null) src1 src2)))
       (:printer format-3-reg
		 ((op ,op) (op3 ,op3) (rd nil :type ',dest-kind))
	 	 ,printer
	         ,@(when print-name `(:print-name ,print-name)))
       (:printer format-3-immed
	 	 ((op ,op) (op3 ,op3) (rd nil :type ',dest-kind))
	 	 ,printer
	         ,@(when print-name `(:print-name ,print-name)))
       ,@(when flushable
	   '((:attributes flushable)))
       (:dependencies
	(reads src1)
	,@(let ((reads-list nil))
	    (dolist (read reads)
	      (push (list 'reads read) reads-list))
	    reads-list)
	,@(cond ((eq load-store :store)
		 '((reads dst)
		   (if src2 (reads src2))))
		 ((eq load-store t)
		  '((reads :memory)
		    (reads dst)
		    (if src2 (reads src2))))
		((eq load-store :load)
		 '((reads :memory)
		   (if src2 (reads src2) (reads dst))))
		(t
		 '((if src2 (reads src2) (reads dst)))))
	,@(let ((writes-list nil))
	    (dolist (write writes)
	      (push (list 'writes write) writes-list))
	    writes-list)
	,@(cond ((eq load-store :store)
		 '((writes :memory :partially t)))
		((eq load-store t)
		 '((writes :memory :partially t)
		   (writes dst)))
		((eq load-store :load)
		 '((writes dst)))
		(t
		 '((writes dst)))))
       (:delay 0)
       (:emitter (emit-format-3-inst segment ,op ,op3 dst src1 src2
				     :load-store ,load-store
				     :fixup ,fixup
				     :dest-kind (not (eq ',dest-kind 'reg)))))))

(defmacro define-f3-shift-inst (name op op3 &key extended)
  `(define-instruction ,name (segment dst src1 &optional src2)
     (:declare (type tn dst)
	       (type (or tn (unsigned-byte 6) null) src1 src2))
     (:printer format-3-shift-reg
	       ((op ,op) (op3 ,op3) (x ,(if extended 1 0)) (i 0)))
     (:printer format-3-shift-immed
	       ((op ,op) (op3 ,op3) (x ,(if extended 1 0)) (i 1)))
     (:dependencies
      (reads src1)
      (if src2 (reads src2) (reads dst))
      (writes dst))
     (:delay 0)
     (:emitter (emit-format-3-shift-inst segment ,op ,op3 dst src1 src2
					 :extended ,extended))))

) ; eval-when (compile eval)

(define-f3-inst ldsb #b11 #b001001 :load-store :load)
(define-f3-inst ldsh #b11 #b001010 :load-store :load)
(define-f3-inst ldub #b11 #b000001 :load-store :load)
(define-f3-inst lduh #b11 #b000010 :load-store :load)

;; This instruction is called lduw for V9 , but looks exactly like ld
;; on previous architectures.
(define-f3-inst ld #b11 #b000000 :load-store :load
		#+sparc-v9 :print-name #+sparc-v9 'lduw)

(define-f3-inst ldsw #b11 #b001000 :load-store :load) ; v9

;; ldd is deprecated on the Sparc V9.
(define-f3-inst ldd #b11 #b000011 :load-store :load)

(define-f3-inst ldx #b11 #b001011 :load-store :load) ; v9

(define-f3-inst ldf #b11 #b100000 :dest-kind fp-reg :load-store :load)
(define-f3-inst lddf #b11 #b100011 :dest-kind fp-reg :load-store :load)
(define-f3-inst ldqf #b11 #b100010 :dest-kind fp-reg :load-store :load)	; v9
(define-f3-inst stb #b11 #b000101 :load-store :store)
(define-f3-inst sth #b11 #b000110 :load-store :store)
(define-f3-inst st #b11 #b000100 :load-store :store)

;; std is deprecated on the Sparc V9.
(define-f3-inst std #b11 #b000111 :load-store :store)

(define-f3-inst stx #b11 #b001110 :load-store :store) ; v9

(define-f3-inst stf #b11 #b100100 :dest-kind fp-reg :load-store :store)
(define-f3-inst stdf #b11 #b100111 :dest-kind fp-reg :load-store :store)
(define-f3-inst stqf #b11 #b100110 :dest-kind fp-reg :load-store :store) ; v9
(define-f3-inst ldstub #b11 #b001101 :load-store t)

;; swap is deprecated on the Sparc V9
(define-f3-inst swap #b11 #b001111 :load-store t)

(define-f3-inst add #b10 #b000000 :fixup t)
(define-f3-inst addcc #b10 #b010000 :writes :psr)
(define-f3-inst addx #b10 #b001000 :reads :psr)
(define-f3-inst addxcc #b10 #b011000 :reads :psr :writes :psr)
(define-f3-inst taddcc #b10 #b100000 :writes :psr)

;; taddcctv is deprecated on the Sparc V9.  Use taddcc and bpvs or
;; taddcc and trap to get a similar effect.  (Requires changing the C
;; code though!)
;;(define-f3-inst taddcctv #b10 #b100010 :writes :psr)

(define-f3-inst sub #b10 #b000100)
(define-f3-inst subcc #b10 #b010100 :writes :psr)
(define-f3-inst subx #b10 #b001100 :reads :psr)
(define-f3-inst subxcc #b10 #b011100 :reads :psr :writes :psr)
(define-f3-inst tsubcc #b10 #b100001 :writes :psr)

;; tsubcctv is deprecated on the Sparc V9.  Use tsubcc and bpvs or
;; tsubcc and trap to get a similar effect.  (Requires changing the C
;; code though!)
;;(define-f3-inst tsubcctv #b10 #b100011 :writes :psr)

(define-f3-inst mulscc #b10 #b100100 :reads :y :writes (:psr :y))
(define-f3-inst and #b10 #b000001)
(define-f3-inst andcc #b10 #b010001 :writes :psr)
(define-f3-inst andn #b10 #b000101)
(define-f3-inst andncc #b10 #b010101 :writes :psr)
(define-f3-inst or #b10 #b000010)
(define-f3-inst orcc #b10 #b010010 :writes :psr)
(define-f3-inst orn #b10 #b000110)
(define-f3-inst orncc #b10 #b010110 :writes :psr)
(define-f3-inst xor #b10 #b000011)
(define-f3-inst xorcc #b10 #b010011 :writes :psr)
(define-f3-inst xnor #b10 #b000111)
(define-f3-inst xnorcc #b10 #b010111 :writes :psr)

(define-f3-shift-inst sll #b10 #b100101)
(define-f3-shift-inst srl #b10 #b100110)
(define-f3-shift-inst sra #b10 #b100111)
(define-f3-shift-inst sllx #b10 #b100101 :extended t)	; v9
(define-f3-shift-inst srlx #b10 #b100110 :extended t)	; v9
(define-f3-shift-inst srax #b10 #b100111 :extended t)	; v9

(define-f3-inst save #b10 #b111100 :reads :psr :writes :psr)
(define-f3-inst restore #b10 #b111101 :reads :psr :writes :psr)

;; smul, smulcc, umul, umulcc, sdiv, sdivcc, udiv, and udivcc are
;; deprecated on the Sparc V9.  Use mulx, sdivx, and udivx instead.
(define-f3-inst smul #b10 #b001011 :writes :y)			; v8
(define-f3-inst smulcc #b10 #b011011 :writes (:psr :y))		; v8
(define-f3-inst umul #b10 #b001010 :writes :y)			; v8
(define-f3-inst umulcc #b10 #b011010 :writes (:psr :y))		; v8
(define-f3-inst sdiv #b10 #b001111 :reads :y)			; v8
(define-f3-inst sdivcc #b10 #b011111 :reads :y :writes :psr)	; v8
(define-f3-inst udiv #b10 #b001110 :reads :y)			; v8
(define-f3-inst udivcc #b10 #b011110 :reads :y :writes :psr)	; v8

(define-f3-inst mulx #b10 #b001001)	; v9 for both signed and unsigned
(define-f3-inst sdivx #b10 #b101101)	; v9
(define-f3-inst udivx #b10 #b001101)	; v9

(define-f3-inst popc #b10 #b101110)	; v9: count one bits


;;;; Random instructions.

;; ldfsr is deprecated on the Sparc V9.  Use ldxfsr instead
(define-instruction ldfsr (segment src1 src2)
  (:declare (type tn src1) (type (signed-byte 13) src2))
  (:printer format-3-immed ((op #b11) (op3 #b100001) (rd 0)))
  :pinned
  (:delay 0)
  (:emitter (emit-format-3-immed segment #b11 0 #b100001
				 (reg-tn-encoding src1) 1 src2)))

#+sparc-64
(define-instruction ldxfsr (segment src1 src2)
  (:declare (type tn src1) (type (signed-byte 13) src2))
  (:printer format-3-immed ((op #b11) (op3 #b100001) (rd 1))
	    '(:name :tab "[" rs1 (:unless (:constant 0) "+" immed) "], %FSR")
	    :print-name 'ldx)
  :pinned
  (:delay 0)
  (:emitter (emit-format-3-immed segment #b11 1 #b100001
				 (reg-tn-encoding src1) 1 src2)))
  
;; stfsr is deprecated on the Sparc V9.  Use stxfsr instead.
(define-instruction stfsr (segment src1 src2)
  (:declare (type tn src1) (type (signed-byte 13) src2))
  (:printer format-3-immed ((op #b11) (op3 #b100101) (rd 0)))
  :pinned
  (:delay 0)
  (:emitter (emit-format-3-immed segment #b11 0 #b100101 
				 (reg-tn-encoding src1) 1 src2)))

#+sparc-64
(define-instruction stxfsr (segment src1 src2)
  (:declare (type tn src1) (type (signed-byte 13) src2))
  (:printer format-3-immed ((op #b11) (op3 #b100101) (rd 1))
	    '(:name :tab "%FSR, [" rs1 "+" (:unless (:constant 0) "+" immed) "]")
	    :print-name 'stx)
  :pinned
  (:delay 0)
  (:emitter (emit-format-3-immed segment #b11 1 #b100101 
				 (reg-tn-encoding src1) 1 src2)))

(eval-when (compile load eval)
  (defun sethi-arg-printer (value stream dstate)
    (format stream "%hi(#x~8,'0x)" (ash value 10))
    ;; Save the immediate value and the destination register from this
    ;; sethi instruction.  This is used later to print some possible
    ;; notes about the value loaded by sethi.
    (let* ((word (disassem::sap-ref-int (disassem:dstate-segment-sap dstate)
					(disassem:dstate-cur-offs dstate)
					vm:word-bytes
					(disassem::dstate-byte-order dstate)))
	   (imm22 (ldb (byte 22 0) word))
	   (rd (ldb (byte 5 25) word)))
      (push (cons rd imm22) *note-sethi-inst*)
      ))
) ; eval-when (compile load eval)

(define-instruction sethi (segment dst src1)
  (:declare (type tn dst)
	    (type (or (signed-byte 22) (unsigned-byte 22) fixup) src1))
  (:printer format-2-immed
            ((op2 #b100) (immed nil :printer #'sethi-arg-printer)))
  (:dependencies (writes dst))
  (:delay 0)
  (:emitter
   (etypecase src1
     (integer
      (emit-format-2-immed segment #b00 (reg-tn-encoding dst) #b100
				 src1))
     (fixup
      (note-fixup segment :sethi src1)
      (emit-format-2-immed segment #b00 (reg-tn-encoding dst) #b100 0)))))
			   
;; rdy is deprecated on the Sparc V9.  It's not needed with 64-bit
;; registers.
(define-instruction rdy (segment dst)
  (:declare (type tn dst))
  (:printer format-3-reg ((op #b10) (op3 #b101000) (rs1 0) (rs2 0))
            '('RD :tab '%Y ", " rd))
  (:dependencies (reads :y) (writes dst))
  (:delay 0)
  (:emitter (emit-format-3-immed segment #b10 (reg-tn-encoding dst) #b101000
				 0 0 0)))

(defconstant wry-printer
  '('WR :tab rs1 (:unless (:constant 0) ", " (:choose immed rs2)) ", " '%Y))

;; wry is deprecated on the Sparc V9.  It's not needed with 64-bit
;; registers.
(define-instruction wry (segment src1 &optional src2)
  (:declare (type tn src1) (type (or (signed-byte 13) tn null) src2))
  (:printer format-3-reg ((op #b10) (op3 #b110000) (rd 0)) wry-printer)
  (:printer format-3-immed ((op #b10) (op3 #b110000) (rd 0)) wry-printer)
  (:dependencies (reads src1) (if src2 (reads src2)) (writes :y))
  (:delay 3)
  (:emitter
   (etypecase src2
     (null 
      (emit-format-3-reg segment #b10 0 #b110000 (reg-tn-encoding src1) 0 0 0))
     (tn
      (emit-format-3-reg segment #b10 0 #b110000 (reg-tn-encoding src1) 0 0
			 (reg-tn-encoding src2)))
     (integer
      (emit-format-3-immed segment #b10 0 #b110000 (reg-tn-encoding src1) 1
			   src2)))))

;; Read the tick register available on sparc v9
(define-instruction rdtick (segment dst)
  (:declare (type tn dst))
  (:printer format-3-reg ((op #b10) (op3 #b101000) (rs1 4) (rs2 0))
            '('RD :tab '%TICK ", " rd))
  (:dependencies (reads :tick) (writes dst))
  (:delay 0)
  (:emitter (emit-format-3-immed segment #b10 (reg-tn-encoding dst) #b101000
				 4 0 0)))

;; Sparc-v9 Compare and Swap instructions

(defconstant immediate-asi-alist
  '((:asi_aiup . #x10)			; ASI_AS_IF_USER_PRIMARY
    (:asi_aius . #x11)			; ASI_AS_IF_USER_SECONDARY
    (:asi_aiup_l . #x18)		; ASI_AS_IF_USER_PRIMARY_LITTLE
    (:asi_aius_l . #x19)		; ASI_AS_IF_USER_SECONDARY_LITTLE
    (:asi_p . #x80)			; ASI_PRIMARY
    (:asi_s . #x81)			; ASI_SECONDARY
    (:asi_pnf . #x82)			; ASI_PRIMARY_NOFAULT
    (:asi_snf . #x83)			; ASI_SECONDARY_NOFAULT
    (:asi_p_l . #x88)			; ASI_PRIMARY_LITTLE
    (:asi_s_l . #x89)			; ASI_SECONDARY_LITTLE
    (:asi_pnf_l . #x8a)			; ASI_PRIMARY_NOFAULT_LITTLE
    (:asi_snf_l . #x8b)))		; ASI_SECONDARY_NOFAULT_LITTLE

(deftype immediate-asi ()
  `(member ,@(mapcar #'car immediate-asi-alist)))

(disassem:define-argument-type immediate-asi
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((symbolic (rassoc value immediate-asi-alist)))
		   (if symbolic
		       (format stream "#~A" (car symbolic))
		       (format stream "~D" value)))))

(defconstant compare-swap-asi-printer
  `(:name :tab "[" rs1 "]" '%asi
	  ", "
	  rs2
	  ", "
	  rd))

(defconstant compare-swap-immed-asi-printer
  `(:name :tab "[" rs1 "]"
	  asi
	  ", "
	  rs2
	  ", "
	  rd))
	  
(macrolet
    ((cas (name op3)
     `(define-instruction ,name (segment dst src1 src2 &key immed-asi)
	(:declare (type tn dst src1 src2)
		  (type (or null (unsigned-byte 8) immediate-asi) immed-asi))
	(:printer format-3-reg
		  ((op #b11) (op3 ,op3) (i 1) (asi nil))
		  compare-swap-asi-printer
		  )
	(:printer format-3-reg
		  ((op #b11) (op3 ,op3) (i 0) (asi nil :type 'immediate-asi))
		  compare-swap-immed-asi-printer
		  )
	(:dependencies (reads src1)
		       (reads src2)
		       (reads dst)
		       (reads :memory)
		       (writes dst)
		       (writes :memory))
	(:delay 0)
	(:emitter
	 (let ((asi-value (if immed-asi
			      (if (integerp immed-asi)
				  immed-asi
				  (cdr (assoc immed-asi immediate-asi-alist))))))
	   (emit-format-3-reg segment #b11 (reg-tn-encoding dst) ,op3
			      (reg-tn-encoding src1)
			      (if immed-asi 0 1)
			      (or asi-value 0)
			      (reg-tn-encoding src2)))))))
  ;; 32-bit compre and swap
  (cas casa  #b111100)
  ;; 64-bit compare and swap
  (cas casxa #b111110))

;; Prefetch
(defconstant prefetch-type-alist
  '((:n_reads . 0)
    (:one_read . 1)
    (:n_writes . 2)
    (:one_write . 3)
    (:page . 4)))

(deftype prefetch-type ()
  `(member ,@(mapcar #'car prefetch-type-alist)))

(disassem:define-argument-type prefetch-fcn
    :printer #'(lambda (value stream dstate)
		 (declare (stream stream) (fixnum value) (ignore dstate))
		 (let ((symbolic (rassoc value prefetch-type-alist)))
		   (if symbolic
		       (format stream "#~A" (car symbolic))
		       (format stream "~D" value)))))

(define-instruction prefetch (segment fcn src1 src2)
  (:declare (type tn src1)
	    (type (or tn (signed-byte 13)) src2)
	    (type (or (unsigned-byte 5) prefetch-type) fcn))
  (:printer format-3-reg
	    ((op #b11) (op3 #b101101) (i 0) (rd nil :type 'prefetch-fcn))
	    load-printer)
  (:printer format-3-immed
	    ((op #b11) (op3 #b101101) (i 1) (rd nil :type 'prefetch-fcn))
	    load-printer)
  (:delay 0)
  (:emitter
   (let ((fcn-type (if (integerp fcn)
		       fcn
		       (cdr (assoc fcn prefetch-type-alist)))))
     (etypecase src2
       (tn
	(emit-format-3-reg segment #b11 fcn-type #b101101
			   (reg-tn-encoding src1)
			   0 0
			   (reg-tn-encoding src2)))
       (integer
	(emit-format-3-immed segment #b11 fcn-type #b101101
			     (reg-tn-encoding src1)
			     1
			     src2))))))

;;; Some synthetic instructions

;; Sign-extend a 32-bit number to 64 bits.  (Basically sra rs1, %g0,
;; rd).
(define-instruction signx (segment dst &optional src)
  (:declare (type tn dst)
	    (type (or null tn) src))
  (:printer format-3-shift-reg
	    ((op #b10) (op3 #b100111) (x 0) (i 0) (rs2 0))
	    '(:name :tab (:unless (:same-as rd) rs1 ", ") rd))
  (:dependencies
   (if src (reads src) (reads dst))
   (writes dst))
  (:delay 0)
  (:emitter
   (unless src
     (setf src dst))
   (emit-format-3-shift-inst segment #b10 #b100111 dst src zero-tn))
  )

;; Zero-extend (clear upper part of word) a 32-bit number to 64 bits.
;; (Basically srl rs1, %g0, rd)
(define-instruction clruw (segment dst &optional src)
  (:declare (type tn dst)
	    (type (or null tn) src))
  (:printer format-3-shift-reg
	    ((op #b10) (op3 #b100110) (x 0) (i 0) (rs2 0))
	    '(:name :tab (:unless (:same-as rd) rs1 ", ") rd))
  (:dependencies
   (if src (reads src) (reads dst))
   (writes dst))
  (:delay 0)
  (:emitter
   (unless src
     (setf src dst))
   (emit-format-3-shift-inst segment #b10 #b100110 dst src zero-tn))
  )


(defun snarf-error-junk (sap offset &optional length-only)
  (let* ((length (system:sap-ref-8 sap offset))
         (vector (make-array length :element-type '(unsigned-byte 8))))
    (declare (type system:system-area-pointer sap)
             (type (unsigned-byte 8) length)
             (type (simple-array (unsigned-byte 8) (*)) vector))
    (cond (length-only
           (values 0 (1+ length) nil nil))
          (t
           (kernel:copy-from-system-area sap (* sparc:byte-bits (1+ offset))
                                         vector (* sparc:word-bits
                                                   sparc:vector-data-offset)
                                         (* length sparc:byte-bits))
           (collect ((sc-offsets)
                     (lengths))
             (lengths 1)                ; the length byte
             (let* ((index 0)
                    (error-number (c::read-var-integer vector index)))
               (lengths index)
               (loop
                 (when (>= index length)
                   (return))
                 (let ((old-index index))
                   (sc-offsets (c::read-var-integer vector index))
                   (lengths (- index old-index))))
               (values error-number
                       (1+ length)
                       (sc-offsets)
                       (lengths))))))))

(defun unimp-control (chunk inst stream dstate)
  (declare (ignore inst))
  (flet ((nt (x) (if stream (disassem:note x dstate))))
    (case (format-2-unimp-data chunk dstate)
      (#.vm:error-trap
       (nt "Error trap")
       (disassem:handle-break-args #'snarf-error-junk stream dstate))
      (#.vm:cerror-trap
       (nt "Cerror trap")
       (disassem:handle-break-args #'snarf-error-junk stream dstate))
      (#.vm:object-not-list-trap
       (nt "Object not list trap"))
      (#.vm:breakpoint-trap
       (nt "Breakpoint trap"))
      (#.vm:pending-interrupt-trap
       (nt "Pending interrupt trap"))
      (#.vm:halt-trap
       (nt "Halt trap"))
      (#.vm:function-end-breakpoint-trap
       (nt "Function end breakpoint trap"))
      (#.vm:object-not-instance-trap
       (nt "Object not instance trap"))
    )))

(define-instruction unimp (segment data)
  (:declare (type (unsigned-byte 22) data))
  (:printer format-2-unimp () :default :control #'unimp-control
	    :print-name #-sparc-v9 'unimp #+sparc-v9 'illtrap)
  (:delay 0)
  (:emitter (emit-format-2-unimp segment 0 0 0 data)))



;;;; Branch instructions.

;; The branch instruction is deprecated on the Sparc V9.  Use the
;; branch with prediction instructions instead.
(defun emit-relative-branch (segment a op2 cond-or-target target &optional fp)
  (emit-back-patch segment 4
    #'(lambda (segment posn)
	(unless target
	  (setf target cond-or-target)
	  (setf cond-or-target :t))
	(emit-format-2-branch
	  segment #b00 a
	  (if fp
	      (fp-branch-condition cond-or-target)
	      (branch-condition cond-or-target))
	  op2
	  (let ((offset (ash (- (label-position target) posn) -2)))
	    (when (and (= a 1) (> 0 offset))
	      (error "Offset of BA must be positive"))
	    offset)))))

#+sparc-v9
(defun emit-relative-branch-integer (segment a op2 cond-or-target target &optional (cc :icc) (pred :pt))
  (declare (type integer-condition-register cc))
  (emit-back-patch segment 4
    #'(lambda (segment posn)
	(unless target
	  (setf target cond-or-target)
	  (setf cond-or-target :t))
	(emit-format-2-branch-pred
	  segment #b00 a
	  (branch-condition cond-or-target)
	  op2
	  (integer-condition cc)
	  (branch-prediction pred)
	  (let ((offset (ash (- (label-position target) posn) -2)))
	    (when (and (= a 1) (> 0 offset))
	      (error "Offset of BA must be positive"))
	    offset)))))

#+sparc-v9
(defun emit-relative-branch-fp (segment a op2 cond-or-target target &optional (cc :fcc0) (pred :pt))
  (emit-back-patch segment 4
    #'(lambda (segment posn)
	(unless target
	  (setf target cond-or-target)
	  (setf cond-or-target :t))
	(emit-format-2-branch-pred
	  segment #b00 a
	  (fp-branch-condition cond-or-target)
	  op2
	  (fp-condition cc)
	  (branch-prediction pred)
	  (let ((offset (ash (- (label-position target) posn) -2)))
	    (when (and (= a 1) (> 0 offset))
	      (error "Offset of BA must be positive"))
	    offset)))))

;; So that I don't have to go change the syntax of every single use of
;; branches, I'm keeping the Lisp instruction names the same.  They
;; just get translated to the branch with prediction
;; instructions. However, the disassembler uses the correct V9
;; mnemonic.
#-sparc-v9
(define-instruction b (segment cond-or-target &optional target &rest ignored)
  (:declare (type (or label branch-condition) cond-or-target)
	    (type (or label null) target)
	    (ignore ignored))
  (:printer format-2-branch ((op #b00) (op2 #b010)))
  (:attributes branch)
  (:dependencies (reads :psr))
  (:delay 1)
  (:emitter
   (emit-relative-branch segment 0 #b010 cond-or-target target)))

#+sparc-v9
(define-instruction b (segment cond-or-target &optional target pred cc)
  (:declare (type (or label branch-condition) cond-or-target)
	    (type (or label null) target)
	    (type (or null (member :icc :xcc)) cc)
	    (type (or null (member :pt :pn)) pred))
  (:printer format-2-branch-pred ((op #b00) (op2 #b001))
	    branch-pred-printer
	    :print-name 'bp)
  (:attributes branch)
  (:dependencies (reads :psr))
  (:delay 1)
  (:emitter
   (emit-relative-branch-integer segment 0 #b001 cond-or-target target (or cc :icc) (or pred :pt))))

#-sparc-v9
(define-instruction ba (segment cond-or-target &optional target)
  (:declare (type (or label branch-condition) cond-or-target)
	    (type (or label null) target))
  (:printer format-2-branch ((op #b00) (op2 #b010) (a 1))
            nil
            :print-name 'b)
  (:attributes branch)
  (:dependencies (reads :psr))
  (:delay 0)
  (:emitter
   (emit-relative-branch segment 1 #b010 cond-or-target target)))

#+sparc-v9
(define-instruction ba (segment cond-or-target &optional target pred cc)
  (:declare (type (or label branch-condition) cond-or-target)
	    (type (or label null) target)
	    (type (or null (member :icc :xcc)) cc)
	    (type (or null (member :pt :pn)) pred))
  (:printer format-2-branch ((op #b00) (op2 #b001) (a 1))
            nil
            :print-name 'bp)
  (:attributes branch)
  (:dependencies (reads :psr))
  (:delay 0)
  (:emitter
   (emit-relative-branch-integer segment 1 #b001 cond-or-target target (or cc :icc) (or pred :pt))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun trap-arg-printer (value stream dstate)
    ;; We just print a note, if it's one of our recognized traps
    (let ((*package* (find-package :vm)))
      (case value
	(#.pseudo-atomic-trap
	 (disassem:note "Pseudo atomic interrupted trap?" dstate))
	(#.allocation-trap
	 (disassem:note "Allocation trap" dstate)))
      (format stream "~A" value))))

;; The Sparc Compliance Definition 2.4.1 says only trap numbers 16-31
;; are allowed for user code.  All other trap numbers have other
;; uses. The restriction on target will prevent us from using bad trap
;; numbers by mistake.
;;
;; Note that the V9 architecture only allows 7 bits for the immediate
;; trap number.  Previous architectures allowed 13 bits. CMUCL doesn't
;; need all 13 bits, and the SCD only allows 16-31, so we only allow
;; for those now.
(define-instruction t (segment condition src1-or-imm &optional src2
			       #+sparc-v9 (cc #-sparc-64 :icc #+sparc-64 :xcc))
  (:declare (type branch-condition condition)
	    (type (or tn (unsigned-byte 8)) src1-or-imm)
	    (type (or null tn (unsigned-byte 8)) src2)
	    #+sparc-v9
	    (type integer-condition-register cc))
  (:printer format-4-trap-immed ((op #b10)
				 (rd nil :type 'branch-condition)
				 (op3 #b111010)
				 (i 1)
				 (immed nil :printer #'trap-arg-printer))
	    trap-immed-printer)
  (:printer format-4-trap ((op #b10)
			   (rd nil :type 'branch-condition)
			   (op3 #b111010)
			   (i 0)
			   (rs2 nil :type 'reg))
	    trap-printer)
  (:attributes branch)
  (:dependencies (reads :psr))
  (:delay 0)
  (:emitter
   (let ((cc-reg #+sparc-v9 (integer-condition cc)
		 #-sparc-v9 0))
     (etypecase src1-or-imm
       (integer
	;; src2 shouldn't be given (or should be NIL) in this case.
	(assert (null src2))
	(unless (typep src1-or-imm '(integer 16 31))
	  (cerror "Use it anyway"
		  "Immediate trap number ~A specified, but only trap numbers
   16 to 31 are available to the application"
		  src1-or-imm))
	(emit-format-4-trap segment
			    #b10
			    (branch-condition condition)
			    #b111010 0 1
			    cc-reg
			    src1-or-imm))
       (tn
	;; src1 is a register.  src2 must be given.
	(etypecase src2
	  (integer
	   (emit-format-4-trap segment
			       #b10
			       (branch-condition condition)
			       #b111010
			       (reg-tn-encoding src1-or-imm)
			       1
			       cc-reg
			       src2))
	  (tn
	   (emit-format-4-trap segment
			       #b10
			       (branch-condition condition)
			       #b111010
			       (reg-tn-encoding src1-or-imm)
			       0
			       cc-reg
			       (reg-tn-encoding src2))))))))
  )

;; Same as for the branch instructions.  On the Sparc V9, we will use
;; the FP branch with prediction instructions instead.
#-sparc-v9
(define-instruction fb (segment condition target)
  (:declare (type fp-branch-condition condition) (type label target))
  (:printer format-2-branch ((op #B00)
                             (cond nil :type 'branch-fp-condition)
                             (op2 #b110)))
  (:attributes branch)
  (:dependencies (reads :fsr))
  (:delay 1)
  (:emitter
   (emit-relative-branch segment 0 #b110 condition target t)))

#+sparc-v9
(define-instruction fb (segment condition target &optional fcc pred)
  (:declare (type fp-branch-condition condition) (type label target))
  (:printer format-2-fp-branch-pred ((op #b00) (op2 #b101))
	    fp-branch-pred-printer
	    :print-name 'fbp)
  (:attributes branch)
  (:dependencies (reads :fsr))
  (:delay 1)
  (:emitter
   (emit-relative-branch-fp segment 0 #b101 condition target (or fcc :fcc0) (or pred :pt))))

(defconstant jal-printer
  '(:name :tab
          (:choose (rs1 (:unless (:constant 0) (:plus-integer immed)))
                   (:cond ((rs2 :constant 0) rs1)
                          ((rs1 :constant 0) rs2)
                          (t rs1 "+" rs2)))
          (:unless (:constant 0) ", " rd)))

(define-instruction jal (segment dst src1 &optional src2)
  (:declare (type tn dst)
	    (type (or tn integer) src1)
	    (type (or null fixup tn (signed-byte 13)) src2))
  (:printer format-3-reg ((op #b10) (op3 #b111000)) jal-printer :print-name 'jmpl)
  (:printer format-3-immed ((op #b10) (op3 #b111000)) jal-printer :print-name 'jmpl)
  (:attributes branch)
  (:dependencies (reads src1) (if src2 (reads src2) (reads dst)) (writes dst))
  (:delay 1)
  (:emitter
   (unless src2
     (setf src2 src1)
     (setf src1 0))
   (etypecase src2
     (tn
      (emit-format-3-reg segment #b10 (reg-tn-encoding dst) #b111000
			 (if (integerp src1)
			     src1
			     (reg-tn-encoding src1))
			 0 0 (reg-tn-encoding src2)))
     (integer
      (emit-format-3-immed segment #b10 (reg-tn-encoding dst) #b111000
			   (reg-tn-encoding src1) 1 src2))
     (fixup
      (note-fixup segment :add src2)
      (emit-format-3-immed segment #b10 (reg-tn-encoding dst)
			   #b111000 (reg-tn-encoding src1) 1 0)))))

(define-instruction j (segment src1 &optional src2)
  (:declare (type tn src1) (type (or tn (signed-byte 13) fixup null) src2))
  (:printer format-3-reg ((op #b10) (op3 #b111000) (rd 0)) jal-printer)
  (:printer format-3-immed ((op #b10) (op3 #b111000) (rd 0)) jal-printer)
  (:attributes branch)
  (:dependencies (reads src1) (if src2 (reads src2)))
  (:delay 1)
  (:emitter
   (etypecase src2
     (null
      (emit-format-3-reg segment #b10 0 #b111000 (reg-tn-encoding src1) 0 0 0))
     (tn
      (emit-format-3-reg segment #b10 0 #b111000 (reg-tn-encoding src1) 0 0
			 (reg-tn-encoding src2)))
     (integer
      (emit-format-3-immed segment #b10 0 #b111000 (reg-tn-encoding src1) 1
			   src2))
     (fixup
      (note-fixup segment :add src2)
      (emit-format-3-immed segment #b10 0 #b111000 (reg-tn-encoding src1) 1
			   0)))))



;;;; Unary and binary fp insts.

(eval-when (compile eval)

(defmacro define-unary-fp-inst (name opf &key reads extended)
  `(define-instruction ,name (segment dst src)
     (:declare (type tn dst src))
     (:printer format-unary-fpop
       ((op #b10) (op3 #b110100) (opf ,opf)
	(rs1 0)
	(rs2 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
	(rd nil :type ',(if extended 'fp-ext-reg 'fp-reg))))
     (:dependencies
      ,@(when reads
	  `((reads ,reads)))
      (reads dst)
      (reads src)
      (writes dst))
     (:delay 0)
     (:emitter (emit-format-3-fpop segment #b10 (fp-reg-tn-encoding dst)
		#b110100 0 ,opf (fp-reg-tn-encoding src)))))

(defmacro define-binary-fp-inst (name opf &key (op3 #b110100)
				      reads writes delay extended)
  `(define-instruction ,name (segment dst src1 src2)
     (:declare (type tn dst src1 src2))
     (:printer format-binary-fpop
      ((op #b10) (op3 ,op3) (opf ,opf)
       (rs1 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
       (rs2 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
       (rd nil :type ',(if extended 'fp-ext-reg 'fp-reg))
       ))
     (:dependencies
      ,@(when reads
	  `((reads ,reads)))
      (reads src1)
      (reads src2)
      ,@(when writes
	  `((writes ,writes)))
      (writes dst))
     ,@(if delay
	   `((:delay ,delay))
	   '((:delay 0)))
     (:emitter (emit-format-3-fpop segment #b10 (fp-reg-tn-encoding dst)
		,op3 (fp-reg-tn-encoding src1) ,opf
		(fp-reg-tn-encoding src2)))))

(defmacro define-cmp-fp-inst (name opf &key extended)
  (let ((opf0 #b0)
	(opf1 #b010)
	(opf2 #b1))
    `(define-instruction ,name (segment src1 src2 &optional (fcc :fcc0))
       (:declare (type tn src1 src2)
	         (type (member :fcc0 :fcc1 :fcc2 :fcc3) fcc))
       (:printer format-fpop2
		 ((op #b10)
		  (op3 #b110101)
		  (opf0 ,opf0)
		  (opf1 ,opf1)
		  (opf2 ,opf2)
		  (opf3 ,opf)
		  (rs1 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
		  (rs2 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
		  #-sparc-v9
		  (rd 0)
		  #+sparc-v9
		  (rd nil :type 'fp-condition-register))
	)
     (:dependencies
      (reads src1)
      (reads src2)
      (writes :fsr))
     ;; The Sparc V9 doesn't need a delay after a FP compare.
     (:delay #-sparc-v9 1 #+sparc-v9 0)
       (:emitter
	(emit-format-3-fpop2 segment #b10
	                     (or (position fcc '(:fcc0 :fcc1 :fcc2 :fcc3))
				 0)
	                     #b110101
			     (fp-reg-tn-encoding src1)
			     ,opf0 ,opf1 ,opf2 ,opf
			     (fp-reg-tn-encoding src2))))))

); eval-when (compile eval)


(define-unary-fp-inst fitos #b011000100 :reads :fsr)
(define-unary-fp-inst fitod #b011001000 :reads :fsr :extended t)
(define-unary-fp-inst fitoq #b011001100 :reads :fsr :extended t)	; v8

(define-unary-fp-inst fxtos #b010000100 :reads :fsr)                    ; v9
(define-unary-fp-inst fxtod #b010001000 :reads :fsr :extended t)        ; v9
(define-unary-fp-inst fxtoq #b010001100 :reads :fsr :extended t)	; v9


;; I (toy@rtp.ericsson.se) don't think these f{sd}toir instructions
;; exist on any Ultrasparc, but I only have a V9 manual.  The code in
;; float.lisp seems to indicate that they only existed on non-sun4
;; machines (sun3 68K machines?).
#-sparc
(progn
  (define-unary-fp-inst fstoir #b011000001 :reads :fsr)
  (define-unary-fp-inst fdtoir #b011000010 :reads :fsr)
)

(define-unary-fp-inst fstoi #b011010001)
(define-unary-fp-inst fdtoi #b011010010 :extended t)
(define-unary-fp-inst fqtoi #b011010011 :extended t)	; v8

(define-unary-fp-inst fstox #b010000001)                ; v9
(define-unary-fp-inst fdtox #b010000010 :extended t)    ; v9
(define-unary-fp-inst fqtox #b010000011 :extended t)	; v9

(define-unary-fp-inst fstod #b011001001 :reads :fsr)
(define-unary-fp-inst fstoq #b011001101 :reads :fsr)	; v8
(define-unary-fp-inst fdtos #b011000110 :reads :fsr)
(define-unary-fp-inst fdtoq #b011001110 :reads :fsr)	; v8
(define-unary-fp-inst fqtos #b011000111 :reads :fsr)	; v8
(define-unary-fp-inst fqtod #b011001011 :reads :fsr)	; v8

(define-unary-fp-inst fmovs #b000000001)
(define-unary-fp-inst fmovd #b000000010 :extended t)	; v9
(define-unary-fp-inst fmovq #b000000011 :extended t)	; v9

(define-unary-fp-inst fnegs #b000000101)
(define-unary-fp-inst fnegd #b000000110 :extended t)	; v9
(define-unary-fp-inst fnegq #b000000111 :extended t)	; v9

(define-unary-fp-inst fabss #b000001001)
(define-unary-fp-inst fabsd #b000001010 :extended t)	; v9
(define-unary-fp-inst fabsq #b000001011 :extended t)	; v9

(define-unary-fp-inst fsqrts #b000101001 :reads :fsr)		; V7
(define-unary-fp-inst fsqrtd #b000101010 :reads :fsr :extended t)	; V7
(define-unary-fp-inst fsqrtq #b000101011 :reads :fsr :extended t)	; v8

(define-binary-fp-inst fadds #b001000001)
(define-binary-fp-inst faddd #b001000010 :extended t)
(define-binary-fp-inst faddq #b001000011 :extended t)	; v8
(define-binary-fp-inst fsubs #b001000101)
(define-binary-fp-inst fsubd #b001000110 :extended t)
(define-binary-fp-inst fsubq #b001000111 :extended t)	; v8

(define-binary-fp-inst fmuls #b001001001)
(define-binary-fp-inst fmuld #b001001010 :extended t)
(define-binary-fp-inst fmulq #b001001011 :extended t)	; v8
(define-binary-fp-inst fdivs #b001001101)
(define-binary-fp-inst fdivd #b001001110 :extended t)
(define-binary-fp-inst fdivq #b001001111 :extended t)	; v8

;;; Float comparison instructions.
;;;
(define-cmp-fp-inst fcmps #b0001)
(define-cmp-fp-inst fcmpd #b0010 :extended t)
(define-cmp-fp-inst fcmpq #b0011 :extended t) ;v8
(define-cmp-fp-inst fcmpes #b0101)
(define-cmp-fp-inst fcmped #b0110 :extended t)
(define-cmp-fp-inst fcmpeq #b0111 :extended t)	; v8



;;;; li, jali, ji, nop, cmp, not, neg, move, and more

#-sparc-v9
(defun %li (reg value)
  (etypecase value
    ((signed-byte 13)
     (inst add reg zero-tn value))
    ((or (signed-byte 32) (unsigned-byte 32))
     (let ((hi (ldb (byte 22 10) value))
	   (lo (ldb (byte 10 0) value)))
       (inst sethi reg hi)
       (unless (zerop lo)
	 (inst add reg lo))))
    (fixup
     (inst sethi reg value)
     (inst add reg value))))

#+sparc-v9
(defun %li (reg value)
  (etypecase value
    ((signed-byte 13)
     (inst add reg zero-tn value))
    ((unsigned-byte 32)
     (let ((hi (ldb (byte 22 10) value))
	   (lo (ldb (byte 10 0) value)))
       ;; Sethi sets the top 32-bits to zero.
       (inst sethi reg hi)
       (unless (zerop lo)
	 (inst add reg lo))))
    ((signed-byte 32)
     (let ((hi (ldb (byte 22 10) value))
	   (lo (ldb (byte 10 0) value)))
       ;; Sethi sets the top 32-bits to zero.
       (inst sethi reg hi)
       (unless (zerop lo)
	 (inst add reg lo))
       ;; Sign-extend the result
       (inst signx reg)))
    (fixup
     (inst sethi reg value)
     (inst add reg value))))

(define-instruction-macro li (reg value)
  `(%li ,reg ,value))

#+sparc-v9
(progn
(defun %li64 (reg value &optional temp)
  (etypecase value
    ((signed-byte 13)
     (inst add reg zero-tn value))
    ((unsigned-byte 32)
     (let ((hi (ldb (byte 22 10) value))
	   (lo (ldb (byte 10 0) value)))
       (inst sethi reg hi)
       (unless (zerop lo)
	 (inst add reg lo))))
    ((signed-byte 32)
     (let ((hi (ldb (byte 22 10) value))
	   (lo (ldb (byte 10 0) value)))
       ;; Sethi sets the top 32-bits to zero.
       (inst sethi reg hi)
       (unless (zerop lo)
	 (inst add reg lo))
       ;; Sign-extend the result
       (inst signx reg)))
    ((unsigned-byte 32)
     (let ((hi (ldb (byte 22 10) value))
	   (lo (ldb (byte 10 0) value)))
       ;; Sethi sets the top 32-bits to zero.
       (inst sethi reg hi)
       (unless (zerop lo)
	 (inst add reg lo))))
    ((or (signed-byte 64) (unsigned-byte 64))
     (cond (temp
	    ;; If we have a temp register to use, we can use this
	    ;; shorter sequence
	    (let ((hh (ldb (byte 22 42) value))
		  (lm (ldb (byte 22 32) value))
		  (hm (ldb (byte 22 10) value))
		  (lo (ldb (byte 10 0) value)))
	      (inst sethi temp hh)
	      (inst sethi reg lm)
	      (inst or temp hm)
	      (inst or reg lo)
	      (inst sllx temp 32)
	      (inst or reg temp)))
	   (t
	    ;; Hmm, no temp register given, so we have to use the
	    ;; following longer sequence.
	    (let ((bits-63-48 (ldb (byte 16 48) value))
		  (bits-47-36 (ldb (byte 12 36) value))
		  (bits-35-24 (ldb (byte 12 24) value))
		  (bits-23-12 (ldb (byte 12 12) value))
		  (bits-11-00 (ldb (byte 12 0) value)))
	      (inst sethi reg bits-63-48)
	      (inst or reg bits-47-36)
	      (inst sllx reg 12)
	      (inst or reg bits-35-24)
	      (inst sllx reg 12)
	      (inst or reg bits-23-12)
	      (inst sllx reg 12)
	      (inst or reg bits-11-00)))))
    (fixup
     (inst sethi reg value)
     (inst add reg value))))

(define-instruction-macro li64 (reg value &optional temp)
  `(%li64 ,reg ,value ,temp))

)

;; Define LDN/STN synthetic instructions to do "natural" loads and
;; stores for 32-bit or 64-bit objects depending on whether this is a
;; 32-bit or 64-bit build.  Change these to use ldx/stx/sllx/srlx/srax
;; for 64-bit build.
(macrolet ((frob (name inst)
	     `(define-instruction-macro ,name (dst src1 &optional src2)
	       `(inst ,',inst ,dst ,src1 ,src2))))
  (frob ldn ld)
  (frob stn st)
  (frob slln sll)
  (frob srln srl)
  (frob sran sra))
  
;;; Jal to a full 32-bit address.  Tmpreg is trashed.
(define-instruction jali (segment link tmpreg value)
  (:declare (type tn link tmpreg)
	    (type (or (signed-byte 13) (signed-byte 32) (unsigned-byte 32)
		      fixup) value))
  (:attributes variable-length)
 (:vop-var vop)
  (:attributes branch)
  (:dependencies (writes link) (writes tmpreg))
  (:delay 1)
  (:emitter
   (assemble (segment vop)
     (etypecase value
       ((signed-byte 13)
	(inst jal link zero-tn value))
       ((or (signed-byte 32) (unsigned-byte 32))
	(let ((hi (ldb (byte 22 10) value))
	      (lo (ldb (byte 10 0) value)))
	  (inst sethi tmpreg hi)
	  (inst jal link tmpreg lo)))
       (fixup
	(inst sethi tmpreg value)
	(inst jal link tmpreg value))))))

;;; Jump to a full 32-bit address.  Tmpreg is trashed.
(define-instruction ji (segment tmpreg value)
  (:declare (type tn tmpreg)
	    (type (or (signed-byte 13) (signed-byte 32) (unsigned-byte 32)
		      fixup) value))
  (:attributes variable-length)
  (:vop-var vop)
  (:attributes branch)
  (:dependencies (writes tmpreg))
  (:delay 1)
  (:emitter
   (assemble (segment vop)
	     (inst jali zero-tn tmpreg value))))

(define-instruction nop (segment)
  (:printer format-2-immed ((rd 0) (op2 #b100) (immed 0)) '(:name))
  (:attributes flushable)
  (:delay 0)
  (:emitter (emit-format-2-immed segment 0 0 #b100 0)))

(def-vm-support-routine emit-nop (segment)
  (emit-format-2-immed segment 0 0 #b100 0))

(define-instruction cmp (segment src1 &optional src2)
  (:declare (type tn src1) (type (or null tn (signed-byte 13)) src2))
  (:printer format-3-reg ((op #b10) (op3 #b010100) (rd 0))
            '(:name :tab rs1 ", " rs2))
  (:printer format-3-immed ((op #b10) (op3 #b010100) (rd 0))
            '(:name :tab rs1 ", " immed))
  (:dependencies (reads src1) (if src2 (reads src2)) (writes :psr))
  (:delay 0)
  (:emitter
   (etypecase src2
     (null
      (emit-format-3-reg segment #b10 0 #b010100 (reg-tn-encoding src1) 0 0 0))
     (tn
      (emit-format-3-reg segment #b10 0 #b010100 (reg-tn-encoding src1) 0 0
			 (reg-tn-encoding src2)))
     (integer
      (emit-format-3-immed segment #b10 0 #b010100 (reg-tn-encoding src1) 1
			   src2)))))

(define-instruction not (segment dst &optional src1)
  (:declare (type tn dst) (type (or tn null) src1))
  (:printer format-3-reg ((op #b10) (op3 #b000111) (rs2 0))
            '(:name :tab (:unless (:same-as rd) rs1 ", " ) rd))
  (:dependencies (if src1 (reads src1) (reads dst)) (writes dst))
  (:delay 0)
  (:emitter
   (unless src1
     (setf src1 dst))
   (emit-format-3-reg segment #b10 (reg-tn-encoding dst) #b000111
		      (reg-tn-encoding src1) 0 0 0)))

(define-instruction neg (segment dst &optional src1)
  (:declare (type tn dst) (type (or tn null) src1))
  (:printer format-3-reg ((op #b10) (op3 #b000100) (rs1 0))
            '(:name :tab (:unless (:same-as rd) rs2 ", " ) rd))
  (:dependencies (if src1 (reads src1) (reads dst)) (writes dst))
  (:delay 0)
  (:emitter
   (unless src1
     (setf src1 dst))
   (emit-format-3-reg segment #b10 (reg-tn-encoding dst) #b000100
		      0 0 0 (reg-tn-encoding src1))))

;; As in the suggested synthetic instructions, a register move is
;; really just or'ing the src register with %g0.
(define-instruction move (segment dst src1)
  (:declare (type tn dst src1))
  (:printer format-3-reg ((op #b10) (op3 #b000010) (rs1 0))
            '(:name :tab rs2 ", " rd)
	    :print-name 'mov)
  (:attributes flushable)
  (:dependencies (reads src1) (writes dst))
  (:delay 0)
  (:emitter (emit-format-3-reg segment #b10 (reg-tn-encoding dst) #b000010
			       0 0 0 (reg-tn-encoding src1))))



;;;; Instructions for dumping data and header objects.

(define-instruction word (segment word)
  (:declare (type (or (unsigned-byte 32) (signed-byte 32)) word))
  :pinned
  (:delay 0)
  (:emitter
   (emit-word segment word)))

(define-instruction short (segment short)
  (:declare (type (or (unsigned-byte 16) (signed-byte 16)) short))
  :pinned
  (:delay 0)
  (:emitter
   (emit-short segment short)))

(define-instruction byte (segment byte)
  (:declare (type (or (unsigned-byte 8) (signed-byte 8)) byte))
  :pinned
  (:delay 0)
  (:emitter
   (emit-byte segment byte)))

(define-emitter emit-header-object 32
  (byte 24 8) (byte 8 0))
  
(defun emit-header-data (segment type)
  (emit-back-patch
   segment 4
   #'(lambda (segment posn)
       (emit-word segment
		  (logior type
			  (ash (+ posn (component-header-length))
			       (- type-bits word-shift)))))))

(define-instruction function-header-word (segment)
  :pinned
  (:delay 0)
  (:emitter
   (emit-header-data segment function-header-type)))

(define-instruction lra-header-word (segment)
  :pinned
  (:delay 0)
  (:emitter
   (emit-header-data segment return-pc-header-type)))


;;;; Instructions for converting between code objects, functions, and lras.

(defun emit-compute-inst (segment vop dst src label temp calc)
  (emit-chooser
   ;; We emit either 12 or 4 bytes, so we maintain 8 byte alignments.
   segment 12 3
   #'(lambda (segment posn delta-if-after)
       (let ((delta (funcall calc label posn delta-if-after)))
	 (when (<= (- (ash 1 12)) delta (1- (ash 1 12)))
	   (emit-back-patch segment 4
			    #'(lambda (segment posn)
				(assemble (segment vop)
					  (inst add dst src
						(funcall calc label posn 0)))))
	   t)))
   #'(lambda (segment posn)
       (let ((delta (funcall calc label posn 0)))
	 (assemble (segment vop)
		   (inst sethi temp (ldb (byte 22 10) delta))
		   (inst or temp (ldb (byte 10 0) delta))
		   (inst add dst src temp))))))

;; code = fn - fn-ptr-type - header - label-offset + other-pointer-tag
(define-instruction compute-code-from-fn (segment dst src label temp)
  (:declare (type tn dst src temp) (type label label))
  (:attributes variable-length)
  (:dependencies (reads src) (writes dst) (writes temp))
  (:delay 0)
  (:vop-var vop)
  (:emitter
   (emit-compute-inst segment vop dst src label temp
		      #'(lambda (label posn delta-if-after)
			  (- other-pointer-type
			     function-pointer-type
			     (label-position label posn delta-if-after)
			     (component-header-length))))))

;; code = lra - other-pointer-tag - header - label-offset + other-pointer-tag
(define-instruction compute-code-from-lra (segment dst src label temp)
  (:declare (type tn dst src temp) (type label label))
  (:attributes variable-length)
  (:dependencies (reads src) (writes dst) (writes temp))
  (:delay 0)
  (:vop-var vop)
  (:emitter
   (emit-compute-inst segment vop dst src label temp
		      #'(lambda (label posn delta-if-after)
			  (- (+ (label-position label posn delta-if-after)
				(component-header-length)))))))

;; lra = code + other-pointer-tag + header + label-offset - other-pointer-tag
(define-instruction compute-lra-from-code (segment dst src label temp)
  (:declare (type tn dst src temp) (type label label))
  (:attributes variable-length)
  (:dependencies (reads src) (writes dst) (writes temp))
  (:delay 0)
  (:vop-var vop)
  (:emitter
   (emit-compute-inst segment vop dst src label temp
		      #'(lambda (label posn delta-if-after)
			  (+ (label-position label posn delta-if-after)
			     (component-header-length))))))

;;; Sparc V9 additions



;; Conditional move integer on condition code
(define-instruction cmove (segment condition dst src &optional (ccreg :icc))
  (:declare (type (or branch-condition fp-branch-condition) condition)
	    (type cond-move-condition-register ccreg)
	    (type tn dst)
	    (type (or (signed-byte 13) tn) src))
  (:printer format-4-cond-move
	    ((op #b10)
	     (op3 #b101100)
	     (cc2 #b1)
	     (i 0)
	     (cc nil :type 'integer-condition-register))
	     cond-move-printer
	     :print-name 'mov)
  (:printer format-4-cond-move-immed
	    ((op #b10)
	     (op3 #b101100)
	     (cc2 #b1)
	     (i 1)
	     (cc nil :type 'integer-condition-register))
	     cond-move-printer
	     :print-name 'mov)
  (:printer format-4-cond-move
	    ((op #b10)
	     (op3 #b101100)
	     (cc2 #b0)
	     (cond nil :type 'branch-fp-condition)
	     (i 0)
	     (cc nil :type 'fp-condition-register))
	     cond-move-printer
	     :print-name 'mov)
  (:printer format-4-cond-move-immed
	    ((op #b10)
	     (op3 #b101100)
	     (cc2 #b0)
	     (cond nil :type 'branch-fp-condition)
	     (i 1)
	     (cc nil :type 'fp-condition-register))
	     cond-move-printer
	     :print-name 'mov)
  (:delay 0)
  (:dependencies
   (if (member ccreg '(:icc :xcc))
       (reads :psr)
       (reads :fsr))
   (reads src)
   (reads dst)
   (writes dst))
  (:emitter
   (let ((op #b10)
	 (op3 #b101100))
     (multiple-value-bind (cc2 cc01)
	 (cond-move-condition-parts ccreg)
       (etypecase src
	 (tn
	  (emit-format-4-cond-move segment
				   op
				   (reg-tn-encoding dst)
				   op3
				   cc2
				   (if (member ccreg '(:icc :xcc))
				       (branch-condition condition)
				       (fp-branch-condition condition))
				   0
				   cc01
				   (reg-tn-encoding src)))
	 (integer
	  (emit-format-4-cond-move segment
				   op
				   (reg-tn-encoding dst)
				   op3
				   cc2
				   (if (member ccreg '(:icc :xcc))
				       (branch-condition condition)
				       (fp-branch-condition condition))
				   1
				   cc01
				   src)))))))

;; Conditional move floating-point on condition codes
(defmacro define-cond-fp-move (name print-name op op3 opf_low &key extended)
  `(define-instruction ,name (segment condition dst src &optional (ccreg :fcc0))
     (:declare (type (or branch-condition fp-branch-condition) condition)
	       (type cond-move-condition-register ccreg)
	       (type tn dst src))
     (:printer format-fpop2
	       ((op ,op)
		(op3 ,op3)
		(opf0 0)
		(opf1 nil :type 'fp-condition-register-shifted)
		(opf2 0)
		(opf3 ,opf_low)
		(rs1 nil :type 'branch-fp-condition)
		(rs2 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
		(rd nil :type ',(if extended 'fp-ext-reg 'fp-reg)))
                cond-fp-move-printer
                :print-name ',print-name)
     (:printer format-fpop2
	       ((op ,op)
		(op3 ,op3)
		(opf0 1)
		(opf1 nil :type 'integer-condition-register)
		(opf2 0)
		(rs1 nil :type 'branch-condition)
		(opf3 ,opf_low)
		(rs2 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
		(rd nil :type ',(if extended 'fp-ext-reg 'fp-reg)))
               cond-fp-move-printer
               :print-name ',print-name)
     (:delay 0)
     (:dependencies
      (if (member ccreg '(:icc :xcc))
	  (reads :psr)
	  (reads :fsr))
      (reads src)
      (reads dst)
      (writes dst))
     (:emitter
      (multiple-value-bind (opf_cc2 opf_cc01)
	  (cond-move-condition-parts ccreg)
	(emit-format-3-fpop2 segment
			     ,op
			     (fp-reg-tn-encoding dst)
			     ,op3
			     (if (member ccreg '(:icc :xcc))
				 (branch-condition condition)
				 (fp-branch-condition condition))
			     opf_cc2
			     (ash opf_cc01 1)
			     0
			     ,opf_low
			     (fp-reg-tn-encoding src))))))

(define-cond-fp-move cfmovs fmovs #b10 #b110101 #b0001)
(define-cond-fp-move cfmovd fmovd #b10 #b110101 #b0010 :extended t)
(define-cond-fp-move cfmovq fmovq #b10 #b110101 #b0011 :extended t)


;; Move on integer register condition
;;
;; movr dst src reg reg-cond
;;
;; This means if reg satisfies reg-cond, src is copied to dst.  If the
;; condition is not satisfied, nothing is done.
;;
(define-instruction movr (segment dst src2 src1 reg-condition)
  (:declare (type cond-move-integer-condition reg-condition)
	    (type tn dst src1)
	    (type (or (signed-byte 10) tn) src2))
  (:printer format-4-cond-move-integer
	    ((op #b10)
	     (op3 #b101111)
	     (i 0)))
  (:printer format-4-cond-move-integer-immed
	    ((op #b10)
	     (op3 #b101111)
	     (i 1)))
  (:delay 0)
  (:dependencies
   (reads :psr)
   (reads src2)
   (reads src1)
   (reads dst)
   (writes dst))
  (:emitter
   (etypecase src2
     (tn
      (emit-format-4-cond-move-integer
       segment #b10 (reg-tn-encoding dst) #b101111 (reg-tn-encoding src1)
       0 (register-condition reg-condition)
       0 (reg-tn-encoding src2)))
     (integer
      (emit-format-4-cond-move-integer-immed
       segment #b10 (reg-tn-encoding dst) #b101111 (reg-tn-encoding src1)
       1 (register-condition reg-condition) src2)))))


;; Same as MOVR, except we move FP registers depending on the value of
;; an integer register.
;;
;; fmovr dst src reg cond
;;
;; This means if REG satifies COND, SRC is COPIED to DST.  Nothing
;; happens if the condition is not satisfied.
(defmacro define-cond-fp-move-integer (name opf_low &key extended)
  `(define-instruction ,name (segment dst src2 src1 reg-condition)
     (:declare (type cond-move-integer-condition reg-condition)
	       (type tn dst src1 src2))
     (:printer format-fpop2
	       ((op #b10)
		(rd nil :type ',(if extended 'fp-ext-reg 'fp-reg))
		(op3 #b110101)
		(rs1 nil :type 'reg)
		(opf0 0)
		(opf1 nil :type 'register-condition)
		(opf2 0)
		(opf3 ,opf_low)
		(rs2 nil :type ',(if extended 'fp-ext-reg 'fp-reg))
		)
               cond-fp-move-integer-printer)
     (:delay 0)
     (:dependencies
      (reads src2)
      (reads src1)
      (reads dst)
      (writes dst))
     (:emitter
      (emit-format-3-fpop2
       segment
       #b10
       (fp-reg-tn-encoding dst)
       #b110101
       (reg-tn-encoding src1)
       0
       (register-condition reg-condition)
       0
       ,opf_low
       (fp-reg-tn-encoding src2)))))

(define-cond-fp-move-integer fmovrs #b0101)
(define-cond-fp-move-integer fmovrd #b0110 :extended t)
(define-cond-fp-move-integer fmovrq #b0111 :extended t)
