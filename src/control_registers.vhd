----------------------------------------------------------------------------------
-- Control Registers - AXI-Lite Slave
-- Provides configuration and status interface for PCIe GPU Bridge
--
-- Register Map:
--   0x00: VERSION      (R)   - IP Version (0x21000001)
--   0x04: CONTROL      (RW)  - Bit 0: Enable, Bit 1: Reset counters
--   0x08: STATUS       (R)   - Bit 0: Running, Bit 1: FIFO overflow
--   0x0C: BBO_COUNT    (R)   - Total BBOs transmitted
--   0x10: SYMBOL_FILT0 (RW)  - Symbol filter bytes 0-3
--   0x14: SYMBOL_FILT1 (RW)  - Symbol filter bytes 4-7
--   0x18: FILTER_MASK  (RW)  - Bit 0: Filter enable
--   0x1C: RESERVED
--   0x20: LAST_RX_TS   (R)   - Last RX timestamp (T1)
--   0x24: LAST_TX_TS   (R)   - Last TX timestamp (T4)
--   0x28: LATENCY_NS   (R)   - Last FPGA latency in nanoseconds
--   0x2C: MAX_LATENCY  (R)   - Maximum observed latency
--   0x30: MIN_LATENCY  (R)   - Minimum observed latency (non-zero)
--   0x34: UPTIME_SEC   (R)   - Uptime in seconds
--
-- Clock Domain: axi_aclk (XDMA clock, 125-250 MHz)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity control_registers is
    Generic (
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 6   -- 64 bytes address space
    );
    Port (
        -- AXI-Lite Slave Interface
        S_AXI_ACLK     : in  STD_LOGIC;
        S_AXI_ARESETN  : in  STD_LOGIC;

        -- Write address channel
        S_AXI_AWADDR   : in  STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_AWVALID  : in  STD_LOGIC;
        S_AXI_AWREADY  : out STD_LOGIC;

        -- Write data channel
        S_AXI_WDATA    : in  STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_WSTRB    : in  STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH/8-1 downto 0);
        S_AXI_WVALID   : in  STD_LOGIC;
        S_AXI_WREADY   : out STD_LOGIC;

        -- Write response channel
        S_AXI_BRESP    : out STD_LOGIC_VECTOR(1 downto 0);
        S_AXI_BVALID   : out STD_LOGIC;
        S_AXI_BREADY   : in  STD_LOGIC;

        -- Read address channel
        S_AXI_ARADDR   : in  STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_ARVALID  : in  STD_LOGIC;
        S_AXI_ARREADY  : out STD_LOGIC;

        -- Read data channel
        S_AXI_RDATA    : out STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_RRESP    : out STD_LOGIC_VECTOR(1 downto 0);
        S_AXI_RVALID   : out STD_LOGIC;
        S_AXI_RREADY   : in  STD_LOGIC;

        -- Control outputs
        ctrl_enable    : out STD_LOGIC;
        ctrl_reset     : out STD_LOGIC;
        filter_enable  : out STD_LOGIC;
        filter_symbol  : out STD_LOGIC_VECTOR(63 downto 0);

        -- Status inputs
        status_running : in  STD_LOGIC;
        status_overflow: in  STD_LOGIC;
        bbo_count      : in  STD_LOGIC_VECTOR(31 downto 0);
        last_rx_ts     : in  STD_LOGIC_VECTOR(31 downto 0);
        last_tx_ts     : in  STD_LOGIC_VECTOR(31 downto 0);
        latency_ns     : in  STD_LOGIC_VECTOR(31 downto 0);
        max_latency_ns : in  STD_LOGIC_VECTOR(31 downto 0);
        min_latency_ns : in  STD_LOGIC_VECTOR(31 downto 0)
    );
end control_registers;

architecture Behavioral of control_registers is

    -- Version constant
    constant IP_VERSION : STD_LOGIC_VECTOR(31 downto 0) := x"21000001";

    -- AXI-Lite state machines
    type write_state_type is (IDLE, ADDR_DATA, RESP);
    type read_state_type is (IDLE, DATA);
    signal write_state : write_state_type := IDLE;
    signal read_state  : read_state_type := IDLE;

    -- Register storage
    signal reg_control     : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal reg_symbol_filt0: STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal reg_symbol_filt1: STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal reg_filter_mask : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    -- Latched addresses
    signal awaddr_latched  : STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal araddr_latched  : STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');

    -- Uptime counter (assumes 125 MHz clock)
    signal uptime_counter  : unsigned(31 downto 0) := (others => '0');
    signal second_counter  : unsigned(26 downto 0) := (others => '0');  -- Counts to 125M
    constant CLOCKS_PER_SEC: unsigned(26 downto 0) := to_unsigned(125_000_000, 27);

