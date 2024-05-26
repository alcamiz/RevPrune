#ifndef __CUDACC__  
    #define __CUDACC__
#endif

#define MALLOC_CHECK_ 2

#include <stdio.h>
#include <limits.h>
#include "pruning.h"

/*
    Alpha-Beta pruning for the game Reversi/Othello.
    Simulation program, not designed to run a full game.
*/

__device__
int directions[9][2] = {{-1,-1}, {-1, 0}, {-1, 1},
                        { 0,-1}, { 0, 0}, { 0, 1},
                        { 1,-1}, { 1, 0}, { 1, 1}};

__device__ int *galpha, *gbeta;


// From cuda zero-sum games presentation
__device__
void resolve(int *alpha, int *beta) {
    if (*alpha <= *galpha) *alpha = *galpha;
    else atomicMax(galpha, *alpha);

    if (*beta >= *gbeta) *beta = *gbeta;
    else atomicMin(gbeta, *beta);
}

// Check if direction results in valid placement
__device__
bool check_valid(board_t *board, state_t state, int dir, int x, int y) {
    int cur_x = x + directions[dir][0];
    int cur_y = y + directions[dir][1];

    while (BOUND(board->dim_x, cur_x) && BOUND(board->dim_y, cur_y)) {

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

// Check if [x,y] is a valid new move
__device__
void valid_move(board_t *board, state_t state, int x, int y) {

    state_t cur_state = board->states[x * board->dim_y + y];
    if (cur_state != EMPTY) {
        return;
    }

    // for (int i = MAX(x - 1, 0); i <= MIN(x + 1, board->dim_x); i++) {
    //     for (int j = MAX(y - 1, 0); j <= MIN(y + 1, board->dim_y); j++) {

    //         if (i == j) continue;
    //         state_t new_state = board->states[i * board->dim_y + j];

    //         if (new_state != EMPTY && new_state != state) {
    //             int dir = (i + 1) * 3 + (j + 1);
    //             if (check_valid(board, state, dir, i, j)) {
    //                 board->states[x * board->dim_y + y] = VALID;
    //             }
    //         }
    //     }
    // }

    for (int k = 0; k < 9; k++) {
        if (k == 4) continue;

        int i = x + directions[k][0];
        int j = y + directions[k][1];

        if (!BOUND(board->dim_x, i) || !BOUND(board->dim_y, j)) {
            continue;
        }

        state_t new_state = board->states[i * board->dim_y + j];
        if (new_state != EMPTY && new_state != state) {
            if (check_valid(board, state, k, i, j)) {
                board->states[x * board->dim_y + y] = VALID;
            }
        }

    }
}

// Check how much position [x,y] contributes to heuristic
// Simplistic for project to avoid divergent behavior; more powerful ones available.
__device__
int local_eval(board_t *board, state_t state, int x, int y) {
    if (state == board->states[x * board->dim_y + y]) {
        return 1;
    }
    return 0;
}

// Orchestrate prefix-sum (reduce) for final evalution value
__device__
int eval_function(board_t *board, state_t state, int x, int y, int *shared) {

    unsigned int tid = threadIdx.x * blockDim.x + threadIdx.y;
    shared[tid] = local_eval(board, state, x, y);
    __syncthreads();

    for (unsigned int s=blockDim.x/2; s>0; s>>=1) {
        if (tid < s) {
            shared[tid] += shared[tid + s];
        }
        __syncthreads();
    }

    if (tid == 0) {
        return shared[0];
    }
}

// Fail-soft alpha-beta pruning adapted from wikipedia
__device__
int node_traverse(board_t *board, int depth, int alpha, int beta, state_t state, int *sdata) {

    int x = threadIdx.x, y = threadIdx.y, value = 0, count = 0;

    if (depth == 0) {
        return eval_function(board, state, x, y, (int *) sdata);
    }

    // Mark valid moves
    valid_move(board, state, x, y);
    __syncthreads();

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
                if (x == i && y == j) {
                    board->states[i] = state;
                }

                // Maximize score!
                value = MAX(value, node_traverse(board, depth - 1, alpha, beta, WHITE, sdata));
                if (value > beta) {
                    goto end; // β cutoff
                }

                if (threadIdx.x == 0 && threadIdx.y == 0) {
                    alpha = MAX(alpha, value);
                    resolve(&alpha, &beta);
                }

                // Reverse move
                if (x == i && y == j) {
                    board->states[i] = state;
                }

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
                if (x == i && y == j) {
                    board->states[i] = state;
                }

                // Minimize score!
                value = MIN(value, node_traverse(board, depth - 1, alpha, beta, BLACK, sdata));
                if (value < alpha) {
                    goto end; // α cutoff
                }

                if (threadIdx.x == 0 && threadIdx.y == 0) {
                    beta = MIN(beta, value);
                    resolve(&alpha, &beta);
                }

                // Reverse move
                if (x == i && y == j) {
                    board->states[i] = state;
                }

                count += 1;
            }
        }
    }
    end: return value;
}

