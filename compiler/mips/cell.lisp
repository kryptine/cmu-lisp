;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/mips/cell.lisp,v 1.44 1990/09/24 00:32:20 wlott Exp $
;;;
;;;    This file contains the VM definition of various primitive memory access
;;; VOPs for the MIPS.
;;;
;;; Written by Rob MacLachlan
;;;
;;; Converted by William Lott.
;;; 

(in-package "C")


;;;; Data object definition macros.

(vm:define-for-each-primitive-object (obj)
  (collect ((forms))
    (let ((lowtag (vm:primitive-object-lowtag obj)))
      (dolist (slot (vm:primitive-object-slots obj))
	(let* ((name (vm:slot-name slot))
	       (offset (vm:slot-offset slot))
	       (rest-p (vm:slot-rest-p slot))
	       (slot-opts (vm:slot-options slot))
	       (ref-trans (getf slot-opts :ref-trans))
	       (ref-vop (getf slot-opts :ref-vop ref-trans))
	       (set-trans (getf slot-opts :set-trans))
	       (setf-function-p (and (listp set-trans)
				     (= (length set-trans) 2)
				     (eq (car set-trans) 'setf)))
	       (setf-vop (getf slot-opts :setf-vop
			       (when setf-function-p
				 (intern (concatenate
					  'simple-string
					  "SET-"
					  (string (cadr set-trans)))))))
	       (set-vop (getf slot-opts :set-vop
			      (if setf-vop nil set-trans))))
	  (when ref-vop
	    (forms `(define-vop (,ref-vop ,(if rest-p 'slot-ref 'cell-ref))
				(:variant ,offset ,lowtag)
		      ,@(when ref-trans
			  `((:translate ,ref-trans))))))
	  (when (or set-vop setf-vop)
	    (forms `(define-vop ,(cond ((and rest-p setf-vop)
					(error "Can't automatically generate ~
					a setf VOP for :rest-p ~
					slots: ~S in ~S"
					       name
					       (vm:primitive-object-name obj)))
				       (rest-p `(,set-vop slot-set))
				       ((and set-vop setf-function-p)
					(error "Setf functions (list ~S) must ~
					use :setf-vops."
					       set-trans))
				       (set-vop `(,set-vop cell-set))
				       (setf-function-p
					`(,setf-vop cell-setf-function))
				       (t
					`(,setf-vop cell-setf)))
		      (:variant ,offset ,lowtag)
		      ,@(when set-trans
			  `((:translate ,set-trans)))))))))
    (when (forms)
      `(progn
	 ,@(forms)))))



;;;; Symbol hacking VOPs:

;;; Do a cell ref with an error check for being unbound.
;;;
(define-vop (checked-cell-ref)
  (:args (object :scs (descriptor-reg) :target obj-temp))
  (:results (value :scs (descriptor-reg any-reg)))
  (:policy :fast-safe)
  (:vop-var vop)
  (:save-p :compute-only)
  (:temporary (:type random  :scs (non-descriptor-reg)) temp)
  (:temporary (:scs (descriptor-reg) :from (:argument 0)) obj-temp))

;;; With Symbol-Value, we check that the value isn't the trap object.  So
;;; Symbol-Value of NIL is NIL.
;;;
(define-vop (symbol-value checked-cell-ref)
  (:translate symbol-value)
  (:generator 9
    (move obj-temp object)
    (loadw value obj-temp vm:symbol-value-slot vm:other-pointer-type)
    (let ((err-lab (generate-error-code vop unbound-symbol-error obj-temp)))
      (inst xor temp value vm:unbound-marker-type)
      (inst beq temp zero-tn err-lab)
      (inst nop))))

;;; With Symbol-Function, we check that the result is a function, so NIL is
;;; always un-fbound.
;;;
(define-vop (symbol-function checked-cell-ref)
  (:translate symbol-function)
  (:generator 10
    (move obj-temp object)
    (loadw value obj-temp vm:symbol-function-slot vm:other-pointer-type)
    (let ((err-lab (generate-error-code vop undefined-symbol-error obj-temp)))
      (test-simple-type value temp err-lab t vm:function-pointer-type))))

#+nil
(define-vop (symbol-setf-function checked-cell-ref)
  (:translate symbol-setf-function)
  (:generator 10
    (move obj-temp object)
    (loadw value obj-temp vm:symbol-setf-function-slot vm:other-pointer-type)
    (let ((err-lab (generate-error-code vop undefined-symbol-error obj-temp)))
      (test-simple-type value temp err-lab t vm:function-pointer-type))))


;;; Like CHECKED-CELL-REF, only we are a predicate to see if the cell is bound.
(define-vop (boundp-frob)
  (:args (object :scs (descriptor-reg)))
  (:conditional)
  (:info target not-p)
  (:policy :fast-safe)
  (:temporary (:scs (descriptor-reg)) value)
  (:temporary (:type random  :scs (non-descriptor-reg)) temp))

(define-vop (boundp boundp-frob)
  (:translate boundp)
  (:generator 9
    (loadw value object vm:symbol-value-slot vm:other-pointer-type)
    (inst xor temp value vm:unbound-marker-type)
    (if not-p
	(inst beq temp zero-tn target)
	(inst bne temp zero-tn target))
    (inst nop)))


;;; SYMBOL isn't a primitive type, so we can't use it for the arg restriction
;;; on the symbol case of fboundp.  Instead, we transform to a funny function.

(defknown fboundp/symbol (t) boolean (flushable))
;;;
(deftransform fboundp ((x) (symbol))
  '(fboundp/symbol x))
;;;
(define-vop (fboundp/symbol boundp-frob)
  (:translate fboundp/symbol)
  (:generator 10
    (loadw value object vm:symbol-function-slot vm:other-pointer-type)
    (test-simple-type value temp target not-p vm:function-pointer-type)))

(defknown fboundp/setf (t) boolean (flushable))
;;;
(deftransform fboundp ((x) (cons))
  '(foundp/setf (cadr x)))
;;;
(define-vop (fboundp/setf boundp-frob)
  (:translate fboundp/setf)
  (:generator 10
    (loadw value object vm:symbol-setf-function-slot vm:other-pointer-type)
    (test-simple-type value temp target not-p vm:function-pointer-type)))

(define-vop (fast-symbol-value cell-ref)
  (:variant vm:symbol-value-slot vm:other-pointer-type)
  (:policy :fast)
  (:translate symbol-value))

(define-vop (fast-symbol-function cell-ref)
  (:variant vm:symbol-function-slot vm:other-pointer-type)
  (:policy :fast)
  (:translate symbol-function))


(define-vop (set-symbol-function)
  (:translate %sp-set-definition)
  (:policy :fast-safe)
  (:args (symbol :scs (descriptor-reg))
	 (function :scs (descriptor-reg) :target result))
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) type)
  (:temporary (:scs (any-reg)) temp)
  (:save-p :compute-only)
  (:vop-var vop)
  (:generator 30
    (let ((closure (gen-label))
	  (normal-fn (gen-label)))
      (load-type type function (- vm:function-pointer-type))
      (inst nop)
      (inst xor type vm:closure-header-type)
      (inst beq type zero-tn closure)
      (inst xor type (logxor vm:closure-header-type vm:function-header-type))
      (inst beq type zero-tn normal-fn)
      (inst addu temp function
	    (- (ash vm:function-header-code-offset vm:word-shift)
	       vm:function-pointer-type))
      (error-call vop kernel:object-not-function-error function)
      (emit-label closure)
      (inst li temp (make-fixup "closure_tramp" :foreign))
      (emit-label normal-fn)
      (storew function symbol vm:symbol-function-slot vm:other-pointer-type)
      (storew temp symbol vm:symbol-raw-function-addr-slot vm:other-pointer-type)
      (move result function))))


(defknown fmakunbound/symbol (symbol) symbol (unsafe))
;;;
(deftransform fmakunbound ((symbol) (symbol))
  '(progn
     (fmakunbound/symbol symbol)
     t))
;;;
(define-vop (fmakunbound/symbol)
  (:translate fmakunbound/symbol)
  (:policy :fast-safe)
  (:args (symbol :scs (descriptor-reg) :target result))
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:generator 5
    (inst li temp vm:unbound-marker-type)
    (storew temp symbol vm:symbol-function-slot vm:other-pointer-type)
    (inst li temp (make-fixup "undefined_tramp" :foreign))
    (storew temp symbol vm:symbol-raw-function-addr-slot vm:other-pointer-type)
    (move result symbol)))


;;; Binding and Unbinding.

;;; BIND -- Establish VAL as a binding for SYMBOL.  Save the old value and
;;; the symbol on the binding stack and stuff the new value into the
;;; symbol.

(define-vop (bind)
  (:args (val :scs (any-reg descriptor-reg))
	 (symbol :scs (descriptor-reg)))
  (:temporary (:scs (descriptor-reg)) temp)
  (:generator 5
    (loadw temp symbol vm:symbol-value-slot vm:other-pointer-type)
    (inst addu bsp-tn bsp-tn (* 2 vm:word-bytes))
    (storew temp bsp-tn (- vm:binding-value-slot vm:binding-size))
    (storew symbol bsp-tn (- vm:binding-symbol-slot vm:binding-size))
    (storew val symbol vm:symbol-value-slot vm:other-pointer-type)))


(define-vop (unbind)
  (:temporary (:scs (descriptor-reg)) symbol value)
  (:generator 0
    (loadw symbol bsp-tn (- vm:binding-symbol-slot vm:binding-size))
    (loadw value bsp-tn (- vm:binding-value-slot vm:binding-size))
    (storew value symbol vm:symbol-value-slot vm:other-pointer-type)
    (storew zero-tn bsp-tn (- vm:binding-symbol-slot vm:binding-size))
    (inst addu bsp-tn bsp-tn (* -2 vm:word-bytes))))


(define-vop (unbind-to-here)
  (:args (arg :scs (descriptor-reg any-reg) :target where))
  (:temporary (:scs (any-reg) :from (:argument 0)) where)
  (:temporary (:scs (descriptor-reg)) symbol value)
  (:generator 0
    (let ((loop (gen-label))
	  (skip (gen-label))
	  (done (gen-label)))
      (move where arg)
      (inst beq where bsp-tn done)
      (loadw symbol bsp-tn (- vm:binding-symbol-slot vm:binding-size))

      (emit-label loop)
      (inst beq symbol zero-tn skip)
      (loadw value bsp-tn (- vm:binding-value-slot vm:binding-size))
      (storew value symbol vm:symbol-value-slot vm:other-pointer-type)
      (storew zero-tn bsp-tn (- vm:binding-symbol-slot vm:binding-size))

      (emit-label skip)
      (inst addu bsp-tn bsp-tn (* -2 vm:word-bytes))
      (inst bne where bsp-tn loop)
      (loadw symbol bsp-tn (- vm:binding-symbol-slot vm:binding-size))

      (emit-label done))))



;;;; Closure indexing.

(define-vop (closure-index-ref word-index-ref)
  (:variant vm:closure-info-offset vm:function-pointer-type)
  (:translate %closure-index-ref))


;;;; Structure hackery:

;;; ### This is only necessary until we get real structures up and running.

(define-vop (structure-ref slot-ref)
  (:variant vm:vector-data-offset vm:other-pointer-type))

(define-vop (structure-set slot-set)
  (:variant vm:vector-data-offset vm:other-pointer-type))

(define-vop (structure-index-ref word-index-ref)
  (:variant vm:vector-data-offset vm:other-pointer-type))

(define-vop (structure-index-set word-index-set)
  (:variant vm:vector-data-offset vm:other-pointer-type))




;;;; Extra random indexers.

(define-vop (code-constant-set word-index-set)
  (:variant vm:code-constants-offset vm:other-pointer-type))

