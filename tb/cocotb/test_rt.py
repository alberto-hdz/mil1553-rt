import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.utils import get_sim_time

import m1553
from bc import RT_ADDR, idle, message, monitor, send, status_word

BROADCAST = 31
MC_TX_STATUS = 0b00010
MC_RESET = 0b01000
MC_TX_LAST_CMD = 0b10010
MC_SELF_TEST = 0b00011  # not implemented in my RT


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())  # 50 MHz
    dut.rst.value = 1
    dut.rx_p.value = 0
    dut.rx_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    bursts = []
    cocotb.start_soon(monitor(dut, bursts))
    await idle(dut, 2)
    return bursts


async def transact(dut, bursts, cmd, data=(), half=None, resp_words=1):
    """Send one message and return the RT's response (or None). Checks response time.
    resp_words: how many words the RT should send back, so I wait long enough for all of them."""
    n0 = len(bursts)
    await send(dut, half if half is not None else message(cmd, data))
    t_end = get_sim_time("ns")
    await idle(dut, 15 + 20 * resp_words)
    new = bursts[n0:]
    if not new:
        return None
    assert len(new) == 1, f"RT sent {len(new)} separate responses"
    # spec: mid-bit of the last parity bit to mid-sync of the status word
    resp_ns = new[0]["t0"] + 1500 - (t_end - 500)
    assert 4000 <= resp_ns <= 12000, f"response time {resp_ns} ns outside 4-12 us"
    return new[0]["words"]


def check_words(got, expected):
    """expected: list of (is_cmd, word). Every word must have good parity and Manchester coding."""
    assert len(got) == len(expected), f"expected {len(expected)} words, got {len(got)}"
    for i, ((is_cmd, w, par_ok, man_ok), (e_cmd, e_w)) in enumerate(zip(got, expected)):
        assert par_ok and man_ok, f"word {i} badly encoded"
        assert (is_cmd, w) == (e_cmd, e_w), f"word {i}: expected {(e_cmd, hex(e_w))}, got {(is_cmd, hex(w))}"


def rx_cmd(sa, wc, addr=RT_ADDR):
    return m1553.command_word(addr, 0, sa, wc)


def tx_cmd(sa, wc, addr=RT_ADDR):
    return m1553.command_word(addr, 1, sa, wc)


def mode_cmd(code, tr=1, addr=RT_ADDR):
    return m1553.command_word(addr, tr, 0, code)


async def read_status(dut, bursts):
    words = await transact(dut, bursts, mode_cmd(MC_TX_STATUS))
    assert words is not None, "no response to transmit status word"
    return words[0][1]


@cocotb.test()
async def test_receive_then_transmit(dut):
    """BC writes 4 words to subaddress 3, then reads them back."""
    bursts = await setup(dut)
    data = [random.getrandbits(16) for _ in range(4)]
    got = await transact(dut, bursts, rx_cmd(3, 4), data)
    check_words(got, [(True, status_word())])
    got = await transact(dut, bursts, tx_cmd(3, 4), resp_words=5)
    check_words(got, [(True, status_word())] + [(False, w) for w in data])


@cocotb.test()
async def test_word_count_zero_is_32(dut):
    bursts = await setup(dut)
    data = [random.getrandbits(16) for _ in range(32)]
    got = await transact(dut, bursts, rx_cmd(7, 0), data)
    check_words(got, [(True, status_word())])
    got = await transact(dut, bursts, tx_cmd(7, 0), resp_words=33)
    check_words(got, [(True, status_word())] + [(False, w) for w in data])


@cocotb.test()
async def test_broadcast(dut):
    """Broadcast receive: no response, data stored, BCR set in the next status word."""
    bursts = await setup(dut)
    data = [random.getrandbits(16) for _ in range(3)]
    got = await transact(dut, bursts, rx_cmd(9, 3, addr=BROADCAST), data)
    assert got is None, "RT responded to a broadcast"
    assert await read_status(dut, bursts) == status_word(bcr=1)
    got = await transact(dut, bursts, tx_cmd(9, 3), resp_words=4)
    check_words(got, [(True, status_word())] + [(False, w) for w in data])


@cocotb.test()
async def test_wrong_address(dut):
    bursts = await setup(dut)
    other = (RT_ADDR + 1) % 31
    got = await transact(dut, bursts, rx_cmd(3, 2, addr=other), [0x1234, 0x5678])
    assert got is None
    got = await transact(dut, bursts, tx_cmd(3, 2, addr=other), resp_words=3)
    assert got is None


