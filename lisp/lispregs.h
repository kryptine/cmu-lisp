/* $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/lisp/lispregs.h,v 1.7 2004/07/30 00:53:41 rtoy Exp $ */

#if defined(mips) || defined(irix)
#include "mips-lispregs.h"
#endif

#ifdef sparc
#include "sparc-lispregs.h"
#endif

#ifdef ibmrt
#include "rt-lispregs.h"
#endif

#ifdef i386
#include "x86-lispregs.h"
#endif

#ifdef __x86_64
#include "amd64-lispregs.h"
#endif

#ifdef parisc
#include "hppa-lispregs.h"
#endif

#ifdef alpha
#include "alpha-lispregs.h"
#endif

#ifdef ppc
#include "ppc-lispregs.h"
#endif

/* This matches the definition of sc-offset in code/debug-info.lisp */
#define SC_OFFSET(sc,offset) (((offset) << 5) | (sc))

/*
 * Macros to compute the SC_OFFSET value.  See read-var-integer and
 * sc-offset and friends in debug-info.lisp
 */
#define	SC_OFFSET_HI(sc, regnum)	((SC_OFFSET(sc,regnum)) >> 8)
#define	SC_OFFSET_LO(sc, regnum)	((SC_OFFSET(sc,regnum)) & 0xff)



#ifndef LANGUAGE_ASSEMBLY
extern char *lisp_register_names[];
#endif
