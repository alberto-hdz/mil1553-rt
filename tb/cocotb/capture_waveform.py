"""Records one BC-to-RT message and the RT's status response for the README figure."""
import json
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.utils import get_sim_time

import m1553
from bc import RT_ADDR, idle, message, send

OUT = Path(__file__).resolve().parents[2] / "docs" / "waveform.json"
STEP_NS = 20


def level(p, n):
    """Bus level as the transceiver would see it: +1, -1, or 0 for idle."""
    return 1 if (p, n) == (1, 0) else -1 if (p, n) == (0, 1) else 0


@cocotb.test()
async def capture(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())  # 50 MHz
    dut.rst.value = 1
    dut.rx_p.value = 0
    dut.rx_n.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await idle(dut, 2)

    t0 = get_sim_time("ns")
    trace = {"t_us": [], "rx": [], "tx": []}

    async def sampler():
        while True:
            trace["t_us"].append((get_sim_time("ns") - t0) / 1000)
            trace["rx"].append(level(int(dut.rx_p.value), int(dut.rx_n.value)))
            trace["tx"].append(level(int(dut.tx_p.value), int(dut.tx_n.value)))
            await Timer(STEP_NS, units="ns")

    task = cocotb.start_soon(sampler())
    cmd = m1553.command_word(RT_ADDR, 0, 3, 2)  # RT 5, receive, subaddress 3, 2 words
    data = [0x1553, 0xBEEF]
    await send(dut, message(cmd, data))
    await idle(dut, 30)
    task.kill()

    assert any(trace["tx"]), "RT never responded"
    OUT.parent.mkdir(exist_ok=True)
    with open(OUT, "w") as f:
        json.dump({"cmd": cmd, "data": data, **trace}, f)
    dut._log.info(f"wrote {OUT}")
