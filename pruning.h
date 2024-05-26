#define MAX(X, Y) (((X) > (Y)) ? (X) : (Y))
#define MIN(X, Y) (((X) < (Y)) ? (X) : (Y))
#define BOUND(D, N) ((N) > 0 && (N) < (D))

#define MAX_MOVES 8

typedef enum {
    BLACK,
    WHITE,
    EMPTY,
    VALID,

} state_t;

typedef struct {

    int dim_x, dim_y;
    state_t *states;

} board_t;

float parallel_prune(int depth, int dim_x, int dim_y);
state_t *setup_board(int dim_x, int dim_y);
