import importlib
_user = importlib.import_module("user")
add = _user.add

seed = 0


def rand():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    return seed & 0xff


def main():
    TC = 100
    score = 0
    for tc in range(TC):
        a = rand()
        b = rand()

        actual = add(a, b)
        expected = a + b

        if actual == expected:
            score += 1

    print(f"SCORE: {score}")
    if score == TC:
        print("PASS")
        return 0
    else:
        print("FAIL")
        return 1


if __name__ == "__main__":
    main()
