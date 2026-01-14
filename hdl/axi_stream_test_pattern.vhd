--------------------------------------------------------------------------------
-- AXI-Stream Test Pattern Generator
-- Generates incrementing 64-bit counter pattern for XDMA C2H streaming
--
-- Simple continuous streaming source for validating PCIe DMA pipeline
-- Pattern: 0x0000000000000000, 0x0000000000000001, 0x0000000000000002, ...
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi_stream_test_pattern is
    Port (
        -- Clock and Reset
        aclk          : in  std_logic;
        aresetn       : in  std_logic;

        -- AXI-Stream Master Interface (to XDMA S_AXIS_C2H)
        m_axis_tdata  : out std_logic_vector(63 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic;
        m_axis_tkeep  : out std_logic_vector(7 downto 0)
    );
end axi_stream_test_pattern;

architecture Behavioral of axi_stream_test_pattern is
    signal counter       : unsigned(63 downto 0) := (others => '0');
    signal beat_counter  : unsigned(7 downto 0) := (others => '0');

    -- Generate packets of 256 beats (2KB per packet)
    constant BEATS_PER_PACKET : integer := 256;

begin

    -- Always ready to send data
    m_axis_tvalid <= '1';

    -- All bytes valid (64-bit full words)
    m_axis_tkeep <= (others => '1');

    -- Generate incrementing counter
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                counter <= (others => '0');
                beat_counter <= (others => '0');
                m_axis_tdata <= (others => '0');
                m_axis_tlast <= '0';
            else
                -- Only advance when XDMA accepts data
                if m_axis_tready = '1' then
                    -- Output current counter value
                    m_axis_tdata <= std_logic_vector(counter);

                    -- Increment counter
                    counter <= counter + 1;

                    -- Track beats per packet
                    if beat_counter = BEATS_PER_PACKET - 1 then
                        m_axis_tlast <= '1';
                        beat_counter <= (others => '0');
                    else
                        m_axis_tlast <= '0';
                        beat_counter <= beat_counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
