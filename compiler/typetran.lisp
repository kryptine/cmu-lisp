;;; -*- Package: C; Log: C.Log -*-
;;;
;;; **********************************************************************
;;; This code was written as part of the CMU Common Lisp project at
;;; Carnegie Mellon University, and has been placed in the public domain.
;;; If you want to use this code or any part of CMU Common Lisp, please contact
;;; Scott Fahlman or slisp-group@cs.cmu.edu.
;;;
(ext:file-comment
  "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/compiler/typetran.lisp,v 1.11 1991/05/23 17:55:06 ram Exp $")
;;;
;;; **********************************************************************
;;;
;;;    This file contains stuff that implements the portable IR1 semantics of
;;; type tests.  The main thing we do is convert complex type tests into
;;; simpler code that can be compiled inline.
;;;
;;; Written by Rob MacLachlan
;;;
(in-package "C")


;;;; Type predicate translation:
;;;
;;;    We maintain a bidirectional association between type predicates and the
;;; tested type.  The presence of a predicate in this association implies that
;;; it is desirable to implement tests of this type using the predicate.  This
;;; is true both of very simple types.  These are either predicates that the
;;; back end is likely to have special knowledge about, or predicates so
;;; complex that the only reasonable implentation is via function call.
;;;
;;;    Some standard types (such as SEQUENCE) are best tested by letting the
;;; TYPEP source transform do its thing with the expansion.  These types (and
;;; corresponding predicates) are not maintained in this association.  In this
;;; case, there need not be any predicate function unless it is required by
;;; Common Lisp.

