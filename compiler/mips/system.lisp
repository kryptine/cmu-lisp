;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/mips/system.lisp,v 1.35 1990/11/06 14:02:28 wlott Exp $
;;;
;;;    MIPS VM definitions of various system hacking operations.
;;;
;;; Written by Rob MacLachlan
;;;
;;; Mips conversion by William Lott and Christopher Hoover.
;;;
(in-package "MIPS")


;;;; Random pointer comparison VOPs

(define-vop (pointer-compare)
  (:args (x :scs (sap-reg))
	 (y :scs (sap-reg)))
  (:arg-types system-area-pointer system-area-pointer)
  (:temporary (:type random  :scs (non-descriptor-reg)) temp)
  (:conditional)
  (:info target not-p)
  (:policy :fast-safe)
  (:note "inline comparison")
  (:variant-vars condition)
  (:generator 3
    (three-way-comparison x y condition :unsigned not-p target temp)))

(macrolet ((frob (name cond)
	     `(progn
		(def-primitive-translator ,name (x y) `(,',name ,x ,y))
		(defknown ,name (t t) boolean (movable foldable flushable))
		(define-vop (,name pointer-compare)
		  (:translate ,name)
		  (:variant ,cond)))))
  (frob pointer< :lt)
  (frob pointer> :gt))



;;;; Random assertions VOPS.

(define-vop (check-op)
  (:args (x :scs (any-reg descriptor-reg))
	 (y :scs (any-reg descriptor-reg)))
  (:temporary (:type random  :scs (non-descriptor-reg)) temp)
  (:vop-var vop)
  (:save-p :compute-only)
  (:policy :fast-safe))

(define-vop (check<= check-op)
  (:translate check<=)
  (:generator 3
    (let ((target (generate-error-code vop not-<=-error x y)))
      (three-way-comparison x y :gt :signed nil target temp))))

(define-vop (check= check-op)
  (:translate check=)
  (:generator 3
    (let ((target (generate-error-code vop not-=-error x y)))
      (three-way-comparison x y :eq :signed t target temp))))



;;;; Type frobbing VOPs

(define-vop (get-lowtag)
  (:translate get-lowtag)
  (:policy :fast-safe)
  (:args (object :scs (any-reg descriptor-reg)))
  (:results (result :scs (unsigned-reg)))
  (:result-types positive-fixnum)
  (:generator 1
    (inst and result object vm:lowtag-mask)))

(define-vop (get-type)
  (:translate get-type)
  (:policy :fast-safe)
  (:args (object :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:results (result :scs (unsigned-reg)))
  (:result-types positive-fixnum)
  (:generator 6
    (let ((other-ptr (gen-label))
	  (function-ptr (gen-label))
	  (done (gen-label)))
      (simple-test-simple-type object ndescr other-ptr
			       nil vm:other-pointer-type)
      (simple-test-simple-type object ndescr function-ptr
			       nil vm:function-pointer-type)
      (inst and result object (logand vm:other-immediate-0-type
				      vm:other-immediate-1-type))
      (inst beq result done)
      (inst nop)

      (inst b done)
      (inst and result object vm:type-mask)

      (emit-label function-ptr)
      (load-type result object (- vm:function-pointer-type))
      (inst b done)
      (inst nop)

      (emit-label other-ptr)
      (load-type result object (- vm:other-pointer-type))
      (inst nop)
      
      (emit-label done))))

(define-vop (get-header-data)
  (:translate get-header-data)
  (:policy :fast-safe)
  (:args (x :scs (descriptor-reg)))
  (:results (res :scs (unsigned-reg)))
  (:result-types positive-fixnum)
  (:generator 6
    (loadw res x 0 vm:other-pointer-type)
    (inst srl res res vm:type-bits)))

(define-vop (get-closure-length)
  (:translate get-closure-length)
  (:policy :fast-safe)
  (:args (x :scs (descriptor-reg)))
  (:results (res :scs (unsigned-reg)))
  (:result-types positive-fixnum)
  (:generator 6
    (loadw res x 0 vm:function-pointer-type)
    (inst srl res res vm:type-bits)))

(define-vop (set-header-data)
  (:translate set-header-data)
  (:policy :fast-safe)
  (:args (x :scs (descriptor-reg) :target res)
	 (data :scs (any-reg immediate zero)))
  (:arg-types * positive-fixnum)
  (:results (res :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg) :type random) t1 t2)
  (:generator 6
    (loadw t1 x 0 vm:other-pointer-type)
    (inst and t1 vm:type-mask)
    (sc-case data
      (any-reg
       (inst sll t2 data (- vm:type-bits 2))
       (inst or t1 t2))
      (immediate
       (inst or t1 (ash (tn-value data) vm:type-bits)))
      (zero))
    (storew t1 x 0 vm:other-pointer-type)
    (move res x)))


