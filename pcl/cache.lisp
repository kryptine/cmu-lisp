;;;-*-Mode:LISP; Package:(PCL LISP 1000); Base:10; Syntax:Common-lisp -*-
;;;
;;; *************************************************************************
;;; Copyright (c) 1985, 1986, 1987, 1988, 1989, 1990 Xerox Corporation.
;;; All rights reserved.
;;;
;;; Use and copying of this software and preparation of derivative works
;;; based upon this software are permitted.  Any distribution of this
;;; software or derivative works must comply with all applicable United
;;; States export control laws.
;;; 
;;; This software is made available AS IS, and Xerox Corporation makes no
;;; warranty about the software, its performance or its conformity to any
;;; specification.
;;; 
;;; Any person obtaining a copy of this software is requested to send their
;;; name and post office or electronic mail address to:
;;;   CommonLoops Coordinator
;;;   Xerox PARC
;;;   3333 Coyote Hill Rd.
;;;   Palo Alto, CA 94304
;;; (or send Arpanet mail to CommonLoops-Coordinator.pa@Xerox.arpa)
;;;
;;; Suggestions, comments and requests for improvements are also welcome.
;;; *************************************************************************
;;;

(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/pcl/cache.lisp,v 1.23 2002/12/18 00:57:04 pmai Exp $")
;;;
;;; The basics of the PCL wrapper cache mechanism.
;;;

(in-package :pcl)
;;;
;;; The caching algorithm implemented:
;;;
;;; << put a paper here >>
;;;
;;; For now, understand that as far as most of this code goes, a cache has
;;; two important properties.  The first is the number of wrappers used as
;;; keys in each cache line.  Throughout this code, this value is always
;;; called NKEYS.  The second is whether or not the cache lines of a cache
;;; store a value.  Throughout this code, this always called VALUEP.
;;;
;;; Depending on these values, there are three kinds of caches.
;;;
;;; NKEYS = 1, VALUEP = NIL
;;;
;;; In this kind of cache, each line is 1 word long.  No cache locking is
;;; needed since all read's in the cache are a single value.  Nevertheless
;;; line 0 (location 0) is reserved, to ensure that invalid wrappers will
;;; not get a first probe hit.
;;;
;;; To keep the code simpler, a cache lock count does appear in location 0
;;; of these caches, that count is incremented whenever data is written to
;;; the cache.  But, the actual lookup code (see make-dlap) doesn't need to
;;; do locking when reading the cache.
;;; 
;;;
;;; NKEYS = 1, VALUEP = T
;;;
;;; In this kind of cache, each line is 2 words long.  Cache locking must
;;; be done to ensure the synchronization of cache reads.  Line 0 of the
;;; cache (location 0) is reserved for the cache lock count.  Location 1
;;; of the cache is unused (in effect wasted).
;;; 
;;; NKEYS > 1
;;;
;;; In this kind of cache, the 0 word of the cache holds the lock count.
;;; The 1 word of the cache is line 0.  Line 0 of these caches is not
;;; reserved.
;;;
;;; This is done because in this sort of cache, the overhead of doing the
;;; cache probe is high enough that the 1+ required to offset the location
;;; is not a significant cost.  In addition, because of the larger line
;;; sizes, the space that would be wasted by reserving line 0 to hold the
;;; lock count is more significant.
;;;

;;;
;;; Caches
;;;
;;; A cache is essentially just a vector.  The use of the individual `words'
;;; in the vector depends on particular properties of the cache as described
;;; above.
;;;
;;; This defines an abstraction for caches in terms of their most obvious
;;; implementation as simple vectors.  But, please notice that part of the
;;; implementation of this abstraction, is the function lap-out-cache-ref.
;;; This means that most port-specific modifications to the implementation
;;; of caches will require corresponding port-specific modifications to the
;;; lap code assembler.
;;;
(defmacro cache-vector-ref (cache-vector location)
  `(svref (the simple-vector ,cache-vector)
          (ext:truly-the fixnum ,location)))

(defmacro cache-vector-size (cache-vector)
  `(array-dimension (the simple-vector ,cache-vector) 0))

(defun allocate-cache-vector (size)
  (make-array size :adjustable nil))

(defmacro cache-vector-lock-count (cache-vector)
  `(cache-vector-ref ,cache-vector 0))

(defun flush-cache-vector-internal (cache-vector)
  (with-pcl-lock
    (fill (the simple-vector cache-vector) nil)
    (setf (cache-vector-lock-count cache-vector) 0))
  cache-vector)

(defmacro modify-cache (cache-vector &body body)
  `(with-pcl-lock
     (multiple-value-prog1
       (progn ,@body)
       (let ((old-count (cache-vector-lock-count ,cache-vector)))
	 (declare (fixnum old-count))
	 (setf (cache-vector-lock-count ,cache-vector)
	       (if (= old-count most-positive-fixnum)
		   1 (the fixnum (1+ old-count))))))))

(deftype field-type ()
  '(integer 0    ;#.(position 'number wrapper-layout)
            7))  ;#.(position 'number wrapper-layout :from-end t)

(eval-when (:compile-toplevel :load-toplevel :execute)
(defun power-of-two-ceiling (x)
  (declare (fixnum x))
  ;;(expt 2 (ceiling (log x 2)))
  (the fixnum (ash 1 (integer-length (1- x)))))

(defconstant *nkeys-limit* 256)
)

(defstruct (cache
	     (:print-function print-cache)
	     (:constructor make-cache ())
	     (:copier copy-cache-internal))
  (owner nil)
  (nkeys 1 :type (integer 1 #.*nkeys-limit*))
  (valuep nil :type (member nil t))
  (nlines 0 :type fixnum)
  (field 0 :type field-type)
  (limit-fn #'default-limit-fn :type function)
  (mask 0 :type fixnum)
  (size 0 :type fixnum)
  (line-size 1 :type (integer 1 #.(power-of-two-ceiling (1+ *nkeys-limit*))))
  (max-location 0 :type fixnum)
  (vector #() :type simple-vector)
  (overflow nil :type list))

(declaim (ext:freeze-type cache))

(defun print-cache (cache stream depth)
  (declare (ignore depth))
  (printing-random-thing (cache stream)
    (format stream "cache ~D ~S ~D" 
	    (cache-nkeys cache) (cache-valuep cache) (cache-nlines cache))))

(defmacro cache-lock-count (cache)
  `(cache-vector-lock-count (cache-vector ,cache)))