;;; These two variables maintain the translation between types and predicates.
;;; *Predicate-Types* is a hashtable that translates from type predicate names
;;; to CType objects.  *Type-Predicates* is an alist (<type> . <predicate>)
;;; that translates from types to predicates.  We can't use a hashtable, since
;;; there is no such thing as a Type= hashtable.  Establishing this translation
;;;
(defvar *predicate-types* (make-hash-table :test #'eq))
(proclaim '(hash-table *predicate-types*))
(defvar *type-predicates* ())
(proclaim '(list *type-predicates*))


;;; Define-Type-Predicate  --  Interface
;;;
(defmacro define-type-predicate (name type)
  "Define-Type-Predicate Name Type
  Establish an association between the type predicate Name and the
  corresponding Type.  This causes the type predicate to be recognized for
  purposes of optimization."
  `(progn
     (setf (gethash ',name *predicate-types*) (specifier-type ',type))
     (setq *type-predicates*
	   (cons (cons (specifier-type ',type) ',name)
		 (remove ',name *type-predicates* :key #'cdr)))
     (%deftransform ',name '(function (t) *) #'fold-type-predicate)
     ',name))



;;;; IR1 transforms:

;;; Typep IR1 transform  --  Internal
;;;
;;;    If we discover the type argument is constant during IR1 optimization,
;;; then give the source transform another chance.  The source transform can't
;;; pass, since we give it an explicit constant.  At worst, it will convert to
;;; %Typep, which will prevent spurious attempts at transformation (and
;;; possible repeated warnings.) 
;;;
(deftransform typep ((object type))
  (unless (constant-continuation-p type)
    (give-up "Can't open-code test of non-constant type."))
  `(typep object ',(continuation-value type)))


;;; IR1-Transform-Type-Predicate  --  Internal
;;;
;;;    If the continuation Object definitely is or isn't of the specified type,
;;; then return T or NIL as appropriate.  Otherwise quietly Give-Up.
;;;
(defun ir1-transform-type-predicate (object type)
  (declare (type continuation object) (type ctype type))
  (let ((otype (continuation-type object)))
    (cond ((not (types-intersect otype type)) 'nil)
	  ((csubtypep otype type) 't)
	  (t (give-up)))))


;;; %Typep IR1 transform  --  Internal
;;;
;;;    Flush %Typep tests whose result is known at compile time.
;;;
(deftransform %typep ((object type))
  (unless (constant-continuation-p type) (give-up))
  (ir1-transform-type-predicate
   object
   (specifier-type (continuation-value type))))

;;; Fold-Type-Predicate IR1 transform  --  Internal
;;;
;;;    This is the IR1 transform for simple type predicates.  It checks whether
;;; the single argument is known to (not) be of the appropriate type, expanding
;;; to T or NIL as apprporiate.
;;;
(deftransform fold-type-predicate ((object) * * :node node :defun-only t)
  (let ((ctype (gethash (leaf-name
			 (ref-leaf
			  (continuation-use
			   (basic-combination-fun node))))
			*predicate-types*)))
    (assert ctype)
    (ir1-transform-type-predicate object ctype)))


;;;; Standard type predicates:

(define-type-predicate arrayp array)
; No atom.  Use (not cons) deftype.
(define-type-predicate bit-vector-p bit-vector)
(define-type-predicate characterp character)
(define-type-predicate compiled-function-p compiled-function)
(define-type-predicate complexp complex)
(define-type-predicate consp cons)
(define-type-predicate floatp float)
(define-type-predicate functionp function)
(define-type-predicate integerp integer)
(define-type-predicate keywordp keyword)
(define-type-predicate listp list)
(define-type-predicate null null)
(define-type-predicate numberp number)
(define-type-predicate rationalp rational)
(define-type-predicate simple-bit-vector-p simple-bit-vector)
(define-type-predicate simple-string-p simple-string)
(define-type-predicate simple-vector-p simple-vector)
(define-type-predicate stringp string)
(define-type-predicate structurep structure)
(define-type-predicate symbolp symbol)
(define-type-predicate vectorp vector)


;;;; Transforms for type predicates not implemented primitively:
;;;
;;; See also VM dependent transforms.

(def-source-transform atom (x)
  `(not (consp ,x)))


;;;; Typep source transform:

;;; Transform-Numeric-Bound-Test  --  Internal
;;;
;;;    Return a form that tests the variable N-Object for being in the binds
;;; specified by Type.  Base is the name of the base type, for declaration.  We
;;; make safety locally 0 to inhibit any checking of this assertion.
;;;
(defun transform-numeric-bound-test (n-object type base)
  (declare (type numeric-type type))
  (let ((low (numeric-type-low type))
	(high (numeric-type-high type)))
    `(locally
       (declare (optimize (safety 0)))
       (and ,@(when low
		(if (consp low)
		    `((> (the ,base ,n-object) ,(car low)))
		    `((>= (the ,base ,n-object) ,low))))
	    ,@(when high
		(if (consp high)
		    `((< (the ,base ,n-object) ,(car high)))
		    `((<= (the ,base ,n-object) ,high))))))))


;;; Source-Transform-Numeric-Typep  --  Internal
;;;
;;;    Do source transformation of a test of a known numeric type.  We can
;;; assume that the type doesn't have a corresponding predicate, since those
;;; types have already been picked off.  In particular, Class must be
;;; specified, since it is unspecified only in NUMBER and COMPLEX.  Similarly,
;;; we assume that Complexp is always specified.
;;;
;;;    For non-complex types, we just test that the number belongs to the base
;;; type, and then test that it is in bounds.  When Class is Integer, we check
;;; to see if the range is no bigger than FIXNUM.  If so, we check for FIXNUM
;;; instead of INTEGER.  This allows us to use fixnum comparison to test the
;;; bounds.
;;;
;;;    For complex types, we must test for complex, then do the above on both
;;; the real and imaginary parts.  When Class is float, we need only check the
;;; type of the realpart, since the format of the realpart and the imagpart
;;; must be the same.
;;;
(defun source-transform-numeric-typep (object type)
  (let* ((class (numeric-type-class type))
	 (base (ecase class
		 (integer (containing-integer-type type))
		 (rational 'rational)
		 (float (or (numeric-type-format type) 'float))
		 ((nil) 'number))))
    (once-only ((n-object object))
      (ecase (numeric-type-complexp type)
	(:real
	 `(and (typep ,n-object ',base)
	       ,(transform-numeric-bound-test n-object type base)))
	(:complex
	 `(and (complexp ,n-object)
	       ,(once-only ((n-real `(realpart (the complex ,n-object)))
			    (n-imag `(imagpart (the complex ,n-object))))
		  `(progn
		     ,n-imag ; ignorable
		     (and (typep ,n-real ',base)
			  ,@(when (eq class 'integer)
			      `((typep ,n-imag ',base)))
			  ,(transform-numeric-bound-test n-real type base)
			  ,(transform-numeric-bound-test n-imag type
							 base))))))))))


;;; Source-Transform-Hairy-Typep  --  Internal
;;;
;;;    Do the source transformation for a test of a hairy type.  AND, SATISFIES
;;; and NOT are converted into the obvious code.  We convert unknown types to
;;; %TYPEP, emitting an efficiency note if appropriate.
;;;
(defun source-transform-hairy-typep (object type)
  (declare (type hairy-type type))
  (let ((spec (hairy-type-specifier type)))
    (cond ((unknown-type-p type)
	   (when (policy nil (> speed brevity))
	     (compiler-note "Can't open-code test of unknown type ~S."
			    (specifier-type type)))
	   `(%typep ,object ',spec))
	  (t
	   (ecase (first spec)
	     (satisfies `(funcall #',(second spec) ,object))
	     ((not and)
	      (once-only ((n-obj object))
		`(,(first spec) ,@(mapcar #'(lambda (x) 
					      `(typep ,n-obj ',x))
					  (rest spec))))))))))


;;; Source-Transform-Union-Typep  --  Internal
;;;
;;;    Do source transformation for Typep of a known union type.  If a union
;;; type contains LIST, then we pull that out and make it into a single LISTP
;;; call.  Note that if SYMBOL is in the union, then LIST will be a subtype
;;; even without there being any (member NIL).  We just drop through to the
;;; general code in this case, rather than trying to optimize it.
;;;
(defun source-transform-union-typep (object type)
  (let* ((types (union-type-types type))
	 (ltype (specifier-type 'list))
	 (mtype (find-if #'member-type-p types)))
    (cond ((and mtype (csubtypep ltype type))
	   (let ((members (member-type-members mtype)))
	     (once-only ((n-obj object))
	       `(if (listp ,n-obj)
		    t
		    (typep ,n-obj 
			   '(or ,@(mapcar #'type-specifier
					  (remove (specifier-type 'cons)
						  (remove mtype types)))
				(member ,@(remove nil members))))))))
	  (t
	   (once-only ((n-obj object))
	     `(or ,@(mapcar #'(lambda (x)
				`(typep ,n-obj ',(type-specifier x)))
			    types)))))))


;;; FIND-SUPERTYPE-PREDICATE  --  Internal
;;;
;;;    Return the predicate and type from the most specific entry in
;;; *TYPE-PREDICATES* that is a supertype of Type.
;;;
(defun find-supertype-predicate (type)
  (declare (type ctype type))
  (let ((res nil)
	(res-type nil))
    (dolist (x *type-predicates*)
      (let ((stype (car x)))
	(when (and (csubtypep type stype)
		   (or (not res-type)
		       (csubtypep stype res-type)))
	  (setq res-type stype)
	  (setq res (cdr x)))))
    (values res res-type)))


;;; TEST-ARRAY-DIMENSIONS  --  Internal
;;;
;;;    Return forms to test that Obj has the rank and dimensions specified by
;;; Type, where Stype is the type we have checked against (which is the same
;;; but for dimensions.)
;;;
(defun test-array-dimensions (obj type stype)
  (declare (type array-type type stype))
  (let ((obj `(truly-the ,(type-specifier stype) ,obj))
	(dims (array-type-dimensions type)))
    (unless (eq dims '*)
      (collect ((res))
	(when (eq (array-type-dimensions stype) '*)
	  (res `(= (array-rank ,obj) ,(length dims))))

	(do ((i 0 (1+ i))
	     (dim dims (cdr dim)))
	    ((null dim))
	  (let ((dim (car dim)))
	    (unless (eq dim '*)
	      (res `(= (array-dimension ,obj ,i) ,dim)))))
	(res)))))


;;; SOURCE-TRANSFORM-ARRAY-TYPEP  --  Internal
;;;
;;;    If we can find a type predicate that tests for the type w/o dimensions,
;;; then use that predicate and test for dimensions.  Otherwise, just do
;;; %TYPEP.
;;;
(defun source-transform-array-typep (obj type)
  (multiple-value-bind (pred stype)
		       (find-supertype-predicate type)
    (if (and (array-type-p stype)
	     (type= (array-type-specialized-element-type stype)
		    (array-type-specialized-element-type type))
	     (eq (array-type-complexp stype) (array-type-complexp type)))
	(once-only ((n-obj obj))
	  `(and (,pred ,n-obj)
		,@(test-array-dimensions n-obj type stype)))
	`(%typep ,obj ',(type-specifier type)))))


;;; SOURCE-TRANSFORM-STRUCTURE-TYPEP  --  Internal
;;;
;;;    If not currently defined as a structure to the compiler (must have been
;;; undefined) or there is no predicate, then we call STRUCTURE-TYPEP.
;;; Otherwise, we do an EQ test for a direct type match, and if that fails,
;;; deal with inherited types.  If the type is frozen, we can inline the
;;; supertype check, otherwise we have to call the predicate.
;;;
(defun source-transform-structure-typep (obj desc)
  (let* ((type (structure-type-name desc))
	 (def (info type structure-info type)))
    (cond
     ((not def)
      `(lisp::structure-typep ,obj ',type))
     ((not (eq (dd-type def) 'structure))
      (compiler-error "Structure type has :TYPE specified, so it can't ~
      		       be used as an argument to TYPEP:~%  ~S"
		      type))
     (t
      (let ((frozen (info type frozen type))
	    (included (dd-included-by def))
	    (predicate (dd-predicate def))
	    (n-name (gensym)))
	(if (or frozen predicate)
	    (once-only ((object obj))
	      `(and (structurep ,object)
		    (let ((,n-name (structure-ref ,object 0)))
		      (if (eq ,n-name ',type)
			  t
			  ,(if frozen
			       (when included
				 `(member ,n-name ',included :test #'eq))
			       `(locally (declare (notinline ,predicate))
				  (,predicate ,object)))))))
	    `(lisp::structure-typep ,obj ',type)))))))


;;; Source-Transform-Typep  --  Internal
;;;
;;;    If the specifier argument is a quoted constant, then we consider
;;; converting into a simple predicate or other stuff.  If the type is
;;; constant, but we can't transform the call, then we convert to %Typep.  We
;;; only pass when the type is non-constant.  This allows us to recognize
;;; between calls that might later be transformed sucessfully when a constant
;;; type is discovered.  We don't given an efficiency note when we pass, since
;;; the IR1 transform will give one if necessary and appropriate.
;;;
;;; If the type is Type= to a type that has a predicate, then expand to that
;;; predicate.  Otherwise, we dispatch off of the type's type.  These
;;; transformations can increase space, but it is hard to tell when, so we
;;; ignore policy and always do them.
;;;
(def-source-transform typep (object spec)
  (if (and (consp spec) (eq (car spec) 'quote))
      (let* ((type (specifier-type (cadr spec)))
	     (pred (cdr (assoc type *type-predicates* :test #'type=))))
	(if pred
	    `(,pred ,object)
	    (typecase type
	      (numeric-type
	       (source-transform-numeric-typep object type))
	      (hairy-type
	       (source-transform-hairy-typep object type))
	      (union-type
	       (source-transform-union-typep object type))
	      (member-type
	       `(member ,object ',(member-type-members type)))
	      (structure-type
	       (source-transform-structure-typep object type))
	      (args-type
	       (compiler-warning "Illegal type specifier for Typep: ~S."
				 (cadr spec))
	       `(%typep ,object ,spec))
	      (array-type
	       (source-transform-array-typep object type))
	      (t
	       `(%typep ,object ,spec)))))
      (values nil t)))
