library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rt_core is
  generic (
    RT_ADDR       : natural range 0 to 30 := 5;
    CLKS_PER_HALF : positive := 25
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    -- from the decoder
    d_valid  : in  std_logic;
    d_data   : in  std_logic_vector(15 downto 0);
    d_cmd    : in  std_logic;
    d_perr   : in  std_logic;
    d_merr   : in  std_logic;
    d_active : in  std_logic;
    -- to the encoder
    e_push   : out std_logic;
    e_data   : out std_logic_vector(15 downto 0);
    e_cmd    : out std_logic;
    e_full   : in  std_logic;
    e_busy   : in  std_logic;
    -- subaddress RAM
    ram_we   : out std_logic;
    ram_addr : out std_logic_vector(9 downto 0) := (others => '0');
    ram_din  : out std_logic_vector(15 downto 0);
    ram_dout : in  std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of rt_core is
  constant H          : natural := CLKS_PER_HALF;
  constant RESP_CLKS  : natural := 8 * H;   -- 4 us dead time -> about 6 us response time
  constant RX_TIMEOUT : natural := 44 * H;  -- 22 us with no new word
  constant MY_ADDR    : std_logic_vector(4 downto 0) := std_logic_vector(to_unsigned(RT_ADDR, 5));

  type state_t is (IDLE, RX_DATA, GAP, TX_LAST, TX_RD, TX_W, TX_PUSH, TX_DONE);
  type resp_t is (R_STATUS, R_DATA, R_LASTCMD);
  signal state : state_t := IDLE;
  signal resp  : resp_t := R_STATUS;

  signal sa         : std_logic_vector(4 downto 0) := (others => '0');
  signal expect     : natural range 0 to 32 := 0;
  signal idx        : natural range 0 to 32 := 0;
  signal timer      : natural range 0 to RX_TIMEOUT := 0;
  signal bcast      : std_logic := '0';
  signal discard    : std_logic := '0';  -- data word of an unsupported mode code
  signal reset_pend : std_logic := '0';
  signal me         : std_logic := '0';  -- Message Error status bit
  signal bcr        : std_logic := '0';  -- Broadcast Command Received status bit
  signal last_cmd   : std_logic_vector(15 downto 0) := (others => '0');
  signal push_r     : std_logic := '0';
  signal status     : std_logic_vector(15 downto 0);
begin
  -- status word: address, ME, instrumentation, service request, 3 reserved,
  -- BCR, busy, subsystem flag, dynamic bus control accept, terminal flag
  status <= MY_ADDR & me & "0" & "0" & "000" & bcr & "0000";
  e_push <= push_r;

  process (clk)
    variable c       : std_logic_vector(15 downto 0);
    variable is_bc   : std_logic;
    variable is_mode : boolean;
    variable code    : std_logic_vector(4 downto 0);
    variable n       : natural range 0 to 32;
  begin
    if rising_edge(clk) then
      push_r <= '0';
      ram_we <= '0';

      if rst = '1' then
        state      <= IDLE;
        me         <= '0';
        bcr        <= '0';
        reset_pend <= '0';
        last_cmd   <= (others => '0');
        ram_addr   <= (others => '0');

      -- a valid command word for this RT (or broadcast) starts a new message,
      -- even in the middle of one (superseding command)
      elsif d_valid = '1' and d_cmd = '1' and d_perr = '0' and d_merr = '0'
            and (state = IDLE or state = RX_DATA or state = GAP)
            and (d_data(15 downto 11) = MY_ADDR or d_data(15 downto 11) = "11111") then
        c       := d_data;
        code    := c(4 downto 0);
        is_mode := c(9 downto 5) = "00000" or c(9 downto 5) = "11111";
        if c(15 downto 11) = "11111" then
          is_bc := '1';
        else
          is_bc := '0';
        end if;
        if code = "00000" then
          n := 32;  -- word count 0 means 32
        else
          n := to_integer(unsigned(code));
        end if;

        sa      <= c(9 downto 5);
        bcast   <= is_bc;
        discard <= '0';
        timer   <= 0;
        idx     <= 0;
        resp    <= R_STATUS;

        -- transmit status word and transmit last command leave the status and last command alone
        if not (is_mode and c(10) = '1' and (code = "00010" or code = "10010")) then
          last_cmd <= c;
          me       <= '0';
          bcr      <= is_bc;
        end if;

        if is_mode then
          if is_bc = '1' then
            state <= IDLE;                     -- broadcast mode codes not supported
          elsif c(10) = '1' and code = "00010" then
            state <= GAP;                      -- transmit status word
          elsif c(10) = '1' and code = "10010" then
            resp  <= R_LASTCMD;                -- transmit last command
            state <= GAP;
          elsif c(10) = '1' and code = "01000" then
            reset_pend <= '1';                 -- reset remote terminal
            state      <= GAP;
          else
            me <= '1';                         -- unsupported mode code: status with ME set
            if c(10) = '0' and code(4) = '1' then
              expect  <= 1;                    -- it carries a data word; take it and drop it
              discard <= '1';
              state   <= RX_DATA;
            else
              state <= GAP;
            end if;
          end if;
        elsif c(10) = '0' then
          expect <= n;                         -- receive: BC sends n data words
          state  <= RX_DATA;
        elsif is_bc = '1' then
          me    <= '1';                        -- broadcast transmit is illegal: no response
          state <= IDLE;
        else
          expect <= n;                         -- transmit: send status then n data words
          resp   <= R_DATA;
          state  <= GAP;
        end if;

      else
        case state is
          when IDLE =>
            null;

          when RX_DATA =>
            if timer < RX_TIMEOUT then
              timer <= timer + 1;
            end if;
            if d_valid = '1' then
              if d_perr = '1' or d_merr = '1' or d_cmd = '1' then
                me    <= '1';                  -- bad word: no response
                state <= IDLE;
              else
                if discard = '0' then
                  ram_addr <= sa & std_logic_vector(to_unsigned(idx, 5));
                  ram_din  <= d_data;
                  ram_we   <= '1';
                end if;
                timer <= 0;
                if idx + 1 = expect then
                  state <= GAP;
                else
                  idx <= idx + 1;
                end if;
              end if;
            elsif (timer > H and d_active = '0') or timer = RX_TIMEOUT then
              me    <= '1';                    -- gap in the message or too few words
              state <= IDLE;
            end if;

          when GAP =>
            if (timer > H and d_active = '1') or d_valid = '1' then
              me    <= '1';                    -- bus still busy: too many words
              state <= IDLE;
            elsif timer = RESP_CLKS - 1 then
              if bcast = '1' then
                state <= IDLE;                 -- broadcast: never respond
              else
                e_data <= status;
                e_cmd  <= '1';
                push_r <= '1';
                idx    <= 0;
                case resp is
                  when R_STATUS  => state <= TX_DONE;
                  when R_LASTCMD => state <= TX_LAST;
                  when R_DATA    => state <= TX_RD;
                end case;
              end if;
            else
              timer <= timer + 1;
            end if;

          when TX_LAST =>
            if e_full = '0' and push_r = '0' then
              e_data <= last_cmd;
              e_cmd  <= '0';
              push_r <= '1';
              state  <= TX_DONE;
            end if;

          when TX_RD =>
            ram_addr <= sa & std_logic_vector(to_unsigned(idx, 5));
            state    <= TX_W;

          when TX_W =>
            state <= TX_PUSH;                  -- RAM has one clock of read latency

          when TX_PUSH =>
            if e_full = '0' and push_r = '0' then
              e_data <= ram_dout;
              e_cmd  <= '0';
              push_r <= '1';
              if idx + 1 = expect then
                state <= TX_DONE;
              else
                idx   <= idx + 1;
                state <= TX_RD;
              end if;
            end if;

          when TX_DONE =>
            if e_busy = '0' and push_r = '0' then
              if reset_pend = '1' then
                me         <= '0';
                bcr        <= '0';
                reset_pend <= '0';
              end if;
              state <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
