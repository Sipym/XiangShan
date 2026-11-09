/*
 * Interrupts whose handler is the instruction right after the one that makes
 * the interrupt visible, so the interrupt redirect pc equals the sequential
 * pc. The interrupt is made visible either by setting mip.SSIP or by setting
 * mstatus.MIE with SSIP already pending.
 */
#include "common.h"

#define MIP_SSIP 0x2

TEST_BEGIN
  .option norvc
  li s0, 16                     /* iterations */
  li t0, MIP_SSIP
  csrs mie, t0

loop:
  /* raised by the mip write */
  la t0, 1f
  csrw mtvec, t0
  csrsi mstatus, MSTATUS_MIE
  li t0, MIP_SSIP
  csrs mip, t0
1:
  csrr t1, mcause
  bgez t1, fail_1               /* must be an interrupt */
  li t0, MIP_SSIP
  csrc mip, t0

  /* raised by enabling mstatus.MIE */
  la t0, 2f
  csrw mtvec, t0
  li t0, MIP_SSIP
  csrs mip, t0
  csrsi mstatus, MSTATUS_MIE
2:
  csrr t1, mcause
  bgez t1, fail_2
  li t0, MIP_SSIP
  csrc mip, t0

  /* mret re-enables MIE (MPIE=1) with SSIP pending: the interrupt is taken
   * at the mret target, which is also the handler */
  la t0, 3f
  csrw mtvec, t0
  csrw mepc, t0
  li t0, MSTATUS_MPP | MSTATUS_MPIE
  csrs mstatus, t0
  li t0, MIP_SSIP
  csrs mip, t0
  csrw mcause, zero
  mret
3:
  csrr t1, mcause
  bgez t1, fail_3
  li t0, MIP_SSIP
  csrc mip, t0

  addi s0, s0, -1
  bnez s0, loop

  csrci mstatus, MSTATUS_MIE
  la t0, test_unexpected_trap
  csrw mtvec, t0
  TEST_PASS

fail_1: TEST_FAIL(1)
fail_2: TEST_FAIL(2)
fail_3: TEST_FAIL(3)

TEST_END
