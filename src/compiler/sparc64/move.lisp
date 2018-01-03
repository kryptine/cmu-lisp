;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: src/compiler/sparc/move.lisp $")
;;;
;;; **********************************************************************
;;;
;;; $Header: src/compiler/sparc/move.lisp $
;;;
;;;    This file contains the SPARC VM definition of operand loading/saving and
;;; the Move VOP.
;;;
;;; Written by Rob MacLachlan.
;;; SPARC conversion by William Lott.
;;;
(in-package "SPARC")
(intl:textdomain "cmucl-sparc64-vm")


(define-move-function (load-immediate 1) (vop x y)
  ((null immediate zero)
   (any-reg descriptor-reg))
  (let ((val (tn-value x)))
    (etypecase val
      (integer
       (not-implemented "LOAD-IMMEDIATE/INTEGER")
       (inst li y (fixnumize val)))
      (null
       (not-implemented "LOAD-IMMEDIATE/NULL")
       (move y null-tn))
      (symbol
       (not-implemented "LOAD-IMMEDIATE/SYMBOL")
       (load-symbol y val))
      (character
       (not-implemented "LOAD-IMMEDIATE/CHAR")
       (inst li y (logior (ash (char-code val) type-bits)
			  base-char-type))))))

#-(and sparc-v9 sparc-v8plus)
(define-move-function (load-number 1) (vop x y)
  ((immediate zero)
   (signed-reg unsigned-reg))
  (not-implemented "LOAD-NUMBER")
  (inst li y (tn-value x)))

#+(and sparc-v9 sparc-v8plus)
(define-move-function (load-number 1) (vop x y)
  ((immediate zero)
   (signed-reg unsigned-reg signed64-reg unsigned64-reg))
  (not-implemented "LOAD-NUMBER")
  (inst li64 y (tn-value x)))

(define-move-function (load-base-char 1) (vop x y)
  ((immediate) (base-char-reg))
  (not-implemented "LOAD-BASE-CHAR")
  (inst li y (char-code (tn-value x))))

(define-move-function (load-system-area-pointer 1) (vop x y)
  ((immediate) (sap-reg))
  (not-implemented "LOAD-SYSTEM-AREA-POINTER")
  (inst li y (sap-int (tn-value x))))

(define-move-function (load-constant 5) (vop x y)
  ((constant) (descriptor-reg))
  (not-implemented "LOAD-CONSTANT")
  (loadw y code-tn (tn-offset x) other-pointer-type gtemp-tn))

(define-move-function (load-stack 5) (vop x y)
  ((control-stack) (any-reg descriptor-reg))
  (not-implemented "LOAD-STACK")
  (load-stack-tn y x))

(define-move-function (load-number-stack 5) (vop x y)
  ((base-char-stack) (base-char-reg)
   (sap-stack) (sap-reg)
   (signed-stack) (signed-reg)
   (unsigned-stack) (unsigned-reg))
  (let ((nfp (current-nfp-tn vop)))
    (not-implemented "LOAD-NUMBER-STACK")
    (loadw y nfp (tn-offset x))))

(define-move-function (store-stack 5) (vop x y)
  ((any-reg descriptor-reg) (control-stack))
  (not-implemented "DEFINE-MOVE STORE-STACK")
  (store-stack-tn y x))

(define-move-function (store-number-stack 5) (vop x y)
  ((base-char-reg) (base-char-stack)
   (sap-reg) (sap-stack)
   (signed-reg) (signed-stack)
   (unsigned-reg) (unsigned-stack))
  (let ((nfp (current-nfp-tn vop)))
    (not-implemented "STORE-NUMBER-STACK")
    (storew x nfp (tn-offset y))))



;;;; The Move VOP:
;;;
(define-vop (move)
  (:args (x :target y
	    :scs (any-reg descriptor-reg zero null)
	    :load-if (not (location= x y))))
  (:results (y :scs (any-reg descriptor-reg)
	       :load-if (not (location= x y))))
  (:effects)
  (:affected)
  (:generator 0
    (move y x)))

(define-move-vop move :move
  (any-reg descriptor-reg)
  (any-reg descriptor-reg))

;;; Make Move the check VOP for T so that type check generation doesn't think
;;; it is a hairy type.  This also allows checking of a few of the values in a
;;; continuation to fall out.
;;;
(primitive-type-vop move (:check) t)

;;;    The Move-Argument VOP is used for moving descriptor values into another
;;; frame for argument or known value passing.
;;;
(define-vop (move-argument)
  (:args (x :target y
	    :scs (any-reg descriptor-reg zero null))
	 (fp :scs (any-reg)
	     :load-if (not (sc-is y any-reg descriptor-reg))))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (y))
  (:generator 0
    (emit-not-implemented)
    (sc-case y
      ((any-reg descriptor-reg)
       (move y x))
      (control-stack
       (storew x fp (tn-offset y) 0 temp)))))
