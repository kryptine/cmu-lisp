;;;-*-Mode: LISP; Package:(PCL LISP 1000); Base:10; Syntax:Common-lisp -*-
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

(in-package 'pcl)

#|

The CommonLoops evaluator is meta-circular.  

Most of the code in PCL is methods on generic functions, including most of
the code that actually implements generic functions and method lookup.

So, we have a classic bootstrapping problem.   The solution to this is to
first get a cheap implementation of generic functions running, these are
called early generic functions.  These early generic functions and the
corresponding early methods and early method lookup are used to get enough
of the system running that it is possible to create real generic functions
and methods and implement real method lookup.  At that point (done in the
file FIXUP) the function fix-early-generic-functions is called to convert
all the early generic functions to real generic functions.

The cheap generic functions are built using the same funcallable-instance
objects real generic-functions are made out of.  This means that as PCL
is being bootstrapped, the cheap generic function objects which are being
created are the same objects which will later be real generic functions.
This is good because:
  - we don't cons garbage structure
  - we can keep pointers to the cheap generic function objects
    during booting because those pointers will still point to
    the right object after the generic functions are all fixed
    up



This file defines the defmethod macro and the mechanism used to expand it.
This includes the mechanism for processing the body of a method.  defmethod
basically expands into a call to load-defmethod, which basically calls
add-method to add the method to the generic-function.  These expansions can
be loaded either during bootstrapping or when PCL is fully up and running.

An important effect of this structure is it means we can compile files with
defmethod forms in them in a completely running PCL, but then load those files
back in during bootstrapping.  This makes development easier.  It also means
there is only one set of code for processing defmethod.  Bootstrapping works
by being sure to have load-method be careful to call only primitives which
work during bootstrapping.

|#

(proclaim '(notinline make-a-method
		      add-named-method		      
		      ensure-generic-function-using-class

		      add-method
		      remove-method
		      ))

(defvar *early-functions*
	'((make-a-method early-make-a-method
			 real-make-a-method)
	  (add-named-method early-add-named-method
			    real-add-named-method)
	  ))

;;;
;;; For each of the early functions, arrange to have it point to its early
;;; definition.  Do this in a way that makes sure that if we redefine one
;;; of the early definitions the redefinition will take effect.  This makes
;;; development easier.
;;;
;;; The function which generates the redirection closure is pulled out into
;;; a separate piece of code because of a bug in ExCL which causes this not
;;; to work if it is inlined.
;;;
(eval-when (load eval)

  (defun redirect-early-function-internal (to)
    #'(lambda (&rest args) (apply (symbol-function to) args)))
  
  (dolist (fns *early-functions*)
    (let ((name (car fns))
	  (early-name (cadr fns)))
      (setf (symbol-function name)
	    (redirect-early-function-internal early-name))))

  )


;;;
;;; *generic-function-fixups* is used by fix-early-generic-functions to
;;; convert the few functions in the bootstrap which are supposed to be
;;; generic functions but can't be early on.
;;; 
(defvar *generic-function-fixups*
    '((add-method
	((generic-function method)		        ;lambda-list
	 (standard-generic-function method)	        ;specializers
	 real-add-method))			        ;method-function
      (remove-method
	((generic-function method)
	 (standard-generic-function method)
	 real-remove-method))
      (get-method
        ((generic-function qualifiers specializers &optional (errorp t))
	 (standard-generic-function t t)
	 real-get-method))
      (ensure-generic-function-using-class
	((generic-function function-specifier
			   &key generic-function-class environment
			   &allow-other-keys)
	 (generic-function t)
	 real-ensure-gf-using-class--generic-function)
	((generic-function function-specifier
			   &key generic-function-class environment
			   &allow-other-keys)
	 (null t)
	 real-ensure-gf-using-class--null))
      ))


;;;
;;;
;;;
(defmacro defgeneric (function-specifier lambda-list &body options)
  (expand-defgeneric function-specifier lambda-list options))