;;;
;;; Return a cache that has had flush-cache-vector-internal called on it.  This
;;; returns a cache of exactly the size requested, it won't ever return a
;;; larger cache.
;;; 
(defun get-cache-vector (size)
  (flush-cache-vector-internal (make-array size)))


;;;
;;; Wrapper cache numbers
;;; 

;;;
;;; The constant WRAPPER-CACHE-NUMBER-ADDS-OK controls the number of non-zero
;;; bits wrapper cache numbers will have.
;;;
;;; The value of this constant is the number of wrapper cache numbers which
;;; can be added and still be certain the result will be a fixnum.  This is
;;; used by all the code that computes primary cache locations from multiple
;;; wrappers.
;;;
;;; The value of this constant is used to derive the next two which are the
;;; forms of this constant which it is more convenient for the runtime code
;;; to use.
;;; 
(progn
  (defconstant wrapper-cache-number-length
    (integer-length kernel:layout-hash-max))
  
  (defconstant wrapper-cache-number-mask kernel:layout-hash-max)
  
  (defconstant wrapper-cache-number-adds-ok
    (truncate most-positive-fixnum kernel:layout-hash-max)))


;;;
;;; wrappers themselves
;;;
;;; This caching algorithm requires that wrappers have more than one wrapper
;;; cache number.  You should think of these multiple numbers as being in
;;; columns.  That is, for a given cache, the same column of wrapper cache
;;; numbers will be used.
;;;
;;; If at some point the cache distribution of a cache gets bad, the cache
;;; can be rehashed by switching to a different column.
;;;
;;; The columns are referred to by field number which is that number which,
;;; when used as a second argument to wrapper-ref, will return that column
;;; of wrapper cache number.
;;;
;;; This code is written to allow flexibility as to how many wrapper cache
;;; numbers will be in each wrapper, and where they will be located.  It is
;;; also set up to allow port specific modifications to `pack' the wrapper
;;; cache numbers on machines where the addressing modes make that a good
;;; idea.
;;; 

; In CMUCL we want to do type checking as early as possible; structures help this.

(eval-when (:compile-toplevel :load-toplevel :execute)

(defconstant wrapper-cache-number-vector-length
  kernel:layout-hash-length)

(defconstant wrapper-layout (make-list wrapper-cache-number-vector-length
				       :initial-element 'number))
)


(progn

(unless (boundp '*the-class-t*) (setq *the-class-t* nil))

;;; Note that for CMU, the WRAPPER of a built-in or structure class will be
;;; some other kind of KERNEL:LAYOUT, but this shouldn't matter, since the only
;;; two slots that WRAPPER adds are meaningless in those cases.
;;;

(defstruct (wrapper
	    (:include kernel:layout)
	    (:conc-name %wrapper-)
	    (:print-function print-wrapper)
	    (:constructor make-wrapper-internal))
  (instance-slots-layout nil :type list)
  (class-slots nil :type list))
(declaim (ext:freeze-type wrapper))

(defmacro wrapper-class (wrapper)
  `(kernel:class-pcl-class (kernel:layout-class ,wrapper)))
(defmacro wrapper-no-of-instance-slots (wrapper)
  `(kernel:layout-length ,wrapper))

(defmacro wrapper-instance-slots-layout (wrapper)
  `(%wrapper-instance-slots-layout ,wrapper))