begin

    -- Control output assignments
    ctrl_enable   <= reg_control(0);
    ctrl_reset    <= reg_control(1);
    filter_enable <= reg_filter_mask(0);
    filter_symbol <= reg_symbol_filt1 & reg_symbol_filt0;

    -- Uptime counter process
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                uptime_counter <= (others => '0');
                second_counter <= (others => '0');
            else
                if second_counter >= CLOCKS_PER_SEC - 1 then
                    second_counter <= (others => '0');
                    uptime_counter <= uptime_counter + 1;
                else
                    second_counter <= second_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- Write state machine
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                write_state <= IDLE;
                S_AXI_AWREADY <= '0';
                S_AXI_WREADY <= '0';
                S_AXI_BVALID <= '0';
                S_AXI_BRESP <= "00";
                awaddr_latched <= (others => '0');
                reg_control <= (others => '0');
                reg_symbol_filt0 <= (others => '0');
                reg_symbol_filt1 <= (others => '0');
                reg_filter_mask <= (others => '0');
            else
                case write_state is
                    when IDLE =>
                        S_AXI_AWREADY <= '1';
                        S_AXI_WREADY <= '1';
                        S_AXI_BVALID <= '0';

                        if S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' then
                            awaddr_latched <= S_AXI_AWADDR;

                            -- Write to register based on address
                            case S_AXI_AWADDR(5 downto 2) is
                                when "0001" =>  -- 0x04: CONTROL
                                    reg_control <= S_AXI_WDATA;
                                when "0100" =>  -- 0x10: SYMBOL_FILT0
                                    reg_symbol_filt0 <= S_AXI_WDATA;
                                when "0101" =>  -- 0x14: SYMBOL_FILT1
                                    reg_symbol_filt1 <= S_AXI_WDATA;
                                when "0110" =>  -- 0x18: FILTER_MASK
                                    reg_filter_mask <= S_AXI_WDATA;
                                when others =>
                                    null;  -- Read-only or invalid address
                            end case;

                            S_AXI_AWREADY <= '0';
                            S_AXI_WREADY <= '0';
                            write_state <= RESP;

                        elsif S_AXI_AWVALID = '1' then
                            awaddr_latched <= S_AXI_AWADDR;
                            S_AXI_AWREADY <= '0';
                            write_state <= ADDR_DATA;
                        end if;

                    when ADDR_DATA =>
                        S_AXI_WREADY <= '1';

                        if S_AXI_WVALID = '1' then
                            -- Write to register based on latched address
                            case awaddr_latched(5 downto 2) is
                                when "0001" =>  -- 0x04: CONTROL
                                    reg_control <= S_AXI_WDATA;
                                when "0100" =>  -- 0x10: SYMBOL_FILT0
                                    reg_symbol_filt0 <= S_AXI_WDATA;
                                when "0101" =>  -- 0x14: SYMBOL_FILT1
                                    reg_symbol_filt1 <= S_AXI_WDATA;
                                when "0110" =>  -- 0x18: FILTER_MASK
                                    reg_filter_mask <= S_AXI_WDATA;
                                when others =>
                                    null;
                            end case;

                            S_AXI_WREADY <= '0';
                            write_state <= RESP;
                        end if;

                    when RESP =>
                        S_AXI_BVALID <= '1';
                        S_AXI_BRESP <= "00";  -- OKAY

                        if S_AXI_BREADY = '1' then
                            S_AXI_BVALID <= '0';
                            write_state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- Read state machine
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                read_state <= IDLE;
                S_AXI_ARREADY <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RDATA <= (others => '0');
                S_AXI_RRESP <= "00";
                araddr_latched <= (others => '0');
            else
                case read_state is
                    when IDLE =>
                        S_AXI_ARREADY <= '1';
                        S_AXI_RVALID <= '0';

                        if S_AXI_ARVALID = '1' then
                            araddr_latched <= S_AXI_ARADDR;
                            S_AXI_ARREADY <= '0';
                            read_state <= DATA;
                        end if;

                    when DATA =>
                        S_AXI_RVALID <= '1';
                        S_AXI_RRESP <= "00";  -- OKAY

                        -- Read from register based on address
                        case araddr_latched(5 downto 2) is
                            when "0000" =>  -- 0x00: VERSION
                                S_AXI_RDATA <= IP_VERSION;
                            when "0001" =>  -- 0x04: CONTROL
                                S_AXI_RDATA <= reg_control;
                            when "0010" =>  -- 0x08: STATUS
                                S_AXI_RDATA <= (31 downto 2 => '0') & status_overflow & status_running;
                            when "0011" =>  -- 0x0C: BBO_COUNT
                                S_AXI_RDATA <= bbo_count;
                            when "0100" =>  -- 0x10: SYMBOL_FILT0
                                S_AXI_RDATA <= reg_symbol_filt0;
                            when "0101" =>  -- 0x14: SYMBOL_FILT1
                                S_AXI_RDATA <= reg_symbol_filt1;
                            when "0110" =>  -- 0x18: FILTER_MASK
                                S_AXI_RDATA <= reg_filter_mask;
                            when "1000" =>  -- 0x20: LAST_RX_TS
                                S_AXI_RDATA <= last_rx_ts;
                            when "1001" =>  -- 0x24: LAST_TX_TS
                                S_AXI_RDATA <= last_tx_ts;
                            when "1010" =>  -- 0x28: LATENCY_NS
                                S_AXI_RDATA <= latency_ns;
                            when "1011" =>  -- 0x2C: MAX_LATENCY
                                S_AXI_RDATA <= max_latency_ns;
                            when "1100" =>  -- 0x30: MIN_LATENCY
                                S_AXI_RDATA <= min_latency_ns;
                            when "1101" =>  -- 0x34: UPTIME_SEC
                                S_AXI_RDATA <= std_logic_vector(uptime_counter);
                            when others =>
                                S_AXI_RDATA <= (others => '0');
                        end case;

                        if S_AXI_RREADY = '1' then
                            S_AXI_RVALID <= '0';
                            read_state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
