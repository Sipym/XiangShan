/*
 * Interrupts: supervisor software interrupt raised through mip.SSIP and
 * machine timer interrupt raised through CLINT mtimecmp, both taken in M-mode
 * with a vectored mtvec; an S-mode software interrupt delegated through
 * mideleg; and wfi with a pending-but-globally-disabled interrupt, which must
 * fall through.
 */
#include "common.h"

#define CAUSE_INTR_SSI 1
#define MIP_SSIP       0x2
#define MSTATUS_SIE    0x2

TEST_BEGIN
  .option norvc
  la t0, vec_table
  ori t0, t0, 1                 /* vectored */
  csrw mtvec, t0
  li s0, 8                      /* iterations */
  li s1, 0                      /* software interrupts taken */
  li s2, 0                      /* timer interrupts taken */
  li s3, 0                      /* S-mode software interrupts taken */
  li t0, CLINT_MTIMECMP
  li t1, -1
  sd t1, 0(t0)

loop:
  /* software interrupt: taken right after the csrs that raises it */
  addi s4, s1, 1
  li t0, MIP_SSIP
  csrs mie, t0
  csrsi mstatus, MSTATUS_MIE
  csrs mip, t0
  csrci mstatus, MSTATUS_MIE
  bne s1, s4, fail_1

  /* timer interrupt: spin on mtime until the handler has run */
  li t0, MIP_MTIP
  csrs mie, t0
  li t0, CLINT_MTIMECMP
  sd zero, 0(t0)
  addi s5, s2, 1
  csrsi mstatus, MSTATUS_MIE
2:
  li t0, CLINT_MTIMECMP + 0x7ff8 /* mtime */
  ld t1, 0(t0)
  bne s2, s5, 2b
  csrci mstatus, MSTATUS_MIE

  /* wfi with a pending, enabled but globally masked interrupt falls through */
  li t0, MIP_SSIP
  csrs mip, t0
  wfi
  csrc mip, t0

  addi s0, s0, -1
  bnez s0, loop

  /* S-mode software interrupt delegated through mideleg */
  la t0, s_handler
  csrw stvec, t0
  li t0, MIP_SSIP
  csrw mideleg, t0
  csrs mie, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S
  csrs mstatus, t0
  la t0, s_entry
  csrw mepc, t0
  mret
s_entry:
  csrsi sstatus, MSTATUS_SIE
  li t0, MIP_SSIP
  csrs sip, t0
  csrci sstatus, MSTATUS_SIE
  li t0, 1
  bne s3, t0, fail_3
  ecall                         /* back to M through vec_table entry 0 */

  .align 2
vec_table:
  j exc_handler                 /* 0: exceptions */
  j ssi_handler                 /* 1: SSI */
  j fail_4                      /* 2 */
  j fail_4                      /* 3: MSI */
  j fail_4                      /* 4 */
  j fail_4                      /* 5: STI */
  j fail_4                      /* 6 */
  j mti_handler                 /* 7: MTI */

ssi_handler:
  csrr t0, mcause
  li t1, (1 << 63) | CAUSE_INTR_SSI
  bne t0, t1, fail_5
  li t0, MIP_SSIP
  csrc mip, t0
  addi s1, s1, 1
  mret

mti_handler:
  csrr t0, mcause
  li t1, (1 << 63) | CAUSE_INTR_MTI
  bne t0, t1, fail_6
  li t0, CLINT_MTIMECMP
  li t1, -1
  sd t1, 0(t0)
  addi s2, s2, 1
  mret

exc_handler:
  csrr t0, mcause
  li t1, CAUSE_ECALL_S
  bne t0, t1, fail_7
  TEST_PASS

  .align 2
s_handler:
  csrr t0, scause
  li t1, (1 << 63) | CAUSE_INTR_SSI
  bne t0, t1, fail_8
  li t0, MIP_SSIP
  csrc sip, t0
  addi s3, s3, 1
  sret

fail_1: TEST_FAIL(1)
fail_3: TEST_FAIL(3)
fail_4: TEST_FAIL(4)
fail_5: TEST_FAIL(5)
fail_6: TEST_FAIL(6)
fail_7: TEST_FAIL(7)
fail_8: TEST_FAIL(8)

TEST_END
