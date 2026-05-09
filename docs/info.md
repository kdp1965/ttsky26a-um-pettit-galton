<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This is a VGA Demo that draws a Galton peg board and "drops" soft paint balls (they "squish" at the bottom) onto the pegboard.  
It also has audio output when the balls hit the pegs if the Audio PMOD is connected (output on uio_out[7]).  The PMOD
can be used to speed up (up) or slow down (down) the ball drop speed, "Hold" the ball at the top prior to dropping using
gamepad "A" button, or try to coerce the ball to a certain direction using left / right (at properly timed locations).

## How to test

Connect the VGA Pmod and enjoy.  Optionally connect gamepad and/or audio PMODs.

## External hardware

VGA Pmod.
Optional Gamepad PMOD
Optional Audio PMOD (output is on uio_out[7]
