# Unit test chạy trên máy build (không cần thiết bị, không cần Theos).
#   make -C tests test

CC      ?= cc
CFLAGS  += -std=c11 -Wall -Wextra -Werror -g -fsanitize=address,undefined
LDFLAGS += -fsanitize=address,undefined -lm

BIN  = test_ocp_util
FUZZ = fuzz_ocp_util

.PHONY: all test fuzz clean
all: test fuzz

test: $(BIN)
	./$(BIN)

fuzz: $(FUZZ)
	./$(FUZZ)

$(BIN): test_ocp_util.c ../Core/ocp_util.c ../Core/ocp_util.h
	$(CC) $(CFLAGS) -o $@ test_ocp_util.c ../Core/ocp_util.c $(LDFLAGS)

$(FUZZ): fuzz_ocp_util.c ../Core/ocp_util.c ../Core/ocp_util.h
	$(CC) $(CFLAGS) -o $@ fuzz_ocp_util.c ../Core/ocp_util.c $(LDFLAGS)

clean:
	rm -f $(BIN) $(FUZZ)