__global__
void traverse_wrapper(board_t *board, int *depth) {

    extern __shared__ int sdata[];
    // int idx = blockIdx.x;
    node_traverse(board, *depth, INT_MIN, INT_MAX, BLACK, (int *) sdata);
}

float parallel_prune(int depth, int dim_x, int dim_y) {
    int *d_depth;
    state_t *d_states;
    board_t *d_board, board;

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    cudaMalloc((void **) &d_depth, sizeof(int));
    cudaMemcpy(d_depth, &depth, sizeof(int), cudaMemcpyHostToDevice);

    cudaMalloc((void **) &d_states, sizeof(state_t) * dim_x * dim_y);
    state_t *base_states = setup_board(dim_x, dim_y);
    cudaMemcpy(d_states, base_states, sizeof(state_t) * dim_x * dim_y, cudaMemcpyHostToDevice);

    board.dim_x = dim_x;
    board.dim_y = dim_y;
    board.states = d_states;

    cudaMalloc((void **) &d_board, sizeof(board_t));
    cudaMemcpy(d_board, &board, sizeof(board_t), cudaMemcpyHostToDevice);

    int alpha = INT_MIN;
    int beta = INT_MAX;

    cudaMemcpyToSymbol("galpha", &alpha, sizeof(int), size_t(0), cudaMemcpyHostToDevice);
    cudaMemcpyToSymbol("gbeta", &beta, sizeof(int), size_t(0), cudaMemcpyHostToDevice);

    dim3 grid(1);
    dim3 block(dim_x, dim_y);

    cudaEventRecord(start);
    traverse_wrapper <<<grid, block, dim_x * dim_y>>> (d_board, d_depth);
    cudaEventRecord(stop);

    cudaFree(d_depth);
    cudaFree(d_states);
    cudaFree(d_board);

    cudaEventSynchronize(stop);
    float milliseconds = 0.0;
    cudaEventElapsedTime(&milliseconds, start, stop);

    return milliseconds;

    // cudaMalloc((void **) &d_boards, sizeof(state_t *) * MAX_MOVES);

    // for (int i = 0; i < depth; i++) {
    //     cudaMemcpy(&(d_depths[i]), &depth, sizeof(int), cudaMemcpyHostToDevice);
    // }

    // state_t *base_board = setup_board(dim_x, dim_y);

    // for (int i = 0; i < MAX_MOVES; i++) {
    //     state_t *d_board;
    //     cudaMalloc((void **) &d_board, sizeof(state_t) * dim_x * dim_y);
    //     boards[i] = d_board;
    //     // cudaMemcpy(d_board, base_board, sizeof(state_t) * dim_x * dim_y, cudaMemcpyHostToDevice);
    //     cudaMemcpy(&(d_boards[i]), &d_board, sizeof(state_t *), cudaMemcpyHostToDevice);
    // }

    // int cur_move[2] = {(dim_x / 2) - 1, (dim_y / 2) + 1}; // Arbitrary leftmost move, heurestic used for better performance
    // state_t m_states[2] = {BLACK, WHITE};

    // state_t cur_state = m_states[i % 2];

    // Setup boards
    // for (int j = 0; j < MAX_MOVES; j++) {
    //     cudaMemcpy(boards[j], base_board, sizeof(state_t) * dim_x * dim_y, cudaMemcpyHostToDevice);
    // }

    // // Perform leftmost move of game tree
    // base_board[cur_move[0] * dim_y + cur_move[1]] = cur_state;

    // // Update move
    // if (cur_move[1] < dim_y) {
    //     cur_move[1] += 1;
    // } else {
    //     cur_move[0] += 1;
    // }

    // // Get evaluation
    // int val = seq_eval(base_board, dim_x, dim_y, cur_state);
    // if (i % 2 == 0) {
    //     alpha = max(val, alpha);
    // } else {
    //     beta = min(val, beta);
    // }
}
