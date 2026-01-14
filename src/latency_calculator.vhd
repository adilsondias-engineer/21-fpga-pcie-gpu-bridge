----------------------------------------------------------------------------------
-- Latency Calculator
-- Computes FPGA latency from 4-point timestamps and tracks min/max/last
--
-- Timestamps are 125 MHz cycle counts (8 ns per cycle):
--   T1: ITCH parse start (RGMII RX domain)
--   T2: CDC FIFO write (RGMII RX domain)
--   T3: BBO FIFO read (TX domain)
--   T4: UDP TX start (TX domain)
--
-- Latency = (T2 - T1) + (T4 - T3) in 8 ns units
-- Output is in nanoseconds = latency * 8
--
-- Clock Domain: axi_aclk (XDMA clock)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity latency_calculator is
    Port (
        clk            : in  STD_LOGIC;
        rst            : in  STD_LOGIC;

        -- Timestamp inputs (valid with update pulse)
        ts_valid       : in  STD_LOGIC;
        ts_t1          : in  STD_LOGIC_VECTOR(31 downto 0);
        ts_t2          : in  STD_LOGIC_VECTOR(31 downto 0);
        ts_t3          : in  STD_LOGIC_VECTOR(31 downto 0);
        ts_t4          : in  STD_LOGIC_VECTOR(31 downto 0);

        -- Reset statistics
        stats_reset    : in  STD_LOGIC;

        -- Latency outputs (in nanoseconds)
        last_latency_ns: out STD_LOGIC_VECTOR(31 downto 0);
        max_latency_ns : out STD_LOGIC_VECTOR(31 downto 0);
        min_latency_ns : out STD_LOGIC_VECTOR(31 downto 0);

        -- Last timestamps (for register readback)
        last_rx_ts     : out STD_LOGIC_VECTOR(31 downto 0);  -- T1
        last_tx_ts     : out STD_LOGIC_VECTOR(31 downto 0)   -- T4
    );
end latency_calculator;

architecture Behavioral of latency_calculator is

    -- Constants
    constant NS_PER_CYCLE : integer := 8;  -- 125 MHz = 8 ns per cycle

    -- Internal registers
    signal last_latency_reg : unsigned(31 downto 0) := (others => '0');
    signal max_latency_reg  : unsigned(31 downto 0) := (others => '0');
    signal min_latency_reg  : unsigned(31 downto 0) := (others => '1');  -- Start at max
    signal last_rx_ts_reg   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal last_tx_ts_reg   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    -- Calculation pipeline
    signal calc_valid_p1    : STD_LOGIC := '0';
    signal latency_a_p1     : unsigned(31 downto 0) := (others => '0');  -- T2 - T1
    signal latency_b_p1     : unsigned(31 downto 0) := (others => '0');  -- T4 - T3
    signal t1_latched       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal t4_latched       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    signal calc_valid_p2    : STD_LOGIC := '0';
    signal total_latency_p2 : unsigned(31 downto 0) := (others => '0');
    signal t1_latched_p2    : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal t4_latched_p2    : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

begin

    -- Output assignments
    last_latency_ns <= std_logic_vector(last_latency_reg);
    max_latency_ns  <= std_logic_vector(max_latency_reg);
    min_latency_ns  <= std_logic_vector(min_latency_reg);
    last_rx_ts      <= last_rx_ts_reg;
    last_tx_ts      <= last_tx_ts_reg;

    -- Pipeline process
    process(clk)
        variable delta_a   : unsigned(31 downto 0);
        variable delta_b   : unsigned(31 downto 0);
        variable total_ns  : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                calc_valid_p1 <= '0';
                calc_valid_p2 <= '0';
                latency_a_p1 <= (others => '0');
                latency_b_p1 <= (others => '0');
                total_latency_p2 <= (others => '0');
                last_latency_reg <= (others => '0');
                max_latency_reg <= (others => '0');
                min_latency_reg <= (others => '1');
                last_rx_ts_reg <= (others => '0');
                last_tx_ts_reg <= (others => '0');
                t1_latched <= (others => '0');
                t4_latched <= (others => '0');
                t1_latched_p2 <= (others => '0');
                t4_latched_p2 <= (others => '0');
            else
                -- Statistics reset
                if stats_reset = '1' then
                    max_latency_reg <= (others => '0');
                    min_latency_reg <= (others => '1');
                end if;

                -- Pipeline stage 1: Calculate deltas (handle wrap-around)
                calc_valid_p1 <= ts_valid;
                if ts_valid = '1' then
                    -- Latency A = T2 - T1 (ITCH parse time in 125 MHz domain)
                    delta_a := unsigned(ts_t2) - unsigned(ts_t1);
                    latency_a_p1 <= delta_a;

                    -- Latency B = T4 - T3 (FIFO to TX time in 125 MHz domain)
                    delta_b := unsigned(ts_t4) - unsigned(ts_t3);
                    latency_b_p1 <= delta_b;

                    -- Latch timestamps for register output
                    t1_latched <= ts_t1;
                    t4_latched <= ts_t4;
                end if;

                -- Pipeline stage 2: Sum and convert to nanoseconds
                calc_valid_p2 <= calc_valid_p1;
                if calc_valid_p1 = '1' then
                    -- Total latency in cycles = A + B
                    -- Convert to nanoseconds: * 8 (shift left 3)
                    total_ns := (latency_a_p1 + latency_b_p1) sll 3;
                    total_latency_p2 <= total_ns;
                    t1_latched_p2 <= t1_latched;
                    t4_latched_p2 <= t4_latched;
                end if;

                -- Pipeline stage 3: Update statistics
                if calc_valid_p2 = '1' then
                    -- Update last latency
                    last_latency_reg <= total_latency_p2;
                    last_rx_ts_reg <= t1_latched_p2;
                    last_tx_ts_reg <= t4_latched_p2;

                    -- Update max (ignore obviously invalid values > 1 second)
                    if total_latency_p2 > max_latency_reg and total_latency_p2 < 1_000_000_000 then
                        max_latency_reg <= total_latency_p2;
                    end if;

                    -- Update min (ignore zero values)
                    if total_latency_p2 < min_latency_reg and total_latency_p2 > 0 then
                        min_latency_reg <= total_latency_p2;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
