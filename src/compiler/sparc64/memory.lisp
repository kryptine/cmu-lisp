;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: src/compiler/sparc/memory.lisp $")
;;;
;;; **********************************************************************
;;;
;;;    This file contains the SPARC definitions of some general purpose memory
;;; reference VOPs inherited by basic memory reference operations.
;;;
;;; Written by Rob MacLachlan
;;;
;;; Converted by William Lott.
;;; 

(in-package "SPARC")

;;; Cell-Ref and Cell-Set are used to define VOPs like CAR, where the offset to
;;; be read or written is a property of the VOP used.
;;;
(define-vop (cell-ref)
  (:args (object :scs (descriptor-reg)))
  (:results (value :scs (descriptor-reg any-reg)))
  (:variant-vars offset lowtag)
  (:policy :fast-safe)
  (:generator 4
    (emit-not-implemented)
    (loadw value object offset lowtag)))
;;;
(define-vop (cell-set)
  (:args (object :scs (descriptor-reg))
         (value :scs (descriptor-reg any-reg)))
  (:variant-vars offset lowtag)
  (:policy :fast-safe)
  (:generator 4
    (emit-not-implemented)
    (storew value object offset lowtag)))

;;; Slot-Ref and Slot-Set are used to define VOPs like Closure-Ref, where the
;;; offset is constant at compile time, but varies for different uses.  We add
;;; in the stardard g-vector overhead.
;;;
(define-vop (slot-ref)
  (:args (object :scs (descriptor-reg)))
  (:results (value :scs (descriptor-reg any-reg)))
  (:variant-vars base lowtag)
  (:info offset)
  (:generator 4
    (emit-not-implemented)
    (loadw value object (+ base offset) lowtag)))
;;;
(define-vop (slot-set)
  (:args (object :scs (descriptor-reg))
	 (value :scs (descriptor-reg any-reg)))
  (:variant-vars base lowtag)
  (:info offset)
  (:generator 4
    (emit-not-implemented)
    (storew value object (+ base offset) lowtag)))



;;;; Indexed references:

;;; Define-Indexer  --  Internal
;;;
;;;    Define some VOPs for indexed memory reference.
;;;
(defmacro define-indexer (name write-p op shift)
  `(define-vop (,name)
     (:args (object :scs (descriptor-reg))
	    (index :scs (any-reg zero immediate))
	    ,@(when write-p
		'((value :scs (any-reg descriptor-reg) :target result))))
     (:arg-types * tagged-num ,@(when write-p '(*)))
     (:temporary (:scs (non-descriptor-reg)) temp)
     (:results (,(if write-p 'result 'value)
		:scs (any-reg descriptor-reg)))
     (:result-types *)
     (:variant-vars offset lowtag)
     (:policy :fast-safe)
     (:generator 5
       (emit-not-implemented)
       (sc-case index
	 ((immediate zero)
	  (let ((offset (- (+ (if (sc-is index zero)
				  0
				  (ash (tn-value index)
				       (- vm:word-shift ,shift)))
			      (ash offset vm:word-shift))
			   lowtag)))
	    (etypecase offset
	      ((signed-byte 13)
	       (inst ,op value object offset))
	      ((or (unsigned-byte 32) (signed-byte 32))
	       (inst li temp offset)
	       (inst ,op value object temp)))))
	 (t
	  ,@(unless (zerop shift)
	      (if (minusp shift)
		  `((inst slln temp index ,(- shift)))
		  `((inst srln temp index ,shift))))
	  (inst add temp ,(if (zerop shift) 'index 'temp)
		(- (ash offset vm:word-shift) lowtag))
	  (inst ,op value object temp)))
       ,@(when write-p
	   '((move result value))))))

#+sparc-v9
(define-indexer signed-word-index-ref nil ldsw 0)
#+sparc-v9
(define-indexer signed-word-index-set nil st 0)
(define-indexer word-index-ref nil ldn -1)
(define-indexer word-index-set t stn -1)
(define-indexer halfword-index-ref nil lduh 1)
(define-indexer signed-halfword-index-ref nil ldsh 1)
(define-indexer halfword-index-set t sth 1)
(define-indexer byte-index-ref nil ldub 2)
(define-indexer signed-byte-index-ref nil ldsb 2)
(define-indexer byte-index-set t stb 2)