(defmacro wrapper-class-slots (wrapper)
  `(%wrapper-class-slots ,wrapper))
(defmacro wrapper-cache-number-vector (x) x))

;;; BOOT-MAKE-WRAPPER  --  Interface
;;;
;;;    Called in BRAID when we are making wrappers for classes whose slots are
;;; not initialized yet, and which may be built-in classes.  We pass in the
;;; class name in addition to the class.
;;;
(defun boot-make-wrapper (length name &optional class)
  (let ((found (lisp:find-class name nil)))
    (cond
     (found
      (unless (kernel:class-pcl-class found)
	(setf (kernel:class-pcl-class found) class))
      (assert (eq (kernel:class-pcl-class found) class))
      (let ((layout (kernel:class-layout found)))
	(assert layout)
	layout))
     (t
      (kernel:initialize-layout-hash
       (make-wrapper-internal
	:length length
	:class (kernel:make-standard-class :name name :pcl-class class)))))))


;;; The following variable may be set to a standard-class that has
;;; already been created by the lisp code and which is to be redefined
;;; by PCL. This allows standard-classes to be defined and used for
;;; type testing and dispatch before PCL is loaded.

(defvar *pcl-class-boot* nil)

;;; MAKE-WRAPPER  --  Interface
;;;
;;;    In CMU CL, the layouts (a.k.a wrappers) for built-in and structure
;;; classes already exist when PCL is initialized, so we don't necessarily
;;; always make a wrapper.  Also, we help maintain the mapping between
;;; lisp:class and pcl::class objects.
;;;
(defun make-wrapper (length class)
  (cond
   ((typep class 'std-class)
    (kernel:initialize-layout-hash
     (make-wrapper-internal
      :length length
      :class
      (let ((owrap (class-wrapper class)))
	(cond (owrap
	       (kernel:layout-class owrap))
	      ((*subtypep (class-of class)
			  *the-class-standard-class*)
	       (cond ((and *pcl-class-boot*
			   (eq (slot-value class 'name) *pcl-class-boot*))
		      (let ((found (lisp:find-class (slot-value class 'name))))
			(unless (kernel:class-pcl-class found)
			  (setf (kernel:class-pcl-class found) class))
			(assert (eq (kernel:class-pcl-class found) class))
			found))
		     (t
		      (kernel:make-standard-class :pcl-class class))))
	      (t
	       (kernel:make-random-pcl-class :pcl-class class)))))))
   (t
    (let* ((found (lisp:find-class (slot-value class 'name)))
	   (layout (kernel:class-layout found)))
      (unless (kernel:class-pcl-class found)
	(setf (kernel:class-pcl-class found) class))
      (assert (eq (kernel:class-pcl-class found) class))
      (assert layout)
      layout))))

(defun print-wrapper (wrapper stream depth)
  (declare (ignore depth))
  (printing-random-thing (wrapper stream)
    (format stream "Wrapper ~S" (wrapper-class wrapper))))

(defmacro first-wrapper-cache-number-index ()
  0)

(defmacro next-wrapper-cache-number-index (field-number)
  `(and (< ,field-number #.(1- wrapper-cache-number-vector-length))
        (1+ ,field-number)))

(defmacro cache-number-vector-ref (cnv n)
  `(wrapper-cache-number-vector-ref ,cnv ,n))

(defmacro wrapper-cache-number-vector-ref (wrapper n)
  `(kernel:layout-hash ,wrapper ,n))

(defmacro class-no-of-instance-slots (class)
  `(wrapper-no-of-instance-slots (class-wrapper ,class)))

(defmacro wrapper-class* (wrapper)
  `(let ((wrapper ,wrapper))
     (or (wrapper-class wrapper)
         (find-structure-class
	  (lisp:class-name (kernel:layout-class wrapper))))))

;;;
;;; The wrapper cache machinery provides general mechanism for trapping on
;;; the next access to any instance of a given class.  This mechanism is
;;; used to implement the updating of instances when the class is redefined
;;; (make-instances-obsolete).  The same mechanism is also used to update
;;; generic function caches when there is a change to the supers of a class.
;;;
;;; Basically, a given wrapper can be valid or invalid.  If it is invalid,
;;; it means that any attempt to do a wrapper cache lookup using the wrapper
;;; should trap.  Also, methods on slot-value-using-class check the wrapper
;;; validity as well.  This is done by calling check-wrapper-validity.
;;; 

(declaim (inline invalid-wrapper-p))

(defun invalid-wrapper-p (wrapper)
  (not (null (kernel:layout-invalid wrapper))))

(defvar *previous-nwrappers* (make-hash-table))

(defun invalidate-wrapper (owrapper state nwrapper)
  (assert (member state '(:flush :obsolete) :test #'eq))
  (let ((new-previous ()))
    ;;
    ;; First off, a previous call to invalidate-wrapper may have recorded
    ;; owrapper as an nwrapper to update to.  Since owrapper is about to
    ;; be invalid, it no longer makes sense to update to it.
    ;;
    ;; We go back and change the previously invalidated wrappers so that
    ;; they will now update directly to nwrapper.  This corresponds to a
    ;; kind of transitivity of wrapper updates.
    ;; 
    (dolist (previous (gethash owrapper *previous-nwrappers*))
      (when (eq state :obsolete)
	(setf (first previous) :obsolete))
      (setf (second previous) nwrapper)
      (push previous new-previous))

    (loop for i below kernel:layout-hash-length do
	    (setf (kernel:layout-hash owrapper i) 0))
    
    (let ((new-state (list state nwrapper)))
      (setf (kernel:layout-invalid owrapper) new-state)
      (push new-state new-previous)
      (setf (gethash owrapper *previous-nwrappers*) ()
	    (gethash nwrapper *previous-nwrappers*) new-previous))))

(defun check-wrapper-validity (instance)
  (let* ((owrapper (wrapper-of instance))
	 (state (kernel:layout-invalid owrapper)))
    (if (null state)
	owrapper
	(ecase (first state)
	  (:flush
	   (flush-cache-trap owrapper (second state) instance))
	  (:obsolete
	   (obsolete-instance-trap owrapper (second state) instance))))))

(declaim (inline check-obsolete-instance))

(defun check-obsolete-instance (instance)
  (when (invalid-wrapper-p (kernel:layout-of instance))
    (check-wrapper-validity instance)))



(defun get-cache (nkeys valuep limit-fn nlines)
  (let ((cache (make-cache)))
    (declare (type cache cache))
    (multiple-value-bind (cache-mask actual-size line-size nlines)
	(compute-cache-parameters nkeys valuep nlines)
      (setf (cache-nkeys cache) nkeys
	    (cache-valuep cache) valuep
	    (cache-nlines cache) nlines
	    (cache-field cache) (first-wrapper-cache-number-index)
	    (cache-limit-fn cache) limit-fn
	    (cache-mask cache) cache-mask
	    (cache-size cache) actual-size
	    (cache-line-size cache) line-size
	    (cache-max-location cache) (let ((line (1- nlines)))
					 (if (= nkeys 1)
					     (* line line-size)
					     (1+ (* line line-size))))
	    (cache-vector cache) (get-cache-vector actual-size)
	    (cache-overflow cache) nil)
      cache)))

(defun get-cache-from-cache (old-cache new-nlines 
			     &optional (new-field (first-wrapper-cache-number-index)))
  (let ((nkeys (cache-nkeys old-cache))
	(valuep (cache-valuep old-cache))
	(cache (make-cache)))
    (declare (type cache cache))
    (multiple-value-bind (cache-mask actual-size line-size nlines)
	(if (= new-nlines (cache-nlines old-cache))
	    (values (cache-mask old-cache) (cache-size old-cache) 
		    (cache-line-size old-cache) (cache-nlines old-cache))
	    (compute-cache-parameters nkeys valuep new-nlines))
      (setf (cache-owner cache) (cache-owner old-cache)
	    (cache-nkeys cache) nkeys
	    (cache-valuep cache) valuep
	    (cache-nlines cache) nlines
	    (cache-field cache) new-field
	    (cache-limit-fn cache) (cache-limit-fn old-cache)
	    (cache-mask cache) cache-mask
	    (cache-size cache) actual-size
	    (cache-line-size cache) line-size
	    (cache-max-location cache) (let ((line (1- nlines)))
					 (if (= nkeys 1)
					     (* line line-size)
					     (1+ (* line line-size))))
	    (cache-vector cache) (get-cache-vector actual-size)
	    (cache-overflow cache) nil)
      cache)))

(defun copy-cache (old-cache)
  (let* ((new-cache (copy-cache-internal old-cache))
	 (size (cache-size old-cache))
	 (old-vector (cache-vector old-cache))
	 (new-vector (get-cache-vector size)))
    (declare (simple-vector old-vector new-vector))
    (dotimes (i size)
      (declare (fixnum i))
      (setf (svref new-vector i) (svref old-vector i)))
    (setf (cache-vector new-cache) new-vector)
    new-cache))

(defun compute-line-size (x)
  (power-of-two-ceiling x))

(defun compute-cache-parameters (nkeys valuep nlines-or-cache-vector)
  ;;(declare (values cache-mask actual-size line-size nlines))
  (declare (fixnum nkeys))
  (if (= nkeys 1)
      (let* ((line-size (if valuep 2 1))
	     (cache-size (if (typep nlines-or-cache-vector 'fixnum)
			     (the fixnum 
				  (* line-size
				     (the fixnum 
					  (power-of-two-ceiling 
					    nlines-or-cache-vector))))
			     (cache-vector-size nlines-or-cache-vector))))
	(declare (fixnum line-size cache-size))
	(values (logxor (the fixnum (1- cache-size)) (the fixnum (1- line-size)))
		cache-size
		line-size
		(the (values fixnum t) (floor cache-size line-size))))
      (let* ((line-size (power-of-two-ceiling (if valuep (1+ nkeys) nkeys)))
	     (cache-size (if (typep nlines-or-cache-vector 'fixnum)
			     (the fixnum
				  (* line-size
				     (the fixnum
					  (power-of-two-ceiling 
					    nlines-or-cache-vector))))
			     (1- (cache-vector-size nlines-or-cache-vector)))))
	(declare (fixnum line-size cache-size))
	(values (logxor (the fixnum (1- cache-size)) (the fixnum (1- line-size)))
		(the fixnum (1+ cache-size))
		line-size
		(the (values fixnum t) (floor cache-size line-size))))))



;;;
;;; The various implementations of computing a primary cache location from
;;; wrappers.  Because some implementations of this must run fast there are
;;; several implementations of the same algorithm.
;;;
;;; The algorithm is:
;;;
;;;  SUM       over the wrapper cache numbers,
;;;  ENSURING  that the result is a fixnum
;;;  MASK      the result against the mask argument.
;;;
;;;

;;;
;;; COMPUTE-PRIMARY-CACHE-LOCATION
;;; 
;;; The basic functional version.  This is used by the cache miss code to
;;; compute the primary location of an entry.  
;;;
(defun compute-primary-cache-location (field mask wrappers)
  (declare (type field-type field) (fixnum mask))
  (if (not (listp wrappers))
      (logand mask (the fixnum (wrapper-cache-number-vector-ref wrappers field)))
      (let ((location 0) (i 0))
	(declare (fixnum location i))
	(dolist (wrapper wrappers)
	  ;;
	  ;; First add the cache number of this wrapper to location.
	  ;; 
	  (let ((wrapper-cache-number (wrapper-cache-number-vector-ref wrapper field)))
	    (declare (fixnum wrapper-cache-number))
	    (if (zerop wrapper-cache-number)
		(return-from compute-primary-cache-location 0)
		(setq location (the fixnum (+ location wrapper-cache-number)))))
	  ;;
	  ;; Then, if we are working with lots of wrappers, deal with
	  ;; the wrapper-cache-number-mask stuff.
	  ;; 
	  (when (and (not (zerop i))
		     (zerop (mod i wrapper-cache-number-adds-ok)))
	    (setq location
		  (logand location wrapper-cache-number-mask)))
	  (incf i))
	(the fixnum (1+ (logand mask location))))))

;;;
;;; COMPUTE-PRIMARY-CACHE-LOCATION-FROM-LOCATION
;;;
;;; This version is called on a cache line.  It fetches the wrappers from
;;; the cache line and determines the primary location.  Various parts of
;;; the cache filling code call this to determine whether it is appropriate
;;; to displace a given cache entry.
;;; 
;;; If this comes across a wrapper whose cache-no is 0, it returns the symbol
;;; invalid to suggest to its caller that it would be provident to blow away
;;; the cache line in question.
;;;
(defun compute-primary-cache-location-from-location (to-cache from-location 
						     &optional (from-cache to-cache))
  (declare (type cache to-cache from-cache) (fixnum from-location))
  (let ((result 0)
	(cache-vector (cache-vector from-cache))
	(field (cache-field to-cache))
	(mask (cache-mask to-cache))
	(nkeys (cache-nkeys to-cache)))
    (declare (type field-type field) (fixnum result mask nkeys)
	     (simple-vector cache-vector))
    (dotimes (i nkeys)
      (declare (fixnum i))
      (let* ((wrapper (cache-vector-ref cache-vector (+ i from-location)))
	     (wcn (wrapper-cache-number-vector-ref wrapper field)))
	(declare (fixnum wcn))
	(setq result (+ result wcn)))
      (when (and (not (zerop i))
		 (zerop (mod i wrapper-cache-number-adds-ok)))
	(setq result (logand result wrapper-cache-number-mask))))    
    (if (= nkeys 1)
	(logand mask result)
	(the fixnum (1+ (logand mask result))))))


;;;
;;;  NIL              means nothing so far, no actual arg info has NILs
;;;                   in the metatype
;;;  CLASS            seen all sorts of metaclasses
;;;                   (specifically, more than one of the next 4 values)
;;;  T                means everything so far is the class T
;;;  STANDARD-CLASS   seen only standard classes
;;;  BUILT-IN-CLASS   seen only built in classes
;;;  STRUCTURE-CLASS  seen only structure classes
;;;  
(defun raise-metatype (metatype new-specializer)
  (let ((slot      (find-class 'slot-class))
	(std       (find-class 'std-class))
	(standard  (find-class 'standard-class))
	(fsc       (find-class 'funcallable-standard-class))
	(structure (find-class 'structure-class))
	(built-in  (find-class 'built-in-class)))
    (flet ((specializer->metatype (x)
	     (let ((meta-specializer 
		     (if (eq *boot-state* 'complete)
			 (class-of (specializer-class x))
			 (class-of x))))
	       (cond ((eq x *the-class-t*) t)
		     ((*subtypep meta-specializer std)  'standard-instance)
		     ((*subtypep meta-specializer standard)  'standard-instance)
		     ((*subtypep meta-specializer fsc)       'standard-instance)
		     ((*subtypep meta-specializer structure) 'structure-instance)
		     ((*subtypep meta-specializer built-in)  'built-in-instance)
		     ((*subtypep meta-specializer slot)      'slot-instance)
		     (t (error "PCL can not handle the specializer ~S (meta-specializer ~S)."
			       new-specializer meta-specializer))))))
      ;;
      ;; We implement the following table.  The notation is
      ;; that X and Y are distinct meta specializer names.
      ;; 
      ;;   NIL    <anything>    ===>  <anything>
      ;;    X      X            ===>      X
      ;;    X      Y            ===>    CLASS
      ;;    
      (let ((new-metatype (specializer->metatype new-specializer)))
	(cond ((eq new-metatype 'slot-instance) 'class)
	      ((null metatype) new-metatype)
	      ((eq metatype new-metatype) new-metatype)
	      (t 'class))))))

(defmacro with-dfun-wrappers ((args metatypes)
			      (dfun-wrappers invalid-wrapper-p 
					     &optional wrappers classes types)
			      invalid-arguments-form
			      &body body)
  `(let* ((args-tail ,args) (,invalid-wrapper-p nil) (invalid-arguments-p nil)
	  (,dfun-wrappers nil) (dfun-wrappers-tail nil)
	  ,@(when wrappers
	      `((wrappers-rev nil) (types-rev nil) (classes-rev nil))))
     (dolist (mt ,metatypes)
       (unless args-tail
	 (setq invalid-arguments-p t)
	 (return nil))
       (let* ((arg (pop args-tail))
	      (wrapper nil)
	      ,@(when wrappers
		  `((class *the-class-t*)
		    (type t))))
	 (unless (eq mt t)
	   (setq wrapper (wrapper-of arg))
	   (when (invalid-wrapper-p wrapper)
	     (setq ,invalid-wrapper-p t)
	     (setq wrapper (check-wrapper-validity arg)))
	   (cond ((null ,dfun-wrappers)
		  (setq ,dfun-wrappers wrapper))
		 ((not (consp ,dfun-wrappers))
		  (setq dfun-wrappers-tail (list wrapper))
		  (setq ,dfun-wrappers (cons ,dfun-wrappers dfun-wrappers-tail)))
		 (t
		  (let ((new-dfun-wrappers-tail (list wrapper)))
		    (setf (cdr dfun-wrappers-tail) new-dfun-wrappers-tail)
		    (setf dfun-wrappers-tail new-dfun-wrappers-tail))))
	   ,@(when wrappers
	       `((setq class (wrapper-class* wrapper))
		 (setq type `(class-eq ,class)))))
	 ,@(when wrappers
	     `((push wrapper wrappers-rev)
	       (push class classes-rev)
	       (push type types-rev)))))
     (if invalid-arguments-p
	 ,invalid-arguments-form
	 (let* (,@(when wrappers
		    `((,wrappers (nreverse wrappers-rev))
		      (,classes (nreverse classes-rev))
		      (,types (mapcar (lambda (class)
					`(class-eq ,class))
			              ,classes)))))
	   ,@body))))


;;;
;;; Some support stuff for getting a hold of symbols that we need when
;;; building the discriminator codes.  Its ok for these to be interned
;;; symbols because we don't capture any user code in the scope in which
;;; these symbols are bound.
;;; 

(defvar *dfun-arg-symbols* '(.ARG0. .ARG1. .ARG2. .ARG3.))

(defun dfun-arg-symbol (arg-number)
  (or (nth arg-number (the list *dfun-arg-symbols*))
      (intern (format nil ".ARG~A." arg-number) *the-pcl-package*)))

(defun dfun-arg-symbol-list (metatypes)
  (loop for i from 0 and s in metatypes
        collect (dfun-arg-symbol i)))

(defvar *slot-vector-symbols* '(.SLOTS0. .SLOTS1. .SLOTS2. .SLOTS3.))

(defun slot-vector-symbol (arg-number)
  (or (nth arg-number (the list *slot-vector-symbols*))
      (intern (format nil ".SLOTS~A." arg-number) *the-pcl-package*)))

(defun make-dfun-lambda-list (metatypes applyp)
  (if applyp
      (nconc (dfun-arg-symbol-list metatypes) (list '&rest '.dfun-rest-arg.))
      (dfun-arg-symbol-list metatypes)))

(defun make-dlap-lambda-list (metatypes applyp)
  (if applyp
      (nconc (dfun-arg-symbol-list metatypes) (list '&rest))
      (dfun-arg-symbol-list metatypes)))

(defun make-emf-call (metatypes applyp fn-variable &optional emf-type)
  (let ((required (dfun-arg-symbol-list metatypes)))
    `(,(if (eq emf-type 'fast-method-call)
	   'invoke-effective-method-function-fast
	   'invoke-effective-method-function)
      ,fn-variable ,applyp ,@required ,@(when applyp `(.dfun-rest-arg.)))))

(defun make-fast-method-call-lambda-list (metatypes applyp)
  (let ((required (dfun-arg-symbol-list metatypes)))
    (if applyp
	`(.pv-cell. .next-method-call. ,@required .dfun-rest-arg.)
	`(.pv-cell. .next-method-call. ,@required))))


(defmacro with-local-cache-functions ((cache) &body body)
  `(let ((.cache. ,cache))
     (declare (type cache .cache.))
     (labels ((cache () .cache.)
	      (nkeys () (cache-nkeys .cache.))
	      (line-size () (cache-line-size .cache.))
	      (vector () (cache-vector .cache.))
	      (valuep () (cache-valuep .cache.))
	      (nlines () (cache-nlines .cache.))
	      (max-location () (cache-max-location .cache.))
	      (limit-fn () (cache-limit-fn .cache.))
	      (size () (cache-size .cache.))
	      (mask () (cache-mask .cache.))
	      (field () (cache-field .cache.))
	      (overflow () (cache-overflow .cache.))
	      ;;
	      ;; Return T IFF this cache location is reserved.  The
	      ;; only time this is true is for line number 0 of an
	      ;; nkeys=1 cache.
	      ;;
	      (line-reserved-p (line)
		(declare (fixnum line))
		(and (= (nkeys) 1)
		     (= line 0)))
	      ;;
	      (location-reserved-p (location)
		(declare (fixnum location))
		(and (= (nkeys) 1)
		     (= location 0)))
	      ;;
	      ;; Given a line number, return the cache location.
	      ;; This is the value that is the second argument to
	      ;; cache-vector-ref.  Basically, this deals with the
	      ;; offset of nkeys>1 caches and multiplies by line
	      ;; size.
	      ;; 	  
	      (line-location (line)
		(declare (fixnum line))
		(when (line-reserved-p line)
		  (error "line is reserved"))
		(if (= (nkeys) 1)
		    (the fixnum (* line (line-size)))
		    (the fixnum (1+ (the fixnum (* line (line-size)))))))
	      ;;
	      ;; Given a cache location, return the line.  This is
	      ;; the inverse of LINE-LOCATION.
	      ;; 	  
	      (location-line (location)
		(declare (fixnum location))
		(if (= (nkeys) 1)
		    (floor location (line-size))
		    (floor (the fixnum (1- location)) (line-size))))
	      ;;
	      ;; Given a line number, return the wrappers stored at
	      ;; that line.  As usual, if nkeys=1, this returns a
	      ;; single value.  Only when nkeys>1 does it return a
	      ;; list.  An error is signalled if the line is
	      ;; reserved.
	      ;;
	      (line-wrappers (line)
		(declare (fixnum line))
		(when (line-reserved-p line) (error "Line is reserved."))
		(location-wrappers (line-location line)))
	      ;;
	      (location-wrappers (location) ; avoid multiplies caused by line-location
		(declare (fixnum location))
		(if (= (nkeys) 1)
		    (cache-vector-ref (vector) location)
		    (let ((list (make-list (nkeys)))
			  (vector (vector)))
		      (declare (simple-vector vector))
		      (dotimes (i (nkeys) list)
			(declare (fixnum i))
			(setf (nth i list) (cache-vector-ref vector (+ location i)))))))
	      ;;
	      ;; Given a line number, return true IFF the line's
	      ;; wrappers are the same as wrappers.
	      ;;
	      (line-matches-wrappers-p (line wrappers)
		(declare (fixnum line))
		(and (not (line-reserved-p line))
		     (location-matches-wrappers-p (line-location line) wrappers)))
	      ;;
	      (location-matches-wrappers-p (loc wrappers) ; must not be reserved
		(declare (fixnum loc))
		(let ((cache-vector (vector)))
		  (declare (simple-vector cache-vector))
		  (if (= (nkeys) 1)
		      (eq wrappers (cache-vector-ref cache-vector loc))
		      (dotimes (i (nkeys) t)
			(declare (fixnum i))
			(unless (eq (pop wrappers)
				    (cache-vector-ref cache-vector (+ loc i)))
			  (return nil))))))
	      ;;
	      ;; Given a line number, return the value stored at that line.
	      ;; If valuep is NIL, this returns NIL.  As with line-wrappers,
	      ;; an error is signalled if the line is reserved.
	      ;; 
	      (line-value (line)
		(declare (fixnum line))
		(when (line-reserved-p line) (error "Line is reserved."))
		(location-value (line-location line)))
	      ;;
	      (location-value (loc)
		(declare (fixnum loc))
		(and (valuep)
		     (cache-vector-ref (vector) (+ loc (nkeys)))))
	      ;;
	      ;; Given a line number, return true IFF that line has data in
	      ;; it.  The state of the wrappers stored in the line is not
	      ;; checked.  An error is signalled if line is reserved.
	      (line-full-p (line)
		(when (line-reserved-p line) (error "Line is reserved."))
		(not (null (cache-vector-ref (vector) (line-location line)))))
	      ;;
	      ;; Given a line number, return true IFF the line is full and
	      ;; there are no invalid wrappers in the line, and the line's
	      ;; wrappers are different from wrappers.
	      ;; An error is signalled if the line is reserved.
	      ;;
	      (line-valid-p (line wrappers)
		(declare (fixnum line))
		(when (line-reserved-p line) (error "Line is reserved."))
		(location-valid-p (line-location line) wrappers))
	      ;;
	      (location-valid-p (loc wrappers)
		(declare (fixnum loc))
		(let ((cache-vector (vector))
		      (wrappers-mismatch-p (null wrappers)))
		  (declare (simple-vector cache-vector))
		  (dotimes (i (nkeys) wrappers-mismatch-p)
		    (declare (fixnum i))
		    (let ((wrapper (cache-vector-ref cache-vector (+ loc i))))
		      (when (or (null wrapper)
				(invalid-wrapper-p wrapper))
			(return nil))
		      (unless (and wrappers
				   (eq wrapper
				       (if (consp wrappers) (pop wrappers) wrappers)))
			(setq wrappers-mismatch-p t))))))
	      ;;
	      ;; How many unreserved lines separate line-1 and line-2.
	      ;;
	      (line-separation (line-1 line-2)
		(declare (fixnum line-1 line-2))
		(let ((diff (the fixnum (- line-2 line-1))))
		  (declare (fixnum diff))
		  (when (minusp diff)
		    (setq diff (+ diff (nlines)))
		    (when (line-reserved-p 0)
		      (setq diff (1- diff))))
		  diff))
	      ;;
	      ;; Given a cache line, get the next cache line.  This will not
	      ;; return a reserved line.
	      ;; 
	      (next-line (line)
		(declare (fixnum line))
		(if (= line (the fixnum (1- (nlines))))
		    (if (line-reserved-p 0) 1 0)
		    (the fixnum (1+ line))))
	      ;;
	      (next-location (loc)
		(declare (fixnum loc))
		(if (= loc (max-location))
		    (if (= (nkeys) 1)
			(line-size)
			1)
		    (the fixnum (+ loc (line-size)))))
	      ;;
	      ;; Given a line which has a valid entry in it, this
	      ;; will return the primary cache line of the wrappers
	      ;; in that line.  We just call
	      ;; COMPUTE-PRIMARY-CACHE-LOCATION-FROM-LOCATION, this
	      ;; is an easier packaging up of the call to it.
	      ;; 
	      (line-primary (line)
		(declare (fixnum line))
		(location-line (line-primary-location line)))
	      ;;
	      (line-primary-location (line)
		(declare (fixnum line))
		(compute-primary-cache-location-from-location
		 (cache) (line-location line))))
       (declare (ignorable #'cache #'nkeys #'line-size #'vector #'valuep
			   #'nlines #'max-location #'limit-fn #'size
			   #'mask #'field #'overflow #'line-reserved-p
			   #'location-reserved-p #'line-location
			   #'location-line #'line-wrappers #'location-wrappers
			   #'line-matches-wrappers-p
			   #'location-matches-wrappers-p
			   #'line-value #'location-value #'line-full-p
			   #'line-valid-p #'location-valid-p
			   #'line-separation #'next-line #'next-location
			   #'line-primary #'line-primary-location))
       ,@body)))


;;;
;;; Here is where we actually fill, recache and expand caches.
;;;
;;; The functions FILL-CACHE and PROBE-CACHE are the ONLY external
;;; entrypoints into this code.
;;;
;;; FILL-CACHE returns 1 value: a new cache
;;;
;;;   a wrapper field number
;;;   a cache
;;;   a mask
;;;   an absolute cache size (the size of the actual vector)
;;; It tries to re-adjust the cache every time it makes a new fill.  The
;;; intuition here is that we want uniformity in the number of probes needed to
;;; find an entry.  Furthermore, adjusting has the nice property of throwing out
;;; any entries that are invalid.
;;;
(defvar *cache-expand-threshold* 1.25)

(defun fill-cache (cache wrappers value)
  ;;(declare (values cache))
  ;; fill-cache won't return if wrappers is nil, might as well check.
  (assert wrappers)
  (or (fill-cache-p nil cache wrappers value)
      (and (< (ceiling (* (cache-count cache) 1.25))
	      (if (= (cache-nkeys cache) 1)
		  (1- (cache-nlines cache))
		  (cache-nlines cache)))
	   (adjust-cache cache wrappers value))
      (expand-cache cache wrappers value)))

(defvar *check-cache-p* nil)

(defmacro maybe-check-cache (cache)
  `(progn
     (when *check-cache-p*
       (check-cache ,cache))
     ,cache))

(defun check-cache (cache)
  (with-local-cache-functions (cache)
    (let ((location (if (= (nkeys) 1) 0 1))
	  (limit (funcall (limit-fn) (nlines))))
      (dotimes (i (nlines) cache)
	(declare (fixnum i))
	(when (and (not (location-reserved-p location))
		   (line-full-p i))
	  (let* ((home-loc (compute-primary-cache-location-from-location 
			    cache location))
		 (home (location-line (if (location-reserved-p home-loc)
					  (next-location home-loc)
					  home-loc)))
		 (sep (when home (line-separation home i))))
	    (when (and sep (> sep limit))
	      (error "bad cache ~S ~@
                      value at location ~D is ~D lines from its home. limit is ~D."
		     cache location sep limit))))
	(setq location (next-location location))))))

(defun probe-cache (cache wrappers &optional default limit-fn)
  ;;(declare (values value))
  (unless wrappers (error "probe-cache: wrappers arg is NIL!"))
  (with-local-cache-functions (cache)
    (let* ((location (compute-primary-cache-location (field) (mask) wrappers))
	   (limit (funcall (or limit-fn (limit-fn)) (nlines))))
      (declare (fixnum location limit))
      (when (location-reserved-p location)
	(setq location (next-location location)))
      (dotimes (i (1+ limit))
	(declare (fixnum i))
	(when (location-matches-wrappers-p location wrappers)
	  (return-from probe-cache (or (not (valuep))
				       (location-value location))))
	(setq location (next-location location)))
      (dolist (entry (overflow))
	(when (equal (car entry) wrappers)
	  (return-from probe-cache (or (not (valuep))
				       (cdr entry)))))
      default)))

(defun map-cache (function cache &optional set-p)
  (with-local-cache-functions (cache)
    (let ((set-p (and set-p (valuep))))
      (dotimes (i (nlines) cache)
	(declare (fixnum i))
	(unless (or (line-reserved-p i) (not (line-valid-p i nil)))
	  (let ((value (funcall function (line-wrappers i) (line-value i))))
	    (when set-p
	      (setf (cache-vector-ref (vector) (+ (line-location i) (nkeys)))
		    value)))))
      (dolist (entry (overflow))
	(let ((value (funcall function (car entry) (cdr entry))))
	  (when set-p
	    (setf (cdr entry) value))))))
  cache)

(defun cache-count (cache)
  (with-local-cache-functions (cache)
    (let ((count 0))
      (declare (fixnum count))
      (dotimes (i (nlines) count)
	(declare (fixnum i))
	(unless (line-reserved-p i)
	  (when (line-full-p i)
	    (incf count)))))))

(defun entry-in-cache-p (cache wrappers value)
  (declare (ignore value))
  (with-local-cache-functions (cache)
    (dotimes (i (nlines))
      (declare (fixnum i))
      (unless (line-reserved-p i)
	(when (equal (line-wrappers i) wrappers)
	  (return t))))))

;;;
;;; returns T or NIL
;;;
(defun fill-cache-p (forcep cache wrappers value)
  (with-local-cache-functions (cache)
    (let* ((location (compute-primary-cache-location (field) (mask) wrappers))
	   (primary (location-line location)))
      (declare (fixnum location primary))
      (multiple-value-bind (free emptyp)
	  (find-free-cache-line primary cache wrappers)
	(when (or forcep emptyp)
	  (when (not emptyp)
	    (push (cons (line-wrappers free) (line-value free)) 
		  (cache-overflow cache)))
	  ;;(fill-line free wrappers value)
	  (let ((line free))
	    (declare (fixnum line))
	    (when (line-reserved-p line)
	      (error "Attempt to fill a reserved line."))
	    (let ((loc (line-location line))
		  (cache-vector (vector)))
	      (declare (fixnum loc) (simple-vector cache-vector))
	      (cond ((= (nkeys) 1)
		     (setf (cache-vector-ref cache-vector loc) wrappers)
		     (when (valuep)
		       (setf (cache-vector-ref cache-vector (1+ loc)) value)))
		    (t
		     (let ((i 0))
		       (declare (fixnum i))
		       (dolist (w wrappers)
			 (setf (cache-vector-ref cache-vector (+ loc i)) w)
			 (setq i (the fixnum (1+ i)))))
		     (when (valuep)
		       (setf (cache-vector-ref cache-vector (+ loc (nkeys)))
			     value))))
	      (maybe-check-cache cache))))))))

(defun fill-cache-from-cache-p (forcep cache from-cache from-line)
  (declare (fixnum from-line))
  (with-local-cache-functions (cache)
    (let ((primary (location-line (compute-primary-cache-location-from-location
				   cache (line-location from-line) from-cache))))
      (declare (fixnum primary))
      (multiple-value-bind (free emptyp)
	  (find-free-cache-line primary cache)
	(when (or forcep emptyp)
	  (when (not emptyp)
	    (push (cons (line-wrappers free) (line-value free))
		  (cache-overflow cache)))
	  ;;(transfer-line from-cache-vector from-line cache-vector free)
	  (let ((from-cache-vector (cache-vector from-cache))
		(to-cache-vector (vector))
		(to-line free))
	    (declare (fixnum to-line))
	    (if (line-reserved-p to-line)
		(error "transfering something into a reserved cache line.")
		(let ((from-loc (line-location from-line))
		      (to-loc (line-location to-line)))
		  (declare (fixnum from-loc to-loc))
		  (modify-cache to-cache-vector
				(dotimes (i (line-size))
				  (declare (fixnum i))
				  (setf (cache-vector-ref to-cache-vector
							  (+ to-loc i))
					(cache-vector-ref from-cache-vector
							  (+ from-loc i)))))))
	    (maybe-check-cache cache)))))))

;;;
;;; Returns NIL or (values <field> <cache-vector>)
;;; 
;;; This is only called when it isn't possible to put the entry in the cache
;;; the easy way.  That is, this function assumes that FILL-CACHE-P has been
;;; called as returned NIL.
;;;
;;; If this returns NIL, it means that it wasn't possible to find a wrapper
;;; field for which all of the entries could be put in the cache (within the
;;; limit).  
;;;
(defun adjust-cache (cache wrappers value)
  (with-local-cache-functions (cache)
    (let ((ncache (get-cache-from-cache cache (nlines) (field))))
      (do ((nfield (cache-field ncache)
		   (when (< nfield (1- kernel:layout-hash-length))
		     (1+ nfield))))
	  ((null nfield) nil)
	(setf (cache-field ncache) nfield)
	(labels ((try-one-fill-from-line (line)
		   (fill-cache-from-cache-p nil ncache cache line))
		 (try-one-fill (wrappers value)
		   (fill-cache-p nil ncache wrappers value)))
	  (if (and (dotimes (i (nlines) t)
		     (declare (fixnum i))
		     (when (and (null (line-reserved-p i))
				(line-valid-p i wrappers))
		       (unless (try-one-fill-from-line i) (return nil))))
		   (dolist (wrappers+value (cache-overflow cache) t)
		     (unless (try-one-fill (car wrappers+value) (cdr wrappers+value))
		       (return nil)))
		   (try-one-fill wrappers value))
	      (progn 
		     (return (maybe-check-cache ncache)))
	      (flush-cache-vector-internal (cache-vector ncache))))))))
		       
;;;
;;; returns: (values <cache>)
;;;
(defun expand-cache (cache wrappers value)
  ;;(declare (values cache))
  (with-local-cache-functions (cache)
    (let ((ncache (get-cache-from-cache cache (* (nlines) 2))))
      (labels ((do-one-fill-from-line (line)
		 (unless (fill-cache-from-cache-p nil ncache cache line)
		   (do-one-fill (line-wrappers line) (line-value line))))
	       (do-one-fill (wrappers value)
		 (setq ncache (or (adjust-cache ncache wrappers value)
				  (fill-cache-p t ncache wrappers value))))
	       (try-one-fill (wrappers value)
		 (fill-cache-p nil ncache wrappers value)))
	(dotimes (i (nlines))
	  (declare (fixnum i))
	  (when (and (null (line-reserved-p i))
		     (line-valid-p i wrappers))
	    (do-one-fill-from-line i)))
	(dolist (wrappers+value (cache-overflow cache))
	  (unless (try-one-fill (car wrappers+value) (cdr wrappers+value))
	    (do-one-fill (car wrappers+value) (cdr wrappers+value))))
	(unless (try-one-fill wrappers value)
	  (do-one-fill wrappers value))
	(maybe-check-cache ncache)))))


;;;
;;; This is the heart of the cache filling mechanism.  It implements the decisions
;;; about where entries are placed.
;;; 
;;; Find a line in the cache at which a new entry can be inserted.
;;;
;;;   <line>
;;;   <empty?>           is <line> in fact empty?
;;;
(defun find-free-cache-line (primary cache &optional wrappers)
  ;;(declare (values line empty?))
  (declare (fixnum primary))
  (with-local-cache-functions (cache)
    (when (line-reserved-p primary) (setq primary (next-line primary)))
    (let ((limit (funcall (limit-fn) (nlines)))
	  (wrappedp nil)
	  (lines nil)
	  (p primary) (s primary))
      (declare (fixnum p s limit))
      (block find-free
	(loop
	 ;; Try to find a free line starting at <s>.  <p> is the
	 ;; primary line of the entry we are finding a free
	 ;; line for, it is used to compute the seperations.
	 (do* ((line s (next-line line))
	       (nsep (line-separation p s) (1+ nsep)))
	      (())
	   (declare (fixnum line nsep))
	   (when (null (line-valid-p line wrappers)) ;If this line is empty or
	     (push line lines)		;invalid, just use it.
	     (return-from find-free))
	   (when (and wrappedp (>= line primary))
	     ;; have gone all the way around the cache, time to quit
	     (return-from find-free-cache-line (values primary nil)))
	   (let ((osep (line-separation (line-primary line) line)))
	     (when (>= osep limit)
	       (return-from find-free-cache-line (values primary nil)))
	     (when (cond ((= nsep limit) t)
			 ((= nsep osep) (zerop (random 2)))
			 ((> nsep osep) t)
			 (t nil))
	       ;; See if we can displace what is in this line so that we
	       ;; can use the line.
	       (when (= line (the fixnum (1- (nlines)))) (setq wrappedp t))
	       (setq p (line-primary line))
	       (setq s (next-line line))
	       (push line lines)
	       (return nil)))
	   (when (= line (the fixnum (1- (nlines)))) (setq wrappedp t)))))
      ;; Do all the displacing.
      (loop 
       (when (null (cdr lines)) (return nil))
       (let ((dline (pop lines))
	     (line (car lines)))
	 (declare (fixnum dline line))
	 ;;Copy from line to dline (dline is known to be free).
	 (let ((from-loc (line-location line))
	       (to-loc (line-location dline))
	       (cache-vector (vector)))
	   (declare (fixnum from-loc to-loc) (simple-vector cache-vector))
	   (modify-cache cache-vector
			 (dotimes (i (line-size))
			   (declare (fixnum i))
			   (setf (cache-vector-ref cache-vector (+ to-loc i))
				 (cache-vector-ref cache-vector (+ from-loc i)))
			   (setf (cache-vector-ref cache-vector (+ from-loc i))
				 nil))))))
      (values (car lines) t))))

(defun default-limit-fn (nlines)
  (case nlines
    ((1 2 4) 1)
    ((8 16)  4)
    (otherwise 6)))

(defvar *empty-cache* (make-cache)) ; for defstruct slot initial value forms
