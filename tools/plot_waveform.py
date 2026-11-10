"""Plots the simulated bus traffic recorded by tb/cocotb/capture_waveform.py.
Usage: python3 tools/plot_waveform.py docs/waveform.json docs/waveform.png"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    w = json.load(f)
t, rx, tx = w["t_us"], w["rx"], w["tx"]
cmd, data = w["cmd"], w["data"]

BLUE, ORANGE, GRAY = "#2563eb", "#ea580c", "#6b7280"
tx_start = next(t[i] for i, v in enumerate(tx) if v != 0)
msg_end = 20.0 * (1 + len(data))
# spec response time: mid-bit of the last parity bit to mid-sync of the status word
resp = (tx_start + 1.5) - (msg_end - 0.5)

fig, (top, bot) = plt.subplots(2, 1, figsize=(11, 6.2), gridspec_kw={"height_ratios": [1.15, 1]})

# top: whole message and response
top.step(t, [v + 3 for v in rx], where="post", color=BLUE, lw=1)
top.step(t, tx, where="post", color=ORANGE, lw=1)
top.set_yticks([3, 0], ["BC → RT", "RT → BC"])
top.set_ylim(-2.7, 5.5)
top.set_xlim(-2, tx_start + 24)
labels = [f"Command\nRT {cmd >> 11}, R, SA {(cmd >> 5) & 31}, WC {cmd & 31}"] + [
    f"Data {i + 1}\n0x{d:04X}" for i, d in enumerate(data)]
for i, lab in enumerate(labels):
    top.text(20 * i + 10, 4.75, lab, ha="center", va="center", fontsize=8.5, color=BLUE)
    if i:
        top.axvline(20 * i, color=GRAY, lw=0.6, ls=":", ymin=0.55)
top.text(tx_start + 10, 1.75, f"Status word\n0x{(cmd >> 11) << 11:04X}, no errors",
         ha="center", va="center", fontsize=8.5, color=ORANGE)
top.annotate("", xy=(tx_start + 1.5, -1.5), xytext=(msg_end - 0.5, -1.5),
             arrowprops=dict(arrowstyle="<->", color=GRAY, lw=0.8))
top.text((msg_end + tx_start + 1) / 2, -1.8, f"response time {resp:.1f} µs (spec 4–12 µs)",
         ha="center", va="top", fontsize=8.5, color=GRAY)
top.set_title("Simulated BC → RT receive message and status response (rt_top, GHDL + cocotb)",
              fontsize=10, loc="left")

# bottom: zoom on the command word
z = [(ti, v) for ti, v in zip(t, rx) if ti <= 20.5]
bot.step([a for a, _ in z], [b for _, b in z], where="post", color=BLUE, lw=1.2)
bot.set_xlim(-0.5, 20.5)
bot.set_ylim(-1.6, 1.9)
bot.set_yticks([1, 0, -1], ["+", "idle", "−"])
bot.axvspan(0, 3, color=BLUE, alpha=0.08)
bot.text(1.5, 1.45, "sync\n(command)", ha="center", va="center", fontsize=8)
bits = [(cmd >> (15 - i)) & 1 for i in range(16)]
bits.append(1 - (sum(bits) & 1))
fields = [("RT addr", 0, 5), ("T/R", 5, 6), ("subaddress", 6, 11), ("word count", 11, 16), ("P", 16, 17)]
for i, b in enumerate(bits):
    x = 3 + i
    bot.axvline(x, color=GRAY, lw=0.4, ls=":")
    bot.text(x + 0.5, 1.25, str(b), ha="center", va="center", fontsize=8)
for name, a, b in fields:
    bot.text(3 + (a + b) / 2, 1.65, name, ha="center", va="center", fontsize=7.5, color=GRAY)
bot.set_xlabel("time (µs)")
bot.set_title("Command word: 3 µs sync, 16 bits Manchester II (1 = high→low, 0 = low→high), odd parity",
              fontsize=10, loc="left")

for ax in (top, bot):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
fig.tight_layout()
fig.savefig(dst, dpi=160)
print(f"wrote {dst} (response time {resp:.2f} us)")
