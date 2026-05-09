![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout - Tiny Galton Board by Ken Pettit

- [Read the documentation for project](docs/info.md)

## This is a Demoscene project submitted to ttsky26a that presents a Galton Peg Board:

![](docs/galton_frame.png)

## External hardware

VGA Pmod.
Optional Gamepad PMOD
Optional Audio PMOD (output is on uio_out[7]

## Demo in action

- [View on VGA Plaground](https://vga-playground.com/?repo=https%3A%2F%2Fgithub.com%2Fkdp1965%2Fttsky26a-um-pettit-galton)

## Proof of randomness

The Tiny Galton demo uses 3 different length Linear Feedback Shift Registers (LFSRs) to generate "randomness" in 
deciding which way the ball will bounce as it hits a peg on the playing field.  Typical Galton Boards follow a
bell curve distribution where the balls will land.  Since this demo only collects balls up until any one bin reaches
a count of 63, it is difficult to see a full bell curve (the outer-most bins are only expected to receive a ball
drop once out of every 4096 balls).

To proove randomness in the LFSR mechanis, a C program simulating the ball-drop and LFSR calculations is included. 
It can be compiled as:

   gcc -o galton_lfsr_sim galton_lfsr_sim.c

A sample run simulating 100K ball drops is shown below in both table and bar chart format:

Balls simulated: 100000

 bin |   actual  |  expected | act/exp
 ----+-----------+-----------+--------
   0 |        28 |      24.4 |  1.147
   1 |       318 |     293.0 |  1.085
   2 |      1641 |    1611.3 |  1.018
   3 |      5301 |    5371.1 |  0.987
   4 |     11967 |   12085.0 |  0.990
   5 |     19282 |   19335.9 |  0.997
   6 |     22594 |   22558.6 |  1.002
   7 |     19596 |   19335.9 |  1.013
   8 |     11905 |   12085.0 |  0.985
   9 |      5405 |    5371.1 |  1.006
  10 |      1631 |    1611.3 |  1.012
  11 |       306 |     293.0 |  1.044
  12 |        26 |      24.4 |  1.065

Outer-bin summary:
  bin  0 (12 lefts):  28 hits   (first at ball #5986)
  bin 12 (12 rights): 26 hits   (first at ball #9805)

Histogram (max bin = 22594):
                            ███
                            ███
                            ███
                            ███
                        ▅▅▅ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                        ███ ███ ███
                    ▇▇▇ ███ ███ ███ ▆▆▆
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███
                    ███ ███ ███ ███ ███ ▁▁▁
                ███ ███ ███ ███ ███ ███ ███
                ███ ███ ███ ███ ███ ███ ███
                ███ ███ ███ ███ ███ ███ ███
                ███ ███ ███ ███ ███ ███ ███
            ▁▁▁ ███ ███ ███ ███ ███ ███ ███ ▁▁▁
            ███ ███ ███ ███ ███ ███ ███ ███ ███
    ___ ▃▃▃ ███ ███ ███ ███ ███ ███ ███ ███ ███ ▃▃▃ ___ 
    ----------------------------------------------------
    00  01  02  03  04  05  06  07  08  09  10  11  12


