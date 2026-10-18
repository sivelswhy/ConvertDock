/* Configuration de LAME 3.100 pour macOS (remplace le config.h généré par ./configure). */
#ifndef LAME_CONFIG_H
#define LAME_CONFIG_H

/* SwiftPM définit DEBUG en mode debug : LAME afficherait alors ses traces internes. */
#undef DEBUG
#ifndef NDEBUG
#define NDEBUG 1
#endif

#define STDC_HEADERS 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_LIMITS_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_UNISTD_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STRCHR 1
#define HAVE_MEMCPY 1
#define PROTOTYPES 1

/* Optimisations portables (pas d'assembleur x86 : compatible Apple Silicon). */
#define TAKEHIRO_IEEE754_HACK 1
#define USE_FAST_LOG 1

/* Types entiers et flottants. */
#define SIZEOF_SHORT 2
#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_FLOAT 4
#define SIZEOF_DOUBLE 8
#define HAVE_INT8_T 1
#define HAVE_INT16_T 1
#define HAVE_INT32_T 1
#define HAVE_INT64_T 1
#define HAVE_UINT8_T 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT64_T 1
typedef float ieee754_float32_t;
#define HAVE_IEEE754_FLOAT32_T 1

#define PACKAGE "lame"
#define VERSION "3.100"

#endif
