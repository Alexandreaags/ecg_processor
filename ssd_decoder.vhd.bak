library ieee;
use ieee.std_logic_1164.all;

entity ssd_decoder is
    port (
        in_val : in  std_logic_vector(3 downto 0);
        out_seg: out std_logic_vector(6 downto 0) -- gfedcba (0 acende)
    );
end entity;

architecture rtl of ssd_decoder is
begin
    process(in_val)
    begin
        case in_val is
            -- Lógica invertida (0 = LED ligado) comum na maioria das placas DE
            when "0000" => out_seg <= "1000000"; -- 0
            when "0001" => out_seg <= "1111001"; -- 1
            when "0010" => out_seg <= "0100100"; -- 2
            when "0011" => out_seg <= "0110000"; -- 3
            when "0100" => out_seg <= "0011001"; -- 4
            when "0101" => out_seg <= "0010010"; -- 5
            when "0110" => out_seg <= "0000010"; -- 6
            when "0111" => out_seg <= "1111000"; -- 7
            when "1000" => out_seg <= "0000000"; -- 8
            when "1001" => out_seg <= "0010000"; -- 9
            when others => out_seg <= "0111111"; -- Traço (-)
        end case;
    end process;
end rtl;