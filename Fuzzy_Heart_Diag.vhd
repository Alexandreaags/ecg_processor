library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Fuzzy_Heart_Diag is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        bpm_in   : in  std_logic_vector(7 downto 0); -- BPM 0-255
        diag_out : out std_logic_vector(1 downto 0)  -- 01:L, 10:N, 11:H
    );
end Fuzzy_Heart_Diag;

architecture Behavioral of Fuzzy_Heart_Diag is
    -- Sinais internos (unsigned para facilitar contas)
    signal mu_low    : unsigned(7 downto 0);
    signal mu_normal : unsigned(7 downto 0);
    signal mu_high   : unsigned(7 downto 0);
    signal bpm_uns   : unsigned(7 downto 0);
begin
    bpm_uns <= unsigned(bpm_in);

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mu_low <= (others => '0'); 
                mu_normal <= (others => '0'); 
                mu_high <= (others => '0');
                diag_out <= "00";
            else
                -- 1. FUZZIFICAÇÃO (Calcula Grau de Pertinência 0 a 255)
                
                -- === BAIXO (Trapezoidal descendente) ===
                -- < 50: 100%. Entre 50 e 60: Desce. > 60: 0%
                if bpm_uns <= 50 then 
                    mu_low <= to_unsigned(255, 8);
                elsif bpm_uns < 60 then 
                    -- Reta descida: (60 - BPM) * 25
                    mu_low <= resize((60 - bpm_uns) * 25, 8);
                else 
                    mu_low <= (others => '0'); 
                end if;

                -- === NORMAL (Triangular) ===
                -- 50 a 75: Sobe. 75 a 100: Desce.
                if bpm_uns <= 50 or bpm_uns >= 100 then 
                    mu_normal <= (others => '0');
                elsif bpm_uns <= 75 then 
                    -- Reta subida: (BPM - 50) * 10
                    mu_normal <= resize((bpm_uns - 50) * 10, 8);
                else 
                    -- Reta descida: (100 - BPM) * 10
                    mu_normal <= resize((100 - bpm_uns) * 10, 8); 
                end if;

                -- === ALTO (Trapezoidal ascendente) ===
                -- < 90: 0%. Entre 90 e 100: Sobe. > 100: 100%
                if bpm_uns <= 90 then 
                    mu_high <= (others => '0');
                elsif bpm_uns < 100 then 
                    -- Reta subida: (BPM - 90) * 25
                    mu_high <= resize((bpm_uns - 90) * 25, 8);
                else 
                    mu_high <= to_unsigned(255, 8); 
                end if;

                -- 2. DEFUZZIFICAÇÃO (Max / Winner-Take-All)
                if (mu_low >= mu_normal) and (mu_low >= mu_high) then
                    diag_out <= "01"; -- Low
                elsif (mu_normal >= mu_low) and (mu_normal >= mu_high) then
                    diag_out <= "10"; -- Normal
                else
                    diag_out <= "11"; -- High
                end if;
            end if;
        end if;
    end process;
end Behavioral;