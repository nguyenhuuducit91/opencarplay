# Unit test chạy trên máy build (không cần thiết bị, không cần Theos).
#   make -C tests test

CC      ?= cc
CFLAGS  += -std=c11 -Wall -Wextra -Werror -g -fsanitize=address,undefined
LDFLAGS += -fsanitize=address,undefined -lm

BIN = test_ocp_util
SRC = test_ocp_util.c ../Core/ocp_util.c

.PHONY: test clean
test: $(BIN)
	./$(BIN)

$(BIN): $(SRC) ../Core/ocp_util.h
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)

clean:
	rm -f $(BIN)
