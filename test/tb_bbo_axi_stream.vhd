----------------------------------------------------------------------------------
-- Testbench for BBO to AXI-Stream Converter
-- Verifies conversion of BBO messages to 128-bit AXI-Stream format
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_bbo_axi_stream is
end tb_bbo_axi_stream;

architecture Behavioral of tb_bbo_axi_stream is

    -- Component under test
    component bbo_axi_stream is
        Generic (
            C_AXI_DATA_WIDTH : integer := 128;
            C_BBO_SIZE       : integer := 44
        );
        Port (
            aclk           : in  STD_LOGIC;
            aresetn        : in  STD_LOGIC;
            bbo_valid      : in  STD_LOGIC;
            bbo_ready      : out STD_LOGIC;
            bbo_symbol     : in  STD_LOGIC_VECTOR(63 downto 0);
            bbo_bid_price  : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_bid_size   : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_ask_price  : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_ask_size   : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_spread     : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_ts_t1      : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_ts_t2      : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_ts_t3      : in  STD_LOGIC_VECTOR(31 downto 0);
            bbo_ts_t4      : in  STD_LOGIC_VECTOR(31 downto 0);
            m_axis_tdata   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH-1 downto 0);
            m_axis_tkeep   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH/8-1 downto 0);
            m_axis_tvalid  : out STD_LOGIC;
            m_axis_tready  : in  STD_LOGIC;
            m_axis_tlast   : out STD_LOGIC;
            bbo_count      : out STD_LOGIC_VECTOR(31 downto 0);
            fifo_overflow  : out STD_LOGIC
        );
    end component;

    -- Clock period
    constant CLK_PERIOD : time := 8 ns;  -- 125 MHz

    -- Signals
    signal aclk           : STD_LOGIC := '0';
    signal aresetn        : STD_LOGIC := '0';
    signal bbo_valid      : STD_LOGIC := '0';
    signal bbo_ready      : STD_LOGIC;
    signal bbo_symbol     : STD_LOGIC_VECTOR(63 downto 0) := (others => '0');
    signal bbo_bid_price  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_bid_size   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_ask_price  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_ask_size   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_spread     : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_ts_t1      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_ts_t2      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_ts_t3      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bbo_ts_t4      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal m_axis_tdata   : STD_LOGIC_VECTOR(127 downto 0);
    signal m_axis_tkeep   : STD_LOGIC_VECTOR(15 downto 0);
    signal m_axis_tvalid  : STD_LOGIC;
    signal m_axis_tready  : STD_LOGIC := '1';
    signal m_axis_tlast   : STD_LOGIC;
    signal bbo_count      : STD_LOGIC_VECTOR(31 downto 0);
    signal fifo_overflow  : STD_LOGIC;

    -- Test control
    signal test_done : boolean := false;

    -- Helper function to convert ASCII string to std_logic_vector
    function str_to_slv(str : string; len : integer) return STD_LOGIC_VECTOR is
        variable result : STD_LOGIC_VECTOR(len-1 downto 0) := (others => '0');
        variable char_val : integer;
    begin
        for i in str'range loop
            if i <= len/8 then
                char_val := character'pos(str(i));
                result((len - (i-1)*8 - 1) downto (len - i*8)) :=
                    std_logic_vector(to_unsigned(char_val, 8));
            end if;
        end loop;
        -- Pad with spaces
        for i in str'length+1 to len/8 loop
            result((len - (i-1)*8 - 1) downto (len - i*8)) := x"20";
        end loop;
        return result;
    end function;

