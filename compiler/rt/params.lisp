;;; -*- Package: RT; Log: c.log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public
;;; domain.  If you want to use this code or any part of CMU Common
;;; Lisp, please contact Scott Fahlman (Scott.Fahlman@CS.CMU.EDU)
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/rt/params.lisp,v 1.1 1991/02/18 15:08:05 chiles Exp $
;;;
;;; This file contains some parameterizations of various VM attributes for the
;;; IBM RT.  This file is separate from other stuff, so we can compile and
;;; load it earlier.
;;;
;;; Written by Rob MacLachlan
;;; Converted to MIPS by William Lott.
;;; Converted to IBM RT by William Lott and Bill Chiles.
;;;

(in-package "RT")
(use-package "C")

(export '(word-bits byte-bits word-shift word-bytes
	  halt-trap pending-interrupt-trap error-trap cerror-trap))



;;;; Compiler constants.

(eval-when (compile eval load)

(setf (backend-name *target-backend*) "RT")
(setf (backend-version *target-backend*) "IBM RT/Mach 0.0")
(setf (backend-fasl-file-type *target-backend*) "rtf")
(setf (backend-fasl-file-implementation *target-backend*)
      rt-fasl-file-implementation)
(setf (backend-fasl-file-version *target-backend*) 1)
(setf (backend-register-save-penalty *target-backend*) 3)
(setf (backend-byte-order *target-backend*) :big-endian)

) ;eval-when



;;;; Machine Architecture parameters:

(eval-when (compile load eval)

(defconstant word-bits 32
  "Number of bits per word where a word holds one lisp descriptor.")

(defconstant byte-bits 8
  "Number of bits per byte where a byte is the smallest addressable object.")

(defconstant word-shift (1- (integer-length (/ word-bits byte-bits)))
  "Number of bits to shift between word addresses and byte addresses.")

(defconstant word-bytes (/ word-bits byte-bits)
  "Number of bytes in a word.")

(defparameter target-most-positive-fixnum (1- (ash 1 29))
  "most-positive-fixnum in the target architecture.")

(defparameter target-most-negative-fixnum (ash -1 29)
  "most-negative-fixnum in the target architecture.")

(defconstant float-sign-shift 31)

;;; The exponent min/max values are wrong, I think.  The denorm, infinity, etc.
;;; info must go in there somewhere.

(defconstant single-float-bias 126)
(defconstant single-float-exponent-byte (byte 8 23))
(defconstant single-float-significand-byte (byte 23 0))
(defconstant single-float-normal-exponent-min 0)
(defconstant single-float-normal-exponent-max 255)
(defconstant single-float-hidden-bit (ash 1 23))

(defconstant double-float-bias 1022)
(defconstant double-float-exponent-byte (byte 11 20))
(defconstant double-float-significand-byte (byte 20 0))
(defconstant double-float-normal-exponent-min 0)
(defconstant double-float-normal-exponent-max #x7FF)
(defconstant double-float-hidden-bit (ash 1 20))

(defconstant single-float-digits
  (+ (byte-size single-float-significand-byte) 1))

(defconstant double-float-digits
  (+ (byte-size double-float-significand-byte) word-bits 1))

); eval-when




;;;; Description of the target address space.

;;; Where to put the different spaces.
;;; 
(defparameter target-read-only-space-start #x00100000)
(defparameter target-static-space-start    #x04000000)
(defparameter target-dynamic-space-start   #x06000000)



;;;; Other non-type constants.

(defenum (:suffix -trap :start 8)
  halt
  pending-interrupt
  error
  cerror)



;;;; Static symbols.

;;; These symbols are loaded into static space directly after NIL so
;;; that the system can compute their address by adding a constant
;;; amount to NIL.
;;;
;;; The exported static symbols are a subset of the static symbols that get
;;; exported to the C header file.  NOTE: EXPORTED-STATIC-SYMBOLS IS DEFINED
;;; AS A FUNCTION OF THE ORDERING OF THIS LIST.
;;;
(defparameter static-symbols
  '(t

    ;; Random stuff needed for initialization.
    lisp::lisp-environment-list
    lisp::lisp-command-line-list

    ;; Functions that C needs to call.
    lisp::%initial-function
    lisp::maybe-gc
    kernel::internal-error

    ;; Free Pointers
    lisp::*read-only-space-free-pointer*
    lisp::*static-space-free-pointer*
    lisp::*initial-dynamic-space-free-pointer*
    rt::*allocation-pointer*
    rt::*binding-stack-pointer*

    ;; Things needed for non-local-exit.
    lisp::*current-catch-block*
    lisp::*current-unwind-protect-block*
    *eval-stack-top*

    ;; Interrupt Handling
    lisp::*pseudo-atomic-atomic*
    lisp::*pseudo-atomic-interrupted*
    mach::*interrupts-enabled*
    mach::*interrupt-pending*
    lisp::*free-interrupt-context-index*

    ;; Static functions.
    two-arg-+ two-arg-- two-arg-* two-arg-/ two-arg-< two-arg-> two-arg-=
    two-arg-<= two-arg->= two-arg-/= %negate two-arg-and two-arg-ior two-arg-xor
    length two-arg-gcd two-arg-lcm
    ))

(defparameter exported-static-symbols
  (subseq static-symbols 0 (1+ (position 'lisp::*free-interrupt-context-index*
					 static-symbols))))



;;;; Assembler parameters:

;;; The number of bits per element in the assemblers code vector.
;;;
(defparameter *assembly-unit-length* 8)
