"""Decoder tests: clean, jittered and off-rate traffic, plus parity, Manchester and idle-noise checks."""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import m1553
from bc import HALF_PS, idle, message, send


async def collect(dut, out):
    """Record every word the decoder reports."""
    while True:
        await RisingEdge(dut.clk)
        if dut.valid.value == 1:
            out.append((bool(dut.is_cmd.value), int(dut.data.value),
                        int(dut.perr.value), int(dut.merr.value)))


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())  # 50 MHz
    dut.rst.value = 1
    dut.rx_p.value = 0
    dut.rx_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    got = []
    cocotb.start_soon(collect(dut, got))
    await idle(dut, 2)
    return got


def random_message():
    n = random.randint(0, 32)
    return random.getrandbits(16), [random.getrandbits(16) for _ in range(n)]


def expected(cmd, data_words):
    return [(True, cmd, 0, 0)] + [(False, w, 0, 0) for w in data_words]


async def run_messages(dut, n_msgs, half_ps=HALF_PS, jitter_ps=0, single_edge_ps=0):
    got = await setup(dut)
    exp = []
    for _ in range(n_msgs):
        cmd, data_words = random_message()
        half = message(cmd, data_words)
        offsets = None
        if jitter_ps:
            offsets = [random.randint(-jitter_ps, jitter_ps) for _ in half]
        if single_edge_ps:
            # move one real transition per word by the full amount
            offsets = [0] * len(half)
            for w in range(len(half) // 40):
                edges = [i for i in range(w * 40 + 1, w * 40 + 40) if half[i] != half[i - 1]]
                offsets[random.choice(edges)] = random.choice([-single_edge_ps, single_edge_ps])
        await send(dut, half, half_ps, offsets)
        await idle(dut, random.randint(4, 12))
        exp += expected(cmd, data_words)
    assert len(got) == len(exp), f"expected {len(exp)} words, decoder reported {len(got)}"
    for i, (g, e) in enumerate(zip(got, exp)):
        assert g == e, f"word {i}: expected {e}, got {g}"
    dut._log.info(f"{len(exp)} words decoded bit-exact")


@cocotb.test()
async def test_clean(dut):
    """Random messages (command + 0..32 contiguous data words), ideal timing."""
    await run_messages(dut, 50)


@cocotb.test()
async def test_jitter_100ns(dut):
    """Every edge moved randomly by up to +/-100 ns."""
    await run_messages(dut, 50, jitter_ps=100_000)


@cocotb.test()
async def test_single_edge_150ns(dut):
    """One transition per word moved by the full +/-150 ns."""
    await run_messages(dut, 50, single_edge_ps=150_000)


@cocotb.test()
async def test_rate_fast(dut):
    """Bus 0.1% fast."""
    await run_messages(dut, 20, half_ps=499_500)


@cocotb.test()
async def test_rate_slow(dut):
    """Bus 0.1% slow."""
    await run_messages(dut, 20, half_ps=500_500)


@cocotb.test()
async def test_parity_error(dut):
    """Flip the parity bit (still valid Manchester) and expect perr."""
    got = await setup(dut)
    word = random.getrandbits(16)
    half = m1553.encode(word, False)
    half[38], half[39] = half[39], half[38]
    await send(dut, half)
    await idle(dut, 5)
    assert got == [(False, word, 1, 0)], f"got {got}"


@cocotb.test()
async def test_manchester_error(dut):
    """Remove the mid-bit transition from data bit 5 and expect merr."""
    got = await setup(dut)
    word = random.getrandbits(16)
    half = m1553.encode(word, True)
    half[6 + 2 * 5 + 1] = half[6 + 2 * 5]
    await send(dut, half)
    await idle(dut, 5)
    assert len(got) == 1 and got[0][3] == 1, f"got {got}"


@cocotb.test()
async def test_idle_noise(dut):
    """Short pulses on an idle bus must not look like a sync."""
    got = await setup(dut)
    for _ in range(50):
        await send(dut, [1, 0, 1, 1, 0, 0])
        await idle(dut, 3)
    assert got == [], f"decoder reported words from noise: {got}"
