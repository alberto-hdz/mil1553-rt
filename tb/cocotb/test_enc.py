import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import m1553

HALF_NS = 500  # 1 Mbps -> 0.5 us per half bit


async def capture_word(dut):
    """Bus monitor: wait for the transmitter to turn on, then sample each half bit at its center."""
    await RisingEdge(dut.tx_en)
    await Timer(HALF_NS // 2, units="ns")
    half = []
    for _ in range(40):
        half.append(int(dut.tx.value))
        await Timer(HALF_NS, units="ns")
    return m1553.decode(half)


@cocotb.test()
async def test_random_words(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())  # 50 MHz
    dut.rst.value = 1
    dut.start.value = 0
    dut.is_cmd.value = 0
    dut.data_in.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0

    for _ in range(200):
        word = random.getrandbits(16)
        is_cmd = random.getrandbits(1)
        dut.data_in.value = word
        dut.is_cmd.value = is_cmd
        mon = cocotb.start_soon(capture_word(dut))
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        got_cmd, got_word, par_ok, man_ok = await mon
        assert man_ok, "Manchester violation on TX"
        assert par_ok, f"bad parity for {word:#06x}"
        assert got_cmd == bool(is_cmd), "wrong sync type"
        assert got_word == word, f"sent {word:#06x}, got {got_word:#06x}"
        await Timer(4, units="us")  # inter-message gap


@cocotb.test()
async def test_back_to_back(dut):
    """Words pushed while busy must go out with no gap between them."""
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    dut.rst.value = 1
    dut.start.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0

    words = [(random.getrandbits(16), random.getrandbits(1)) for _ in range(5)]

    async def capture():
        await RisingEdge(dut.tx_en)
        await Timer(HALF_NS // 2, units="ns")
        half = []
        for _ in range(40 * len(words)):
            assert dut.tx_en.value == 1, "gap between words"
            half.append(int(dut.tx.value))
            await Timer(HALF_NS, units="ns")
        return [m1553.decode(half[40 * k:40 * k + 40]) for k in range(len(words))]

    mon = cocotb.start_soon(capture())
    for w, c in words:
        while dut.full.value == 1:
            await RisingEdge(dut.clk)
        dut.data_in.value = w
        dut.is_cmd.value = c
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        await RisingEdge(dut.clk)
    got = await mon
    for (w, c), (g_cmd, g_w, par_ok, man_ok) in zip(words, got):
        assert par_ok and man_ok
        assert (g_cmd, g_w) == (bool(c), w)