(defun expand-defgeneric (function-specifier lambda-list options)
  (when (listp function-specifier) (do-standard-defsetf-1 (cadr function-specifier)))
  (let ((initargs ()))
    (flet ((duplicate-option (name)
	     (error "The option ~S appears more than once." name)))
      ;;
      ;; INITARG takes this screwy new argument to get around a bad
      ;; interaction between lexical macros and setf in the Lucid
      ;; compiler.
      ;; 
      (macrolet ((initarg (key &optional new)
		   (if new
		       `(setf (getf initargs ,key) ,new)
		       `(getf initargs ,key))))
	(dolist (option options)
	  (ecase (car option)
	    (:argument-precedence-order
	      (if (initarg :argument-precedence-order)
		  (duplicate-option :argument-precedence-order)
		  (initarg :argument-precedence-order `',(cdr option))))
	    (declare
	      (initarg :declarations
		       (append (cdr option) (initarg :declarations))))
	    (:documentation
	      (if (initarg :documentation)
		  (duplicate-option :documentation)
		  (initarg :documentation `',(cadr option))))
	    (:method-combination
	      (if (initarg :method-combination)
		  (duplicate-option :method-combination)
		  (initarg :method-combination `',(cdr option))))
	    (:generic-function-class
	      (if (initarg :generic-function-class)
		  (duplicate-option :generic-function-class)
		  (initarg :generic-function-class `',(cadr option))))
	    (:method-class
	      (if (initarg :method-class)
		  (duplicate-option :method-class)
		  (initarg :method-class `',(cadr option))))
	    (:method
	      (error
		"DEFGENERIC doesn't support the :METHOD option yet."))))

	(let ((declarations (initarg :declarations)))
	  (when declarations (initarg :declarations `',declarations)))))
    `(progn
       (proclaim-defgeneric ',function-specifier ',lambda-list)
       ,(make-top-level-form `(defgeneric ,function-specifier)
	  *defgeneric-times*
	  `(load-defgeneric ',function-specifier ',lambda-list ,@initargs)))))

(defun load-defgeneric (function-specifier lambda-list &rest initargs)
  (when (listp function-specifier) (do-standard-defsetf-1 (cadr function-specifier)))
  (apply #'ensure-generic-function
	 function-specifier
	 :lambda-list lambda-list
	 :definition-source `((defgeneric ,function-specifier)
			      ,(load-truename))
	 initargs))


;;;
;;;
;;;
(defmacro DEFMETHOD (&rest args &environment env)
  #+(or (not :lucid) :lcl3.0)	
  (declare (arglist name
		    {method-qualifier}*
		    specialized-lambda-list
		    &body body))
  (multiple-value-bind (name qualifiers lambda-list body)
      (parse-defmethod args)
    (let ((proto-method (method-prototype-for-gf name)))
      (expand-defmethod
	proto-method name qualifiers lambda-list body env))))

;;;
;;; takes a name which is either a generic function name or a list specifying
;;; a setf generic function (like: (SETF <generic-function-name>)).  Returns
;;; the prototype instance of the method-class for that generic function.
;;;
;;; If there is no generic function by that name, this returns the default
;;; value, the prototype instance of the class STANDARD-METHOD.  This default
;;; value is also returned if the spec names an ordinary function or even a
;;; macro.  In effect, this leaves the signalling of the appropriate error
;;; until load time.
;;;
;;; NOTE that during bootstrapping, this function is allowed to return NIL.
;;; 
(defun method-prototype-for-gf (name)      
  (let ((gf? (and (gboundp name)
		  (gdefinition name))))
    (cond ((neq *boot-state* 'complete) nil)
	  ((or (null gf?)
	       (not (generic-function-p gf?)))	        ;Someone else MIGHT
						        ;error at load time.
	   (class-prototype (find-class 'standard-method)))
	  (t
	    (class-prototype (or (generic-function-method-class gf?)
				 (find-class 'standard-method)))))))


;#-Genera
(defun expand-defmethod (proto-method name qualifiers lambda-list body env)
  (when (listp name) (do-standard-defsetf-1 (cadr name)))
  (multiple-value-bind (fn-form specializers doc plist)
      (expand-defmethod-internal name qualifiers lambda-list body env)
    (make-top-level-form `(defmethod ,name ,@qualifiers ,specializers)
			 *defmethod-times*
      `(progn
	 (proclaim-defgeneric ',name ',lambda-list)
	 (load-defmethod
	  ',(if proto-method
		(class-name (class-of proto-method))
		'standard-method)
	  ',name
	  ',qualifiers
	  (list ,@(mapcar #'(lambda (specializer)
			      (if (consp specializer)
				  ``(,',(car specializer) ,,(cadr specializer))
				  `',specializer))
			  specializers))
	  ',(extract-lambda-list lambda-list)
	  ',doc
	  ',(getf plist :isl-cache-symbol) ;Paper over a bug in KCL by
					   ;passing the cache-symbol
					   ;here in addition to in the
					   ;plist.
	  ',plist
	  ,fn-form)))))

#||
#+Genera
(defun expand-defmethod (proto-method name qualifiers lambda-list body env)
  (when (listp name) (do-standard-defsetf-1 (cadr name)))
  (multiple-value-bind (fn-form specializers doc plist)
      (expand-defmethod-internal name qualifiers lambda-list body env)
    (let ((fn-args (cadadr fn-form))
	  (fn-body (cddadr fn-form))
	  (method-name `(method ,name ,@qualifiers ,specializers)))
      `(progn
	 (proclaim '(function ,name))
	 (defun ,method-name ,fn-args
	   ,@fn-body)
	 (load-defmethod
	   ',(if proto-method
		 (class-name (class-of proto-method))
		 'standard-method)
	   ',name
	   ',qualifiers
	   (list ,@(mapcar #'(lambda (specializer)
			       (if (consp specializer)
				   ``(,',(car specializer) ,,(cadr specializer))
				   `',specializer))
			   specializers))
	   ',(extract-lambda-list lambda-list)
	   ',doc
	   ',(getf plist :isl-cache-symbol)	;Paper over a bug in KCL by
						;passing the cache-symbol
						;here in addition to in the
						;plist.
	   ',plist
	   #',method-name)))))
||#

(defun expand-defmethod-internal
       (generic-function-name qualifiers specialized-lambda-list body env)
  ;;(declare (values fn-form specializers doc))
  (declare (ignore qualifiers))
  (when (listp generic-function-name)
    (do-standard-defsetf-1 (cadr generic-function-name)))
  (multiple-value-bind (documentation declarations real-body)
      (extract-declarations body)
    (multiple-value-bind (parameters lambda-list specializers)
	(parse-specialized-lambda-list specialized-lambda-list)

      
      (let* ((required-parameters
	       (mapcar #'(lambda (r s) (declare (ignore s)) r)
		       parameters
		       specializers))
	     (parameters-to-reference
	       (make-parameter-references specialized-lambda-list
					  required-parameters
					  declarations
					  generic-function-name
					  specializers))
	     (class-declarations 
	       `(declare
		  ,@(remove nil
			    (mapcar #'(lambda (a s) (and (symbolp s)
							 (neq s 't)
							 `(class ,a ,s)))
				    parameters
				    specializers))))
	     (method-lambda 
	       ;; Remove the documentation string and insert the
	       ;; appropriate class declarations.  The documentation
	       ;; string is removed to make it easy for us to insert
	       ;; new declarations later, they will just go after the
	       ;; cadr of the method lambda.  The class declarations
	       ;; are inserted to communicate the class of the method's
	       ;; arguments to the code walk.
	       (let ()
		 `(lambda ,lambda-list
		    ,class-declarations
		    ,@declarations
		    (progn ,@parameters-to-reference)
		    (block ,(if (listp generic-function-name)
				(cadr generic-function-name)
				generic-function-name)
		      ,@real-body))))

	     (constant-value-p (and (null (cdr real-body))
				    (constantp (car real-body))))
	     (constant-value (and constant-value-p
				  (eval (car real-body))))
	     (plist (if (and constant-value-p
			     (or (typep constant-value '(or number character))
				 (and (symbolp constant-value)
				      (symbol-package constant-value))))
			(list :constant-value constant-value)
			()))

	     (call-next-method-p nil)   ;flag indicating that call-next-method
	                                ;should be in the method definition
	     (closurep nil)		;flag indicating that #'call-next-method
					;was seen in the body of a method
	     (next-method-p-p nil)      ;flag indicating that next-method-p
                                        ;should be in the method definition
	     (save-original-args nil)   ;flag indicating whether or not the
				        ;original arguments to the method
					;must be preserved.  This happens
					;for two reasons:
	                                ; - the method takes &mumble args,
					;   so one of the lexical functions
					;   might be used in a default value
	                                ;   form
					; - call-next-method is used without
					;   arguments at least once in the
					;   body of the method
	     (original-args ())
	     (applyp nil)		;flag indicating whether or not the
					;method takes &mumble arguments. If
					;it does, it means call-next-method
					;without arguments must be APPLY'd
					;to original-args.  If this gets set
					;true, save-original-args is set so
					;as well
	     (aux-bindings ())		;Suffice to say that &aux is one of
					;damndest things to have put in a
					;language.
	     (need-pv-p nil)
	     (slots (mapcar #'list required-parameters))
	     (walked-lambda nil))
	(flet ((walk-function (form context env)
		 (cond ((not (eq context ':eval)) form)
		       ((not (listp form)) form)
		       ((eq (car form) 'call-next-method)
			(setq call-next-method-p 't)
			(unless (cdr form)
			  (setq save-original-args t))
			form)
		       ((eq (car form) 'next-method-p)
			(setq next-method-p-p 't)
			form)
		       ((and (eq (car form) 'function)
			     (cond ((eq (cadr form) 'call-next-method)
				    (setq call-next-method-p 't)
				    (setq save-original-args 't)
				    (setq closurep t)
				    form)
				   ((eq (cadr form) 'next-method-p)
				    (setq next-method-p-p 't)
				    (setq closurep t)
				    form)
				   (t nil))))
		       ((and (or (eq (car form) 'slot-value)
				 (eq (car form) 'set-slot-value)
				 (eq (car form) 'slot-boundp))
			     (constantp (caddr form)))
			(let ((parameter
                               (can-optimize-access form
                                                    required-parameters env)))
                          (ecase (car form)
                            (slot-value
                             (optimize-slot-value     slots parameter form))
                            (set-slot-value
                             (optimize-set-slot-value slots parameter form))
                            (slot-boundp
                             (optimize-slot-boundp    slots parameter form)))))
		       ((and (or (symbolp (car form))
				 (and (consp (car form))
				      (eq (caar form) 'setf)))
			     (gboundp (car form))
			     (if (eq *boot-state* 'complete)
				 (standard-generic-function-p (gdefinition (car form)))
				 (funcallable-instance-p (gdefinition (car form)))))
			(optimize-generic-function-call form required-parameters env))
		       (t form))))
	  
	  (setq walked-lambda (walk-form method-lambda env #'walk-function))

	  ;;
	  ;; Add &allow-other-keys to the lambda list as an interim
	  ;; way of implementing lambda list congruence rules.
	  ;;
	  (when (and (memq '&key lambda-list)
		     (not (memq '&allow-other-keys lambda-list)))
	    (let* ((rll (reverse lambda-list))
		   (aux (memq '&aux rll)))
	      (setq lambda-list
		    (if aux
			(progn (setf (cdr aux)
				     (cons '&allow-other-keys (cdr aux)))
			       (nreverse rll))
		        (nconc (nreverse rll) (list '&allow-other-keys))))))
	  ;; Scan the lambda list to determine whether this method
	  ;; takes &mumble arguments.  If it does, we set applyp and
	  ;; save-original-args true.
	  ;; 
	  ;; This is also the place where we construct the original
	  ;; arguments lambda list if there has to be one.
	  (dolist (p lambda-list)
	    (if (memq p lambda-list-keywords)
		(if (eq p '&aux)
		    (progn
		      (setq aux-bindings (cdr (memq '&aux lambda-list)))
		      (return nil))
		    (progn
		      (setq applyp t
			    save-original-args t)
		      (push '&rest original-args)
		      (push (make-symbol "AMPERSAND-ARGS") original-args)
		      (return nil)))
		(push (make-symbol (symbol-name p)) original-args)))
	  (setq original-args (if save-original-args
				  (nreverse original-args)
				  ()))
	  
	  (multiple-value-bind (ignore walked-declarations walked-lambda-body)
	      (extract-declarations (cddr walked-lambda))
	    (declare (ignore ignore))

	    
            (when (setq need-pv-p (some #'cdr slots))
              (setq slots (slot-name-lists-from-slots slots))
              (setq plist (list* :isl slots plist))
              (setq walked-lambda-body 
                    (add-pv-binding walked-lambda-body plist required-parameters)))
            (when (or next-method-p-p call-next-method-p)
              (setq plist (list* :needs-next-methods-p 't plist)))

            ;;; changes are here... (mt)
            (let ((fn-body `(lambda ,lambda-list
                              ,@walked-declarations
                              ,.walked-lambda-body)))
              (when (or call-next-method-p next-method-p-p)
                (setq fn-body (add-lexical-functions-to-method-lambda
                               walked-declarations
                               walked-lambda-body
                               fn-body
                               original-args
                               lambda-list
                               save-original-args
                               applyp
                               aux-bindings
                               call-next-method-p
                               next-method-p-p
                               closurep)))
              (values
               (if need-pv-p
                   (make-pv-fn-form `(function ,fn-body) plist)
                   `(function ,fn-body))
               specializers
               documentation
               plist))))))))

(defun add-lexical-functions-to-method-lambda (walked-declarations
					       walked-lambda-body
					       walked-lambda
					       original-args
					       lambda-list
					       save-original-args
					       applyp
					       aux-bindings
					       call-next-method-p
					       next-method-p-p
					       closurep)
  (cond ((and (null closurep)
	      (null applyp)
	      (null save-original-args))
	 ;; OK to use MACROLET, CALL-NEXT-METHOD is always passed some args, and
	 ;; all args are mandatory (else APPLYP would be true).
	 `(lambda ,lambda-list
	    ,@walked-declarations
	    (let ((.next-method. (car *next-methods*))
		  (.next-methods. (cdr *next-methods*)))
	      (macrolet ((call-next-method ,lambda-list
			   `(if .next-method.
				(let ((*next-methods* .next-methods.))
				  (function-funcall .next-method. ,,@lambda-list))
				(error "No next method.")))
			 (next-method-p () `(not (null .next-method.))))
		,@walked-lambda-body))))
	((and (null closurep)
	      (null applyp)
	      save-original-args)
	 ;; OK to use MACROLET.  CALL-NEXT-METHOD is sometimes called in the
	 ;; body with zero args, so we have to save the original args.
	 (if save-original-args
	     ;; CALL-NEXT-METHOD is sometimes called with no args
	     `(lambda ,original-args
		(let ((.next-method. (car *next-methods*))
		      (.next-methods. (cdr *next-methods*)))
		  (macrolet ((call-next-method (&rest cnm-args)
			       `(if .next-method.
				    (let ((*next-methods* .next-methods.))
				      (function-funcall 
				       .next-method.
				       ,@(if cnm-args cnm-args ',original-args)))
				    (error "No next method.")))
			     (next-method-p () `(not (null .next-method.))))
		    (let* (,@(mapcar #'list lambda-list original-args)
			     ,@aux-bindings)
		      ,@walked-declarations
		      ,@walked-lambda-body))))))
	((and (null save-original-args)
	      (null applyp))
	 ;;
	 ;; We don't have to save the original arguments.  In addition,
	 ;; this method doesn't take any &mumble arguments (this means
	 ;; that there is no way the lexical functions can be used inside
	 ;; of the default value form for an &mumble argument).
	 ;;
	 ;; We can expand this into a simple lambda expression with an
	 ;; FLET to define the lexical functions.
	 ;; 
	 `(lambda ,lambda-list
	    ,@walked-declarations
	    (let ((.next-method. (car *next-methods*))
		  (.next-methods. (cdr *next-methods*)))
	      (flet (,@(and call-next-method-p
			    '((call-next-method (&rest cnm-args)
				#+Genera
				(declare (dbg:invisible-frame :clos-internal))
				(if .next-method.
				    (let ((*next-methods* .next-methods.))
				      (function-apply .next-method. cnm-args))
				    (error "No next method.")))))
		     ,@(and next-method-p-p
			    '((next-method-p ()
				(not (null .next-method.))))))
		,@walked-lambda-body))))
	((null applyp)
	 ;;
	 ;; This method doesn't accept any &mumble arguments.  But we
	 ;; do have to save the original arguments (this is because
	 ;; call-next-method is being called with no arguments).
	 ;; Have to be careful though, there may be multiple calls to
	 ;; call-next-method, all we know is that at least one of them
	 ;; is with no arguments.
	 ;; 
	 `(lambda ,original-args
	    (let ((.next-method. (car *next-methods*))
		  (.next-methods. (cdr *next-methods*)))
	      (flet (,@(and call-next-method-p
                            `((call-next-method (&rest cnm-args)
				(if .next-method.
				    (let ((*next-methods* .next-methods.))
				      (if cnm-args
					  (function-apply .next-method. cnm-args)
					  (function-funcall .next-method.
							    ,@original-args)))
				    (error "No next method.")))))
		     ,@(and next-method-p-p
			    '((next-method-p ()
				(not (null .next-method.))))))
		(let* (,@(mapcar #'list
				 (remtail lambda-list (memq '&aux lambda-list))
				 original-args)
		       ,@aux-bindings)
		  ,@walked-declarations
		  ,@walked-lambda-body)))))
	(t
	 ;;
	 ;; This is the fully general case.
	 ;; We must allow for the lexical functions being used inside
	 ;; the default value forms of &mumble arguments, and if must
	 ;; allow for call-next-method being called with no arguments.
	 ;; 
	 `(lambda ,original-args
	    (let ((.next-method. (car *next-methods*))
		  (.next-methods. (cdr *next-methods*)))
	      (flet (,@(and call-next-method-p
			    `((call-next-method (&rest cnm-args)
				(if .next-method.
				    (let ((*next-methods* .next-methods.))
				      (if cnm-args
					  (function-apply .next-method. cnm-args)
					  (function-apply .next-method.
							  ,@(remove '&rest
								    original-args))))
				    (error "No next method.")))))
		     ,@(and next-method-p-p
			    '((next-method-p ()
				(not (null .next-method.))))))
		(apply (function ,walked-lambda)
		       ,@(remove '&rest original-args))))))))


(defun make-parameter-references (specialized-lambda-list
				  required-parameters
				  declarations
				  generic-function-name
				  specializers)
  (flet ((ignoredp (symbol)
	   (dolist (decl (cdar declarations))
	     (when (and (eq (car decl) 'ignore)
			(memq symbol (cdr decl)))
	       (return t)))))	   
    (gathering ((references (collecting)))
      (iterate ((s (list-elements specialized-lambda-list))
		(p (list-elements required-parameters)))
	(progn p)
	(cond ((not (listp s)))
	      ((ignoredp (car s))
	       (warn "In defmethod ~S ~S, there is a~%~
                      redundant ignore declaration for the parameter ~S."
		     generic-function-name
		     specializers
		     (car s)))
	      (t
	       (gather (car s) references)))))))


(defvar *method-function-plist* (make-hash-table :test #'eq))

(defun method-function-plist (method-function)
  (gethash method-function *method-function-plist*))

(defun #-setf SETF\ PCL\ METHOD-FUNCTION-PLIST #+setf (setf method-function-plist)
       (val method-function)
  (setf (gethash method-function *method-function-plist*) val))

(defun method-function-get (method-function key)
  (getf (method-function-plist method-function) key))

(defun #-setf SETF\ PCL\ METHOD-FUNCTION-GET #+setf (setf method-function-get)
       (val method-function key)
  (setf (getf  (method-function-plist method-function) key) val))


(defun method-function-isl (method-function)
  (method-function-get method-function :isl))

(defun method-function-needs-next-methods-p (method-function)
  (method-function-get method-function :needs-next-methods-p))



(defmacro method-function-closure-generator (method-function)
  `(method-function-get ,method-function 'closure-generator))

(defun load-defmethod
       (class name quals specls ll doc isl-cache-symbol plist fn)
  (when (listp name) (do-standard-defsetf-1 (cadr name)))
  (let ((method-spec (make-method-spec name quals specls)))
    (record-definition 'method method-spec)
    (setq fn (set-function-name fn method-spec))
    (load-defmethod-internal
      name quals specls ll doc isl-cache-symbol plist fn class)))

(defun load-defmethod-internal
       (gf-spec qualifiers specializers
	lambda-list doc isl-cache-symbol plist fn method-class)
  (when (listp gf-spec) (do-standard-defsetf-1 (cadr gf-spec)))
  (when plist
    (setq plist (copy-list plist))	     ;Do this to keep from affecting
					     ;the plist that is about to be
					     ;dumped when we are compiling.
    (let ((uisl (getf plist :isl))
	  (isl nil))
      (when uisl
	(setq isl (intern-slot-name-lists uisl))
	(setf (getf plist :isl) isl))
      (when isl-cache-symbol
	(setf (getf plist :isl-cache-symbol) isl-cache-symbol)
	(set isl-cache-symbol isl)))

    (loop (when (null plist) (return nil))
          (setf (getf (method-function-plist fn) (pop plist)) (pop plist))))
  (let ((method (add-named-method
		  gf-spec qualifiers specializers lambda-list fn
		  :documentation doc
		  :definition-source `((defmethod ,gf-spec
						  ,@qualifiers
						  ,specializers)
				       ,(load-truename)))))
    (unless (or (eq method-class 'standard-method)
		(eq (find-class method-class nil) (class-of method)))
      (format *error-output*
	      "At the time the method with qualifiers ~:~S and~%~
               specializers ~:S on the generic function ~S~%~
               was compiled, the method-class for that generic function was~%~
               ~S.  But, the method class is now ~S, this~%~
               may mean that this method was compiled improperly."
	      qualifiers specializers gf-spec
	      method-class (class-name (class-of method))))
    method))


(defun make-method-spec (gf-spec qualifiers unparsed-specializers)
  `(method ,gf-spec ,@qualifiers ,unparsed-specializers))



(defun analyze-lambda-list (lambda-list)
  ;;(declare (values nrequired noptional keysp restp allow-other-keys-p
  ;;                 keywords keyword-parameters))
  (flet ((parse-keyword-argument (arg)
	   (if (listp arg)
	       (if (listp (car arg))
		   (caar arg)
		   (make-keyword (car arg)))
	       (make-keyword arg))))
    (let ((nrequired 0)
	  (noptional 0)
	  (keysp nil)
	  (restp nil)
	  (allow-other-keys-p nil)
	  (keywords ())
	  (keyword-parameters ())
	  (state 'required))
      (dolist (x lambda-list)
	(if (memq x lambda-list-keywords)
	    (case x
	      (&optional         (setq state 'optional))
	      (&key              (setq keysp 't
				       state 'key))
	      (&allow-other-keys (setq allow-other-keys-p 't))
	      (&rest             (setq restp 't
				       state 'rest))
	      (&aux              (return t))
	      (otherwise
		(error "Encountered the non-standard lambda list keyword ~S." x)))
	    (ecase state
	      (required  (incf nrequired))
	      (optional  (incf noptional))
	      (key       (push (parse-keyword-argument x) keywords)
			 (push x keyword-parameters))
	      (rest      ()))))
      (values nrequired noptional keysp restp allow-other-keys-p
	      (reverse keywords)
	      (reverse keyword-parameters)))))

(defun keyword-spec-name (x)
  (let ((key (if (atom x) x (car x))))
    (if (atom key)
	(intern (symbol-name key) (find-package "KEYWORD"))
	(car key))))

(defun ftype-declaration-from-lambda-list (lambda-list #+cmu name)
  (multiple-value-bind (nrequired noptional keysp restp allow-other-keys-p
				  keywords keyword-parameters)
      (analyze-lambda-list lambda-list)
    (declare (ignore keyword-parameters))
    (let* (#+cmu (old (c::info function type name))
	   #+cmu (old-ftype (if (c::function-type-p old) old nil))
	   #+cmu (old-restp (and old-ftype (c::function-type-rest old-ftype)))
	   #+cmu (old-keys (and old-ftype
				(mapcar #'c::key-info-name
					(c::function-type-keywords old-ftype))))
	   #+cmu (old-keysp (and old-ftype (c::function-type-keyp old-ftype)))
	   #+cmu (old-allowp (and old-ftype (c::function-type-allowp old-ftype)))
	   (keywords #+cmu (union old-keys (mapcar #'keyword-spec-name keywords))
		     #-cmu (mapcar #'keyword-spec-name keywords)))
      `(function ,(append (make-list nrequired :initial-element 't)
			  (when (plusp noptional)
			    (append '(&optional)
				    (make-list noptional :initial-element 't)))
			  (when (or restp #+cmu old-restp)
			    '(&rest t))
			  (when (or keysp #+cmu old-keysp)
			    (append '(&key)
				    (mapcar #'(lambda (key)
						`(,key t))
					    keywords)
				    (when (or allow-other-keys-p #+cmu old-allowp)
				      '(&allow-other-keys)))))
		 *))))

(defun proclaim-defgeneric (spec lambda-list)
  (when (consp spec)
    (setq spec (get-setf-function-name (cadr spec))))
  (let ((decl `(ftype ,(ftype-declaration-from-lambda-list lambda-list #+cmu spec)
		      ,spec)))
    #+cmu (proclaim decl)
    #+kcl (setf (get spec 'compiler::proclaimed-closure) t)))

;;;; Early generic-function support
;;;
;;;
(defvar *early-generic-functions* ())

(defun ensure-generic-function (function-specifier
				&rest all-keys
				&key environment
				&allow-other-keys)
  (declare (ignore environment))
  (let ((existing (and (gboundp function-specifier)		       
		       (gdefinition function-specifier))))
    (if (and existing
	     (eq *boot-state* 'complete)
	     (null (generic-function-p existing)))
	(generic-clobbers-function function-specifier)
	(apply #'ensure-generic-function-using-class existing function-specifier all-keys))))

(defun generic-clobbers-function (function-specifier)
  #+Lispm (zl:signal 'generic-clobbers-function :name function-specifier)
  #-Lispm (error "~S already names an ordinary function or a macro,~%~
                  you may want to replace it with a generic function, but doing so~%~
                  will require that you decide what to do with the existing function~%~
                  definition.~%~
                  The PCL-specific function MAKE-SPECIALIZABLE may be useful to you."
		 function-specifier))

#+Lispm
(zl:defflavor generic-clobbers-function (name) (si:error)
  :initable-instance-variables)

#+Lispm
(zl:defmethod #+Genera (dbg:report generic-clobbers-function)
	      #+ti (generic-clobbers-function :report)
	      (stream)
 (format stream
	 "~S aready names a ~a"
	 name
	 (if (and (symbolp name) (macro-function name)) "macro" "function")))

#+Genera
(zl:defmethod (sys:proceed generic-clobbers-function :specialize-it) ()
  "Make it specializable anyway?"
  (make-specializable name))

#+ti
(zl:defmethod
     (generic-clobbers-function :case :proceed-asking-user :specialize-it)
     (continuation ignore)
  "Make it specializable anyway?"
  (make-specializable name)
  (funcall continuation :specialize-it))

;;;
;;; This is the early definition of ensure-generic-function-using-class.
;;; 
;;; The static-slots field of the funcallable instances used as early generic
;;; functions is used to store the early methods and early discriminator code
;;; for the early generic function.  The static slots field of the fins
;;; contains a list whose:
;;;    CAR    -   a list of the early methods on this early gf
;;;    CADR   -   the early discriminator code for this method
;;;    
(defun ensure-generic-function-using-class (existing spec &rest keys
					    &key (lambda-list nil lambda-list-p)
					    &allow-other-keys)
  (declare (ignore keys))
  (if existing
      existing
      (unless (assoc spec *generic-function-fixups* :test #'equal)
	(pushnew spec *early-generic-functions* :test #'equal)
	(let ((fin (allocate-funcallable-instance-1)))
	  (when (eq spec 'print-object)
	    (set-funcallable-instance-function
	     fin #'(lambda (instance stream)
		     (printing-random-thing (instance stream)
		       (format stream "std-instance")))))
	  (setf (gdefinition spec) fin)
	  (when lambda-list-p
	    (proclaim-defgeneric spec lambda-list))
	  (setf (fsc-instance-slots fin) (list nil nil spec))
	  (set-function-name fin spec)
	  fin))))

(defun early-gf-p (x)
  (and (fsc-instance-p x)
       (listp (fsc-instance-slots x))))

(defmacro early-gf-methods (early-gf)		;These are macros so that
  `(car (fsc-instance-slots ,early-gf)))	;they can be setf'd.
						;
(defmacro early-gf-discriminator-code (early-gf);
  `(cadr (fsc-instance-slots ,early-gf)))	;

(defun early-gf-name (early-gf)
  (caddr (fsc-instance-slots early-gf)))


(defmacro real-ensure-gf-internal (gf-class all-keys env)
  `(progn
     (cond ((symbolp ,gf-class)
	    (setq ,gf-class (find-class ,gf-class t ,env)))
	   ((classp ,gf-class))
	   (t
	    (error "The :GENERIC-FUNCTION-CLASS argument (~S) was neither a~%~
                    class nor a symbol that names a class."
		   ,gf-class)))
     (remf ,all-keys :generic-function-class)
     (remf ,all-keys :environment)
     (let ((combin (getf ,all-keys :method-combination '.shes-not-there.)))
       (unless (eq combin '.shes-not-there.)
	 (setf (getf ,all-keys :method-combination)
	       (find-method-combination (class-prototype ,gf-class)
					(car combin)
					(cdr combin)))))
     ))
     
(defun real-ensure-gf-using-class--generic-function
       (existing
	function-specifier
	&rest all-keys
	&key environment (lambda-list nil lambda-list-p)
	     (generic-function-class 'standard-generic-function gf-class-p)
	&allow-other-keys)
  (declare (ignore function-specifier))
  (real-ensure-gf-internal generic-function-class all-keys environment)
  (unless (or (null gf-class-p)
	      (eq (class-of existing) generic-function-class))
    (change-class existing generic-function-class))
  (prog1
      (apply #'reinitialize-instance existing all-keys)
    (when lambda-list-p
      (proclaim-defgeneric function-specifier lambda-list))))

(defun real-ensure-gf-using-class--null
       (existing
	function-specifier
	&rest all-keys
	&key environment (lambda-list nil lambda-list-p)
	     (generic-function-class 'standard-generic-function)
	&allow-other-keys)
  (declare (ignore existing))
  (real-ensure-gf-internal generic-function-class all-keys environment)
  (prog1
      (setf (gdefinition function-specifier)
	    (apply #'make-instance generic-function-class 
		   :name function-specifier all-keys))
    (when lambda-list-p
      (proclaim-defgeneric function-specifier lambda-list))))



(defun early-make-a-method (class qualifiers arglist specializers function doc
			    &optional slot-name)
  (let ((parsed ())
	(unparsed ()))
    ;; Figure out whether we got class objects or class names as the
    ;; specializers and set parsed and unparsed appropriately.  If we
    ;; got class objects, then we can compute unparsed, but if we got
    ;; class names we don't try to compute parsed.
    ;; 
    ;; Note that the use of not symbolp in this call to every should be
    ;; read as 'classp' we can't use classp itself because it doesn't
    ;; exist yet.
    (if (every #'(lambda (s) (not (symbolp s))) specializers)
	(setq parsed specializers
	      unparsed (mapcar #'(lambda (s)
				   (if (eq s 't) 't (class-name s)))
			       specializers))
	(setq unparsed specializers
	      parsed ()))
    (list :early-method		  ;This is an early method dammit!
	  
	  function                ;Function is here for the benefit
				  ;of early-lookup-method.
	  
	  parsed                  ;The parsed specializers.  This is used
				  ;by early-method-specializers to cache
				  ;the parse.  Note that this only comes
				  ;into play when there is more than one
				  ;early method on an early gf.
	  
	  (list class             ;A list to which real-make-a-method
		qualifiers        ;can be applied to make a real method
		arglist           ;corresponding to this early one.
		unparsed
		function
		doc
		slot-name)
	  )))

(defun real-make-a-method
       (class qualifiers lambda-list specializers function doc
	&optional slot-name)
  (setq specializers (parse-specializers specializers))
  (make-instance class :qualifiers qualifiers
		       :lambda-list lambda-list
		       :specializers specializers
		       :function function
		       :documentation doc
		       :slot-name slot-name
		       :allow-other-keys t))

(defun early-method-function (early-method)
  (cadr early-method))

(defun early-method-standard-accessor-p (early-method)
  (let ((class (car (cadddr early-method))))
    (or (eq class 'standard-reader-method)
        (eq class 'standard-writer-method)
        (eq class 'standard-boundp-method))))

;;;
;;; Fetch the specializers of an early method.  This is basically just a
;;; simple accessor except that when the second argument is t, this converts
;;; the specializers from symbols into class objects.  The class objects
;;; are cached in the early method, this makes bootstrapping faster because
;;; the class objects only have to be computed once.
;;; NOTE:
;;;  the second argument should only be passed as T by early-lookup-method.
;;;  this is to implement the rule that only when there is more than one
;;;  early method on a generic function is the conversion from class names
;;;  to class objects done.
;;;  the corresponds to the fact that we are only allowed to have one method
;;;  on any generic function up until the time classes exist.
;;;  
(defun early-method-specializers (early-method &optional objectsp)
  (if (and (listp early-method)
	   (eq (car early-method) :early-method))
      (cond ((eq objectsp 't)
	     (or (caddr early-method)
		 (setf (caddr early-method)
		       (mapcar #'find-class (cadddr (cadddr early-method))))))
	    (t
	     (cadddr (cadddr early-method))))
      (error "~S is not an early-method." early-method)))

(defun early-method-qualifiers (early-method)
  (cadr (cadddr early-method)))

(defun early-add-named-method (generic-function-name
			       qualifiers
			       specializers
			       arglist
			       function
			       &rest options)
  (declare (ignore options))
  (let* ((gf (ensure-generic-function generic-function-name))
	 (existing
	   (dolist (m (early-gf-methods gf))
	     (when (and (equal (early-method-specializers m) specializers)
			(equal (early-method-qualifiers m) qualifiers))
	       (return m))))
	 (new (make-a-method 'standard-method
			     qualifiers
			     arglist
			     specializers
			     function
			     ())))
    (when existing (remove-method gf existing))
    (add-method gf new)))

;;;
;;; This is the early version of add-method.  Later this will become a
;;; generic function.  See fix-early-generic-functions which has special
;;; knowledge about add-method.
;;;
(defun add-method (generic-function method)
  (when (not (fsc-instance-p generic-function))
    (error "Early add-method didn't get a funcallable instance."))
  (when (not (and (listp method) (eq (car method) :early-method)))
    (error "Early add-method didn't get an early method."))
  (push method (early-gf-methods generic-function))
  (early-update-discriminator-code generic-function))

;;;
;;; This is the early version of remove method.
;;;
(defun remove-method (generic-function method)
  (when (not (fsc-instance-p generic-function))
    (error "Early remove-method didn't get a funcallable instance."))
  (when (not (and (listp method) (eq (car method) :early-method)))
    (error "Early remove-method didn't get an early method."))
  (setf (early-gf-methods generic-function)
	(remove method (early-gf-methods generic-function)))
  (early-update-discriminator-code generic-function))

;;;
;;; And the early version of get-method.
;;;
(defun get-method (generic-function qualifiers specializers
				    &optional (errorp t))
  (if (early-gf-p generic-function)
      (or (dolist (m (early-gf-methods generic-function))
	    (when (and (or (equal (early-method-specializers m nil)
				  specializers)
			   (equal (early-method-specializers m 't)
				  specializers))
		       (equal (early-method-qualifiers m) qualifiers))
	      (return m)))
	  (if errorp
	      (error "Can't get early method.")
	      nil))
      (real-get-method generic-function qualifiers specializers errorp)))

(defun early-update-discriminator-code (generic-function)
  (let* ((methods (early-gf-methods generic-function))
	 (early-dfun
	   (cond ((null methods)
		  #'(lambda (&rest ignore)
		      (declare (ignore ignore))
		      (error "Called an early generic-function that ~
                              has no methods?")))
		 ((null (cdr methods))
		  ;; If there is only one method, just use that method's
		  ;; function.  This corresponds to the important fact
		  ;; that early generic-functions with only one method
		  ;; always call that method when they are called.  If
		  ;; there is more than one method, we have to install
		  ;; a simple little discriminator-code for this generic
		  ;; function.
		  (cadr (car methods)))
		 (t
		  (set-function-name 
		   #'(lambda (&rest args) (early-dfun methods args))
		   (early-gf-name generic-function))))))
    (set-funcallable-instance-function generic-function early-dfun)
    (setf (early-gf-discriminator-code generic-function) early-dfun)))

(defun early-get-cpl (object)
  (bootstrap-get-slot 'std-class
		      (class-of object)
		      'class-precedence-list))

(defun early-sort-methods (list args)
  (if (null (cdr list))
      list
      (sort list
	    #'(lambda (specls-1 specls-2)
		(iterate ((s1 (list-elements specls-1))
			  (s2 (list-elements specls-2))
			  (a (list-elements args)))
		  (cond ((eq s1 s2))
			((eq s2 *the-class-t*) (return t))
			((eq s1 *the-class-t*) (return nil))
			(t (return (memq s2 (memq s1 (early-get-cpl a))))))))
	    :key #'(lambda (em) (early-method-specializers em t)))))

(defun early-dfun (methods args)
  (let ((primary ())
	(before ())
	(after ())
	(around ()))
    (dolist (method methods)
      (let* ((specializers (early-method-specializers method t))
	     (qualifiers (early-method-qualifiers method))
	     (args args)
	     (specs specializers))
	(when (loop
		(when (or (null args)
			  (null specs))
		  ;; If we are out of specs, then we must be in the optional,
		  ;; rest or keywords arguments.  This method is applicable
		  ;; to these arguments.  Return T.
		  (return t))
		(let ((arg (pop args))
		      (spec (pop specs)))
		  (unless (or (eq spec *the-class-t*)
			      (memq spec (early-get-cpl arg)))
		    (return nil))))
	  (cond ((null qualifiers) (push method primary))
		((equal qualifiers '(:before)) (push method before))
		((equal qualifiers '(:after))  (push method after))
		((equal qualifiers '(:around)) (push method around))
		(t
		 (error "Unrecognized qualifer in early method."))))))
    (setq primary (early-sort-methods primary args)
	  before  (early-sort-methods before  args)
	  after   (early-sort-methods after   args)
	  around  (early-sort-methods around  args))
    (flet ((do-main-combined-method (&rest arguments)
             (dolist (m before) (apply (cadr m) arguments))
             (multiple-value-prog1
               (let ((*next-methods* (mapcar #'car (cdr primary))))
                 (apply (cadar primary) arguments))
               (dolist (m after) (apply (cadr m) arguments)))))
      (if (null around)
          (apply #'do-main-combined-method args)
          (let ((*next-methods*
                  (append (mapcar #'cadr (cdr around))
                          (list #'do-main-combined-method))))
            (apply (cadar around) args))))))

(defvar *fegf-debug-p* nil)

(defun fix-early-generic-functions (&optional (noisyp *fegf-debug-p*))
  (allocate-instance (find-class 'standard-generic-function)) ;Be sure this
					                      ;class has an
					                      ;instance.
  (let* ((class (find-class 'standard-generic-function))
	 (wrapper (class-wrapper class))
	 (n-static-slots (class-no-of-instance-slots class))
	 (default-initargs (default-initargs class ()))
	 #+Lucid
	 (lucid::*redefinition-action* nil))
    (flet ((fix-structure (gf)
	     (let ((static-slots
		    (%allocate-static-slot-storage--class n-static-slots)))
	       (setf (fsc-instance-wrapper gf) wrapper
		     (fsc-instance-slots gf) static-slots))))
      ;; Rearrange *early-generic-functions* to speed up fix-early-generic-functions.
      (let ((accessors nil))
	(dolist (early-gf-spec *early-generic-functions*)
	  (when (every #'early-method-standard-accessor-p
		       (early-gf-methods (gdefinition early-gf-spec)))
	    (push early-gf-spec accessors)))
	(dolist (spec (nconc accessors
			     '(accessor-method-slot-name
			       generic-function-methods
			       method-specializers
			       specializerp
			       specializer-type
			       specializer-class
			       slot-definition-location
			       slot-definition-name
			       class-slots
			       gf-arg-info
			       class-precedence-list
			       slot-boundp-using-class
			       (setf slot-value-using-class)
			       slot-value-using-class)))
	  (setq *early-generic-functions* 
		(cons spec (delete spec *early-generic-functions* :test #'equal)))))
      (dolist (early-gf-spec *early-generic-functions*)
	(when noisyp (format t "~&~S..." early-gf-spec))
	(let* ((early-gf (gdefinition early-gf-spec))
	       (early-static-slots
		(fsc-instance-slots early-gf))
	       (early-discriminator-code nil)
	       (early-methods nil)
	       (aborted t))
	  (flet ((trampoline (&rest args)
		   (apply early-discriminator-code args)))
	    (if (not (listp early-static-slots))
		(when noisyp (format t "already fixed?"))
		(unwind-protect
		     (progn
		       (setq early-discriminator-code
			     (early-gf-discriminator-code early-gf))
		       (setq early-methods
			     (early-gf-methods early-gf))
		       (setf (gdefinition early-gf-spec) #'trampoline)
		       (when noisyp (format t "trampoline..."))
		       (fix-structure early-gf)
		       (when noisyp (format t "fixed..."))
		       (apply #'initialize-instance early-gf
			      :name early-gf-spec default-initargs)
		       (loop
			(when (null early-methods) (return nil))
			(let ((early-method (pop early-methods)))
			  (destructuring-bind
				(class quals lambda-list specs fn doc slot-name)
			      (cadddr early-method)
			    (setq specs (early-method-specializers early-method t))
			    (let ((method (real-make-a-method class
							      quals
							      lambda-list
							      specs
							      fn
							      doc
							      slot-name)))
			      (real-add-method early-gf method)
			      (when noisyp (format t "m"))))))
		       (setf (generic-function-name early-gf) early-gf-spec)
		       (setq aborted nil))
		  (setf (gdefinition early-gf-spec) early-gf)
		  (when noisyp (format t "."))
		  (when aborted
		    (setf (fsc-instance-slots early-gf)
			  early-static-slots))))))))
	  
    (dolist (fns *early-functions*)
      (setf (symbol-function (car fns)) (symbol-function (caddr fns))))
      
    (dolist (fixup *generic-function-fixups*)
      (let ((fspec (car fixup))
	    (methods (cdr fixup))
	    (gf (make-instance 'standard-generic-function)))
	(set-function-name gf fspec)
	(setf (generic-function-name gf) fspec)
	(loop 
	 (when (null methods) (return nil))
	 (let ((method (pop methods)))
	   (destructuring-bind (lambda-list specializers method-fn-name)
	       method
	     (let* ((fn (if method-fn-name
			    (symbol-function method-fn-name)
			    (symbol-function fspec)))
		    (method (make-a-method 'standard-method
					   ()
					   lambda-list
					   specializers
					   fn
					   nil)))
	       (real-add-method gf method)))))
	(setf (gdefinition fspec) gf)))))


;;;
;;; parse-defmethod is used by defmethod to parse the &rest argument into
;;; the 'real' arguments.  This is where the syntax of defmethod is really
;;; implemented.
;;; 
(defun parse-defmethod (cdr-of-form)
  ;;(declare (values name qualifiers specialized-lambda-list body))
  (let ((name (pop cdr-of-form))
	(qualifiers ())
	(spec-ll ()))
    (loop (if (and (car cdr-of-form) (atom (car cdr-of-form)))
	      (push (pop cdr-of-form) qualifiers)
	      (return (setq qualifiers (nreverse qualifiers)))))
    (setq spec-ll (pop cdr-of-form))
    (values name qualifiers spec-ll cdr-of-form)))

(defun parse-specializers (specializers)
  (flet ((parse (spec)
	   (let ((result (specializer-from-type spec)))
	     (if (specializerp result)
		 result
		 (if (symbolp spec)
		     (error "~S used as a specializer,~%~
                             but is not the name of a class."
			    spec)
		     (error "~S is not a legal specializer." spec))))))
    (mapcar #'parse specializers)))

(defun unparse-specializers (specializers-or-method)
  (if (listp specializers-or-method)
      (flet ((unparse (spec)
	       (if (specializerp spec)
                   (let ((type (specializer-type spec)))
                     (if (and (consp type)
                              (eq (car type) 'class))
                         (let* ((class (cadr type))
                                (class-name (class-name class)))
                           (if (eq class (find-class class-name nil))
                               class-name
                               type))
                         type))
		   (error "~S is not a legal specializer." spec))))
	(mapcar #'unparse specializers-or-method))
      (unparse-specializers (method-specializers specializers-or-method))))

(defun parse-method-or-spec (spec &optional (errorp t))
  ;;(declare (values generic-function method method-name))
  (let (gf method name temp)
    (if (method-p spec)	
	(setq method spec
	      gf (method-generic-function method)
	      temp (and gf (generic-function-name gf))
	      name (if temp
		       (intern-function-name
			 (make-method-spec temp
					   (method-qualifiers method)
					   (unparse-specializers
					     (method-specializers method))))
		       (make-symbol (format nil "~S" method))))
	(multiple-value-bind (gf-spec quals specls)
	    (parse-defmethod spec)
	  (and (setq gf (and (or errorp (gboundp gf-spec))
			     (gdefinition gf-spec)))
	       (let ((nreq (compute-discriminating-function-arglist-info gf)))
		 (setq specls (append (parse-specializers specls)
				      (make-list (- nreq (length specls))
						 :initial-element
						 *the-class-t*)))
		 (and 
		   (setq method (get-method gf quals specls errorp))
		   (setq name
			 (intern-function-name (make-method-spec gf-spec
								 quals
								 specls))))))))
    (values gf method name)))



(defun extract-parameters (specialized-lambda-list)
  (multiple-value-bind (parameters ignore1 ignore2)
      (parse-specialized-lambda-list specialized-lambda-list)
    (declare (ignore ignore1 ignore2))
    parameters))

(defun extract-lambda-list (specialized-lambda-list)
  (multiple-value-bind (ignore1 lambda-list ignore2)
      (parse-specialized-lambda-list specialized-lambda-list)
    (declare (ignore ignore1 ignore2))
    lambda-list))

(defun extract-specializer-names (specialized-lambda-list)
  (multiple-value-bind (ignore1 ignore2 specializers)
      (parse-specialized-lambda-list specialized-lambda-list)
    (declare (ignore ignore1 ignore2))
    specializers))

(defun extract-required-parameters (specialized-lambda-list)
  (multiple-value-bind (ignore1 ignore2 ignore3 required-parameters)
      (parse-specialized-lambda-list specialized-lambda-list)
    (declare (ignore ignore1 ignore2 ignore3))
    required-parameters))

(defun parse-specialized-lambda-list (arglist &optional post-keyword)
  ;;(declare (values parameters lambda-list specializers required-parameters))
  (let ((arg (car arglist)))
    (cond ((null arglist) (values nil nil nil nil))
	  ((eq arg '&aux)
	   (values nil arglist nil))
	  ((memq arg lambda-list-keywords)
	   (unless (memq arg '(&optional &rest &key &allow-other-keys &aux))
	     ;; Warn about non-standard lambda-list-keywords, but then
	     ;; go on to treat them like a standard lambda-list-keyword
	     ;; what with the warning its probably ok.
	     (warn "Unrecognized lambda-list keyword ~S in arglist.~%~
                    Assuming that the symbols following it are parameters,~%~
                    and not allowing any parameter specializers to follow~%~
                    to follow it."
		   arg))
	   ;; When we are at a lambda-list-keyword, the parameters don't
	   ;; include the lambda-list-keyword; the lambda-list does include
	   ;; the lambda-list-keyword; and no specializers are allowed to
	   ;; follow the lambda-list-keywords (at least for now).
	   (multiple-value-bind (parameters lambda-list)
	       (parse-specialized-lambda-list (cdr arglist) t)
	     (values parameters
		     (cons arg lambda-list)
		     ()
		     ())))
	  (post-keyword
	   ;; After a lambda-list-keyword there can be no specializers.
	   (multiple-value-bind (parameters lambda-list)
	       (parse-specialized-lambda-list (cdr arglist) t)	       
	     (values (cons (if (listp arg) (car arg) arg) parameters)
		     (cons arg lambda-list)
		     ()
		     ())))
	  (t
	   (multiple-value-bind (parameters lambda-list specializers required)
	       (parse-specialized-lambda-list (cdr arglist))
	     (values (cons (if (listp arg) (car arg) arg) parameters)
		     (cons (if (listp arg) (car arg) arg) lambda-list)
		     (cons (if (listp arg) (cadr arg) 't) specializers)
		     (cons (if (listp arg) (car arg) arg) required)))))))


(eval-when (load eval)
  (setq *boot-state* 'early))


#-cmu ;; CMUCL Has a real symbol-macrolet
(progn
(defmacro symbol-macrolet (bindings &body body &environment env)
  (let ((specs (mapcar #'(lambda (binding)
			   (list (car binding)
				 (variable-lexical-p (car binding) env)
				 (cadr binding)))
		       bindings)))
    (walk-form `(progn ,@body)
	       env
	       #'(lambda (f c e)
		   (expand-symbol-macrolet-internal specs f c e)))))

(defun expand-symbol-macrolet-internal (specs form context env)
  (let ((entry nil))
    (cond ((not (eq context :eval)) form)
	  ((symbolp form)
	   (if (and (setq entry (assoc form specs))
		    (eq (cadr entry) (variable-lexical-p form env)))
	       (caddr entry)
	       form))
	  ((not (listp form)) form)
	  ((member (car form) '(setq setf))
	   ;; Have to be careful.  We must only convert the form to a SETF
	   ;; form when we convert one of the 'logical' variables to a form
	   ;; Otherwise we will get looping in implementations where setf
	   ;; is a macro which expands into setq.
	   (let ((kind (car form)))
	     (labels ((scan-setf (tail)
			(if (null tail)
			    nil
			    (walker::relist*
			      tail
			      (if (and (setq entry (assoc (car tail) specs))
				       (eq (cadr entry)
					   (variable-lexical-p (car tail)
							       env)))
				  (progn (setq kind 'setf)
					 (caddr entry))
				  (car tail))
			      (cadr tail)
			      (scan-setf (cddr tail))))))
	       (let (new-tail)
		 (setq new-tail (scan-setf (cdr form)))
		 (walker::recons form kind new-tail)))))
	  ((eq (car form) 'multiple-value-setq)
	   (let* ((vars (cadr form))
		  (gensyms (mapcar #'(lambda (i) (declare (ignore i)) (gensym))
				   vars)))
	     `(multiple-value-bind ,gensyms 
		  ,(caddr form)
		.,(reverse (mapcar #'(lambda (v g) `(setf ,v ,g))
				   vars
				   gensyms)))))
	  (t form))))
)

(defmacro with-slots (slots instance &body body)
  (let ((in (gensym)))
    `(let ((,in ,instance))
       #+cmu (declare (ignorable ,in))
       ,@(let ((instance (if (and (consp instance) (eq (car instance) 'the))
                             (third instance)
                             instance)))
	   (and (symbolp instance)
                `((declare (variable-rebinding ,in ,instance)))))
       ,in
       (symbol-macrolet ,(mapcar #'(lambda (slot-entry)
				     (let ((variable-name 
					    (if (symbolp slot-entry)
						slot-entry
						(car slot-entry)))
					   (slot-name
					    (if (symbolp slot-entry)
						slot-entry
						(cadr slot-entry))))
				       `(,variable-name
					  (slot-value ,in ',slot-name))))
				 slots)
			,@body))))

(defmacro with-accessors (slots instance &body body)
  (let ((in (gensym)))
    `(let ((,in ,instance))
       #+cmu (declare (ignorable ,in))
       ,@(let ((instance (if (and (consp instance) (eq (car instance) 'the))
                             (third instance)
                             instance)))
	   (and (symbolp instance)
                `((declare (variable-rebinding ,in ,instance)))))
       ,in
       (symbol-macrolet ,(mapcar #'(lambda (slot-entry)
				   (let ((variable-name (car slot-entry))
					 (accessor-name (cadr slot-entry)))
				     `(,variable-name
				        (,accessor-name ,in))))
			       slots)
          ,@body))))



