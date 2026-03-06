#include <cstdio>

extern int add(int a, int b);

static int seed = 0;

int rand() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed & 0xff;
}

int main() {
    int TC = 100;
    int score = 0;
    for (int tc = 0; tc < TC; tc++) {
        int a = rand();
        int b = rand();

        int actual = add(a, b);
        int expected = a + b;

        if (actual == expected) {
            score += 1;
        }
    }

    std::printf("SCORE: %d\n", score);
    if (score == TC) {
        std::printf("PASS\n");
        return 0;
    } else {
        std::printf("FAIL\n");
        return 1;
    }
}
