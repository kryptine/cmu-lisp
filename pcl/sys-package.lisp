

;;; Definitions for package SLOT-ACCESSOR-NAME of type ESTABLISH
(LISP::IN-PACKAGE "SLOT-ACCESSOR-NAME" :USE LISP::NIL :NICKNAMES
    '("S-A-N"))

;;; Definitions for package PCL of type ESTABLISH
(LISP::IN-PACKAGE "PCL" :USE LISP::NIL)

;;; Definitions for package ITERATE of type ESTABLISH
(LISP::IN-PACKAGE "ITERATE" :USE LISP::NIL)

;;; Definitions for package WALKER of type ESTABLISH
(LISP::IN-PACKAGE "WALKER" :USE LISP::NIL)

;;; Definitions for package DSYS of type ESTABLISH
(LISP::IN-PACKAGE "DSYS" :USE LISP::NIL)

;;; Definitions for package SLOT-ACCESSOR-NAME of type EXPORT
(LISP::IN-PACKAGE "SLOT-ACCESSOR-NAME" :USE 'LISP::NIL :NICKNAMES
    '("S-A-N"))
(LISP::IMPORT 'LISP::NIL)
(LISP::EXPORT 'LISP::NIL)

;;; Definitions for package PCL of type EXPORT
(LISP::IN-PACKAGE "PCL" :USE '("LISP" "ITERATE" "WALKER"))
(LISP::IMPORT 'LISP::NIL)
(LISP::EXPORT
    '(PCL::CLASS-OF PCL::NO-APPLICABLE-METHOD
         PCL::ENSURE-GENERIC-FUNCTION PCL::SLOT-MISSING
         PCL::CALL-NEXT-METHOD PCL::MAKE-INSTANCES-OBSOLETE
         PCL::METHOD-QUALIFIERS PCL::STANDARD-CLASS PCL::PRINT-OBJECT
         PCL::STRUCTURE-CLASS PCL::MAKE-INSTANCE PCL::DEFGENERIC
         PCL::REINITIALIZE-INSTANCE PCL::STANDARD-METHOD
         PCL::FUNCTION-KEYWORDS PCL::STANDARD PCL::FIND-METHOD
         PCL::INITIALIZE-INSTANCE PCL::GENERIC-FLET PCL::SLOT-UNBOUND
         PCL::SYMBOL-MACROLET PCL::ADD-METHOD PCL::WITH-ACCESSORS
         PCL::SLOT-BOUNDP PCL::SHARED-INITIALIZE
         PCL::STANDARD-GENERIC-FUNCTION PCL::WITH-ADDED-METHODS
         PCL::NEXT-METHOD-P PCL::SLOT-VALUE PCL::STANDARD-OBJECT
         PCL::BUILT-IN-CLASS PCL::NO-NEXT-METHOD PCL::SLOT-MAKUNBOUND
         PCL::INVALID-METHOD-ERROR PCL::METHOD-COMBINATION-ERROR
         PCL::SLOT-EXISTS-P PCL::WITH-SLOTS
         PCL::DEFINE-METHOD-COMBINATION PCL::CHANGE-CLASS
         PCL::DEFMETHOD PCL::UPDATE-INSTANCE-FOR-DIFFERENT-CLASS
         PCL::UPDATE-INSTANCE-FOR-REDEFINED-CLASS PCL::REMOVE-METHOD
         PCL::CALL-METHOD PCL::CLASS-NAME PCL::FIND-CLASS PCL::DEFCLASS
         PCL::COMPUTE-APPLICABLE-METHODS PCL::GENERIC-LABELS))

;;; Definitions for package ITERATE of type EXPORT
(LISP::IN-PACKAGE "ITERATE" :USE '("WALKER" "LISP"))
(LISP::IMPORT 'LISP::NIL)
(LISP::EXPORT
    '(ITERATE::SUMMING ITERATE::MINIMIZING ITERATE::PLIST-ELEMENTS
         ITERATE::ITERATE* ITERATE::MAXIMIZING ITERATE::LIST-TAILS
         ITERATE::*ITERATE-WARNINGS* ITERATE::GATHERING
         ITERATE::EACHTIME ITERATE::ELEMENTS ITERATE::GATHER
         ITERATE::LIST-ELEMENTS ITERATE::WHILE ITERATE::ITERATE
         ITERATE::UNTIL ITERATE::JOINING ITERATE::COLLECTING
         ITERATE::WITH-GATHERING ITERATE::INTERVAL))

;;; Definitions for package WALKER of type EXPORT
(LISP::IN-PACKAGE "WALKER" :USE '("LISP"))
(LISP::IMPORT 'LISP::NIL)
(LISP::EXPORT
    '(WALKER::DEFINE-WALKER-TEMPLATE WALKER::*VARIABLE-DECLARATIONS*
         WALKER::NESTED-WALK-FORM WALKER::VARIABLE-DECLARATION
         WALKER::VARIABLE-LEXICAL-P WALKER::VARIABLE-SPECIAL-P
         WALKER::WALK-FORM WALKER::VARIABLE-GLOBALLY-SPECIAL-P))

;;; Definitions for package DSYS of type EXPORT
(LISP::IN-PACKAGE "DSYS" :USE '("LISP"))
(LISP::IMPORT '(USER::*INITIALIZE-SYSTEMS-P* USER::INITIALIZE-SYSTEMS))
(LISP::EXPORT
    '(DSYS::SOURCE-FILE DSYS::DIRECTORYP DSYS::SET-SYSTEM-SOURCE-FILE
         DSYS::*DEFAULT-FASL-PATHNAME-TYPE* DSYS::LOAD-TRUENAME
         DSYS::READ-DISTRIBUTION DSYS::SUBFILE DSYS::LOAD-FILE
         DSYS::DIRECTORY-PATHNAME-AS-FILE DSYS::*SYSTEMS-BANNER*
         DSYS::FIND-SYSTEM DSYS::COMPILE-SYSTEM-FILE
         DSYS::LOAD-FILE-FILE DSYS::LOAD-SYSTEM DSYS::MAP-SYSTEM-ALL
         DSYS::*SKIP-LOAD-IF-LOADED-P* DSYS::OBJECT-FILE
         DSYS::ADD-SYSTEM-LOCATION-DIRECTORY
         DSYS::COMPILE-FILE-PATHNAME
         DSYS::*DSYS-SHADOWING-IMPORT-SYMBOLS*
         DSYS::*DEFAULT-LISP-PATHNAME-TYPE*
         DSYS::*DEFAULT-DIRECTORY-STRING* DSYS::DEFSYSTEM
         DSYS::CREATE-DIRECTORY DSYS::TYPE-FOR-DIRECTORY
         DSYS::*SYSTEM-LOCATION-DIRECTORY-LIST* DSYS::LOAD-SYSTEM-ALL
         DSYS::MAP-SYSTEM DSYS::GENERIC-PATHNAME
         DSYS::*SUBFILE-DEFAULT-ROOT-PATHNAME* DSYS::ENSURE-DIRECTORY
         USER::*INITIALIZE-SYSTEMS-P* DSYS::WRITE-DISTRIBUTION
         DSYS::*SKIP-COMPILE-FILE-FWD* DSYS::DEFAULT-PATHNAME-DEFAULTS
         DSYS::COMPILE-SYSTEM DSYS::COMPILE-SYSTEM-ALL
         DSYS::LOAD-SYSTEM-FILE DSYS::PATHNAME-AS-DIRECTORY
         USER::INITIALIZE-SYSTEMS))

;;; Definitions for package SLOT-ACCESSOR-NAME of type SHADOW
(LISP::IN-PACKAGE "SLOT-ACCESSOR-NAME")
(LISP::SHADOW 'LISP::NIL)
(LISP::SHADOWING-IMPORT 'LISP::NIL)
(LISP::IMPORT 'LISP::NIL)

;;; Definitions for package PCL of type SHADOW
(LISP::IN-PACKAGE "PCL")
(LISP::SHADOW '(PCL::DOTIMES PCL::DOCUMENTATION))
(LISP::SHADOWING-IMPORT 'LISP::NIL)
(LISP::IMPORT '(SYSTEM::STRUCTUREP))

;;; Definitions for package ITERATE of type SHADOW
(LISP::IN-PACKAGE "ITERATE")
(LISP::SHADOW 'LISP::NIL)
(LISP::SHADOWING-IMPORT 'LISP::NIL)
(LISP::IMPORT 'LISP::NIL)

;;; Definitions for package WALKER of type SHADOW
(LISP::IN-PACKAGE "WALKER")
(LISP::SHADOW 'LISP::NIL)
(LISP::SHADOWING-IMPORT 'LISP::NIL)
(LISP::IMPORT 'LISP::NIL)

;;; Definitions for package DSYS of type SHADOW
(LISP::IN-PACKAGE "DSYS")
(LISP::SHADOW
    '(DSYS::MERGE-PATHNAMES DSYS::MAKE-PATHNAME DSYS::PATHNAME-HOST
         DSYS::PATHNAME-DEVICE DSYS::PATHNAME-DIRECTORY
         DSYS::PATHNAME-NAME DSYS::PATHNAME-TYPE
         DSYS::PATHNAME-VERSION))
(LISP::SHADOWING-IMPORT 'LISP::NIL)
(LISP::IMPORT
    '(USER::*INITIALIZE-SYSTEMS-P* USER::INITIALIZE-SYSTEMS
         PCL::*PATHNAME-EXTENSIONS*
         USER::*CHOOSE-SOURCE-OR-OBJECT-FILE-ACTION*
         PCL::*DEFAULT-PATHNAME-EXTENSIONS*))

(in-package 'SI)
(export '(%structure-name
          %compiled-function-name
          %set-compiled-function-name))
(in-package 'pcl)
