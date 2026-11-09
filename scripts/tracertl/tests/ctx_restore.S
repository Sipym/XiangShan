/*
 * FP context status restored from memory, the way the checkpoint
 * restorer does it: mstatus is loaded from a data word and written with csrw,
 * then FP instructions run. TraceRTL does not load the program
 * image, so the RTL sees a different loaded value than NEMU did.
 */
#include "common.h"

TEST_BEGIN
  .option norvc
  la t0, saved_mstatus
  ld t1, 0(t0)
  csrw mstatus, t1
  li s0, 32                     /* iterations */
  la s1, buf
loop:
  fcvt.d.l f1, s0
  fadd.d f0, f0, f1
  fsd f0, 0(s1)
  fld f2, 0(s1)
  fmul.d f3, f2, f1
  fsd f3, 0(s1)
  addi s0, s0, -1
  bnez s0, loop
  TEST_PASS

TEST_END

  .data
  .align 3
saved_mstatus:
  .dword MSTATUS_MPP | MSTATUS_FS
  .align 3
buf:
  .zero 8