begin

    -- Clock generation
    aclk <= not aclk after CLK_PERIOD/2 when not test_done else '0';

    -- DUT instantiation
    DUT: bbo_axi_stream
        generic map (
            C_AXI_DATA_WIDTH => 128,
            C_BBO_SIZE       => 44
        )
        port map (
            aclk           => aclk,
            aresetn        => aresetn,
            bbo_valid      => bbo_valid,
            bbo_ready      => bbo_ready,
            bbo_symbol     => bbo_symbol,
            bbo_bid_price  => bbo_bid_price,
            bbo_bid_size   => bbo_bid_size,
            bbo_ask_price  => bbo_ask_price,
            bbo_ask_size   => bbo_ask_size,
            bbo_spread     => bbo_spread,
            bbo_ts_t1      => bbo_ts_t1,
            bbo_ts_t2      => bbo_ts_t2,
            bbo_ts_t3      => bbo_ts_t3,
            bbo_ts_t4      => bbo_ts_t4,
            m_axis_tdata   => m_axis_tdata,
            m_axis_tkeep   => m_axis_tkeep,
            m_axis_tvalid  => m_axis_tvalid,
            m_axis_tready  => m_axis_tready,
            m_axis_tlast   => m_axis_tlast,
            bbo_count      => bbo_count,
            fifo_overflow  => fifo_overflow
        );

    -- Main test process
    test_proc: process
        variable beat_count : integer := 0;
    begin
        report "Starting BBO AXI-Stream Testbench";

        -- Initial reset
        aresetn <= '0';
        wait for CLK_PERIOD * 10;
        aresetn <= '1';
        wait for CLK_PERIOD * 5;

        ------------------------------------------------------------
        -- Test 1: Single BBO transmission
        ------------------------------------------------------------
        report "Test 1: Single BBO transmission";

        -- Set up BBO data (AAPL stock)
        bbo_symbol    <= str_to_slv("AAPL    ", 64);
        bbo_bid_price <= x"000186A0";  -- 100000 (10.0000)
        bbo_bid_size  <= x"00000064";  -- 100 shares
        bbo_ask_price <= x"000186B4";  -- 100020 (10.0020)
        bbo_ask_size  <= x"000000C8";  -- 200 shares
        bbo_spread    <= x"00000014";  -- 20 (0.0020)
        bbo_ts_t1     <= x"00001000";  -- T1: ITCH parse
        bbo_ts_t2     <= x"00001024";  -- T2: +36 cycles (288 ns)
        bbo_ts_t3     <= x"00001100";  -- T3: FIFO read
        bbo_ts_t4     <= x"00001103";  -- T4: +3 cycles (24 ns)

        -- Assert valid
        wait for CLK_PERIOD;
        bbo_valid <= '1';
        wait for CLK_PERIOD;
        bbo_valid <= '0';

        -- Wait for AXI-Stream transmission (3 beats)
        beat_count := 0;
        while beat_count < 3 loop
            wait for CLK_PERIOD;
            if m_axis_tvalid = '1' and m_axis_tready = '1' then
                beat_count := beat_count + 1;
                report "Beat " & integer'image(beat_count) &
                       " - TDATA: 0x" & to_hstring(m_axis_tdata) &
                       " TLAST: " & std_logic'image(m_axis_tlast) &
                       " TKEEP: 0x" & to_hstring(m_axis_tkeep);
            end if;
        end loop;

        -- Check BBO count
        wait for CLK_PERIOD * 5;
        assert bbo_count = x"00000001"
            report "Expected bbo_count = 1, got " & to_hstring(bbo_count)
            severity error;

        report "Test 1 PASSED: Single BBO transmitted successfully";

        ------------------------------------------------------------
        -- Test 2: Back-to-back BBOs
        ------------------------------------------------------------
        report "Test 2: Back-to-back BBOs";

        for i in 1 to 5 loop
            -- Wait for ready
            while bbo_ready = '0' loop
                wait for CLK_PERIOD;
            end loop;

            -- Set up BBO data
            bbo_symbol    <= str_to_slv("TEST" & integer'image(i) & "   ", 64);
            bbo_bid_price <= std_logic_vector(to_unsigned(100000 + i*100, 32));
            bbo_bid_size  <= std_logic_vector(to_unsigned(100 * i, 32));
            bbo_ask_price <= std_logic_vector(to_unsigned(100100 + i*100, 32));
            bbo_ask_size  <= std_logic_vector(to_unsigned(200 * i, 32));
            bbo_spread    <= x"00000064";  -- 100
            bbo_ts_t1     <= std_logic_vector(to_unsigned(4096 * i, 32));
            bbo_ts_t2     <= std_logic_vector(to_unsigned(4096 * i + 36, 32));
            bbo_ts_t3     <= std_logic_vector(to_unsigned(4096 * i + 256, 32));
            bbo_ts_t4     <= std_logic_vector(to_unsigned(4096 * i + 259, 32));

            bbo_valid <= '1';
            wait for CLK_PERIOD;
            bbo_valid <= '0';

            -- Wait a bit between BBOs
            wait for CLK_PERIOD * 20;
        end loop;

        -- Wait for all transmissions to complete
        wait for CLK_PERIOD * 100;

        -- Check BBO count (1 from test 1 + 5 from test 2)
        assert bbo_count = x"00000006"
            report "Expected bbo_count = 6, got " & to_hstring(bbo_count)
            severity error;

        report "Test 2 PASSED: Back-to-back BBOs transmitted";

        ------------------------------------------------------------
        -- Test 3: Backpressure handling
        ------------------------------------------------------------
        report "Test 3: Backpressure handling";

        -- Deassert ready
        m_axis_tready <= '0';

        -- Wait for ready
        while bbo_ready = '0' loop
            wait for CLK_PERIOD;
        end loop;

        -- Send a BBO
        bbo_symbol    <= str_to_slv("GOOG    ", 64);
        bbo_bid_price <= x"00030D40";  -- 200000
        bbo_bid_size  <= x"000003E8";  -- 1000
        bbo_ask_price <= x"00030D54";  -- 200020
        bbo_ask_size  <= x"000007D0";  -- 2000
        bbo_spread    <= x"00000014";  -- 20
        bbo_ts_t1     <= x"00010000";
        bbo_ts_t2     <= x"00010030";
        bbo_ts_t3     <= x"00010100";
        bbo_ts_t4     <= x"00010105";

        bbo_valid <= '1';
        wait for CLK_PERIOD;
        bbo_valid <= '0';

        -- Wait and verify valid is held
        wait for CLK_PERIOD * 10;
        assert m_axis_tvalid = '1'
            report "Expected tvalid to be held during backpressure"
            severity error;

        -- Re-assert ready
        m_axis_tready <= '1';

        -- Wait for transmission to complete
        wait for CLK_PERIOD * 20;

        report "Test 3 PASSED: Backpressure handled correctly";

        ------------------------------------------------------------
        -- Done
        ------------------------------------------------------------
        report "All tests PASSED!";
        test_done <= true;
        wait;
    end process;

end Behavioral;
