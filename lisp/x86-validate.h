/*
 *
 * This code was written as part of the CMU Common Lisp project at
 * Carnegie Mellon University, and has been placed in the public domain.
 *
 *  $Header: /Volumes/share2/src/cmucl/cvs2git/cvsroot/src/lisp/x86-validate.h,v 1.7 1998/08/30 04:56:49 dtc Exp $
 *
 */

/*
 * Address map:
 *
 *  FreeBSD:
 *	0x00000000->0x0E000000 224M C program and memory allocation.
 *	0x0E000000->0x10000000  32M Foreign segment.
 *	0x10000000->0x20000000 256M Read-Only Space.
 *	0x20000000->0x28000000 128M Reserved for shared libraries.
 *	0x28000000->0x38000000 256M Static Space.
 *	0x38000000->0x40000000 128M Binding stack growing up.
 *	0x40000000->0x48000000 128M Control stack growing down.
 *	0x48000000->0xC8000000 2GB  Dynamic Space.
 *	0xE0000000->           256M C stack - Alien stack.
 *  Linux:
 *	0x00000000->0x08000000 128M Unused.
 *	0x08000000->0x10000000 128M C program and memory allocation.
 *	0x10000000->0x20000000 256M Read-Only Space.
 *	0x20000000->0x28000000 128M Binding stack growing up.
 *	0x28000000->0x38000000 256M Static Space.
 *	0x38000000->0x40000000 128M Control stack growing down.
 *	0x40000000->0x48000000 128M Reserved for shared libraries.
 *	0x48000000->0xB8000000 1.75G Dynamic Space.
 *
 */

#define READ_ONLY_SPACE_START   (0x10000000)
#define READ_ONLY_SPACE_SIZE    (0x0ffff000) /* 256MB - 1 page */

#define STATIC_SPACE_START	(0x28000000)
#define STATIC_SPACE_SIZE	(0x0ffff000) /* 256MB - 1 page */

#ifdef __FreeBSD__
#define BINDING_STACK_START	(0x38000000)
#define BINDING_STACK_SIZE	(0x07fff000) /* 128MB - 1 page */
#define CONTROL_STACK_START	(0x40000000)
#define CONTROL_STACK_SIZE	(0x08000000) /* 128MB */
#endif

#ifdef __linux__
#define BINDING_STACK_START	(0x20000000)
#define BINDING_STACK_SIZE	(0x07fff000) /* 128MB - 1 page */
#define CONTROL_STACK_START	(0x30001000)
#define CONTROL_STACK_SIZE	(0x07fff000) /* 128MB - 1 page */
#endif

#define CONTROL_STACK_END	(CONTROL_STACK_START + CONTROL_STACK_SIZE)

/* Note that GENCGC only uses dynamic_space 0. */
#define DYNAMIC_0_SPACE_START	(0x48000000)
#ifdef GENCGC
#ifdef __FreeBSD__
#define DYNAMIC_SPACE_SIZE	(0x40000000) /* May be up to 2GB */
#endif
#ifdef __linux__
#define DYNAMIC_SPACE_SIZE	(0x40000000) /* May be up to 1.75GB */
#endif
#else
#define DYNAMIC_SPACE_SIZE	(0x04000000) /* 64MB */
#endif

#define DYNAMIC_1_SPACE_START	(DYNAMIC_0_SPACE_START + DYNAMIC_SPACE_SIZE)
