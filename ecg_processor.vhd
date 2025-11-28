library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecg_processor is
    port (
        clk_50mhz : in  std_logic;
        rst_n     : in  std_logic;
        hex5, hex4, hex3, hex2, hex1, hex0 : out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of ecg_processor is

    -- Componentes
    component ecg_rom is
        port (clk : in std_logic; addr : in integer range 0 to 16383; q : out integer range 0 to 4095);
    end component;

    component ssd_decoder is
        port (in_val : in std_logic_vector(3 downto 0); out_seg: out std_logic_vector(6 downto 0));
    end component;

    component Multi_Fuzzy_Diag is
        Port (
            clk : in std_logic; reset : in std_logic; bpm_in : in std_logic_vector(7 downto 0);
            diag_child, diag_adult, diag_elder : out std_logic_vector(1 downto 0)
        );
    end component;

    -- Definição da Máquina de Estados
    type state_type is (ST_IDLE, ST_WAIT_RELEASE, ST_MEASURING);
    signal current_state : state_type := ST_IDLE;

    -- Valores de Display REGISTRADOS
    signal stored_id_tens : integer range 0 to 9 := 0;
    signal stored_id_unit : integer range 0 to 9 := 0; 
    signal stored_bpm     : integer range 0 to 999 := 0;
    
    -- Valores de Processamento ATIVOS
    signal active_id_tens : integer range 0 to 9 := 0;
    signal active_id_unit : integer range 0 to 9 := 1;
    signal active_bpm     : integer range 0 to 999 := 0;
    signal pat_global_cnt : integer range 1 to 80 := 1;

    -- Processamento de ECG
    signal rom_addr       : integer range 0 to 16383 := 0;
    signal sample_data    : integer range 0 to 4095 := 0;
    signal sample_cnt     : integer range 0 to 188 := 0; 
    signal peak_timer     : integer range 0 to 2000 := 0;
    
    -- Controle de Tempo
    signal tick_enable    : std_logic; 
    signal div_cnt        : integer range 0 to 600000 := 0; 
    signal show_diag_mode : std_logic;

    -- Interconexões
    signal fzy_in  : std_logic_vector(7 downto 0);
    signal d_child, d_adult, d_elder : std_logic_vector(1 downto 0);
    signal s_idt, s_idu, s_bph, s_bpt, s_bpu : std_logic_vector(6 downto 0);

    function get_char(code : std_logic_vector(1 downto 0)) return std_logic_vector is
    begin
        case code is
            when "01" => return "1000111"; -- L
            when "10" => return "0101011"; -- n
            when "11" => return "0001001"; -- H
            when others => return "0111111"; -- -
        end case;
    end function;

begin

    -- Instanciações
    rom_i : ecg_rom port map (clk_50mhz, rom_addr, sample_data);

    fzy_in <= std_logic_vector(to_unsigned(stored_bpm, 8)) when stored_bpm < 255 else "11111111";
    
    fzy_i : Multi_Fuzzy_Diag port map (
        clk => clk_50mhz, reset => not rst_n, bpm_in => fzy_in,
        diag_child => d_child, diag_adult => d_adult, diag_elder => d_elder
    );

    u0: ssd_decoder port map (std_logic_vector(to_unsigned(stored_id_tens, 4)), s_idt);
    u1: ssd_decoder port map (std_logic_vector(to_unsigned(stored_id_unit, 4)), s_idu);
    u2: ssd_decoder port map (std_logic_vector(to_unsigned(stored_bpm/100, 4)), s_bph);
    u3: ssd_decoder port map (std_logic_vector(to_unsigned((stored_bpm/10) mod 10, 4)), s_bpt);
    u4: ssd_decoder port map (std_logic_vector(to_unsigned(stored_bpm mod 10, 4)), s_bpu);

    show_diag_mode <= '1' when sample_cnt > 94 else '0';

    process(show_diag_mode, s_idt, s_idu, s_bph, s_bpt, s_bpu, d_child, d_adult, d_elder)
    begin
        if show_diag_mode = '0' then
            hex5 <= s_idt; hex4 <= s_idu; 
            hex3 <= "1111111";            
            hex2 <= s_bph; hex1 <= s_bpt; hex0 <= s_bpu; 
        else
            hex5 <= "1000110"; hex4 <= get_char(d_child);
            hex3 <= "0001000"; hex2 <= get_char(d_adult);
            hex1 <= "1001111"; hex0 <= get_char(d_elder);
        end if;
    end process;

    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if rst_n = '0' then
                rom_addr <= 0;
                sample_cnt <= 0;
                pat_global_cnt <= 1;
                active_id_tens <= 0; active_id_unit <= 1;
                
                stored_id_tens <= 0; stored_id_unit <= 0; stored_bpm <= 0;
                
                div_cnt <= 0; tick_enable <= '0';
                
                -- Reset da FSM
                current_state <= ST_IDLE;
                peak_timer <= 0;
            else
                -- Divisor de Clock (Tick approx 94Hz)
                tick_enable <= '0';
                if div_cnt >= 531914 then 
                    div_cnt <= 0;
                    tick_enable <= '1';
                else
                    div_cnt <= div_cnt + 1;
                end if;

                if tick_enable = '1' then
                    
                    -- Timer roda independente do estado, desde que não estoure
                    if peak_timer < 2000 then peak_timer <= peak_timer + 1; end if;

                    -- Máquina de Estados para Detecção de Pico
                    case current_state is
                        
                        -- ST_IDLE: Aguarda o primeiro pulso apenas para sincronizar o início da contagem
                        when ST_IDLE =>
                            if sample_data > 3480 then
                                peak_timer <= 0; -- Zera timer para começar a medir a distância até o próximo
                                current_state <= ST_WAIT_RELEASE;
                            end if;

                        -- ST_WAIT_RELEASE: O sinal está alto, esperamos cair para evitar falsos positivos
                        when ST_WAIT_RELEASE =>
                            if sample_data < 2000 then
                                current_state <= ST_MEASURING;
                            end if;

                        -- ST_MEASURING:O sinal está baixo, estamos contando o tempo (peak_timer incrementando acima)
                        -- Se detectarmos um novo pico aqui, calculamos o BPM
                        when ST_MEASURING =>
                            if sample_data > 3480 then
                                -- Pico encontrado!
                                if peak_timer > 5 then
                                    active_bpm <= 7500 / peak_timer;
                                end if;
                                peak_timer <= 0; -- Reinicia contagem para o próximo
                                current_state <= ST_WAIT_RELEASE; -- Volta a esperar o sinal descer
                            end if;
                            
                    end case;

                    -- Lógica de troca de paciente/display (Reset cíclico)
                    if sample_cnt = 187 then
                        stored_id_tens <= active_id_tens;
                        stored_id_unit <= active_id_unit;
                        stored_bpm     <= active_bpm;

                        sample_cnt <= 0;
                        current_state <= ST_IDLE; -- Força volta para busca inicial (reseta first_peak logicamente)
                        
                        if pat_global_cnt = 80 then
                            pat_global_cnt <= 1;
                            rom_addr <= 0;
                            active_id_tens <= 0; 
                            active_id_unit <= 1;
                        else
                            pat_global_cnt <= pat_global_cnt + 1;
                            rom_addr <= rom_addr + 1;
                            if active_id_unit = 9 then
                                active_id_unit <= 0;
                                active_id_tens <= active_id_tens + 1;
                            else
                                active_id_unit <= active_id_unit + 1;
                            end if;
                        end if;
                    else
                        sample_cnt <= sample_cnt + 1;
                        rom_addr <= rom_addr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end rtl;