(define-vop (structurify)
  (:policy :fast-safe)
  (:translate structurify)
  (:args (vec :scs (descriptor-reg) :target struct))
  (:results (struct :scs (descriptor-reg)))
  (:temporary (:scs (any-reg)) temp)
  (:generator 2
    (inst li temp vm:structure-header-type)
    (storew temp vec 0 vm:other-pointer-type)
    (move struct vec)))


(define-vop (lisp::make-fixnum)
  (:args (ptr :scs (any-reg descriptor-reg)))
  (:results (res :scs (any-reg descriptor-reg)))
  (:generator 1
    ;;
    ;; Some code (the hash table code) depends on this returning a
    ;; positive number so make sure it does.
    (inst sll res ptr 3)
    (inst srl res res 1)))

(define-vop (lisp::make-other-immediate-type)
  (:args (val :scs (any-reg descriptor-reg))
	 (type :scs (any-reg descriptor-reg immediate unsigned-immediate)
	       :target temp))
  (:results (res :scs (any-reg descriptor-reg)))
  (:temporary (:type random  :scs (non-descriptor-reg)) temp)
  (:generator 2
    (sc-case type
      ((immediate unsigned-immediate)
       (inst sll temp val vm:type-bits)
       (inst or res temp (tn-value type)))
      (t
       (inst sra temp type 2)
       (inst sll res val (- vm:type-bits 2))
       (inst or res res temp)))))


;;;; Allocation

(define-vop (dynamic-space-free-pointer)
  (:results (int :scs (sap-reg)))
  (:result-types system-area-pointer)
  (:translate dynamic-space-free-pointer)
  (:policy :fast-safe)
  (:generator 1
    (move int alloc-tn)))

(define-vop (binding-stack-pointer-sap)
  (:results (int :scs (sap-reg)))
  (:result-types system-area-pointer)
  (:translate binding-stack-pointer-sap)
  (:policy :fast-safe)
  (:generator 1
    (move int bsp-tn)))

(define-vop (control-stack-pointer-sap)
  (:results (int :scs (sap-reg)))
  (:result-types system-area-pointer)
  (:translate control-stack-pointer-sap)
  (:policy :fast-safe)
  (:generator 1
    (move int csp-tn)))


;;;; Code object frobbing.

(define-vop (code-instructions)
  (:args (code :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:results (sap :scs (sap-reg)))
  (:result-types system-area-pointer)
  (:generator 10
    (loadw ndescr code 0 vm:other-pointer-type)
    (inst srl ndescr vm:type-bits)
    (inst sll ndescr vm:word-shift)
    (inst subu ndescr vm:other-pointer-type)
    (inst addu sap code ndescr)))

(define-vop (compute-function)
  (:args (code :scs (descriptor-reg))
	 (offset :scs (signed-reg unsigned-reg)))
  (:arg-types * positive-fixnum)
  (:results (func :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:generator 10
    (loadw ndescr code 0 vm:other-pointer-type)
    (inst srl ndescr vm:type-bits)
    (inst sll ndescr vm:word-shift)
    (inst addu ndescr offset)
    (inst addu ndescr (- vm:function-pointer-type vm:other-pointer-type))
    (inst addu func code ndescr)))


;;;; Other random VOPs.


(defknown mach::do-pending-interrupt () (values))
(define-vop (mach::do-pending-interrupt)
  (:policy :fast-safe)
  (:translate mach::do-pending-interrupt)
  (:generator 1
    (inst break vm:pending-interrupt-trap)))


(define-vop (lisp::halt)
  (:generator 1
    (inst break vm:halt-trap)))