;;;
(define-move-vop move-argument :move-argument
  (any-reg descriptor-reg)
  (any-reg descriptor-reg))



;;;; ILLEGAL-MOVE

;;; This VOP exists just to begin the lifetime of a TN that couldn't be written
;;; legally due to a type error.  An error is signalled before this VOP is
;;; so we don't need to do anything (not that there would be anything sensible
;;; to do anyway.)
;;;
(define-vop (illegal-move)
  (:args (x) (type))
  (:results (y))
  (:ignore y)
  (:vop-var vop)
  (:save-p :compute-only)
  (:generator 666
    (error-call vop object-not-type-error x type)))



;;;; Moves and coercions:

;;; These MOVE-TO-WORD VOPs move a tagged integer to a raw full-word
;;; representation.  Similarly, the MOVE-FROM-WORD VOPs converts a raw integer
;;; to a tagged bignum or fixnum.

;;; Arg is a fixnum, so just shift it.  We need a type restriction because some
;;; possible arg SCs (control-stack) overlap with possible bignum arg SCs.
;;;
(define-vop (move-to-word/fixnum)
  (:args (x :scs (any-reg descriptor-reg)))
  (:results (y :scs (signed-reg unsigned-reg)))
  (:arg-types tagged-num)
  (:note _N"fixnum untagging")
  (:generator 1
    (emit-not-implemented)
    (inst sran y x fixnum-tag-bits)))

;;;
(define-move-vop move-to-word/fixnum :move
  (any-reg descriptor-reg) (signed-reg unsigned-reg))

;;; Arg is a non-immediate constant, load it.
(define-vop (move-to-word-c)
  (:args (x :scs (constant)))
  (:results (y :scs (signed-reg unsigned-reg)))
  (:note _N"constant load")
  (:generator 1
    (emit-not-implemented)
    (inst li y (tn-value x))))

;;;
(define-move-vop move-to-word-c :move
  (constant) (signed-reg unsigned-reg))

;;; Arg is a fixnum or bignum, figure out which and load if necessary.
#-(and sparc-v9 sparc-v8plus)
(define-vop (move-to-word/integer)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (signed-reg unsigned-reg)))
  (:note _N"integer to untagged word coercion")
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:generator 4
    (let ((done (gen-label)))
      (emit-not-implemented)
      (inst andcc temp x fixnum-tag-mask)
      (inst b :eq done)
      (inst sran y x fixnum-tag-bits)
      
      (loadw y x bignum-digits-offset other-pointer-type)
      
      (emit-label done))))

;; Same as above, but the number is sign-extended to a full 64-bit
;; length.  Not really needed, I suppose.
#+(and sparc-v9 sparc-v8plus)
(define-vop (move-to-word/integer)
  (:args (x :scs (descriptor-reg)))
  (:results (y :scs (signed-reg unsigned-reg)))
  (:note _N"integer to untagged word coercion")
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:generator 4
    (let ((done (gen-label)))
      (emit-not-implemented)
      (inst andcc temp x fixnum-tag-mask)
      (inst signx temp x)		; sign-extend x to temp
      (inst b :eq done)
      (inst srax y temp fixnum-tag-bits)
      
      (loadsw y x bignum-digits-offset other-pointer-type)
      
      (emit-label done))))

;;;
(define-move-vop move-to-word/integer :move
  (descriptor-reg) (signed-reg unsigned-reg))


    
;;; Result is a fixnum, so we can just shift.  We need the result type
;;; restriction because of the control-stack ambiguity noted above.
;;;
(define-vop (move-from-word/fixnum)
  (:args (x :scs (signed-reg unsigned-reg)))
  (:results (y :scs (any-reg descriptor-reg)))
  (:result-types tagged-num)
  (:note _N"fixnum tagging")
  (:generator 1
    (emit-not-implemented)
    (inst slln y x fixnum-tag-bits)))
;;;
(define-move-vop move-from-word/fixnum :move
  (signed-reg unsigned-reg) (any-reg descriptor-reg))


