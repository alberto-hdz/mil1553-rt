-- manchester_dec.vhd
-- Manchester II decoder for my 1553 RT. Finds the sync by how long the bus
-- holds one level, then samples the middle of every half bit and checks
-- parity and the mid-bit transition. Each word is timed from its own sync.

library ieee;
use ieee.std_logic_1164.all;

entity manchester_dec is
  generic (CLKS_PER_HALF : positive := 25);  -- 50 MHz clock -> 0.5 us half bit
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    rx_p   : in  std_logic;  -- bus positive (from transceiver)
    rx_n   : in  std_logic;  -- bus negative (from transceiver)
    valid  : out std_logic;  -- one-clock pulse per received word
    data   : out std_logic_vector(15 downto 0);
    is_cmd : out std_logic;  -- '1' = command/status sync, '0' = data sync
    perr   : out std_logic;  -- parity error
    merr   : out std_logic;  -- Manchester error (no mid-bit transition)
    active : out std_logic   -- bus is not idle
  );
end entity;

architecture rtl of manchester_dec is
  constant H        : natural := CLKS_PER_HALF;
  constant SYNC_MIN : natural := (5 * H) / 2;  -- 1.25 us: longer than any run inside a word (1.0 us)
  constant SYNC_MAX : natural := 5 * H;        -- 2.5 us: covers a sync half merged with the previous parity half
  constant RUN_SAT  : natural := 6 * H;        -- run counter stops here so it can't wrap

  subtype lvl_t is std_logic_vector(1 downto 0);
  constant POS : lvl_t := "10";
  constant NEG : lvl_t := "01";

  type state_t is (HUNT, SYNC2, BITS);
  signal state : state_t := HUNT;

  signal p_meta, p_s, n_meta, n_s : std_logic := '0';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of p_meta, p_s, n_meta, n_s : signal is "TRUE";  -- keep synchronizer flops together
  signal lvl, lvl_prev : lvl_t := "00";
  signal run      : natural range 0 to RUN_SAT := 0;
  signal ct       : natural range 0 to 3 * H := 0;
  signal ph       : natural range 0 to 2 * H - 1 := 0;
  signal bit_i    : natural range 0 to 16 := 0;
  signal sync_lvl : lvl_t := "00";
  signal s1       : lvl_t := "00";
  signal sr       : std_logic_vector(16 downto 0) := (others => '0');
  signal m_acc    : std_logic := '0';
  signal cmd_r    : std_logic := '0';
begin
  -- two-flop synchronizers, then a registered copy of the bus level
  sync_proc : process (clk)
  begin
    if rising_edge(clk) then
      p_meta   <= rx_p;
      p_s      <= p_meta;
      n_meta   <= rx_n;
      n_s      <= n_meta;
      lvl      <= p_s & n_s;
      lvl_prev <= lvl;
    end if;
  end process;

  active <= '0' when lvl = "00" else '1';

  dec_proc : process (clk)
    variable bad : std_logic;
    variable par : std_logic;
  begin
    if rising_edge(clk) then
      valid <= '0';

      -- how many clocks the bus has held its current level
      if lvl /= lvl_prev then
        run <= 1;
      elsif run < RUN_SAT then
        run <= run + 1;
      end if;

      if rst = '1' then
        state <= HUNT;
      else
        case state is
          when HUNT =>
            -- mid-sync: a long run of one polarity flipping to the other
            if (lvl_prev = POS and lvl = NEG) or (lvl_prev = NEG and lvl = POS) then
              if run >= SYNC_MIN and run <= SYNC_MAX then
                state    <= SYNC2;
                ct       <= 1;
                sync_lvl <= lvl;
                if lvl_prev = POS then
                  cmd_r <= '1';
                else
                  cmd_r <= '0';
                end if;
              end if;
            end if;

          when SYNC2 =>
            ct <= ct + 1;
            if ct = (3 * H) / 2 and lvl /= sync_lvl then
              state <= HUNT;  -- second half of the sync is missing, not a real sync
            elsif ct = 3 * H - 1 then
              -- end of the sync, first data bit starts next clock
              state <= BITS;
              ph    <= 0;
              bit_i <= 0;
              m_acc <= '0';
            end if;

          when BITS =>
            -- sample the center of each half bit, timed from the mid-sync edge
            if ph = H / 2 then
              s1 <= lvl;
            end if;
            if ph = H + H / 2 then
              bad := '0';
              if s1 = lvl or (s1 /= POS and s1 /= NEG) or (lvl /= POS and lvl /= NEG) then
                bad := '1';
              end if;
              if s1 = POS then
                sr <= sr(15 downto 0) & '1';
              else
                sr <= sr(15 downto 0) & '0';
              end if;
              m_acc <= m_acc or bad;
            end if;
            if ph = 2 * H - 1 then
              ph <= 0;
              if bit_i = 16 then
                -- bit 16 is the parity bit, so the word is done
                par := '0';
                for i in 0 to 16 loop
                  par := par xor sr(i);
                end loop;
                data   <= sr(16 downto 1);
                perr   <= not par;  -- odd parity: XOR of all 17 bits must be '1'
                merr   <= m_acc;
                is_cmd <= cmd_r;
                valid  <= '1';
                state  <= HUNT;
              else
                bit_i <= bit_i + 1;
              end if;
            else
              ph <= ph + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
