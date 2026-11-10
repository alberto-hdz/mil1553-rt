"""My bus controller model: drives the RT's receive lines and decodes its transmit lines."""
import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.utils import get_sim_time

import m1553

HALF_PS = 500_000  # 0.5 us per half bit at 1 Mbps
RT_ADDR = 5


async def send(dut, half, half_ps=HALF_PS, offsets=None):
    """Drive half-bit levels onto rx_p/rx_n. offsets[i] (ps) moves the edge at the start of half bit i."""
    t = 0
    for i, level in enumerate(half):
        target = i * half_ps + (offsets[i] if offsets and i else 0)
        if target > t:
            await Timer(target - t, units="ps")
            t = target
        dut.rx_p.value = level
        dut.rx_n.value = 1 - level
    await Timer(len(half) * half_ps - t, units="ps")
    dut.rx_p.value = 0
    dut.rx_n.value = 0


async def idle(dut, us):
    dut.rx_p.value = 0
    dut.rx_n.value = 0
    await Timer(us, units="us")


def message(cmd, data_words=()):
    """Command word followed by contiguous data words, as half-bit levels."""
    half = m1553.encode(cmd, True)
    for w in data_words:
        half += m1553.encode(w, False)
    return half


async def monitor(dut, bursts):
    """Record every RT transmission: start time and decoded words."""
    while True:
        await RisingEdge(dut.tx_p)  # every response starts with a status word (positive sync first)
        t0 = get_sim_time("ns")
        await Timer(HALF_PS // 2, units="ps")
        words = []
        while True:
            half = []
            for _ in range(40):
                p, n = int(dut.tx_p.value), int(dut.tx_n.value)
                half.append(1 if (p, n) == (1, 0) else 0 if (p, n) == (0, 1) else None)
                await Timer(HALF_PS, units="ps")
            assert None not in half, "RT went idle in the middle of a word"
            words.append(m1553.decode(half))
            if int(dut.tx_p.value) == 0 and int(dut.tx_n.value) == 0:
                break
        bursts.append({"t0": t0, "words": words})


def status_word(me=0, bcr=0):
    return (RT_ADDR << 11) | (me << 10) | (bcr << 4)
