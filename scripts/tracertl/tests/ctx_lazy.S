/*
 * Lazy FP context switch: with mstatus.FS Off an FP instruction traps as
 * illegal, the handler enables FP and returns to the same instruction, which
 * then executes. Both an FP convert and an FP move take the trap.
 */
#include "common.h"

TEST_BEGIN
  .option norvc
  la t0, lazy_handler
  csrw mtvec, t0
  li s0, 8                      /* iterations */
  li s2, 0                      /* traps taken */
  la s1, buf
loop:
  li t0, MSTATUS_FS
  csrc mstatus, t0
  fcvt.d.l f1, s0               /* traps: FS Off */
  fadd.d f0, f0, f1
  fsd f0, 0(s1)
  li t0, MSTATUS_FS
  csrc mstatus, t0
  fmv.d.x f2, s0                /* traps: FS Off */
  fadd.d f2, f2, f1
  addi s0, s0, -1
  bnez s0, loop
  li t0, 16
  bne s2, t0, fail_1
  la t0, test_unexpected_trap
  csrw mtvec, t0
  TEST_PASS

  .align 2
lazy_handler:
  csrr t1, mcause
  li t2, CAUSE_ILLEGAL
  bne t1, t2, fail_2
  addi s2, s2, 1
  li t1, MSTATUS_FS_INIT
  csrs mstatus, t1
  mret

fail_1: TEST_FAIL(1)
fail_2: TEST_FAIL(2)

TEST_END

  .data
  .align 3
buf:
  .zero 8
