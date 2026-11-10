"""My bit-true reference model for MIL-STD-1553B words."""

SYNC_CMD = [1, 1, 1, 0, 0, 0]   # command/status sync: 1.5 us high, 1.5 us low
SYNC_DATA = [0, 0, 0, 1, 1, 1]  # data sync: 1.5 us low, 1.5 us high


def odd_parity(word):
    """Parity bit that makes the total number of ones (16 bits + parity) odd."""
    return 1 - (bin(word & 0xFFFF).count("1") & 1)


def command_word(rt_addr, tx, subaddr, word_count):
    """Build a 16-bit command word. word_count 32 is encoded as 0."""
    return (rt_addr << 11) | (tx << 10) | (subaddr << 5) | (word_count & 0x1F)


def encode(word, is_cmd):
    """Return the 40 half-bit levels (0.5 us each) for one word."""
    half = list(SYNC_CMD if is_cmd else SYNC_DATA)
    bits = [(word >> (15 - i)) & 1 for i in range(16)] + [odd_parity(word)]
    for b in bits:
        half += [1, 0] if b else [0, 1]
    return half


def decode(half):
    """Decode 40 half-bit levels. Returns (is_cmd, word, parity_ok, manchester_ok)."""
    sync = half[:6]
    is_cmd = sync == SYNC_CMD
    word, ones, man_ok = 0, 0, True
    for i in range(17):
        a, b = half[6 + 2 * i], half[7 + 2 * i]
        if a == b:
            man_ok = False
        if i < 16:
            word = (word << 1) | a
        ones += a
    return is_cmd, word, (ones & 1) == 1, man_ok
