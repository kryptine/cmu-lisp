;;; -*- Package: SPARC -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/sparc/alloc.lisp,v 1.18 2003/09/03 20:09:31 toy Exp $")
;;;
;;; **********************************************************************
;;;
;;; Allocation VOPs for the SPARC port.
;;;
;;; Written by William Lott.
;;; 

(in-package "SPARC")


;;;; Dynamic-Extent.

;;;
;;; Take an arg where to move the stack pointer instead of returning
;;; it via :results, because the former generates a single move.
;;;
(define-vop (%dynamic-extent-start)
  (:args (saved-stack-pointer :scs (any-reg control-stack)))
  (:results)
  (:policy :safe)
  (:generator 0
    (sc-case saved-stack-pointer
      (control-stack
       (let ((offset (tn-offset saved-stack-pointer)))
	 (storew csp-tn cfp-tn offset)))
      (any-reg
       (move saved-stack-pointer csp-tn)))))

(define-vop (%dynamic-extent-end)
  (:args (saved-stack-pointer :scs (any-reg control-stack)))
  (:results)
  (:policy :safe)
  (:generator 0
    (sc-case saved-stack-pointer
      (control-stack
       (let ((offset (tn-offset saved-stack-pointer)))
	 (loadw csp-tn cfp-tn offset)))
      (any-reg
       (move csp-tn saved-stack-pointer)))))

;;;; LIST and LIST*

(define-vop (list-or-list*)
  (:args (things :more t))
  (:temporary (:scs (descriptor-reg) :type list) ptr)
  (:temporary (:scs (descriptor-reg)) temp)
  (:temporary (:scs (descriptor-reg) :type list :to (:result 0) :target result)
	      res)
  (:temporary (:scs (non-descriptor-reg)) alloc-temp)
  (:info num dynamic-extent)
  (:results (result :scs (descriptor-reg)))
  (:variant-vars star)
  (:policy :safe)
  (:generator 0
    (cond ((zerop num)
	   (move result null-tn))
	  ((and star (= num 1))
	   (move result (tn-ref-tn things)))
	  (t
	   (macrolet
	       ((maybe-load (tn)
		  (once-only ((tn tn))
		    `(sc-case ,tn
		       ((any-reg descriptor-reg zero null)
			,tn)
		       (control-stack
			(load-stack-tn temp ,tn)
			temp)))))
	     (let* ((cons-cells (if star (1- num) num))
		    (alloc (* (pad-data-block cons-size) cons-cells)))
	       (pseudo-atomic ()
		 (allocation res alloc list-pointer-type
			     :stack-p dynamic-extent
			     :temp-tn alloc-temp)
		 (move ptr res)
		 (dotimes (i (1- cons-cells))
		   (storew (maybe-load (tn-ref-tn things)) ptr
			   cons-car-slot list-pointer-type)
		   (setf things (tn-ref-across things))
		   (inst add ptr ptr (pad-data-block cons-size))
		   (storew ptr ptr
			   (- cons-cdr-slot cons-size)
			   list-pointer-type))
		 (storew (maybe-load (tn-ref-tn things)) ptr
			 cons-car-slot list-pointer-type)
		 (storew (if star
			     (maybe-load (tn-ref-tn (tn-ref-across things)))
			     null-tn)
			 ptr cons-cdr-slot list-pointer-type))
	       (move result res)))))))

(define-vop (list list-or-list*)
  (:variant nil))

(define-vop (list* list-or-list*)
  (:variant t))


;;;; Special purpose inline allocators.

(define-vop (allocate-code-object)
  (:args (boxed-arg :scs (any-reg))
	 (unboxed-arg :scs (any-reg)))
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) ndescr)
  (:temporary (:scs (non-descriptor-reg)) size)
  (:temporary (:scs (any-reg) :from (:argument 0)) boxed)
  (:temporary (:scs (non-descriptor-reg) :from (:argument 1)) unboxed)
  (:generator 100
    (inst add boxed boxed-arg (fixnumize (1+ code-trace-table-offset-slot)))
    (inst and boxed (lognot lowtag-mask))
    (inst srl unboxed unboxed-arg word-shift)
    (inst add unboxed lowtag-mask)
    (inst and unboxed (lognot lowtag-mask))
    (pseudo-atomic ()
      ;; Figure out how much space we really need and allocate it.
      (inst add size boxed unboxed)
      (allocation result size other-pointer-type :temp-tn ndescr)
      (inst sll ndescr boxed (- type-bits word-shift))
      (inst or ndescr code-header-type)
      (storew ndescr result 0 other-pointer-type)
      (storew unboxed result code-code-size-slot other-pointer-type)
      (storew null-tn result code-entry-points-slot other-pointer-type)
      (storew null-tn result code-debug-info-slot other-pointer-type))))

(define-vop (make-fdefn)
  (:args (name :scs (descriptor-reg) :to :eval))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg) :from :argument))
  (:policy :fast-safe)
  (:translate make-fdefn)
  (:generator 37
    (with-fixed-allocation (result temp fdefn-type fdefn-size)
      (inst li temp (make-fixup (extern-alien-name "undefined_tramp") :foreign))
      (storew name result fdefn-name-slot other-pointer-type)
      (storew null-tn result fdefn-function-slot other-pointer-type)
      (storew temp result fdefn-raw-addr-slot other-pointer-type))))


(define-vop (make-closure)
  (:args (function :to :save :scs (descriptor-reg)))
  (:info length dynamic-extent)
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg)))
  (:generator 10
    (let ((size (+ length closure-info-offset)))
      (pseudo-atomic ()
        (allocation result (pad-data-block size) function-pointer-type
		    :stack-p dynamic-extent
		    :temp-tn temp)
	(inst li temp (logior (ash (1- size) type-bits) closure-header-type))
	(storew temp result 0 function-pointer-type)))
    (storew function result closure-function-slot function-pointer-type)))

;;; The compiler likes to be able to directly make value cells.
;;; 
(define-vop (make-value-cell)
  (:args (value :to :save :scs (descriptor-reg any-reg)))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:results (result :scs (descriptor-reg)))
  (:generator 10
    (with-fixed-allocation
	(result temp value-cell-header-type value-cell-size))
    (storew value result value-cell-value-slot other-pointer-type)))



;;;; Automatic allocators for primitive objects.

(define-vop (make-unbound-marker)
  (:args)
  (:results (result :scs (any-reg)))
  (:generator 1
    (inst li result unbound-marker-type)))

(define-vop (fixed-alloc)
  (:args)
  (:info name words type lowtag dynamic-extent)
  (:ignore name)
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:generator 4
    (pseudo-atomic ()
      (allocation result (pad-data-block words) lowtag
		  :stack-p dynamic-extent
		  :temp-tn temp)
      (when type
	(inst li temp (logior (ash (1- words) type-bits) type))
	(storew temp result 0 lowtag)))))

(define-vop (var-alloc)
  (:args (extra :scs (any-reg)))
  (:arg-types positive-fixnum)
  (:info name words type lowtag)
  (:ignore name)
  (:results (result :scs (descriptor-reg)))
  (:temporary (:scs (any-reg)) bytes header)
  (:temporary (:scs (any-reg)) temp)
  (:generator 6
    (inst add bytes extra (* (1+ words) word-bytes))
    (inst sll header bytes (- type-bits 2))
    (inst add header header (+ (ash -2 type-bits) type))
    (inst and bytes (lognot lowtag-mask))
    (pseudo-atomic ()
      ;; Need to be careful if the lowtag and the pseudo-atomic flag
      ;; are not compatible
      (allocation result bytes lowtag :temp-tn temp)
      (storew header result 0 lowtag))))
