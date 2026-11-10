# MIL-STD-1553B Remote Terminal (VHDL)

![tests](https://github.com/alberto-hdz/mil1553-rt/actions/workflows/tests.yml/badge.svg)

MIL-STD-1553B is the command/response data bus used in military aircraft avionics: a bus controller (BC) sends commands at 1 Mbps and remote terminals (RTs) answer with a status word and data. This repo is my VHDL implementation of a 1553B **remote terminal**, verified in simulation with a Python/cocotb bus controller model and implemented on a Xilinx Artix-7.

## Architecture

```mermaid
flowchart LR
    RX["rx_p / rx_n"] --> DEC["manchester_dec<br/>sync detect, bit sampling,<br/>parity + Manchester checks"]
    DEC --> CORE["rt_core<br/>command decode, word count,<br/>response gap, status word,<br/>mode codes, error handling"]
    CORE <--> RAM["subaddr_ram<br/>32 SA x 32 words x 16 bit<br/>(one 18Kb BRAM)"]
    CORE --> ENC["manchester_enc<br/>sync + Manchester II,<br/>odd parity, holding register"]
    ENC --> TX["tx_p / tx_n"]
```

The bus pins are two-wire (positive / negative / both low = idle), matching the logic side of a 1553 transceiver.

| File | What it does |
|---|---|
| `rtl/manchester_enc.vhd` | Builds the 40 half-bit pattern (3 µs sync, 16 data bits, odd parity) and shifts it out at 1 Mbps. A one-word holding register keeps consecutive words contiguous. |
| `rtl/manchester_dec.vhd` | Two-flop synchronizer, run-length sync detection, half-bit sampling timed from the mid-sync edge, parity and Manchester error flags. |
| `rtl/rt_core.vhd` | RT protocol state machine. |
| `rtl/subaddr_ram.vhd` | Receive/transmit data buffer. |
| `rtl/rt_top.vhd` | Top level. Generics: `RT_ADDR` (0–30), `CLKS_PER_HALF` (25 at 50 MHz, 50 at 100 MHz). |
| `model/m1553.py` | Bit-true Python reference model (word encode/decode, parity, command word). |
| `tb/cocotb/` | cocotb testbenches and the bus controller model (`bc.py`). |
| `syn/` | Vivado non-project build script, constraints, and post-route reports. |

## Supported

- BC→RT (receive) and RT→BC (transmit) messages, word count 1–32 (WC = 0 means 32)
- Broadcast receive (RT address 31): data stored, no response, Broadcast Command Received bit set
- Status word with Message Error and Broadcast Command Received bits
- Mode codes: Transmit Status Word (00010), Reset Remote Terminal (01000), Transmit Last Command (10010). Other mode codes get a status word with Message Error set.
- Error handling: parity error, Manchester error, too few words, too many words, gap inside a message, wrong sync type. On any of these the RT sets Message Error and does not respond, as the standard requires.
- Superseding command: a new valid command cuts off an unfinished message.
- Response time: about 6.1 µs (spec: 4–12 µs, measured mid-parity to mid-sync).

## Not supported

- RT-to-RT transfers
- Broadcast mode codes
- Dual-redundant bus (A/B)
- Double buffering: receive data is written to RAM as it arrives, so a message that fails partway still leaves its earlier words in RAM
- Real transceiver / transformer-coupled bus (logic-level only)

## Verification

All testbenches are cocotb (Python) running on GHDL. Every run uses a new random seed, and GitHub Actions runs everything on each push.

| Testbench | Tests | Coverage |
|---|---|---|
| `test_enc.py` | 2 | 200 random words decoded by the reference model; back-to-back words with no gap |
| `test_dec.py` | 8 | About 3,400 words per run decoded bit-exact across: ideal timing, ±100 ns random jitter on every edge, one edge per word moved ±150 ns, bus rate ±0.1%, parity error, Manchester error, idle-bus noise |
| `test_rt.py` | 13 | Every feature above plus 40 random read/write messages checked against a Python model of the subaddress RAM. Every response is checked for the 4–12 µs response time. |

**Mutation checks**: I broke the design on purpose to confirm the tests catch it.

| Bug injected | Caught by |
|---|---|
| Even parity instead of odd in the encoder | `test_random_words`: bad parity on the first word |
| Sync threshold lowered from 1.25 µs to 0.75 µs | `test_idle_noise`: 12 false words decoded from noise |
| Response gap cut from 4 µs to 1 µs | `test_receive_then_transmit`: response time 3.1 µs, below the 4 µs minimum |

## Design notes

- **Sync detection.** The longest constant level inside a valid word is 1.0 µs (a 1 followed by a 0). A sync half is 1.5 µs, so a run of at least 1.25 µs followed by a polarity flip marks the middle of a sync. The upper limit is 2.5 µs because a data sync can merge with the last half of the previous word's parity bit.
- **Timing recovery.** Each word is timed from its own mid-sync edge. A 0.1% rate error over one 20 µs word is only 20 ns, well inside the 250 ns sampling margin, so re-timing on every bit is not needed.
- **Contiguous words.** Integration testing showed my first encoder left a one-clock idle gap between words. I added a one-word holding register so the next word starts the same clock the previous one ends, and added `test_back_to_back` to keep it fixed.
- **Too many words.** The RT knows how many words to expect. If the bus is still active 0.5 µs into the response gap, the BC is still sending, so the RT sets Message Error and stays silent.

## FPGA implementation

Vivado 2024.2, Artix-7 `xc7a200tfbg484-1`, 100 MHz clock (`CLKS_PER_HALF = 50`), post-route:

| Resource | Used |
|---|---|
| Slice LUTs | 197 |
| Slice registers | 255 |
| Block RAM | 1 RAMB18 (0.5 tile) |
| DSP48 | 0 |

| Timing | Result |
|---|---|
| WNS (setup) | +4.539 ns (critical path about 5.5 ns) |
| WHS (hold) | +0.059 ns |
| Failing endpoints | 0 of 544 |

The bus inputs are asynchronous to the system clock, so they go through two-flop synchronizers marked `ASYNC_REG` and are false-pathed in `syn/rt_top.xdc`. Full reports are in `syn/reports/`.

To rebuild, run this from `syn/`: `vivado -mode batch -source build.tcl`

## Running the tests

Requirements: GHDL, Python 3, cocotb 1.9.2.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install cocotb==1.9.2
make test
```

Run one testbench with `make test-enc`, `make test-dec`, or `make test-rt`. A full run takes a few minutes.
