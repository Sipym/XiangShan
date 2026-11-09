/*
 * FP context status set up by an immediate CSR write: mstatus.FS is enabled
 * with csrs, then FP instructions run and dirty it.
 * Run with --skip-traceinstr past the csrs to start TraceRTL with FS in
 * their reset state, the way a mid-program trace does.
 */
#include "common.h"

TEST_BEGIN
  .option norvc
  li t0, MSTATUS_FS_INIT
  csrs mstatus, t0
  .globl ctx_body
ctx_body:
  li s0, 32                     /* iterations */
  la s1, buf
  fcvt.d.l f0, s0
  fsrmi 0
loop:
  fcvt.d.l f1, s0
  fadd.d f0, f0, f1
  fmul.d f2, f0, f1
  fsd f2, 0(s1)
  fld f3, 0(s1)
  feq.d t0, f2, f3
  csrr t1, fflags
  addi s0, s0, -1
  bnez s0, loop
  TEST_PASS

TEST_END

  .data
  .align 3
buf:
  .zero 8