@cocotb.test()
async def test_parity_error(dut):
    """Bad parity in data word 2: no response, ME set, then cleared by the next good command."""
    bursts = await setup(dut)
    half = message(rx_cmd(3, 4), [0x1111, 0x2222, 0x3333, 0x4444])
    w2 = 40 * 3  # start of data word 2 (0-based) after the command word
    half[w2 + 38], half[w2 + 39] = half[w2 + 39], half[w2 + 38]
    assert await transact(dut, bursts, None, half=half) is None
    assert await read_status(dut, bursts) == status_word(me=1)
    got = await transact(dut, bursts, rx_cmd(3, 1), [0xBEEF])
    check_words(got, [(True, status_word())])


@cocotb.test()
async def test_manchester_error(dut):
    bursts = await setup(dut)
    half = message(rx_cmd(3, 2), [0xAAAA, 0x5555])
    w1 = 40 * 1
    half[w1 + 6 + 2 * 7 + 1] = half[w1 + 6 + 2 * 7]  # no mid-bit transition in bit 7
    assert await transact(dut, bursts, None, half=half) is None
    assert await read_status(dut, bursts) == status_word(me=1)


@cocotb.test()
async def test_too_few_words(dut):
    bursts = await setup(dut)
    assert await transact(dut, bursts, rx_cmd(3, 4), [1, 2, 3]) is None
    assert await read_status(dut, bursts) == status_word(me=1)


@cocotb.test()
async def test_too_many_words(dut):
    bursts = await setup(dut)
    assert await transact(dut, bursts, rx_cmd(3, 4), [1, 2, 3, 4, 5]) is None
    assert await read_status(dut, bursts) == status_word(me=1)


@cocotb.test()
async def test_transmit_last_command(dut):
    bursts = await setup(dut)
    first = rx_cmd(12, 1)
    await transact(dut, bursts, first, [0x0F0F])
    got = await transact(dut, bursts, mode_cmd(MC_TX_LAST_CMD), resp_words=2)
    check_words(got, [(True, status_word()), (False, first)])


@cocotb.test()
async def test_reset_rt(dut):
    bursts = await setup(dut)
    await transact(dut, bursts, rx_cmd(3, 4), [1, 2])  # too few words -> ME
    assert await read_status(dut, bursts) == status_word(me=1)
    got = await transact(dut, bursts, mode_cmd(MC_RESET))
    check_words(got, [(True, status_word())])
    assert await read_status(dut, bursts) == status_word()


@cocotb.test()
async def test_unsupported_mode_code(dut):
    bursts = await setup(dut)
    got = await transact(dut, bursts, mode_cmd(MC_SELF_TEST))
    check_words(got, [(True, status_word(me=1))])


@cocotb.test()
async def test_superseding_command(dut):
    """A new command cuts off an unfinished message; the RT answers only the new one."""
    bursts = await setup(dut)
    await send(dut, message(rx_cmd(3, 4), [1, 2]))
    await idle(dut, 6)
    data = [random.getrandbits(16)]
    got = await transact(dut, bursts, rx_cmd(4, 1), data)
    check_words(got, [(True, status_word())])
    got = await transact(dut, bursts, tx_cmd(4, 1), resp_words=2)
    check_words(got, [(True, status_word())] + [(False, w) for w in data])


@cocotb.test()
async def test_random_messages(dut):
    """Random receive and transmit messages checked against a model of the subaddress RAM.
    Reset does not clear the RAM and earlier tests wrote to it, so I only check words written here."""
    bursts = await setup(dut)
    ram = {}
    checked = 0
    for _ in range(40):
        sa = random.randint(1, 8)  # a few subaddresses so reads often hit data written here
        wc = random.randint(1, 32)
        if random.getrandbits(1):
            data = [random.getrandbits(16) for _ in range(wc)]
            got = await transact(dut, bursts, rx_cmd(sa, wc % 32), data)
            check_words(got, [(True, status_word())])
            for i, w in enumerate(data):
                ram[(sa, i)] = w
        else:
            got = await transact(dut, bursts, tx_cmd(sa, wc % 32), resp_words=wc + 1)
            check_words(got[:1], [(True, status_word())])
            assert len(got) == wc + 1, f"expected {wc + 1} words, got {len(got)}"
            for i in range(wc):
                if (sa, i) in ram:
                    assert got[1 + i][1] == ram[(sa, i)], f"SA {sa} word {i} does not match"
                    checked += 1
    dut._log.info(f"40 random messages passed, {checked} read-back words matched the RAM model")
