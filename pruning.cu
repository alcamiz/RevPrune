#define _XOPEN_SOURCE 700

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <getopt.h>
#include <float.h>

#include "pruning.h"

int directions[9][2] = {{-1,-1}, {-1, 0}, {-1, 1},
                            { 0,-1}, { 0, 0}, { 0, 1},
                            { 1,-1}, { 1, 0}, { 1, 1}};

int seq_eval(board_t *board, state_t state) {
    int val = 0;
    for (int i = 0; i < board->dim_x; i++) {
        for (int j = 0; j < board->dim_y; j++) {
            if (board->states[i * board->dim_y + j] == state) {
                val += 1;
            }
        }
    }
    return val;
}

bool seq_valid(board_t *board, state_t state, int dir, int x, int y) {
    // printf("Here\n");

    int cur_x = x + directions[dir][0];
    int cur_y = y + directions[dir][1];

    while (BOUND(board->dim_x, cur_x) && BOUND(board->dim_y, cur_y)) {
            // printf("Enter %d %d %d\n", dir, directions[dir][0], directions[dir][1]);

        state_t cur_state = board->states[cur_x * board->dim_y + cur_y];

        if (cur_state == EMPTY) {
            return true;
        }
        if (cur_state == state) {
            return false;
        }

        cur_x += directions[dir][0];
        cur_y += directions[dir][1];
    }

    return false;
}

void seq_move(board_t *board, state_t state) {

    for (int x = 0; x < board->dim_x; x++) {
        for (int y = 0; y < board->dim_y; y++) {
    
            state_t cur_state = board->states[x * board->dim_y + y];
            if (cur_state != EMPTY) {
                continue;
            }

            for (int k = 0; k < 9; k++) {
                if (k == 4) continue;

                int i = x + directions[k][0];
                int j = y + directions[k][1];

                if (!BOUND(board->dim_x, i) || !BOUND(board->dim_y, j)) {
                    continue;
                }

                state_t new_state = board->states[i * board->dim_y + j];
                if (new_state != EMPTY && new_state != state) {
                    if (seq_valid(board, state, k, i, j)) {
                        board->states[x * board->dim_y + y] = VALID;
                    }
                }

            }

            // for (int i = MAX(x - 1, 0); i <= MIN(x + 1, board->dim_x); i++) {
            //     for (int j = MAX(y - 1, 0); j <= MIN(y + 1, board->dim_y); j++) {

            //         if (i == j) continue;
            //         state_t new_state = board->states[i * board->dim_y + j];

            //         if (new_state != EMPTY && new_state != state) {
            //             int dir = (i + 1) * 3 + (j + 1);
            //             if (seq_valid(board, state, dir, i, j)) {
            //                 board->states[x * board->dim_y + y] = VALID;
            //             }
            //         }
            //     }
            // }
        }
    }
}

int seq_traverse(board_t *board, int depth, int alpha, int beta, state_t state) {

    int count, value = 0;

    if (depth == 0) {
        return seq_eval(board, state);
    }

    // Mark valid moves
    seq_move(board, state);

    if (state == BLACK) {
        value = INT_MIN;

        // Iterate through all moves
        count = 0;
        for (int i = 0; i < board->dim_x; i++) {
            for (int j = 0; j < board->dim_y; j++) {

                if (count >= MAX_MOVES) {
                    goto end;
                }

                if (board->states[i] != VALID) continue;

                // Move piece
                board->states[i] = state;

                // Maximize score!
                value = MAX(value, seq_traverse(board, depth - 1, alpha, beta, WHITE));
                if (value > beta) {
                    goto end; // β cutoff
                }

                alpha = MAX(alpha, value);

                // Reverse move
                board->states[i] = state;

                count += 1;
            }
        }

    } else if (state == WHITE) {
        value = INT_MAX;

        // Iterate through all moves
        count = 0;
        for (int i = 0; i < board->dim_x; i++) {
            for (int j = 0; j < board->dim_y; j++) {

                if (count >= MAX_MOVES) {
                    goto end;
                }

                if (board->states[i] != VALID) continue;

                // Move piece
                board->states[i] = state;

                // Minimize score!
                value = MIN(value, seq_traverse(board, depth - 1, alpha, beta, BLACK));
                if (value < alpha) {
                    goto end; // α cutoff
                }

                beta = MIN(beta, value);

                // Reverse move
                board->states[i] = state;

                count += 1;
            }
        }
    }
    end: return value;
}

state_t *setup_board(int dim_x, int dim_y) {
    state_t *board = (state_t *) malloc(dim_x * dim_y * sizeof(state_t));
    for (int i = 0; i < dim_x * dim_y; i++) {
        board[i] = EMPTY;
    }
    
    int cur_x = dim_x / 2;
    int cur_y = dim_y / 2;

    board[cur_x * dim_y + cur_y] = BLACK;
    board[(cur_x - 1) * dim_y + (cur_y - 1)] = BLACK;

    board[(cur_x - 1) * dim_y + cur_y] = WHITE;
    board[cur_x * dim_y + (cur_y - 1)] = WHITE;

    return board;
}

float sequential_wrapper(int depth, int dim_x, int dim_y) {
    struct timespec tic, toc;

    state_t *states = setup_board(dim_x, dim_y);
    board_t board = {.dim_x = dim_x, .dim_y = dim_y, .states = states};

    clock_gettime(CLOCK_MONOTONIC, &tic);
    seq_traverse(&board, depth, INT_MIN, INT_MAX, BLACK);
    clock_gettime(CLOCK_MONOTONIC, &toc);

    return ((float) (toc.tv_sec - tic.tv_sec) * 1000.0f + (float) (toc.tv_nsec - tic.tv_nsec) / 1000000.0f);
}

int main(int argc, char *argv[]) {

    int id = -1, depth = 0, dim_x = 0, dim_y = 0;
    bool threaded = false;

    while (true) {
        id = getopt(argc, argv, "td:x:y:");

        if (id == -1)
            break;

        switch (id) {
            case 't':
                threaded = true;
                break;
            case 'd':
                depth = atoi(optarg);
                break;

            case 'x':
                dim_x = atoi(optarg);
                break;

            case 'y':
                dim_y = atoi(optarg);
                break;

            default:
                printf("GetOpt Failure\n");
                return EXIT_FAILURE;
        }
    }
    
    float time = 0.0;
    if (!threaded) {
        time = sequential_wrapper(depth, dim_x, dim_y);
    } else {
        time = parallel_prune(depth, dim_x, dim_y);
    }
    printf("%f\n", time);
}