;;; Result may be a bignum, so we have to check.  Use a worst-case cost to make
;;; sure people know they may be number consing.
;;;
(define-vop (move-from-signed)
  (:args (arg :scs (signed-reg unsigned-reg) :target x))
  (:results (y :scs (any-reg descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg) :from (:argument 0)) x temp)
  (:note _N"signed word to integer coercion")
  (:generator 20
    (emit-not-implemented)
    (move x arg)
    (let ((done (gen-label)))
      ;; Need to figure out if we have a fixnum or not, so look at the
      ;; top 3 bits of the 32-bit int.  If these 3 bits are 0 or 7,
      ;; then we have a fixnum.  Otherwise we need to allocate a
      ;; bignum.
      ;;
      ;; A simple way to tell if those 3 bits are 0 or 7 was given by
      ;; Frode Vatvedt Fjeld: (zerop (logand #b110 (1+ temp)))
      (inst srln temp x positive-fixnum-bits)
      (inst add temp 1)
      (inst andcc temp #b110)
      (inst b :eq done)
      (inst slln y x fixnum-tag-bits)
      
      (with-fixed-allocation
	(y temp bignum-type (1+ bignum-digits-offset))
	(storew x y bignum-digits-offset other-pointer-type))
      (emit-label done))))
;;;
(define-move-vop move-from-signed :move
  (signed-reg) (descriptor-reg))

;;; Result may be a bignum, so we have to check.  Use a worst-case cost to make
;;; sure people know they may be number consing.
;;;
    
;;; Check for fixnum, and possibly allocate one or two word bignum result.  Use
;;; a worst-case cost to make sure people know they may be number consing.
;;;
#-sparc-v9
(define-vop (move-from-unsigned)
  (:args (arg :scs (signed-reg unsigned-reg) :target x))
  (:results (y :scs (any-reg descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg) :from (:argument 0)) x temp)
  (:note _N"unsigned word to integer coercion")
  (:generator 20
    (emit-not-implemented)
    (move x arg)
    (let ((done (gen-label))
	  (one-word (gen-label)))
      (inst sran temp x positive-fixnum-bits)
      (inst cmp temp)
      (inst b :eq done)
      (inst slln y x fixnum-tag-bits)

      ;; We always allocate 2 words even if we don't need it.  (The
      ;; copying GC will take care of freeing the unused extra word.)
      (with-fixed-allocation
	  (y temp bignum-type (+ 2 bignum-digits-offset))
	(inst cmp x)
	(inst b :ge one-word)
	(inst li temp (logior (ash 1 type-bits) bignum-type))
	(inst li temp (logior (ash 2 type-bits) bignum-type))
	(emit-label one-word)
	;; Set the header word, then the actual digit.  The extra
	;; digit, if any, is automatically set to zero, so we don't
	;; have to.
	(storew temp y 0 other-pointer-type)
	(storew x y bignum-digits-offset other-pointer-type))
      (emit-label done))))

#+sparc-v9
(define-vop (move-from-unsigned)
  (:args (arg :scs (signed-reg unsigned-reg) :target x))
  (:results (y :scs (any-reg descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg) :from (:argument 0)) x temp)
  (:note _N"unsigned word to integer coercion")
  (:generator 20
    (emit-not-implemented)
    (move x arg)
    (let ((done (gen-label)))
      (inst sran temp x positive-fixnum-bits)
      (inst cmp temp)
      (inst b :eq done)
      (inst slln y x fixnum-tag-bits)

      ;; We always allocate 2 words even if we don't need it.  (The
      ;; copying GC will take care of freeing the unused extra word.)
      (with-fixed-allocation (y temp nil (+ 2 bignum-digits-offset))
	(inst cmp x)
	(inst li temp (logior (ash 2 type-bits) bignum-type))
	(inst cmove :ge temp (logior (ash 1 type-bits) bignum-type))
	;; Set the header word, then the actual digit.  The extra
	;; digit, if any, is automatically set to zero, so we don't
	;; have to.
	(storew temp y 0 other-pointer-type)
	(storew x y bignum-digits-offset other-pointer-type))
      (emit-label done))))
;;;
(define-move-vop move-from-unsigned :move
  (unsigned-reg) (descriptor-reg))


;;; Move untagged numbers.
;;;
(define-vop (word-move)
  (:args (x :target y
	    :scs (signed-reg unsigned-reg)
	    :load-if (not (location= x y))))
  (:results (y :scs (signed-reg unsigned-reg)
	       :load-if (not (location= x y))))
  (:effects)
  (:affected)
  (:note _N"word integer move")
  (:generator 0
    (move y x)))
;;;
(define-move-vop word-move :move
  (signed-reg unsigned-reg) (signed-reg unsigned-reg))

;;; Move untagged number arguments/return-values.
;;;
(define-vop (move-word-argument)
  (:args (x :target y
	    :scs (signed-reg unsigned-reg))
	 (fp :scs (any-reg)
	     :load-if (not (sc-is y sap-reg))))
  (:results (y))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:note _N"word integer argument move")
  (:generator 0
    (emit-not-implemented)
    (sc-case y
      ((signed-reg unsigned-reg)
       (move y x))
      ((signed-stack unsigned-stack)
       (storew x fp (tn-offset y) 0 temp)))))
;;;
(define-move-vop move-word-argument :move-argument
  (descriptor-reg any-reg signed-reg unsigned-reg) (signed-reg unsigned-reg))

;;; Use standard MOVE-ARGUMENT + coercion to move an untagged number to a
;;; descriptor passing location.
;;;
(define-move-vop move-argument :move-argument
  (signed-reg unsigned-reg) (any-reg descriptor-reg))
