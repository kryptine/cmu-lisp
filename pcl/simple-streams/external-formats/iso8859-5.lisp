;;; -*- Mode: LISP; Syntax: ANSI-Common-Lisp; Package: STREAM -*-
;;;
;;; **********************************************************************
;;; This code was written by Paul Foley and has been placed in the public
;;; domain.
;;;
(ext:file-comment "$Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/pcl/simple-streams/external-formats/iso8859-5.lisp,v 1.1.2.1 2008/07/02 01:22:10 rtoy Exp $")

(defconstant +iso-8859-5+
  (make-array 96 :element-type '(unsigned-byte 16)
     :initial-contents #(160 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034
                         1035 1036 173 1038 1039 1040 1041 1042 1043 1044 1045
                         1046 1047 1048 1049 1050 1051 1052 1053 1054 1055 1056
                         1057 1058 1059 1060 1061 1062 1063 1064 1065 1066 1067
                         1068 1069 1070 1071 1072 1073 1074 1075 1076 1077 1078
                         1079 1080 1081 1082 1083 1084 1085 1086 1087 1088 1089
                         1090 1091 1092 1093 1094 1095 1096 1097 1098 1099 1100
                         1101 1102 1103 8470 1105 1106 1107 1108 1109 1110 1111
                         1112 1113 1114 1115 1116 167 1118 1119)))

(define-external-format :iso8859-5 (:iso8859-2)
  ((table +iso-8859-5+)))