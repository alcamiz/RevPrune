<div align="center">

# Alpha-Beta Pruning for Reversi in CUDA

An implementation of alpha-bet pruning running on a CUDA gpu.
Uses built-in support for recursive functions, so it might not run
on all graphic cards.

This was designed for and tested in pedagogical machines provided by
the CS department at UT Austin.

Developed in 2023

</div>

## Building

To compile, run:

```
make all
```

To execute, run:

```
./pruning -d 10 -x 32 -y 32 -t
```

Execution Options:
-d: depth of game tree
-x: width of game board
-y: height of game board
-t: Option to activate threaded implementation

Note that x and y must be powers of 2 to satisfy the rules of Reversi/Othello.
Otherwise the initial piece placement can't be achieved.
