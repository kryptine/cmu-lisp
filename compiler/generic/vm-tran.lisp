;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the Spice Lisp project at
;;; Carnegie-Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of Spice Lisp, please contact
;;; Scott Fahlman (FAHLMAN@CMUC). 
;;; **********************************************************************
;;;
;;; $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/generic/vm-tran.lisp,v 1.22 1991/01/13 23:37:26 ram Exp $
;;;
;;;    This file contains impelemtentation-dependent transforms.
;;;
;;; Written by Rob MacLachlan
;;;
(in-package "C")

;;; We need to define these predicates, since the TYPEP source transform picks
;;; whichever predicate was defined last when there are multiple predicates for
;;; equivalent types.
;;;
(def-source-transform short-float-p (x) `(single-float-p ,x))
(def-source-transform long-float-p (x) `(double-float-p ,x))

(def-source-transform funcallable-instance-p (x)
  `(eql (get-type ,x) vm:funcallable-instance-header-type))

(def-source-transform compiled-function-p (x)
  `(functionp ,x))

(def-source-transform char-int (x)
  `(char-code ,x))

(deftransform abs ((x) (rational))
  '(if (< x 0) (- x) x))



(macrolet ((frob (name primitive)
	     `(def-source-transform ,name (&rest foo)
		`(truly-the nil
			    (%primitive ,',primitive ,@foo)))))
  (frob %type-check-error type-check-error)
  (frob %odd-keyword-arguments-error odd-keyword-arguments-error)
  (frob %unknown-keyword-argument-error unknown-keyword-argument-error)
  (frob %argument-count-error argument-count-error))


(def-source-transform %more-arg-context (&rest foo)
  `(truly-the (values t fixnum) (%primitive more-arg-context ,@foo)))
;;;
(def-source-transform %verify-argument-count (&rest foo)
  `(%primitive verify-argument-count ,@foo))



;;; Let these pass for now.

(def-primitive-translator header-ref (obj slot)
  (warn "Someone used HEADER-REF.")
  `(%primitive data-vector-ref/simple-vector ,obj ,slot))

(def-primitive-translator header-set (obj slot value)
  (warn "Someone used HEADER-SET.")
  `(%primitive data-vector-set/simple-vector ,obj ,slot ,value))

(def-primitive-translator header-length (obj)
  (warn "Someone used HEADER-LENGTH.")
  `(%primitive vector-length ,obj))



;;;; Charater support.

;;; There are really only base-chars.
;;;
(def-source-transform characterp (obj)
  `(base-char-p ,obj))

;;; Keep this around in case someone uses it.
;;;
(def-source-transform %string-char-p (obj)
  (warn "Someone used %string-char-p.")
  `(base-char-p ,obj))




;;;; Transforms for data-vector-ref for strange array types.

(deftransform data-vector-ref ((array index)
			       (simple-array t))
  (let ((array-type (continuation-type array)))
    (unless (array-type-p array-type)
      (give-up))
    (let ((dims (array-type-dimensions array-type)))
      (when (or (atom dims) (= (length dims) 1))
	(give-up))
      (let ((el-type (array-type-element-type array-type))
	    (total-size (if (member '* dims)
			    '*
			    (reduce #'* dims))))
	`(data-vector-ref (truly-the (simple-array ,(type-specifier el-type)
						   (,total-size))
				     (%array-data-vector array))
			  index)))))

(deftransform data-vector-set ((array index new-value)
			       (simple-array t t))
  (let ((array-type (continuation-type array)))
    (unless (array-type-p array-type)
      (give-up))
    (let ((dims (array-type-dimensions array-type)))
      (when (or (atom dims) (= (length dims) 1))
	(give-up))
      (let ((el-type (array-type-element-type array-type))
	    (total-size (if (member '* dims)
			    '*
			    (reduce #'* dims))))
	`(data-vector-set (truly-the (simple-array ,(type-specifier el-type)
						   (,total-size))
				     (%array-data-vector array))
			  index
			  new-value)))))


;;; Transforms for getting at arrays of unsigned-byte n when n < 8.

#+nil
(macrolet
    ((frob (type bits)
       (let ((elements-per-word (truncate vm:word-bits bits)))
	 `(progn
	    (deftransform data-vector-ref ((vector index)
					   (,type *))
	      `(multiple-value-bind (word bit)
				    (floor index ,',elements-per-word)
		 (ldb ,(ecase vm:target-byte-order
			 (:little-endian '(byte ,bits (* bit ,bits)))
			 (:big-endian '(byte ,bits (- vm:word-bits
						      (* (1+ bit) ,bits)))))
		      (%raw-bits vector (+ word vm:vector-data-offset)))))
	    (deftransform data-vector-set ((vector index new-value)
					   (,type * *))
	      `(multiple-value-bind (word bit)
				    (floor index ,',elements-per-word)
		 (setf (ldb ,(ecase vm:target-byte-order
			       (:little-endian '(byte ,bits (* bit ,bits)))
			       (:big-endian
				'(byte ,bits (- vm:word-bits
						(* (1+ bit) ,bits)))))
			    (%raw-bits vector (+ word vm:vector-data-offset)))
		       new-value)))))))
  (frob simple-bit-vector 1)
  (frob (simple-array (unsigned-byte 2) (*)) 2)
  (frob (simple-array (unsigned-byte 4) (*)) 4))




;;;; Simple string transforms:

(defconstant vector-data-bit-offset (* vm:vector-data-offset vm:word-bits))

(deftransform subseq ((string start &optional (end nil))
		      (simple-string t &optional t))
  '(let* ((length (- (or end (length string))
		     start))
	  (result (make-string length)))
     (bit-bash-copy string
		    (+ (* start vm:byte-bits) vector-data-bit-offset)
		    result
		    vector-data-bit-offset
		    (* length vm:byte-bits))
     result))


(deftransform copy-seq ((seq) (simple-string))
  '(let* ((length (length seq))
	  (res (make-string length)))
     (bit-bash-copy seq
		    vector-data-bit-offset
		    res
		    vector-data-bit-offset
		    (* length vm:byte-bits))
     res))


(deftransform replace ((string1 string2 &key (start1 0) (start2 0)
				end1 end2)
		       (simple-string simple-string &rest t))
  '(progn
     (bit-bash-copy string2
		    (+ (* start2 vm:byte-bits) vector-data-bit-offset)
		    string1
		    (+ (* start1 vm:byte-bits) vector-data-bit-offset)
		    (* (min (- (or end1 (length string1))
			       start1)
			    (- (or end2 (length string2))
			       start2))
		       vm:byte-bits))
     string1))


(deftransform concatenate ((rtype &rest sequences)
			   (t &rest simple-string)
			   simple-string)
  (collect ((lets)
	    (forms)
	    (all-lengths)
	    (args))
    (dolist (seq sequences)
      (declare (ignore seq))
      (let ((n-seq (gensym))
	    (n-length (gensym)))
	(args n-seq)
	(lets `(,n-length (* (length ,n-seq) vm:byte-bits)))
	(all-lengths n-length)
	(forms `(bit-bash-copy ,n-seq vector-data-bit-offset
			       res start
			       ,n-length))
	(forms `(setq start (+ start ,n-length)))))
    `(lambda (rtype ,@(args))
       (declare (ignore rtype))
       (let* (,@(lets)
	      (res (make-string (truncate (+ ,@(all-lengths)) vm:byte-bits)))
	      (start vector-data-bit-offset))
	 (declare (type index start ,@(all-lengths)))
	 ,@(forms)
	 res))))


;;;; Bit vector hackery:


;;; SIMPLE-BIT-VECTOR bit-array operations are transformed to a word loop that
;;; does 32 bits at a time.
;;;
(loop for (bitfun wordfun) in 
  '((bit-and 32bit-logical-and)
    (bit-ior 32bit-logical-or)
    (bit-xor 32bit-logical-xor)
    (bit-eqv 32bit-logical-eqv)
    (bit-nand 32bit-logical-nand)
    (bit-nor 32bit-logical-nor)
    (bit-andc1 32bit-logical-andc1)
    (bit-andc2 32bit-logical-andc2)
    (bit-orc1 32bit-logical-orc1)
    (bit-orc2 32bit-logical-orc2)) do
  (deftransform bitfun
		((bit-array-1 bit-array-2 result-bit-array)
		 (simple-bit-vector simple-bit-vector simple-bit-vector) *
		 :eval-name t  :node node  :policy (>= speed space))
    `(progn
       ,@(unless (policy node (zerop safety))
	   '((unless (= (length bit-array-1) (length bit-array-2)
			(length result-bit-array))
	       (error "Argument and/or result bit arrays not the same length:~
		       ~%  ~S~%  ~S  ~%  ~S"
		      bit-array-1 bit-array-2 result-bit-array))))
       (do ((index vm:vector-data-offset (1+ index))
	    (end (+ vm:vector-data-offset
		    (truncate (the index
				   (+ (length bit-array-1)
				      vm:word-bits -1))
			      vm:word-bits))))
	   ((= index end) result-bit-array)
	 (declare (optimize (speed 3) (safety 0))
		  (type index index end))
	 (setf (%raw-bits result-bit-array index)
	       (,wordfun (%raw-bits bit-array-1 index)
			 (%raw-bits bit-array-2 index)))))))

(deftransform bit-not
	      ((bit-array-1 result-bit-array)
	       (simple-bit-vector simple-bit-vector) *
	       :node node  :policy (>= speed space))
  `(progn
     ,@(unless (policy node (zerop safety))
	 '((unless (= (length bit-array-1) (length bit-array-2)
		      (length result-bit-array))
	     (error "Argument and result bit arrays not the same length:~
	     	     ~%  ~S~%  ~S"
		    bit-array-1 result-bit-array))))
     (do ((index vm:vector-data-offset (1+ index))
	  (end (+ vm:vector-data-offset
		  (truncate (the index
				 (+ (length bit-array-1)
				    vm:word-bits -1))
			    vm:word-bits))))
	 ((= index end) result-bit-array)
       (declare (optimize (speed 3) (safety 0))
		(type index index end))
       (setf (%raw-bits result-bit-array index)
	     (32bit-logical-not (%raw-bits bit-array-1 index))))))


;;;; Primitive translator for byte-blt


(def-primitive-translator byte-blt (src src-start dst dst-start dst-end)
  `(let ((src ,src)
	 (src-start (* ,src-start vm:byte-bits))
	 (dst ,dst)
	 (dst-start (* ,dst-start vm:byte-bits))
	 (dst-end (* ,dst-end vm:byte-bits)))
     (let ((length (- dst-end dst-start)))
       (etypecase src
	 (system-area-pointer
	  (etypecase dst
	    (system-area-pointer
	     (system-area-copy src src-start dst dst-start length))
	    ((simple-unboxed-array (*))
	     (copy-from-system-area src src-start
				    dst (+ dst-start vector-data-bit-offset)
				    length))))
	 ((simple-unboxed-array (*))
	  (etypecase dst
	    (system-area-pointer
	     (copy-to-system-area src (+ src-start vector-data-bit-offset)
				  dst dst-start
				  length))
	    ((simple-unboxed-array (*))
	     (bit-bash-copy src (+ src-start vector-data-bit-offset)
			    dst (+ dst-start vector-data-bit-offset)
			    length))))))))
