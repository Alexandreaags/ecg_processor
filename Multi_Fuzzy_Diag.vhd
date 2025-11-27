library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Multi_Fuzzy_Diag is
    Port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        bpm_in    : in  std_logic_vector(7 downto 0);
        
        -- Saídas individuais (01:L, 10:N, 11:H)
        diag_child : out std_logic_vector(1 downto 0);
        diag_adult : out std_logic_vector(1 downto 0);
        diag_elder : out std_logic_vector(1 downto 0)
    );
end Multi_Fuzzy_Diag;

architecture Behavioral of Multi_Fuzzy_Diag is
    signal bpm_uns : unsigned(7 downto 0);
begin
    bpm_uns <= unsigned(bpm_in);

    process(clk)
        -- Variáveis auxiliares para Criança
        variable c_mu_low, c_mu_norm, c_mu_high : unsigned(7 downto 0);
        -- Variáveis auxiliares para Adulto
        variable a_mu_low, a_mu_norm, a_mu_high : unsigned(7 downto 0);
        -- Variáveis auxiliares para Idoso
        variable i_mu_low, i_mu_norm, i_mu_high : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                diag_child <= "00"; diag_adult <= "00"; diag_elder <= "00";
            else
                
                -- LÓGICA CRIANÇA (Faixas mais altas)
                -- Baixo < 70, Normal 70-110, Alto > 120
                                
                -- Low (Criança)
                if bpm_uns <= 70 then c_mu_low := to_unsigned(255, 8);
                elsif bpm_uns < 80 then c_mu_low := resize((80 - bpm_uns) * 25, 8);
                else c_mu_low := (others => '0'); end if;
                
                -- Normal (Criança)
                if bpm_uns <= 70 or bpm_uns >= 120 then c_mu_norm := (others => '0');
                elsif bpm_uns <= 95 then c_mu_norm := resize((bpm_uns - 70) * 10, 8);
                else c_mu_norm := resize((120 - bpm_uns) * 10, 8); end if;

                -- High (Criança)
                if bpm_uns <= 110 then c_mu_high := (others => '0');
                elsif bpm_uns < 120 then c_mu_high := resize((bpm_uns - 110) * 25, 8);
                else c_mu_high := to_unsigned(255, 8); end if;

                -- Decisão Criança
                if (c_mu_low >= c_mu_norm) and (c_mu_low >= c_mu_high) then diag_child <= "01";
                elsif (c_mu_norm >= c_mu_low) and (c_mu_norm >= c_mu_high) then diag_child <= "10";
                else diag_child <= "11"; end if;

                -- LÓGICA ADULTO (Faixas Padrão)
                -- Baixo < 50, Normal 50-100, Alto > 90
                                
                -- Low (Adulto)
                if bpm_uns <= 50 then a_mu_low := to_unsigned(255, 8);
                elsif bpm_uns < 60 then a_mu_low := resize((60 - bpm_uns) * 25, 8);
                else a_mu_low := (others => '0'); end if;

                -- Normal (Adulto)
                if bpm_uns <= 50 or bpm_uns >= 100 then a_mu_norm := (others => '0');
                elsif bpm_uns <= 75 then a_mu_norm := resize((bpm_uns - 50) * 10, 8);
                else a_mu_norm := resize((100 - bpm_uns) * 10, 8); end if;

                -- High (Adulto)
                if bpm_uns <= 90 then a_mu_high := (others => '0');
                elsif bpm_uns < 100 then a_mu_high := resize((bpm_uns - 90) * 25, 8);
                else a_mu_high := to_unsigned(255, 8); end if;

                -- Decisão Adulto
                if (a_mu_low >= a_mu_norm) and (a_mu_low >= a_mu_high) then diag_adult <= "01";
                elsif (a_mu_norm >= a_mu_low) and (a_mu_norm >= a_mu_high) then diag_adult <= "10";
                else diag_adult <= "11"; end if;

                -- LÓGICA IDOSO (Faixas mais baixas/críticas)
                -- Baixo < 45, Normal 45-90, Alto > 85
                                
                -- Low (Idoso)
                if bpm_uns <= 45 then i_mu_low := to_unsigned(255, 8);
                elsif bpm_uns < 55 then i_mu_low := resize((55 - bpm_uns) * 25, 8);
                else i_mu_low := (others => '0'); end if;

                -- Normal (Idoso)
                if bpm_uns <= 45 or bpm_uns >= 90 then i_mu_norm := (others => '0');
                elsif bpm_uns <= 65 then i_mu_norm := resize((bpm_uns - 45) * 12, 8);
                else i_mu_norm := resize((90 - bpm_uns) * 10, 8); end if;

                -- High (Idoso)
                if bpm_uns <= 80 then i_mu_high := (others => '0');
                elsif bpm_uns < 90 then i_mu_high := resize((bpm_uns - 80) * 25, 8);
                else i_mu_high := to_unsigned(255, 8); end if;

                -- Decisão Idoso
                if (i_mu_low >= i_mu_norm) and (i_mu_low >= i_mu_high) then diag_elder <= "01";
                elsif (i_mu_norm >= i_mu_low) and (i_mu_norm >= i_mu_high) then diag_elder <= "10";
                else diag_elder <= "11"; end if;

            end if;
        end if;
    end process;
end Behavioral;
