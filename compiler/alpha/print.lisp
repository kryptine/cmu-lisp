;;; -*- Package: ALPHA -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/alpha/print.lisp,v 1.1 1994/04/06 16:54:48 hallgren Exp $")
;;;
;;; **********************************************************************
;;;
;;; This file contains temporary printing utilities and similar noise.
;;;
;;; Written by William Lott.
;;; Converted by Sean Hallgren.

(in-package "ALPHA")


(define-vop (print)
  (:args (object :scs (descriptor-reg) :target a0))
  (:results (result :scs (descriptor-reg)))
  (:save-p t)
  (:temporary (:sc any-reg :offset cfunc-offset :target result :to (:result 0))
	      cfunc)
  (:temporary (:sc descriptor-reg :offset nl0-offset :from (:argument 0)) a0)
  (:temporary (:sc control-stack :offset nfp-save-offset) nfp-save)
  (:temporary (:scs (non-descriptor-reg)) temp)
  (:vop-var vop)
  (:generator 0
    (let ((cur-nfp (current-nfp-tn vop)))
      (move object a0)
      (when cur-nfp
	(store-stack-tn nfp-save cur-nfp))
      (inst li (make-fixup "debug_print" :foreign) cfunc)
      (inst li (make-fixup "call_into_c" :foreign) temp)
      (inst jsr lip-tn temp (make-fixup "call_into_c" :foreign))
      (when cur-nfp
	(maybe-load-stack-nfp-tn cur-nfp nfp-save temp))
      (move cfunc result))))
